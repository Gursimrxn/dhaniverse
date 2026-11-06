//! The whole city as one value: the rules' state, the town's agents and the clock. It changes only through `step`,
//! and only by what it's told, so the same inputs always rebuild the same world. That's what makes the log a save.

use crate::boards::{self, BOARDS};
use crate::feed::{self, Fact};
use crate::seasons::Season;
use agents::{Town, TownConfig};
use rules::chain::{ChainMode, Observation};
use rules::{apply, AccountId, Command, Config, Event, QuestBook, Refusal, Role, State};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

/// The quest book a city starts with unless told otherwise.
pub const DEFAULT_QUESTS: &str = include_str!("../../../quests.toml");

/// What a city starts from, all of it kept in the save's first line: its rules, its quest book, its seed, and where
/// its money settles.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Setup {
    pub seed: u64,
    pub rules: String,
    #[serde(default = "default_quests")]
    pub quests: String,
    #[serde(default)]
    pub chain: ChainMode,
    /// Every ref this town sends to the chain starts with this, so towns sharing a chain never mix theirs up. Chosen
    /// at random when the save is made; empty means none.
    #[serde(default)]
    pub town_id: String,
}

fn default_quests() -> String {
    DEFAULT_QUESTS.to_string()
}

impl Setup {
    /// An offline city with the default quest book.
    pub fn offline(rules: &str, seed: u64) -> Self {
        Setup {
            seed,
            rules: rules.to_string(),
            quests: default_quests(),
            chain: ChainMode::Offline,
            town_id: String::new(),
        }
    }
}

/// Whether this can change who's ahead. Boards aren't worked out for anything else, since most events can't.
fn moves_a_board(event: &Event) -> bool {
    matches!(event, Event::RushEnded { .. })
}

/// Everything that can happen to the world from outside. Time is an input like any other.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum Input {
    /// A name is taken for good by the secret that first said it. Only the hash is ever kept.
    Claim {
        player: AccountId,
        secret_hash: String,
    },
    Connect {
        player: AccountId,
    },
    Disconnect {
        player: AccountId,
    },
    Command {
        by: Role,
        command: Command,
    },
    Advance {
        ms: u64,
    },
    /// A new season: from the calendar, or a rehearsal.
    NextSeason,
    /// Something the chain did, where it happened. `time` is the block's unix seconds, 0 if unknown.
    Chain {
        block: u64,
        log_index: u64,
        #[serde(default)]
        time: u64,
        observed: Observation,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct World {
    /// The rules.toml the city started with, for the parts read outside the rules, such as the offline ledger's.
    pub rules_toml: String,
    pub state: State,
    pub town: Town,
    pub city_ms: u64,
    next_slice: u64,
    connected: BTreeSet<AccountId>,
    claims: BTreeMap<AccountId, String>,
    pub season: Season,
    leaders: BTreeMap<&'static str, AccountId>,
    /// The last day the feed said Kofi was short, so it says so once a day.
    short_of_food_day: Option<u64>,
    /// Each player's count of city days seen, and the last one.
    days_active: BTreeMap<AccountId, (u64, u64)>,
}

impl World {
    /// A new offline city from the text of rules.toml, with the default quest book. Its morning has already happened.
    pub fn new(rules_toml: &str, seed: u64) -> Result<Self, String> {
        Self::start(&Setup::offline(rules_toml, seed))
    }

    /// A new city. Its morning has already happened.
    pub fn start(setup: &Setup) -> Result<Self, String> {
        let config: Config =
            toml::from_str(&setup.rules).map_err(|e| format!("rules.toml: {e}"))?;
        let town: TownConfig =
            toml::from_str(&setup.rules).map_err(|e| format!("rules.toml: {e}"))?;
        let book: QuestBook =
            toml::from_str(&setup.quests).map_err(|e| format!("quests.toml: {e}"))?;
        let mut state = State::with(&config, book, setup.seed, setup.chain)
            .map_err(|r| format!("rules.toml or quests.toml: {r:?}"))?;
        state.town_id = setup.town_id.clone();
        let on_chain = setup.chain.on_chain();
        let mut world = World {
            rules_toml: setup.rules.clone(),
            town: Town::new(town, &config.food, &config.menu, setup.seed, on_chain),
            state,
            city_ms: 0,
            next_slice: 0,
            connected: BTreeSet::new(),
            claims: BTreeMap::new(),
            season: Season::first(),
            leaders: BTreeMap::new(),
            short_of_food_day: None,
            days_active: BTreeMap::new(),
        };
        world.advance(0);
        Ok(world)
    }

    /// Takes one input. A refusal changes nothing.
    pub fn step(&mut self, input: Input) -> Result<Vec<Event>, Refusal> {
        let mut events = self.take_input(input)?;
        self.season.observe(&events);
        self.post_to_feed(&mut events);
        let said = self.town.mentor_speaks(&mut self.state, &events);
        events.extend(said);
        Ok(events)
    }

    fn take_input(&mut self, input: Input) -> Result<Vec<Event>, Refusal> {
        match input {
            Input::Claim {
                player,
                secret_hash,
            } => {
                self.claims.insert(player, secret_hash);
                Ok(Vec::new())
            }
            Input::Connect { player } => Ok(self.connect(player)),
            Input::Disconnect { player } => Ok(self.disconnect(player)),
            Input::Command { by, command } => {
                let events = apply(&mut self.state, by, command)?;
                self.town.observe(&events);
                Ok(events)
            }
            Input::Advance { ms } => Ok(self.advance(ms)),
            Input::NextSeason => Ok(self.next_season()),
            Input::Chain {
                block,
                log_index,
                time,
                observed,
            } => {
                let observe = Command::Observe {
                    block,
                    log_index,
                    time,
                    observed,
                };
                let events = apply(&mut self.state, Role::Chain, observe)?;
                self.town.observe(&events);
                Ok(events)
            }
        }
    }

    /// The feed, from what these events say and from any change of leader. Posts go through the rules like anything else.
    fn post_to_feed(&mut self, events: &mut Vec<Event>) {
        let mut facts: Vec<Fact> = Vec::new();
        for event in events.iter() {
            match feed::read(event) {
                Some(Fact::ShortOfFood) => {
                    let today = Some(self.today());
                    if self.short_of_food_day != today {
                        self.short_of_food_day = today;
                        facts.push(Fact::ShortOfFood);
                    }
                }
                Some(fact) => facts.push(fact),
                None => {}
            }
        }
        if events.iter().any(moves_a_board) {
            facts.extend(self.new_leaders());
        }
        for fact in &facts {
            let words = feed::write(fact);
            let post = Command::PublishPost {
                kind: words.kind.to_string(),
                text: words.text,
                about: words.about,
            };
            events.extend(apply(&mut self.state, Role::Tally, post).unwrap_or_default());
        }
    }

    fn new_leaders(&mut self) -> Vec<Fact> {
        let standings = self.boards();
        let mut facts = Vec::new();
        for board in BOARDS {
            let Some(leader) = standings.get(board).and_then(|names| names.first()) else {
                self.leaders.remove(board);
                continue;
            };
            if self.leaders.get(board) != Some(leader) {
                self.leaders.insert(board, leader.clone());
                facts.push(Fact::NewLeader {
                    account: leader.clone(),
                    board,
                });
            }
        }
        facts
    }

    /// The season's standings, best first. Scores never leave `boards`.
    pub fn boards(&self) -> BTreeMap<&'static str, Vec<AccountId>> {
        boards::standings(&self.state, &self.season)
    }

    /// City days this player has been around for.
    pub fn days_active(&self, player: &str) -> u64 {
        self.days_active.get(player).map_or(0, |(count, _)| *count)
    }

    fn note_active(&mut self, player: &AccountId) {
        let today = self.today();
        let seen = self
            .days_active
            .entry(player.clone())
            .or_insert((0, u64::MAX));
        if seen.1 != today {
            *seen = (seen.0 + 1, today);
        }
    }

    /// The boards start over, and the town hears about it. Names and firsts stay.
    fn next_season(&mut self) -> Vec<Event> {
        let number = self.season.number + 1;
        self.season = self.season.next(self.town.shock_for(number));
        self.leaders.clear();
        self.town.start_season(&mut self.state, number)
    }

    /// The hash that holds this name, if anyone has claimed it.
    pub fn claim(&self, player: &str) -> Option<&str> {
        self.claims.get(player).map(String::as_str)
    }

    pub fn connected(&self) -> impl Iterator<Item = &AccountId> {
        self.connected.iter()
    }

    pub fn today(&self) -> u64 {
        self.city_ms / self.town.city().day_ms
    }

    pub fn day_elapsed_ms(&self) -> u64 {
        self.city_ms % self.town.city().day_ms
    }

    /// A closed week waiting for the server to draw its seed.
    pub fn draw_due(&self) -> Option<u64> {
        self.state.games.draw_due
    }

    pub fn chain(&self) -> ChainMode {
        self.state.mode
    }

    fn connect(&mut self, player: AccountId) -> Vec<Event> {
        let mut events = Vec::new();
        if self.state.life.player(&player).is_none() {
            let arrive = Command::Arrive {
                account: player.clone(),
            };
            events.extend(apply(&mut self.state, Role::Player, arrive).unwrap_or_default());
        }
        let login = Command::Login {
            account: player.clone(),
        };
        events.extend(apply(&mut self.state, Role::Player, login).unwrap_or_default());
        self.note_active(&player);
        self.connected.insert(player);
        events
    }

    /// Logging off walks them away from the stall, which ends any Rush run.
    fn disconnect(&mut self, player: AccountId) -> Vec<Event> {
        self.connected.remove(&player);
        let end = Command::EndRush { account: player };
        apply(&mut self.state, Role::Player, end).unwrap_or_default()
    }

    /// Moves time on, stopping at each trading slice in order, so a long skip plays out exactly as if the time had
    /// passed. The real clock's timers run at each stop too.
    fn advance(&mut self, ms: u64) -> Vec<Event> {
        let city = self.town.city();
        let slice_ms = city.day_ms / city.slices_per_day;
        let target = self.city_ms + ms;
        let mut events = Vec::new();
        loop {
            let next_slice_at = self.next_slice * slice_ms;
            if next_slice_at > target {
                break;
            }
            self.city_ms = next_slice_at;
            events.extend(self.tick());
            events.extend(self.run_slice());
        }
        self.city_ms = target;
        events.extend(self.tick());
        events
    }

    fn tick(&mut self) -> Vec<Event> {
        let tick = Command::Tick {
            now_ms: self.city_ms,
        };
        let events = apply(&mut self.state, Role::Clock, tick).unwrap_or_default();
        self.town.observe(&events);
        events
    }

    fn run_slice(&mut self) -> Vec<Event> {
        let slices = self.town.city().slices_per_day;
        let (day, slice) = (self.next_slice / slices, self.next_slice % slices);
        self.next_slice += 1;
        let mut events = Vec::new();
        let season_days = self.town.config().seasons.season_days;
        if slice == 0 && day > 0 && day % season_days.max(1) == 0 {
            events.extend(self.next_season());
        }
        if slice == 0 {
            events.extend(self.town.start_day(&mut self.state, day));
            let here: Vec<AccountId> = self.connected.iter().cloned().collect();
            for player in &here {
                self.note_active(player);
            }
        }
        events.extend(self.town.run_slice(&mut self.state, day, slice));
        events
    }
}
