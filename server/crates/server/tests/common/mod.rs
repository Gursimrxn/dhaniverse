//! A real server binary and a real WebSocket client, for the tests that talk to the server the way Godot does.
#![allow(dead_code)] // each test file uses its own part of this

use serde_json::{json, Value};
use std::io::{BufRead, BufReader};
use std::net::TcpStream;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::time::Duration;
use tungstenite::stream::MaybeTlsStream;
use tungstenite::{connect, Message, WebSocket};

pub const RULES: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../rules.toml");

/// A running server. It's killed when dropped, the way a crash would stop it.
pub struct Server {
    pub child: Child,
    pub addr: String,
}

impl Server {
    pub fn start(save: &PathBuf, extra: &[&str]) -> Server {
        let mut child = Command::new(env!("CARGO_BIN_EXE_server"))
            .args(["--addr", "127.0.0.1:0", "--debug", "--rules", RULES])
            .arg("--save")
            .arg(save)
            .args(extra)
            .stdout(Stdio::piped())
            .spawn()
            .expect("the server starts");
        let mut reader = BufReader::new(child.stdout.take().unwrap());
        let mut line = String::new();
        reader.read_line(&mut line).unwrap();
        // A demo city says what it played before it says where it's listening.
        if line.starts_with("played") {
            line.clear();
            reader.read_line(&mut line).unwrap();
        }
        let addr = line
            .trim()
            .strip_prefix("listening on ")
            .unwrap_or_else(|| panic!("said: {line}"))
            .to_string();
        Server { child, addr }
    }
}

impl Drop for Server {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

pub struct Client {
    pub socket: WebSocket<MaybeTlsStream<TcpStream>>,
    /// Everything received but not yet asked for.
    pub inbox: Vec<Value>,
    pub refs: u64,
}

impl Client {
    pub fn connect(addr: &str) -> Client {
        let (socket, _) = connect(format!("ws://{addr}")).expect("the socket opens");
        if let MaybeTlsStream::Plain(stream) = socket.get_ref() {
            stream
                .set_read_timeout(Some(Duration::from_secs(20)))
                .unwrap();
        }
        Client {
            socket,
            inbox: Vec::new(),
            refs: 0,
        }
    }

    pub fn send(&mut self, message: Value) {
        self.socket
            .send(Message::text(message.to_string()))
            .unwrap();
    }

    pub fn read(&mut self) -> Value {
        loop {
            match self.socket.read().expect("a message") {
                Message::Text(text) => return serde_json::from_str(text.as_str()).unwrap(),
                Message::Close(_) => return json!({"type": "closed"}),
                _ => {}
            }
        }
    }

    /// Reads until a message of this type, keeping everything before it.
    pub fn until(&mut self, kind: &str) -> Value {
        loop {
            let message = self.read();
            if message["type"] == kind {
                return message;
            }
            self.inbox.push(message);
        }
    }

    pub fn hello(&mut self, player: &str) -> Value {
        let secret = format!("test-secret-of-{player}");
        self.send(json!({"type": "hello", "protocol": 3, "player": player, "secret": secret}));
        self.until("snapshot")
    }

    pub fn command(&mut self, command: Value) -> Value {
        self.refs += 1;
        let reference = format!("c{}", self.refs);
        self.send(json!({"type": "command", "ref": reference, "command": command}));
        let result = self.until("result");
        assert_eq!(result["ref"], reference.as_str());
        result
    }

    pub fn must(&mut self, command: Value) {
        let what = command.clone();
        let result = self.command(command);
        assert_eq!(result["ok"], true, "{what}: {result}");
        println!("  ok: {what}");
    }

    pub fn debug(&mut self, action: Value) {
        self.send(json!({"type": "debug", "action": action}));
        self.until("debug_done");
    }

    /// A meal bought for real, offline: USDC from the rehearsal faucet, a little hunger from a dropped errand, a meal
    /// ticket, and the offline chain eating it. Returns the `MealEaten` event.
    pub fn meal(&mut self, item: &str) -> Value {
        self.debug(json!({"type": "Fund", "usdc": 1_000_000}));
        let errand = json!({"type": "TakeQuest", "quest": "errand:chai_round"});
        if self.command(errand)["ok"] == true {
            self.must(json!({"type": "AbandonQuest", "quest": "errand:chai_round"}));
        }
        self.must(json!({"type": "BuyMeal", "item": item}));
        loop {
            let message = self.read();
            if message["type"] == "event" && message["event"]["type"] == "MealEaten" {
                let event = message["event"].clone();
                self.inbox.push(message);
                // Whatever the meal also caused comes before the answer to this.
                self.send(json!({"type": "profile", "name": "nobody"}));
                self.until("profile");
                return event;
            }
            self.inbox.push(message);
        }
    }

    /// The events received since the last call, by name.
    pub fn take_events(&mut self) -> Vec<Value> {
        let inbox = std::mem::take(&mut self.inbox);
        inbox
            .into_iter()
            .filter(|m| m["type"] == "event")
            .map(|m| m["event"].clone())
            .collect()
    }

    /// The latest `you` received.
    pub fn latest_you(&self) -> Value {
        let found = self.inbox.iter().rev().find(|m| m["type"] == "you");
        found.expect("a you message")["you"].clone()
    }
}

pub fn fresh_save(name: &str) -> PathBuf {
    let path = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join(format!("{name}.jsonl"));
    let _ = std::fs::remove_file(&path);
    path
}

pub fn find<'a>(events: &'a [Value], name: &str) -> &'a Value {
    events
        .iter()
        .find(|e| e["type"] == name)
        .unwrap_or_else(|| panic!("no {name} in {events:#?}"))
}

// ---------------------------------------------------------------- a world with a chain told by hand

use rules::chain::{Observation, NOT_A_LOG};
use rules::{Command as RulesCommand, Event, Role};
use server::world::{Input, World as City};

/// Something the chain did, in the block after the last one the world saw.
pub fn observe(world: &mut City, observed: Observation) -> Result<Vec<Event>, rules::Refusal> {
    let log_index = match observed {
        Observation::Balances { .. }
        | Observation::WalletReady { .. }
        | Observation::PoolBalances { .. } => NOT_A_LOG,
        _ => 0,
    };
    let block = world.state.chain.block + 1;
    world.step(Input::Chain {
        block,
        log_index,
        time: 0,
        observed,
    })
}

/// The inputs that bring energy down to `to`: a quest costing the difference, taken and dropped. `block` is the next
/// block to use, moved on.
pub fn drain_inputs(world: &City, account: &str, to: u32, block: &mut u64) -> Vec<Input> {
    let now = world.state.now_ms;
    let energy = world.state.config.energy;
    let have = world
        .state
        .life
        .player(account)
        .unwrap()
        .energy_now(now, &energy);
    if have <= to {
        return Vec::new();
    }
    let id = 80_000 + *block;
    let created = Input::Chain {
        block: *block,
        log_index: 0,
        time: 0,
        observed: Observation::CampaignCreated {
            id,
            sponsor: "0xtest".into(),
            template: "paint_sign".into(),
            meta_hash: String::new(),
            budget: 1_000_000,
            payout_per_claim: 1_000_000,
            energy_cost: have - to,
            max_claims: 10,
            per_human_cap: 10,
            start: 0,
            end: u64::MAX,
            kind: 0,
            deliver_to: "0xtest".into(),
        },
    };
    *block += 1;
    let quest = format!("campaign:{id}");
    let take = RulesCommand::TakeQuest {
        account: account.into(),
        quest: quest.clone(),
    };
    let drop = RulesCommand::AbandonQuest {
        account: account.into(),
        quest,
    };
    vec![
        created,
        Input::Command {
            by: Role::Player,
            command: take,
        },
        Input::Command {
            by: Role::Player,
            command: drop,
        },
    ]
}

pub fn drain(world: &mut City, account: &str, to: u32) {
    let mut block = world.state.chain.block + 1;
    for input in drain_inputs(world, account, to, &mut block) {
        world.step(input).unwrap();
    }
}

/// The inputs of a meal bought and eaten on chain at this price, the honest way: a wallet, some USDC, hunger, a
/// ticket, and the chain's word that it was eaten.
pub fn meal_inputs(
    world: &City,
    account: &str,
    item: &str,
    usdc: u64,
    reference: &str,
) -> Vec<Input> {
    let player = world.state.life.player(account).expect("arrived");
    let mut block = world.state.chain.block + 1;
    let mut inputs = Vec::new();
    let chain = |observed, inputs: &mut Vec<Input>, block: &mut u64| {
        inputs.push(Input::Chain {
            block: *block,
            log_index: NOT_A_LOG,
            time: 0,
            observed,
        });
        *block += 1;
    };
    if player.wallet.is_none() {
        let ready = Observation::WalletReady {
            player: account.into(),
            address: format!("0x{account}"),
        };
        chain(ready, &mut inputs, &mut block);
    }
    if player.usdc != Some(1_000_000) {
        chain(
            Observation::Balances {
                player: account.into(),
                usdc: 1_000_000,
            },
            &mut inputs,
            &mut block,
        );
    }
    inputs.extend(drain_inputs(world, account, 20, &mut block));
    let buy = RulesCommand::BuyMeal {
        account: account.into(),
        item: item.into(),
        voucher: false,
        reference: reference.into(),
    };
    inputs.push(Input::Command {
        by: Role::Player,
        command: buy,
    });
    let food = world.state.menu_item(item).unwrap().food;
    inputs.push(Input::Chain {
        block,
        log_index: 0,
        time: 0,
        observed: Observation::MealEaten {
            player: account.into(),
            item: item.into(),
            usdc,
            food,
            from_ration: 0,
            // The chain speaks in the town's refs.
            reference: world.state.chain_ref(reference),
            tx: "0xtx".into(),
        },
    });
    inputs
}

/// A meal bought and eaten, as `meal_inputs`. Returns the events of its eating.
pub fn eat(world: &mut City, account: &str, item: &str, usdc: u64, reference: &str) -> Vec<Event> {
    let mut last = Vec::new();
    for input in meal_inputs(world, account, item, usdc, reference) {
        last = world.step(input).unwrap();
    }
    last
}
