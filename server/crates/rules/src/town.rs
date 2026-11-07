//! Which town a ref belongs to. Many saves can use one chain over time, and each restarts its refs (`kofi-0-0`,
//! `rush:0:sam`) from the beginning, so on the chain every ref carries the town's id: `<town_id>:<ref>`. Inside the town
//! refs stay short and plain, and what the chain says about another town's refs is none of this town's business.
//!
//! The draw's week numbers repeat the same way, so on the chain a week is `<the town id's first 32 bits> << 32 | week`.

use crate::chain::{Intent, Observation};
use crate::{Refusal, State};

/// Intents without a ref: the chain keys their failures by these, with no town in them.
const KEYS_WITHOUT_A_TOWN: [&str; 6] = [
    "wallet:",
    "name:",
    "records:",
    "split",
    "rebalance",
    "harvest-yield",
];

impl State {
    /// A ref as the chain sees it.
    pub fn chain_ref(&self, reference: &str) -> String {
        if self.town_id.is_empty() {
            reference.to_string()
        } else {
            format!("{}:{reference}", self.town_id)
        }
    }

    /// This town's own ref, from the chain's, or None for another town's.
    pub fn own_ref(&self, reference: &str) -> Option<String> {
        if self.town_id.is_empty() {
            return Some(reference.to_string());
        }
        let rest = reference.strip_prefix(self.town_id.as_str())?;
        rest.strip_prefix(':').map(str::to_string)
    }

    fn town_tag(&self) -> u64 {
        let hex: String = self.town_id.chars().take(8).collect();
        u64::from_str_radix(&hex, 16).unwrap_or(0)
    }

    /// A draw week as the chain sees it.
    pub fn chain_week(&self, week: u64) -> u64 {
        (self.town_tag() << 32) | (week & 0xFFFF_FFFF)
    }

    /// This town's week, from the chain's, or None for another town's.
    pub fn own_week(&self, chain_week: u64) -> Option<u64> {
        (chain_week >> 32 == self.town_tag()).then_some(chain_week & 0xFFFF_FFFF)
    }

    /// An intent as it goes to the chain: its ref and its draw week carry the town.
    pub fn outward(&self, intent: Intent) -> Intent {
        let mut intent = intent;
        match &mut intent {
            Intent::BuyMeal { reference, .. }
            | Intent::SellHarvest { reference, .. }
            | Intent::PayHouse { reference, .. }
            | Intent::PayRescueMeal { reference, .. }
            | Intent::ClaimCampaign { reference, .. }
            | Intent::Advance { reference, .. }
            | Intent::SwapForQuest { reference, .. }
            | Intent::QuoteSwap { reference, .. }
            | Intent::Deliver { reference, .. }
            | Intent::Withdraw { reference, .. }
            | Intent::CheckHolding { reference, .. } => *reference = self.chain_ref(reference),
            Intent::ClaimDraw {
                week, reference, ..
            } => {
                *week = self.chain_week(*week);
                *reference = self.chain_ref(reference);
            }
            Intent::CommitDraw { week, .. } | Intent::RevealDraw { week, .. } => {
                *week = self.chain_week(*week)
            }
            Intent::EnsureWallet { .. }
            | Intent::RegisterName { .. }
            | Intent::SetRecords { .. }
            | Intent::Split
            | Intent::Rebalance
            | Intent::HarvestYield => {}
        }
        intent
    }

    /// An observation in this town's own refs and weeks, or `NotOurs` for one about another town's.
    pub(crate) fn inward(&self, observed: Observation) -> Result<Observation, Refusal> {
        let mut observed = observed;
        let ours = match &mut observed {
            Observation::MealEaten { reference, .. }
            | Observation::HarvestSold { reference, .. }
            | Observation::Paid { reference, .. }
            | Observation::Claimed { reference, .. }
            | Observation::Advanced { reference, .. }
            | Observation::Delivered { reference, .. }
            | Observation::SwapQuoted { reference, .. }
            | Observation::Holding { reference, .. } => self.take_ref(reference),
            Observation::DrawCommitted { week, .. }
            | Observation::DrawRevealed { week, .. }
            | Observation::DrawClaimed { week, .. } => self.take_week(week),
            Observation::IntentFailed { reference, .. } => self.take_failure_key(reference),
            _ => true,
        };
        if ours {
            Ok(observed)
        } else {
            Err(Refusal::NotOurs)
        }
    }

    fn take_ref(&self, reference: &mut String) -> bool {
        match self.own_ref(reference) {
            Some(own) => {
                *reference = own;
                true
            }
            None => false,
        }
    }

    fn take_week(&self, week: &mut u64) -> bool {
        match self.own_week(*week) {
            Some(own) => {
                *week = own;
                true
            }
            None => false,
        }
    }

    /// A failure's key: a ref of ours, a draw week of ours, or one of the keys that name no town.
    fn take_failure_key(&self, key: &mut String) -> bool {
        if self.take_ref(key) && !self.town_id.is_empty() {
            return true;
        }
        for kind in ["draw-commit:", "draw-reveal:"] {
            if let Some(week) = key.strip_prefix(kind).and_then(|w| w.parse().ok()) {
                return match self.own_week(week) {
                    Some(own) => {
                        *key = format!("{kind}{own}");
                        true
                    }
                    None => false,
                };
            }
        }
        self.town_id.is_empty() || KEYS_WITHOUT_A_TOWN.iter().any(|k| key.starts_with(k))
    }
}

#[cfg(test)]
mod tests {
    use crate::chain::Observation;
    use crate::{Config, Refusal, State};

    fn town(id: &str) -> State {
        let config: Config = toml::from_str(include_str!("../../../rules.toml")).unwrap();
        let mut state = State::new(&config).unwrap();
        state.town_id = id.to_string();
        state
    }

    #[test]
    fn refs_and_weeks_carry_the_town_and_come_back_plain() {
        let a = town("0a1b2c3d4e5f6a7b");
        assert_eq!(a.chain_ref("kofi-0-0"), "0a1b2c3d4e5f6a7b:kofi-0-0");
        assert_eq!(
            a.own_ref("0a1b2c3d4e5f6a7b:kofi-0-0").as_deref(),
            Some("kofi-0-0")
        );
        assert_eq!(a.own_ref("ffffffffffffffff:kofi-0-0"), None);
        assert_eq!(a.own_ref("kofi-0-0"), None);
        assert_eq!(a.own_week(a.chain_week(3)), Some(3));
        assert_eq!(town("ffffffff00000000").own_week(a.chain_week(3)), None);
        let failed = Observation::IntentFailed {
            reference: "split".into(),
            reason: "x".into(),
        };
        assert!(
            a.inward(failed).is_ok(),
            "keys that name no town are anyone's"
        );
        let foreign = Observation::IntentFailed {
            reference: "ffffffffffffffff:meal".into(),
            reason: "x".into(),
        };
        assert_eq!(a.inward(foreign), Err(Refusal::NotOurs));
    }
}
