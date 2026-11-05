//! A test town: the shipped rules.toml and quests.toml, with the food market the contracts' tests build (launch prices
//! of an index of 1.00 and a 5,000 FOOD pool), Sam and Priya arrived with wallets, and a chain that's told by hand.
#![allow(dead_code)] // each test file uses its own part of this

use rules::chain::{HumanId, Intent, Observation};
use rules::{apply, ChainMode, Command, Config, Event, FoodConfig, QuestBook, Refusal, State};

pub const RULES: &str = include_str!("../../../../rules.toml");
pub const QUESTS: &str = include_str!("../../../../quests.toml");
pub const MINUTE: u64 = 60_000;
pub const HOUR: u64 = 60 * MINUTE;
pub const DAY: u64 = 24 * HOUR;
pub const USDC: u64 = 1_000_000;

/// USDC base units: 1 USDC is 1,000,000.
pub const fn usdc_cents(n: u64) -> u64 {
    n * 10_000
}

pub const fn food(n: u64) -> u64 {
    n * 1_000_000
}

/// The shipped numbers, with the contracts' test market (prices about 1,000 a FOOD, 5% a day).
pub fn config() -> Config {
    let mut config: Config = toml::from_str(RULES).unwrap();
    config.food = FoodConfig {
        base_price: 1000,
        start_price: 1000,
        floor: 500,
        ceiling: 3000,
        band_bps: 500,
        pool_food: 5000,
    };
    config.social.emotes = vec!["clap".into(), "wow".into()];
    config
}

pub fn book() -> QuestBook {
    toml::from_str(QUESTS).unwrap()
}

/// A test world, plus counters so every helper call gets a fresh ref and block.
pub struct World {
    pub state: State,
    refs: u64,
    block: u64,
    drains: u64,
}

impl World {
    pub fn new() -> Self {
        Self::with(config())
    }

    /// Sam and Priya have arrived, and have wallets with nothing in them.
    pub fn with(config: Config) -> Self {
        let state = State::with(&config, book(), 7, ChainMode::Offline).unwrap();
        let mut w = World {
            state,
            refs: 0,
            block: 0,
            drains: 0,
        };
        for account in ["sam", "priya"] {
            w.arrive(account);
        }
        w
    }

    pub fn arrive(&mut self, account: &str) -> Vec<Event> {
        let mut events = self
            .run(Command::Arrive {
                account: account.into(),
            })
            .unwrap();
        events.extend(
            self.run(Command::Login {
                account: account.into(),
            })
            .unwrap(),
        );
        self.observe(Observation::WalletReady {
            player: account.into(),
            address: format!("0x{account}"),
        })
        .unwrap();
        self.observe(Observation::Balances {
            player: account.into(),
            usdc: 0,
        })
        .unwrap();
        events
    }

    /// Sends a batch of FOOD to the pool. Returns (bought, paid).
    pub fn buy_food(&mut self, wanted: u64) -> (u64, u64) {
        let reference = self.fresh_ref();
        let events = self.run(Command::BuyFood { wanted, reference }).unwrap();
        match events.last() {
            Some(Event::FoodBought {
                bought, usdc_paid, ..
            }) => (*bought, *usdc_paid),
            other => panic!("expected FoodBought, got {other:?}"),
        }
    }

    pub fn fresh_ref(&mut self) -> String {
        self.refs += 1;
        format!("test ref {}", self.refs)
    }

    /// Applies a command as the role it needs.
    pub fn run(&mut self, command: Command) -> Result<Vec<Event>, Refusal> {
        let role = command.role();
        apply(&mut self.state, role, command)
    }

    /// Something the chain did, in the next block.
    pub fn observe(&mut self, observed: Observation) -> Result<Vec<Event>, Refusal> {
        self.block += 1;
        self.run(Command::Observe {
            block: self.block,
            log_index: 0,
            time: 0,
            observed,
        })
    }

    /// The real clock, to this moment.
    pub fn at(&mut self, now_ms: u64) -> Vec<Event> {
        self.run(Command::Tick { now_ms }).unwrap()
    }

    pub fn later(&mut self, ms: u64) -> Vec<Event> {
        let now = self.state.now_ms + ms;
        self.at(now)
    }

    pub fn fund(&mut self, account: &str, usdc: u64) {
        let _ = self.observe(Observation::Balances {
            player: account.into(),
            usdc,
        });
    }

    pub fn human(account: &str) -> HumanId {
        HumanId(format!("0x{account}-human"))
    }

    pub fn verify(&mut self, account: &str) -> Vec<Event> {
        self.run(Command::VerifyHuman {
            account: account.into(),
            human_id: Self::human(account),
        })
        .unwrap()
    }

    /// HousePool with these balances, each with 4% of itself left to pay today.
    pub fn pools(&mut self, fixed: u64, surprise: u64, safety: u64) -> Vec<Event> {
        self.observe(Observation::PoolBalances {
            fixed,
            surprise,
            safety,
            budget_fixed: fixed / 25,
            budget_surprise: surprise / 25,
            budget_safety: safety / 25,
        })
        .unwrap()
    }

    pub fn energy(&self, account: &str) -> u32 {
        let p = self.state.life.player(account).unwrap();
        p.energy_now(self.state.now_ms, &self.state.config.energy)
    }

    pub fn player(&self, account: &str) -> &rules::life::Player {
        self.state.life.player(account).unwrap()
    }

    /// Spends energy down to `to`, by taking and dropping a quest that costs exactly that much: the honest way to get
    /// hungry in a test.
    pub fn set_energy(&mut self, account: &str, to: u32) {
        let have = self.energy(account);
        assert!(have >= to, "{account} has only {have}");
        if have == to {
            return;
        }
        self.drains += 1;
        let id = 9000 + self.drains;
        self.observe(Observation::CampaignCreated {
            id,
            sponsor: "0xtest".into(),
            template: "paint_sign".into(),
            meta_hash: String::new(),
            budget: USDC,
            payout_per_claim: USDC,
            energy_cost: have - to,
            max_claims: 10,
            per_human_cap: 10,
            start: 0,
            end: u64::MAX,
            kind: 0,
            deliver_to: "0xtest".into(),
        })
        .unwrap();
        let quest = format!("campaign:{id}");
        self.run(Command::TakeQuest {
            account: account.into(),
            quest: quest.clone(),
        })
        .unwrap();
        self.run(Command::AbandonQuest {
            account: account.into(),
            quest,
        })
        .unwrap();
        assert_eq!(self.energy(account), to);
    }
}

/// The intents among these events.
pub fn intents(events: &[Event]) -> Vec<Intent> {
    events
        .iter()
        .filter_map(|e| match e {
            Event::Intent { intent } => Some(intent.clone()),
            _ => None,
        })
        .collect()
}

/// These events without the intents, for comparing what a client would see.
pub fn seen(events: &[Event]) -> Vec<Event> {
    events
        .iter()
        .filter(|e| !matches!(e, Event::Intent { .. }))
        .cloned()
        .collect()
}

/// A tiny repeatable generator, so the property tests below replay the same way every run.
pub struct Rand(pub u64);

impl Rand {
    pub fn below(&mut self, n: u64) -> u64 {
        self.0 = self
            .0
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        (self.0 >> 33) % n
    }
}
