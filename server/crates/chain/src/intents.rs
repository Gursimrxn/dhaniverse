//! The sent-intents table (spec §3.3): every intent's progress, persisted in `intents.jsonl`, so a `ref` is acted on
//! once across restarts. Also the reverse maps the indexer needs (ref hash → ref string, item hash → item name).

use crate::eip712::{item_hash, ref_hash};
use crate::store::{JsonLines, StoreError};
use crate::types::{Intent, IntentExt};
use alloy::primitives::B256;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum IntentState {
    /// Accepted; transactions may be in flight (their hashes are recorded as they're sent).
    Pending { txs: Vec<B256> },
    /// The intent's last transaction succeeded.
    Done { tx: B256, block: u64 },
    /// It failed; the same ref may be submitted again (e.g. a campaign's daily cap resets tomorrow).
    Failed { reason: String },
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
struct Row {
    key: String,
    #[serde(flatten)]
    state: IntentState,
    /// Present on the first row for a key (and on resubmission after a failure).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    intent: Option<Intent>,
    at: u64,
}

/// What [`IntentTable::admit`] decided.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Admission {
    /// New (or retry after failure): go ahead.
    Run,
    /// Already succeeded.
    AlreadyDone,
    /// Already running.
    InFlight,
}

#[derive(Debug)]
pub struct IntentTable {
    log: JsonLines,
    rows: HashMap<String, (IntentState, Intent)>,
    refs: HashMap<B256, String>,
    items: HashMap<B256, String>,
}

fn now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

impl IntentTable {
    pub fn open(dir: &Path) -> Result<IntentTable, StoreError> {
        let (log, rows) = JsonLines::open::<Row>(dir.join("intents.jsonl"))?;
        let mut t = IntentTable {
            log,
            rows: HashMap::new(),
            refs: HashMap::new(),
            items: HashMap::new(),
        };
        for r in rows {
            if let Some(i) = &r.intent {
                t.learn(i);
            }
            let intent = match (r.intent, t.rows.remove(&r.key)) {
                (Some(i), _) => i,
                (None, Some((_, i))) => i,
                (None, None) => continue,
            };
            t.rows.insert(r.key, (r.state, intent));
        }
        Ok(t)
    }

    fn learn(&mut self, intent: &Intent) {
        if !intent.is_repeatable() {
            let key = intent.key();
            self.refs.insert(ref_hash(&key), key);
        }
        match intent {
            Intent::BuyMeal { item, .. } | Intent::PayRescueMeal { item, .. } => {
                self.items.insert(item_hash(item), item.clone());
            }
            _ => {}
        }
    }

    /// Decides whether to run `intent`, recording it as pending when it runs.
    pub fn admit(&mut self, intent: &Intent) -> Result<Admission, StoreError> {
        let key = intent.key();
        match self.rows.get(&key).map(|(s, _)| s) {
            Some(IntentState::Done { .. }) => return Ok(Admission::AlreadyDone),
            Some(IntentState::Pending { .. }) => return Ok(Admission::InFlight),
            Some(IntentState::Failed { .. }) | None => {}
        }
        let state = IntentState::Pending { txs: vec![] };
        self.log.append(&Row {
            key: key.clone(),
            state: state.clone(),
            intent: Some(intent.clone()),
            at: now(),
        })?;
        self.learn(intent);
        self.rows.insert(key, (state, intent.clone()));
        Ok(Admission::Run)
    }

    pub fn sent(&mut self, key: &str, tx: B256) -> Result<(), StoreError> {
        let Some((IntentState::Pending { txs }, _)) = self.rows.get_mut(key) else {
            return Ok(());
        };
        txs.push(tx);
        let state = IntentState::Pending { txs: txs.clone() };
        self.log.append(&Row {
            key: key.into(),
            state,
            intent: None,
            at: now(),
        })
    }

    pub fn done(&mut self, key: &str, tx: B256, block: u64) -> Result<(), StoreError> {
        self.set(key, IntentState::Done { tx, block })
    }

    pub fn failed(&mut self, key: &str, reason: &str) -> Result<(), StoreError> {
        self.set(
            key,
            IntentState::Failed {
                reason: reason.into(),
            },
        )
    }

    fn set(&mut self, key: &str, state: IntentState) -> Result<(), StoreError> {
        let Some(row) = self.rows.get_mut(key) else {
            return Ok(());
        };
        row.0 = state.clone();
        self.log.append(&Row {
            key: key.into(),
            state,
            intent: None,
            at: now(),
        })
    }

    pub fn state(&self, key: &str) -> Option<&IntentState> {
        self.rows.get(key).map(|(s, _)| s)
    }

    /// Intents left pending by a previous run, with the transactions they had sent.
    pub fn unfinished(&self) -> Vec<(Intent, Vec<B256>)> {
        let mut v: Vec<_> = self
            .rows
            .values()
            .filter_map(|(s, i)| match s {
                IntentState::Pending { txs } => Some((i.clone(), txs.clone())),
                _ => None,
            })
            .collect();
        v.sort_by_key(|(i, _)| i.key());
        v
    }

    /// The server's ref string for a hash seen on chain, if this server sent it.
    pub fn ref_of(&self, hash: &B256) -> Option<&str> {
        self.refs.get(hash).map(String::as_str)
    }

    /// The menu item name for an item hash seen on chain, if a meal intent named it.
    pub fn item_of(&self, hash: &B256) -> Option<&str> {
        self.items.get(hash).map(String::as_str)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn meal(r: &str) -> Intent {
        Intent::BuyMeal {
            player: "asha".into(),
            item: "thali".into(),
            food: 6_000_000,
            max_usdc: 25_000,
            reference: r.into(),
        }
    }

    #[test]
    fn a_ref_runs_once_and_survives_restart() {
        let dir = tempfile::tempdir().unwrap();
        {
            let mut t = IntentTable::open(dir.path()).unwrap();
            assert_eq!(t.admit(&meal("m1")).unwrap(), Admission::Run);
            assert_eq!(t.admit(&meal("m1")).unwrap(), Admission::InFlight);
            t.sent("m1", B256::repeat_byte(1)).unwrap();
            t.done("m1", B256::repeat_byte(1), 9).unwrap();
            assert_eq!(t.admit(&meal("m1")).unwrap(), Admission::AlreadyDone);
            assert_eq!(t.admit(&meal("m2")).unwrap(), Admission::Run);
            t.sent("m2", B256::repeat_byte(2)).unwrap();
        }
        let mut t = IntentTable::open(dir.path()).unwrap();
        assert_eq!(t.admit(&meal("m1")).unwrap(), Admission::AlreadyDone);
        assert_eq!(t.ref_of(&ref_hash("m1")), Some("m1"));
        assert_eq!(t.item_of(&item_hash("thali")), Some("thali"));
        let left = t.unfinished();
        assert_eq!(left.len(), 1);
        assert_eq!(left[0].1, vec![B256::repeat_byte(2)]);
    }

    #[test]
    fn failures_may_be_retried() {
        let dir = tempfile::tempdir().unwrap();
        let mut t = IntentTable::open(dir.path()).unwrap();
        t.admit(&meal("m1")).unwrap();
        t.failed("m1", "CampaignEscrow__DailyCapReached").unwrap();
        assert!(matches!(t.state("m1"), Some(IntentState::Failed { .. })));
        assert_eq!(t.admit(&meal("m1")).unwrap(), Admission::Run);
        drop(t);
        let t = IntentTable::open(dir.path()).unwrap();
        assert_eq!(t.state("m1"), Some(&IntentState::Pending { txs: vec![] }));
    }
}
