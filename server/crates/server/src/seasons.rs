//! The season: what the boards measure. A new one clears the rankings and leaves names and firsts alone.

use rules::{AccountId, Event};
use std::collections::BTreeMap;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Season {
    pub number: u32,
    pub shock: String,
    /// Each player's best Market Rush run this season, in orders served.
    best_run: BTreeMap<AccountId, u32>,
}

impl Season {
    pub fn first() -> Self {
        Season {
            number: 1,
            shock: String::new(),
            best_run: BTreeMap::new(),
        }
    }

    /// The next season, with everyone starting level.
    pub fn next(&self, shock: String) -> Self {
        Season {
            number: self.number + 1,
            shock,
            best_run: BTreeMap::new(),
        }
    }

    pub fn observe(&mut self, events: &[Event]) {
        for event in events {
            if let Event::RushEnded { account, served } = event {
                let best = self.best_run.entry(account.clone()).or_insert(0);
                *best = (*best).max(*served);
            }
        }
    }

    pub fn best_run(&self, account: &str) -> u32 {
        self.best_run.get(account).copied().unwrap_or(0)
    }
}
