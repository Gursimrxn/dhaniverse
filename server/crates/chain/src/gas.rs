//! Gas top-ups for server-held player wallets, capped per player per UTC day (spec §3.3), persisted in `gas.jsonl`.

use crate::config::GasPolicy;
use crate::store::{JsonLines, StoreError};
use alloy::primitives::U256;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;

#[derive(Clone, Debug, Serialize, Deserialize)]
struct Row {
    player: String,
    day: u64,
    wei: U256,
}

#[derive(Debug)]
pub struct GasLedger {
    log: JsonLines,
    spent: HashMap<(String, u64), U256>,
}

/// What to do before a player-sent transaction.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TopUp {
    /// Balance is above the floor.
    NotNeeded,
    /// Send this much ETH from the gas station.
    Send(U256),
    /// Today's cap is spent.
    CapReached { spent: U256, cap: U256 },
}

pub fn utc_day(unix_secs: u64) -> u64 {
    unix_secs / 86_400
}

impl GasLedger {
    pub fn open(dir: &Path) -> Result<GasLedger, StoreError> {
        let (log, rows) = JsonLines::open::<Row>(dir.join("gas.jsonl"))?;
        let mut spent: HashMap<(String, u64), U256> = HashMap::new();
        for r in rows {
            *spent.entry((r.player, r.day)).or_default() += r.wei;
        }
        Ok(GasLedger { log, spent })
    }

    pub fn spent(&self, player: &str, day: u64) -> U256 {
        self.spent
            .get(&(player.to_string(), day))
            .copied()
            .unwrap_or_default()
    }

    /// Decides the top-up for a player whose balance is `balance`.
    pub fn plan(&self, policy: &GasPolicy, player: &str, balance: U256, day: u64) -> TopUp {
        if balance >= policy.floor_wei {
            return TopUp::NotNeeded;
        }
        let want = policy.target_wei - balance;
        let spent = self.spent(player, day);
        let left = policy.daily_cap_wei.saturating_sub(spent);
        if left.is_zero() {
            return TopUp::CapReached {
                spent,
                cap: policy.daily_cap_wei,
            };
        }
        let send = want.min(left);
        // Sending less than would reach the floor would only buy a failing transaction.
        if balance + send < policy.floor_wei {
            return TopUp::CapReached {
                spent,
                cap: policy.daily_cap_wei,
            };
        }
        TopUp::Send(send)
    }

    pub fn record(&mut self, player: &str, day: u64, wei: U256) -> Result<(), StoreError> {
        self.log.append(&Row {
            player: player.into(),
            day,
            wei,
        })?;
        *self.spent.entry((player.to_string(), day)).or_default() += wei;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn policy() -> GasPolicy {
        GasPolicy {
            floor_wei: U256::from(100u64),
            target_wei: U256::from(300u64),
            daily_cap_wei: U256::from(500u64),
        }
    }

    #[test]
    fn tops_up_to_target_within_the_daily_cap() {
        let dir = tempfile::tempdir().unwrap();
        let mut g = GasLedger::open(dir.path()).unwrap();
        let p = policy();
        assert_eq!(g.plan(&p, "asha", U256::from(150u64), 1), TopUp::NotNeeded);
        assert_eq!(
            g.plan(&p, "asha", U256::from(50u64), 1),
            TopUp::Send(U256::from(250u64))
        );
        g.record("asha", 1, U256::from(250u64)).unwrap();
        g.record("asha", 1, U256::from(200u64)).unwrap();
        // 50 left today: not enough to reach the floor from 0.
        assert!(matches!(
            g.plan(&p, "asha", U256::ZERO, 1),
            TopUp::CapReached { .. }
        ));
        // ...but enough from 60.
        assert_eq!(
            g.plan(&p, "asha", U256::from(60u64), 1),
            TopUp::Send(U256::from(50u64))
        );
        // A new day, a new cap; other players unaffected.
        assert_eq!(
            g.plan(&p, "asha", U256::ZERO, 2),
            TopUp::Send(U256::from(300u64))
        );
        assert_eq!(
            g.plan(&p, "ben", U256::ZERO, 1),
            TopUp::Send(U256::from(300u64))
        );
        drop(g);
        let g = GasLedger::open(dir.path()).unwrap();
        assert_eq!(g.spent("asha", 1), U256::from(450u64));
    }

    #[test]
    fn days_are_utc() {
        assert_eq!(utc_day(0), 0);
        assert_eq!(utc_day(86_399), 0);
        assert_eq!(utc_day(86_400), 1);
    }
}
