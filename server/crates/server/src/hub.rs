//! The city thread: the one place the world changes. It takes messages from connections, the clock, the chain and the
//! verify page, steps the world, writes the log, carries the world's intents to the ledger, and tells each client what
//! they should see.

use crate::http::VerifyDesk;
use crate::ledger::{hex, keccak_of_hex, random_bytes, HumanVerifier, Intent, Ledger, Observed};
use crate::limits::{self, Limits};
use crate::log::Log;
use crate::names::{self, HelloRefusal};
use crate::net::{ConnId, ToCity, ToClient};
use crate::offline::{OfflineCampaign, OfflineLedger};
use crate::presence::{self, Position, Presence};
use crate::protocol::{self, ClientMessage, DebugAction, PlayerCommand, PROTOCOL_VERSION};
use crate::public::{self, PublicView};
use crate::world::{Input, World};
use rules::chain::Observation;
use rules::{Command, Event, Refusal, Role};
use serde_json::{json, Value};
use std::collections::{BTreeSet, HashMap};
use std::sync::mpsc::{Receiver, RecvTimeoutError, Sender};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// Refs are kept for good, in memory and in the save, so they can't be any size.
const MOST_IN_A_REF: usize = 64;
/// How often the ledger is asked what the chain did.
const LEDGER_POLL: Duration = Duration::from_millis(100);
/// Most rounds of answers taken in one poll, so a chatty ledger can't hold the city thread.
const LEDGER_ROUNDS: usize = 8;

/// When the clock runs. `heartbeat` of None means time moves only by rehearsal skips, which tests rely on.
#[derive(Clone, Copy)]
pub struct Options {
    pub heartbeat: Option<Duration>,
    pub speed: u64,
    pub debug: bool,
}

/// The offline ledger, shared between the hub's `Ledger` and its rehearsal commands.
#[derive(Clone)]
pub struct SharedOffline(pub Arc<Mutex<OfflineLedger>>);

impl Ledger for SharedOffline {
    fn submit(&mut self, intent: Intent) {
        if let Ok(mut ledger) = self.0.lock() {
            ledger.submit(intent);
        }
    }

    fn poll(&mut self) -> Vec<Observed> {
        self.0.lock().map(|mut l| l.poll()).unwrap_or_default()
    }
}

/// What the city thread talks to outside the world: the chain, World ID and the Town Pass links.
pub struct Links {
    pub ledger: Box<dyn Ledger>,
    /// Set offline, for the rehearsal commands that act on the offline chain.
    pub offline: Option<SharedOffline>,
    pub verifier: Arc<dyn HumanVerifier>,
    pub verify: Arc<VerifyDesk>,
    /// Shown in the public view for the pages.
    pub world_app_id: Option<String>,
}

impl Links {
    /// The offline chain, picked up from where this world left it, and the rehearsal verifier.
    pub fn offline(world: &World, debug: bool, public_url: &str) -> Result<Links, String> {
        let ledger = OfflineLedger::resume(&world.rules_toml, &world.state)?;
        let shared = SharedOffline(Arc::new(Mutex::new(ledger)));
        Ok(Links {
            ledger: Box::new(shared.clone()),
            offline: Some(shared),
            verifier: Arc::new(crate::ledger::OfflineVerifier::new(debug)),
            verify: Arc::new(VerifyDesk::new(public_url)),
            world_app_id: None,
        })
    }
}

struct Client {
    out: Sender<ToClient>,
    address: String,
    player: Option<String>,
    /// Kept only on a nameless connection, until the player writes their name.
    secret: Option<String>,
}

pub struct Hub {
    world: World,
    log: Log,
    options: Options,
    links: Links,
    clients: HashMap<ConnId, Client>,
    player_conn: HashMap<String, ConnId>,
    agent_refusals_seen: usize,
    presence: Presence,
    limits: Limits,
    public: Option<Arc<PublicView>>,
    /// The energy each connected player was last sent, so the clock can tell them when it comes back by itself.
    energy_sent: HashMap<String, u32>,
}

impl Hub {
    /// Picks up from the save. Anyone the log still has connected was cut off by a stop, so they're disconnected now.
    /// Everything the chain still owes an answer is sent again: each is safe to send twice.
    pub fn new(world: World, log: Log, options: Options, mut links: Links) -> Result<Self, String> {
        for intent in world.state.open_intents() {
            links.ledger.submit(intent);
        }
        let mut hub = Hub {
            agent_refusals_seen: world.town.refusals.len(),
            world,
            log,
            options,
            links,
            clients: HashMap::new(),
            player_conn: HashMap::new(),
            presence: Presence::default(),
            limits: Limits::default(),
            public: None,
            energy_sent: HashMap::new(),
        };
        let cut_off: Vec<String> = hub.world.connected().cloned().collect();
        for player in cut_off {
            hub.step(Input::Disconnect { player })?;
        }
        Ok(hub)
    }

    /// Where to keep the public view up to date. Done before anyone can connect, so it's ready for them.
    pub fn publish_to(&mut self, view: Arc<PublicView>) {
        self.public = Some(view);
        self.publish_view();
    }

    fn publish_view(&self) {
        if let Some(view) = &self.public {
            let city =
                protocol::public_view(&self.world, self.links.world_app_id.as_deref()).to_string();
            let health = json!({
                "ok": true,
                "seq": self.log.seq(),
                "day": self.world.today(),
                "chain": self.world.chain().name(),
                "block": self.world.state.chain.block,
            });
            view.publish(city, health.to_string());
        }
    }

    /// Runs until the connections' side hangs up, which only happens when the process is ending, or the log fails.
    pub fn run(&mut self, from_net: Receiver<ToCity>) -> Result<(), String> {
        let mut last_beat = Instant::now();
        let mut last_presence = Instant::now();
        let mut last_public = Instant::now();
        let mut last_poll = Instant::now();
        loop {
            // Checked first, so a busy stream of messages can't hold the clock back.
            if last_public.elapsed() >= public::REBUILD_EVERY {
                last_public = Instant::now();
                self.publish_view();
            }
            if last_poll.elapsed() >= LEDGER_POLL {
                last_poll = Instant::now();
                self.poll_ledger()?;
            }
            let mut wait = presence::SEND_EVERY.saturating_sub(last_presence.elapsed());
            if wait.is_zero() {
                last_presence = Instant::now();
                self.send_presence();
                wait = presence::SEND_EVERY;
            }
            wait = wait.min(LEDGER_POLL.saturating_sub(last_poll.elapsed()));
            if let Some(beat) = self.options.heartbeat {
                if last_beat.elapsed() >= beat {
                    let elapsed = last_beat.elapsed();
                    last_beat = Instant::now();
                    self.beat(elapsed)?;
                }
                wait = wait.min(beat.saturating_sub(last_beat.elapsed()));
            }
            match from_net.recv_timeout(wait) {
                Ok(message) => self.handle(message)?,
                Err(RecvTimeoutError::Disconnected) => return Ok(()),
                Err(RecvTimeoutError::Timeout) => {}
            }
        }
    }

    /// What the chain did, each as its own logged input. One the world refuses (seen already, or changing nothing)
    /// isn't logged.
    fn poll_ledger(&mut self) -> Result<(), String> {
        if let Some(offline) = &self.links.offline {
            if let Ok(mut ledger) = offline.0.lock() {
                ledger.set_day(self.world.state.real_day());
            }
        }
        // What the chain answers can ask it for more (a finished quest's claim): offline that's answered at once too,
        // so a few rounds settle a whole chain of steps.
        for _ in 0..LEDGER_ROUNDS {
            let observed = self.links.ledger.poll();
            if observed.is_empty() {
                break;
            }
            self.take_observed(observed)?;
        }
        Ok(())
    }

    fn take_observed(&mut self, observed: Vec<Observed>) -> Result<(), String> {
        for o in observed {
            let input = Input::Chain {
                block: o.block,
                log_index: o.log_index,
                time: o.time,
                observed: o.observed,
            };
            match self.try_step(input)? {
                Ok(())
                | Err(Refusal::NothingNew)
                | Err(Refusal::NotOurs)
                | Err(Refusal::AlreadyObserved { .. }) => {}
                Err(refusal) => eprintln!("an observation was refused: {refusal:?}"),
            }
        }
        Ok(())
    }

    fn beat(&mut self, elapsed: Duration) -> Result<(), String> {
        let ms = elapsed.as_millis() as u64 * self.options.speed;
        self.step(Input::Advance { ms })?;
        self.log.sync()?;
        self.send_times();
        self.send_energy_changes();
        Ok(())
    }

    fn handle(&mut self, message: ToCity) -> Result<(), String> {
        match message {
            ToCity::Opened { conn, address, out } => {
                let open = self
                    .clients
                    .values()
                    .filter(|c| c.address == address)
                    .count();
                let allowed = self.limits.connections.allow(&address, Instant::now());
                if !allowed || open >= limits::OPEN_CONNECTIONS_PER_ADDRESS {
                    let _ = out.send(ToClient::Close);
                    return Ok(());
                }
                let client = Client {
                    out,
                    address,
                    player: None,
                    secret: None,
                };
                self.clients.insert(conn, client);
                Ok(())
            }
            ToCity::Text { conn, text } => self.on_text(conn, &text),
            ToCity::Closed { conn } => self.on_closed(conn),
            ToCity::Verified {
                player,
                human_id,
                reply,
            } => {
                let verify = Command::VerifyHuman {
                    account: player.clone(),
                    human_id,
                };
                let answer = match self.apply(Role::Verifier, verify)? {
                    Ok(()) => {
                        // Offline, the name lands at once; give it a moment to be in the answer.
                        self.poll_ledger()?;
                        let ens = self
                            .world
                            .state
                            .life
                            .player(&player)
                            .and_then(|p| p.ens.clone());
                        Ok(ens)
                    }
                    Err(refusal) => {
                        let name = serde_json::to_value(&refusal).ok();
                        let name = name.and_then(|v| v["type"].as_str().map(str::to_string));
                        Err(name.unwrap_or_else(|| format!("{refusal:?}")))
                    }
                };
                let _ = reply.send(answer);
                Ok(())
            }
        }
    }

    fn on_text(&mut self, conn: ConnId, text: &str) -> Result<(), String> {
        // A connection the limits closed can still have a message on its way in.
        if !self.clients.contains_key(&conn) {
            return Ok(());
        }
        let message: ClientMessage = match serde_json::from_str(text) {
            Ok(message) => message,
            Err(e) => {
                self.error(conn, &format!("can't read that: {e}"));
                return Ok(());
            }
        };
        if let ClientMessage::Hello {
            protocol,
            player,
            secret,
        } = message
        {
            return self.on_hello(conn, protocol, player, secret);
        }
        let message = match message {
            ClientMessage::Command {
                reference,
                command: PlayerCommand::ClaimName { name },
            } => return self.on_claim_name(conn, &reference, name),
            other => other,
        };
        let Some(player) = self.clients.get(&conn).and_then(|c| c.player.clone()) else {
            self.error(conn, "say hello first");
            return Ok(());
        };
        match message {
            ClientMessage::Hello { .. } => Ok(()),
            ClientMessage::Profile { name } => {
                self.send(conn, &protocol::profile(&self.world, &name));
                Ok(())
            }
            ClientMessage::Move { x, y, z, yaw, anim } => {
                if anim.len() > presence::MAX_ANIM {
                    self.error(conn, "that anim name is too long");
                    return Ok(());
                }
                let position = Position { x, y, z, yaw, anim };
                self.presence.moved(&player, position);
                Ok(())
            }
            ClientMessage::Command { reference, command } => {
                if reference.is_empty() {
                    self.error(conn, "a command needs a ref");
                    return Ok(());
                }
                if reference.len() > MOST_IN_A_REF {
                    self.error(conn, "that ref is too long");
                    return Ok(());
                }
                if !self.limits.commands.allow(&player, Instant::now()) {
                    self.error(conn, "too many commands: slow down");
                    return Ok(());
                }
                // A question goes in the save, so asking is limited as a name is.
                if matches!(command, PlayerCommand::AskMentor { .. }) {
                    let address = self.clients.get(&conn).map_or("", |c| &c.address);
                    if !self.limits.mentor_questions.allow(address, Instant::now()) {
                        self.error(conn, "too many questions: try again in a minute");
                        return Ok(());
                    }
                }
                if matches!(command, PlayerCommand::TownPass) {
                    let reply = self.town_pass(&player, &reference);
                    self.send(conn, &reply);
                    return Ok(());
                }
                let Some(command) = command.into_command(&player, &reference) else {
                    return Ok(());
                };
                let result = self.apply(Role::Player, command)?;
                let reply = match result {
                    Ok(()) => json!({"type": "result", "ref": reference, "ok": true}),
                    Err(refusal) => {
                        json!({"type": "result", "ref": reference, "ok": false, "refusal": refusal})
                    }
                };
                self.send(conn, &reply);
                // Offline, the chain answers at once: let it, so a meal or a payout lands right after its result.
                if self.links.offline.is_some() {
                    self.poll_ledger()?;
                }
                Ok(())
            }
            ClientMessage::Debug { action } => {
                if !self.options.debug {
                    self.error(conn, "debug is off: start the server with --debug");
                    return Ok(());
                }
                if let Err(problem) = self.on_debug(&player, action)? {
                    self.error(conn, &problem);
                }
                self.send_you(&player);
                self.send(conn, &json!({"type": "debug_done"}));
                Ok(())
            }
        }
    }

    /// A one-time verify link for the Town Pass. Nothing is logged: the link isn't game state.
    fn town_pass(&mut self, player: &str, reference: &str) -> Value {
        match self.world.state.town_pass_check(player) {
            Ok(wallet) => match self.links.verify.open(player, &wallet) {
                Ok(url) => json!({"type": "result", "ref": reference, "ok": true, "url": url}),
                Err(problem) => {
                    eprintln!("no Town Pass link: {problem}");
                    json!({"type": "result", "ref": reference, "ok": false, "refusal": {"type": "TryAgain"}})
                }
            },
            Err(refusal) => {
                json!({"type": "result", "ref": reference, "ok": false, "refusal": refusal})
            }
        }
    }

    fn on_hello(
        &mut self,
        conn: ConnId,
        protocol: u64,
        player: String,
        secret: String,
    ) -> Result<(), String> {
        if protocol != PROTOCOL_VERSION {
            let text = format!("this server speaks protocol {PROTOCOL_VERSION}");
            self.error(conn, &text);
            return Ok(());
        }
        // A connection is one player for its whole life.
        if let Some(existing) = self.clients.get(&conn).and_then(|c| c.player.clone()) {
            if existing != player {
                self.error(conn, "this connection is already someone else");
                return Ok(());
            }
        }
        // No name yet: they'll write it on the ferry ticket. Nothing is written until they do.
        if player.is_empty() {
            if let Err(refusal) = names::check_secret(&secret) {
                self.refuse_hello(conn, &refusal);
                return Ok(());
            }
            if let Some(client) = self.clients.get_mut(&conn) {
                client.secret = Some(secret);
            }
            self.send(conn, &json!({"type": "nameless"}));
            return Ok(());
        }
        if let Err(refusal) = self.take_name(conn, &player, &secret)? {
            self.refuse_hello(conn, &refusal);
            return Ok(());
        }
        self.enter(conn, player)
    }

    /// The ferry ticket: the first act of a new player. Answered like a command.
    fn on_claim_name(&mut self, conn: ConnId, reference: &str, name: String) -> Result<(), String> {
        let Some(client) = self.clients.get(&conn) else {
            return Ok(());
        };
        if let Some(existing) = &client.player {
            if *existing == name {
                self.send(
                    conn,
                    &json!({"type": "result", "ref": reference, "ok": true}),
                );
            } else {
                self.error(conn, "this connection is already someone else");
            }
            return Ok(());
        }
        let Some(secret) = client.secret.clone() else {
            self.error(conn, "say hello first");
            return Ok(());
        };
        match self.take_name(conn, &name, &secret)? {
            Ok(()) => {
                self.enter(conn, name)?;
                self.send(
                    conn,
                    &json!({"type": "result", "ref": reference, "ok": true}),
                );
            }
            Err(refusal) => self.send(
                conn,
                &json!({"type": "result", "ref": reference, "ok": false, "refusal": refusal}),
            ),
        }
        Ok(())
    }

    /// Says whether this secret may be this name, claiming it if it's free. Someone coming back with the right secret
    /// isn't counted against any limit. The outer Result is the log.
    fn take_name(
        &mut self,
        conn: ConnId,
        player: &str,
        secret: &str,
    ) -> Result<Result<(), HelloRefusal>, String> {
        let name = player.to_string();
        let secret_hash = names::hash_secret(player, secret);
        let held = self.world.claim(player).map(str::to_string);
        if names::check_hello(player, secret).is_ok() && held.as_deref() == Some(&secret_hash) {
            return Ok(Ok(()));
        }
        let address = self.clients.get(&conn).map_or("", |c| &c.address);
        let now = Instant::now();
        if !self.limits.name_tries.allow(address, now) {
            return Ok(Err(HelloRefusal::SlowDown));
        }
        if let Err(refusal) = names::check_hello(player, secret) {
            return Ok(Err(refusal));
        }
        if held.is_some() {
            return Ok(Err(HelloRefusal::NameTaken { name }));
        }
        if !self.limits.new_names.allow(address, now) {
            return Ok(Err(HelloRefusal::SlowDown));
        }
        self.step(Input::Claim {
            player: name,
            secret_hash,
        })?;
        Ok(Ok(()))
    }

    /// Puts a player whose name is settled on this connection, and sends them everything.
    fn enter(&mut self, conn: ConnId, player: String) -> Result<(), String> {
        if let Some(old) = self.player_conn.insert(player.clone(), conn) {
            if old != conn {
                if let Some(client) = self.clients.get_mut(&old) {
                    client.player = None;
                    let kicked = json!({"type": "kicked"}).to_string();
                    let _ = client.out.send(ToClient::Text(kicked));
                    let _ = client.out.send(ToClient::Close);
                }
            }
        }
        if let Some(client) = self.clients.get_mut(&conn) {
            client.player = Some(player.clone());
        }
        // Being in the world first, so the snapshot is the truth from then on.
        if !self.world.connected().any(|p| *p == player) {
            self.step(Input::Connect {
                player: player.clone(),
            })?;
        }
        // A new player's wallet comes from the chain; offline it's there at once, and in the snapshot.
        if self.links.offline.is_some() {
            self.poll_ledger()?;
        }
        let you = protocol::you(&self.world, &player);
        if let Some(energy) = you["energy"].as_u64() {
            self.energy_sent.insert(player.clone(), energy as u32);
        }
        let snapshot = json!({
            "type": "snapshot",
            "seq": self.log.seq(),
            "debug": self.options.debug,
            "you": you,
            "city": protocol::city(&self.world),
            "feed": protocol::feed(&self.world),
        });
        self.send(conn, &snapshot);
        self.presence.touch();
        Ok(())
    }

    fn refuse_hello(&self, conn: ConnId, refusal: &HelloRefusal) {
        self.send(conn, &json!({"type": "hello_refused", "refusal": refusal}));
    }

    fn on_closed(&mut self, conn: ConnId) -> Result<(), String> {
        let Some(client) = self.clients.remove(&conn) else {
            return Ok(());
        };
        let Some(player) = client.player else {
            return Ok(());
        };
        if self.player_conn.get(&player) == Some(&conn) {
            self.player_conn.remove(&player);
            self.energy_sent.remove(&player);
            if self.presence.left(&player) {
                self.send_to_everyone(&json!({"type": "left", "name": player}));
            }
            self.step(Input::Disconnect { player })?;
        }
        Ok(())
    }

    /// Rehearsal. The inner Err is something to tell the client; the outer one is the log.
    fn on_debug(
        &mut self,
        player: &str,
        action: DebugAction,
    ) -> Result<Result<(), String>, String> {
        match action {
            DebugAction::Skip { ms } => {
                self.step(Input::Advance { ms })?;
                self.send_times();
                self.send_energy_changes();
            }
            DebugAction::NextSeason => self.step(Input::NextSeason)?,
            DebugAction::ReadyChest => {
                let ready = Command::ReadyChest {
                    account: player.to_string(),
                };
                if let Err(refusal) = self.apply(Role::Clock, ready)? {
                    return Ok(Err(format!("{refusal:?}")));
                }
            }
            DebugAction::Fund { usdc } => {
                return self.rehearse_offline(|ledger| ledger.fund(player, usdc));
            }
            DebugAction::FundBucket { bucket, usdc } => {
                return self.rehearse_offline(|ledger| Ok(ledger.fund_bucket(bucket, usdc)));
            }
            DebugAction::NewCampaign {
                template,
                payout,
                energy,
                slots,
                boosted,
            } => {
                let campaign = OfflineCampaign {
                    template,
                    sponsor: format!("rehearsal sponsor {player}"),
                    budget: payout.saturating_mul(u64::from(slots)) / 9 * 10 + 10,
                    payout_per_claim: payout,
                    energy_cost: energy,
                    max_claims: slots,
                    per_human_cap: 1,
                    days: 7,
                    kind: u8::from(boosted),
                };
                return self.rehearse_offline(|ledger| ledger.open_campaign(&campaign));
            }
            DebugAction::PassTown => {
                let wallet = match self.world.state.town_pass_check(player) {
                    Ok(wallet) => wallet,
                    Err(refusal) => return Ok(Err(format!("{refusal:?}"))),
                };
                let human_id = match self
                    .links
                    .verifier
                    .verify(&wallet, &json!({"offline": true}))
                {
                    Ok(id) => id,
                    Err(problem) => return Ok(Err(problem)),
                };
                let verify = Command::VerifyHuman {
                    account: player.to_string(),
                    human_id,
                };
                if let Err(refusal) = self.apply(Role::Verifier, verify)? {
                    return Ok(Err(format!("{refusal:?}")));
                }
                self.poll_ledger()?;
            }
        }
        Ok(Ok(()))
    }

    /// Runs a rehearsal against the offline chain, and takes what it says happened like any observation.
    fn rehearse_offline(
        &mut self,
        act: impl FnOnce(&mut OfflineLedger) -> Result<Vec<Observation>, String>,
    ) -> Result<Result<(), String>, String> {
        let Some(offline) = self.links.offline.clone() else {
            return Ok(Err(
                "that rehearsal is for an offline server only".to_string()
            ));
        };
        let observed = {
            let Ok(mut ledger) = offline.0.lock() else {
                return Ok(Err("the offline ledger broke".to_string()));
            };
            match act(&mut ledger) {
                Ok(observations) => ledger.stamp(observations),
                Err(problem) => return Ok(Err(problem)),
            }
        };
        self.take_observed(observed)?;
        self.poll_ledger()?;
        Ok(Ok(()))
    }

    /// One command through the rules. The outer Result is the log; the inner one is the rules' answer.
    fn apply(&mut self, by: Role, command: Command) -> Result<Result<(), Refusal>, String> {
        self.try_step(Input::Command { by, command })
    }

    /// One input that may be refused. A refusal changes nothing and isn't logged.
    fn try_step(&mut self, input: Input) -> Result<Result<(), Refusal>, String> {
        match self.world.step(input.clone()) {
            Ok(events) => {
                self.record(&input, events)?;
                Ok(Ok(()))
            }
            Err(refusal) => Ok(Err(refusal)),
        }
    }

    /// An input that can't be refused.
    fn step(&mut self, input: Input) -> Result<(), String> {
        let events = self
            .world
            .step(input.clone())
            .map_err(|refusal| format!("the clock was refused: {refusal:?}"))?;
        self.record(&input, events)
    }

    /// The log comes first: nothing is told to anyone, or asked of the chain, until it's in the save.
    fn record(&mut self, input: &Input, events: Vec<Event>) -> Result<(), String> {
        let seq = self.log.append(input, &events)?;
        self.report_agent_refusals();
        for event in &events {
            if let Event::Intent { intent } = event {
                self.links.ledger.submit(intent.clone());
            }
        }
        self.send_events(seq, &events);
        self.commit_due_draw()
    }

    /// A closed week's draw needs a seed nobody could guess: drawn here from the operating system, and logged, so a
    /// replay commits the same one. Only its hash goes to the chain until the reveal.
    fn commit_due_draw(&mut self) -> Result<(), String> {
        let Some(week) = self.world.draw_due() else {
            return Ok(());
        };
        let seed = format!("0x{}", hex(&random_bytes(32)?));
        let seed_hash = keccak_of_hex(&seed).ok_or("a seed that isn't hex")?;
        let commit = Command::CommitDraw {
            week,
            seed,
            seed_hash,
        };
        match self.apply(Role::Clock, commit)? {
            Ok(()) => Ok(()),
            Err(refusal) => Err(format!("the draw was refused: {refusal:?}")),
        }
    }

    fn report_agent_refusals(&mut self) {
        for refusal in &self.world.town.refusals[self.agent_refusals_seen..] {
            eprintln!("an agent was refused: {refusal:?}");
        }
        self.agent_refusals_seen = self.world.town.refusals.len();
    }

    fn send_presence(&mut self) {
        let state = &self.world.state;
        let residents = self.world.town.whereabouts(self.world.city_ms);
        if let Some(message) = self
            .presence
            .take_message(residents, |name| state.title(name))
        {
            self.send_to_everyone(&message);
        }
    }

    /// Sends each event to whoever it's for, then fresh numbers to anyone they changed for. Intents never leave.
    fn send_events(&mut self, seq: u64, events: &[Event]) {
        let mut changed = BTreeSet::new();
        let mut city_changed = false;
        for event in events {
            if protocol::is_internal(event) {
                continue;
            }
            let message = json!({"type": "event", "seq": seq, "event": event});
            let names = protocol::named_in(event).unwrap_or_default();
            if protocol::is_public(event) {
                city_changed = true;
                self.send_to_everyone(&message);
            } else {
                for name in &names {
                    self.send_to_player(name, &message);
                }
            }
            city_changed |= protocol::changes_city(event);
            changed.extend(names);
        }
        // A new season clears everyone's ranks.
        if events
            .iter()
            .any(|e| matches!(e, Event::SeasonChanged { .. }))
        {
            changed.extend(self.player_conn.keys().cloned());
        }
        // Anyone not connected is in here too, and nobody is listening for them.
        changed.retain(|name| self.player_conn.contains_key(name));
        for name in &changed {
            self.send_you(name);
        }
        // A title can change with any of those.
        if !changed.is_empty() {
            self.presence.touch();
        }
        if city_changed {
            self.send_to_everyone(&json!({"type": "city", "city": protocol::city(&self.world)}));
        }
    }

    fn send_you(&mut self, name: &str) {
        let you = protocol::you(&self.world, name);
        if let Some(energy) = you["energy"].as_u64() {
            self.energy_sent.insert(name.to_string(), energy as u32);
        }
        self.send_to_player(name, &json!({"type": "you", "you": you}));
    }

    /// Energy comes back by itself below the line, with no event. Whoever's changed hears.
    fn send_energy_changes(&mut self) {
        let now = self.world.state.now_ms;
        let energy = self.world.state.config.energy;
        let changed: Vec<String> = self
            .player_conn
            .keys()
            .filter(|name| {
                let current = self
                    .world
                    .state
                    .life
                    .player(name)
                    .map(|p| p.energy_now(now, &energy));
                current.is_some() && current != self.energy_sent.get(*name).copied()
            })
            .cloned()
            .collect();
        for name in changed {
            self.send_you(&name);
        }
    }

    fn send_times(&self) {
        for name in self.player_conn.keys() {
            self.send_to_player(name, &protocol::time(&self.world));
        }
    }

    fn send_to_player(&self, name: &str, message: &Value) {
        if let Some(conn) = self.player_conn.get(name) {
            self.send(*conn, message);
        }
    }

    fn send_to_everyone(&self, message: &Value) {
        for conn in self.player_conn.values() {
            self.send(*conn, message);
        }
    }

    fn error(&self, conn: ConnId, text: &str) {
        self.send(conn, &json!({"type": "error", "message": text}));
    }

    fn send(&self, conn: ConnId, message: &Value) {
        if let Some(client) = self.clients.get(&conn) {
            let _ = client.out.send(ToClient::Text(message.to_string()));
        }
    }
}
