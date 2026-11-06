//! The `Ledger` seam's words, from the rules crate (`rules::chain`, spec §3.2), plus this crate's helpers.
//!
//! Amounts are base units: USDC and FOOD both use 6 decimals (1 USDC = 1,000,000); quest tokens have their own
//! decimals, so their amounts are `u128` (decimal strings in JSON, via `rules::chain::big`). Players are game names.

pub use rules::chain::{Bucket, HumanId, Intent, Observation, Observed, TicketRange, NOT_A_LOG};
pub use rules::{AccountId, Food, Ref, Usdc};

/// The crate's older name for a player id.
pub type PlayerId = AccountId;

/// `PayoutVoucher.source` for a campaign claim.
pub const CAMPAIGN_SOURCE: u8 = 3;

/// The bucket for a `PayoutVoucher.source` byte (0 to 2); 3 is a campaign, not a bucket.
pub fn bucket_from_source(source: u8) -> Option<Bucket> {
    match source {
        0 => Some(Bucket::Fixed),
        1 => Some(Bucket::Surprise),
        2 => Some(Bucket::Safety),
        _ => None,
    }
}

/// What the executor needs to know about an intent.
pub trait IntentExt {
    /// The ref reported in `IntentFailed`: the intent's ref, or `wallet:<player>`, `name:<player>`,
    /// `records:<player>`, `split`, `rebalance`, `harvest-yield`, `draw-commit:<week>`, `draw-reveal:<week>`.
    fn public_ref(&self) -> String;
    /// The idempotency key in the sent-intents table: the public ref, made specific where one player can ask for
    /// several different things under the same public ref (a name label, a set of records).
    fn key(&self) -> String;
    /// Repeatable keeper housekeeping and reads: never recorded as done, only de-duplicated while in flight.
    fn is_repeatable(&self) -> bool;
    /// The player this intent acts for, if any (the draw winner for `ClaimDraw`).
    fn player(&self) -> Option<&str>;
    /// Short name for logs.
    fn kind(&self) -> &'static str;
}

impl IntentExt for Intent {
    fn public_ref(&self) -> String {
        if let Some(r) = self.reference() {
            return r.to_string();
        }
        match self {
            Intent::EnsureWallet { player } => format!("wallet:{player}"),
            Intent::RegisterName { player, .. } => format!("name:{player}"),
            Intent::SetRecords { player, .. } => format!("records:{player}"),
            Intent::Split => "split".into(),
            Intent::Rebalance => "rebalance".into(),
            Intent::HarvestYield => "harvest-yield".into(),
            Intent::CommitDraw { week, .. } => format!("draw-commit:{week}"),
            Intent::RevealDraw { week, .. } => format!("draw-reveal:{week}"),
            other => other.kind().to_string(),
        }
    }

    fn key(&self) -> String {
        match self {
            Intent::RegisterName { player, label } => format!("name:{player}:{label}"),
            Intent::SetRecords { player, records } => {
                let body = serde_json::to_string(records).unwrap_or_default();
                format!(
                    "records:{player}:{}",
                    alloy::primitives::keccak256(body.as_bytes())
                )
            }
            _ => self.public_ref(),
        }
    }

    fn is_repeatable(&self) -> bool {
        matches!(
            self,
            Intent::Split
                | Intent::Rebalance
                | Intent::HarvestYield
                | Intent::CheckHolding { .. }
                | Intent::QuoteSwap { .. }
        )
    }

    fn player(&self) -> Option<&str> {
        match self {
            Intent::EnsureWallet { player }
            | Intent::BuyMeal { player, .. }
            | Intent::PayHouse { player, .. }
            | Intent::PayRescueMeal { player, .. }
            | Intent::ClaimCampaign { player, .. }
            | Intent::Advance { player, .. }
            | Intent::SwapForQuest { player, .. }
            | Intent::Deliver { player, .. }
            | Intent::RegisterName { player, .. }
            | Intent::SetRecords { player, .. }
            | Intent::ClaimDraw { player, .. }
            | Intent::CheckHolding { player, .. }
            | Intent::QuoteSwap { player, .. } => Some(player),
            _ => None,
        }
    }

    fn kind(&self) -> &'static str {
        match self {
            Intent::EnsureWallet { .. } => "EnsureWallet",
            Intent::BuyMeal { .. } => "BuyMeal",
            Intent::SellHarvest { .. } => "SellHarvest",
            Intent::PayHouse { .. } => "PayHouse",
            Intent::PayRescueMeal { .. } => "PayRescueMeal",
            Intent::ClaimCampaign { .. } => "ClaimCampaign",
            Intent::Advance { .. } => "Advance",
            Intent::SwapForQuest { .. } => "SwapForQuest",
            Intent::Deliver { .. } => "Deliver",
            Intent::RegisterName { .. } => "RegisterName",
            Intent::SetRecords { .. } => "SetRecords",
            Intent::Split => "Split",
            Intent::Rebalance => "Rebalance",
            Intent::HarvestYield => "HarvestYield",
            Intent::CommitDraw { .. } => "CommitDraw",
            Intent::RevealDraw { .. } => "RevealDraw",
            Intent::ClaimDraw { .. } => "ClaimDraw",
            Intent::CheckHolding { .. } => "CheckHolding",
            Intent::QuoteSwap { .. } => "QuoteSwap",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;

    #[test]
    fn keys_and_public_refs() {
        let meal = Intent::BuyMeal {
            player: "asha".into(),
            item: "chai".into(),
            food: 1,
            max_usdc: 5,
            reference: "m1".into(),
        };
        assert_eq!(
            (meal.key(), meal.public_ref()),
            ("m1".to_string(), "m1".to_string())
        );
        assert_eq!(
            Intent::EnsureWallet {
                player: "asha".into()
            }
            .public_ref(),
            "wallet:asha"
        );
        let commit = Intent::CommitDraw {
            week: 3,
            seed_hash: "0x".into(),
            root: String::new(),
            count: 1,
            prize: 1,
            tickets: vec![],
        };
        assert_eq!(commit.key(), "draw-commit:3");
        let name = Intent::RegisterName {
            player: "asha".into(),
            label: "asha".into(),
        };
        assert_eq!(
            (name.key(), name.public_ref()),
            ("name:asha:asha".to_string(), "name:asha".to_string())
        );
        let mut a = BTreeMap::new();
        a.insert("description".to_string(), "Fresh chai".to_string());
        let mut b = a.clone();
        b.insert("avatar".to_string(), "x".to_string());
        let ka = Intent::SetRecords {
            player: "asha".into(),
            records: a,
        };
        let kb = Intent::SetRecords {
            player: "asha".into(),
            records: b,
        };
        assert_ne!(ka.key(), kb.key());
        assert!(ka.key().starts_with("records:asha:0x"));
        assert_eq!(ka.public_ref(), "records:asha");
    }

    #[test]
    fn repeatable_only_housekeeping_and_reads() {
        assert!(Intent::Split.is_repeatable());
        assert!(Intent::HarvestYield.is_repeatable());
        assert!(Intent::CheckHolding {
            player: "a".into(),
            campaign: 1,
            reference: "h".into()
        }
        .is_repeatable());
        assert!(!Intent::RevealDraw {
            week: 1,
            seed: "0x".into()
        }
        .is_repeatable());
    }

    #[test]
    fn quest_token_amounts_are_decimal_strings() {
        let o = Observation::QuestSwap {
            player: "asha".into(),
            token_in: "0x1".into(),
            token_out: "0x2".into(),
            amount_in: 2_000_000,
            amount_out: 5_000_000_000_000_000_000,
            tx: "0x".into(),
        };
        let s = serde_json::to_string(&o).unwrap();
        assert!(s.contains("\"amount_out\":\"5000000000000000000\""), "{s}");
        assert_eq!(serde_json::from_str::<Observation>(&s).unwrap(), o);
    }

    #[test]
    fn bucket_sources() {
        for b in Bucket::ALL {
            assert_eq!(bucket_from_source(b.source()), Some(b));
        }
        assert_eq!(bucket_from_source(CAMPAIGN_SOURCE), None);
    }
}
