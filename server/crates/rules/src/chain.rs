//! The words the town and the chain speak to each other. An `Intent` is something the rules ask the chain to do; an
//! `Observation` is something the chain did. Neither does anything by itself: the server's `Ledger` carries intents out
//! and brings observations back, and each observation enters the world as a logged input, so a replay is exact.
//!
//! Amounts are base units: USDC and FOOD both have 6 decimals (1 USDC = 1,000,000). Quest tokens have their own
//! decimals (MANGO has 18), so their amounts are `u128`, written in JSON as decimal strings (a JSON number can't hold
//! them exactly, and the save's tagged enums can't read a number that big). Players are game names, never addresses.

use crate::{AccountId, Food, Ref, Usdc};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// A `u128` as a decimal string in JSON. A plain number is read too, for amounts that fit in 64 bits.
pub mod big {
    use serde::{de, Deserialize, Deserializer, Serializer};

    pub fn serialize<S: Serializer>(value: &u128, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(&value.to_string())
    }

    #[derive(Deserialize)]
    #[serde(untagged)]
    enum Either {
        Text(String),
        Number(u64),
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(deserializer: D) -> Result<u128, D::Error> {
        match Either::deserialize(deserializer)? {
            Either::Text(text) => text.parse().map_err(de::Error::custom),
            Either::Number(n) => Ok(u128::from(n)),
        }
    }
}

/// A World ID nullifier hash as `0x…` hex. One human, one player.
#[derive(Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(transparent)]
pub struct HumanId(pub String);

impl HumanId {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// A HousePool bucket (`PayoutVoucher.source` 0 to 2). Source 3, a campaign, only exists in `CampaignEscrow`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Bucket {
    /// Rush pot, streak bonus, errands. Funded by food revenue.
    Fixed,
    /// Chests, golden drops, mystery quests, Grandma's strongbox, the weekly draw. Funded by fees and yield.
    Surprise,
    /// Rescue meals only.
    Safety,
}

impl Bucket {
    pub const ALL: [Bucket; 3] = [Bucket::Fixed, Bucket::Surprise, Bucket::Safety];

    /// The `source` byte in a `PayoutVoucher`.
    pub fn source(self) -> u8 {
        match self {
            Bucket::Fixed => 0,
            Bucket::Surprise => 1,
            Bucket::Safety => 2,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Bucket::Fixed => "fixed",
            Bucket::Surprise => "surprise",
            Bucket::Safety => "safety",
        }
    }
}

/// One player's tickets in a week's draw: tickets `from` to `to`, both included, counted from 0.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct TicketRange {
    pub player: AccountId,
    pub from: u64,
    pub to: u64,
}

/// Something the rules ask the chain to do. Each one with a `ref` works once on chain, so sending it again (after a
/// restart, or after an `IntentFailed` such as a daily cap) can never pay twice.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum Intent {
    /// Give the player a wallet, once. Answered by `WalletReady`.
    EnsureWallet { player: AccountId },
    /// The player's wallet buys a meal through `MealCounter` with a server-signed `MealTicket`. Answered by
    /// `MealEaten`, or `IntentFailed`.
    BuyMeal {
        player: AccountId,
        item: String,
        food: Food,
        max_usdc: Usdc,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    /// The farm's keeper sells harvest FOOD through `Farm`. Answered by `HarvestSold`. Only on a chain: offline, the
    /// harvest is sold into the town's own pool.
    SellHarvest {
        food: Food,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    /// A `PayoutVoucher` paying `amount` USDC from a HousePool bucket to the player. Answered by `Paid`.
    PayHouse {
        player: AccountId,
        human_id: HumanId,
        bucket: Bucket,
        amount: Usdc,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    /// A rescue meal, paid from the SAFETY bucket straight into `MealCounter` for the player. Answered by `MealEaten`
    /// with this ref.
    PayRescueMeal {
        player: AccountId,
        human_id: HumanId,
        item: String,
        food: Food,
        max_usdc: Usdc,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    /// A `CampaignClaim` voucher for a finished sponsored quest. Answered by `Claimed`.
    ClaimCampaign {
        campaign: u64,
        player: AccountId,
        human_id: HumanId,
        amount: Usdc,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    /// An `AdvanceVoucher`: cargo money from the campaign for a player whose wallet is short. Answered by `Advanced`.
    Advance {
        campaign: u64,
        player: AccountId,
        human_id: HumanId,
        amount: Usdc,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    /// The player's wallet swaps `usdc_in` USDC for the campaign's quest token through Uniswap's UniversalRouter.
    /// `min_out` 0 means the chain quotes it with its own slippage setting. Answered by `QuestSwap`.
    SwapForQuest {
        player: AccountId,
        campaign: u64,
        usdc_in: Usdc,
        #[serde(with = "big")]
        min_out: u128,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    /// What `usdc_in` USDC would buy of the campaign's quest token on Uniswap now, for the exchange kiosk. A read, no
    /// transaction. Answered by `SwapQuoted` with this ref.
    QuoteSwap {
        player: AccountId,
        campaign: u64,
        usdc_in: Usdc,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    /// The player's wallet sends `amount` USDC to `to`. Answered by `Withdrawn`.
    Withdraw {
        player: AccountId,
        to: String,
        amount: Usdc,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    /// The player's wallet hands its quest tokens to the Spice Merchant. Answered by `Delivered`.
    Deliver {
        player: AccountId,
        campaign: u64,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    /// Register `label.<parent>` to the player's wallet. Answered by `NameRegistered`.
    RegisterName { player: AccountId, label: String },
    /// Write text records on the player's name. `description` is written from the player's own wallet. Answered by
    /// `RecordsSet`.
    SetRecords {
        player: AccountId,
        records: BTreeMap<String, String>,
    },
    /// `Treasury.split()`, by anyone.
    Split,
    /// `FloatManager.rebalance()`, by the keeper.
    Rebalance,
    /// `FloatManager.harvestYield()`, by anyone.
    HarvestYield,
    /// `LuckyLedger.commit`. `root` is left empty: the chain builds it from `tickets` with LuckyLedger's own leaf
    /// encoding, and reports it in `DrawCommitted`. Answered by `DrawCommitted`.
    CommitDraw {
        week: u64,
        seed_hash: String,
        root: String,
        count: u64,
        prize: Usdc,
        tickets: Vec<TicketRange>,
    },
    /// `LuckyLedger.reveal`. Answered by `DrawRevealed`.
    RevealDraw { week: u64, seed: String },
    /// `LuckyLedger.claim` for the winner, with the Merkle proof of their range. Answered by `DrawClaimed`.
    ClaimDraw {
        week: u64,
        player: AccountId,
        from: u64,
        to: u64,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    /// Read the player's balance of the campaign's quest token, for Hold the Line's random checks. Answered by
    /// `Holding` with this ref.
    CheckHolding {
        player: AccountId,
        campaign: u64,
        #[serde(rename = "ref")]
        reference: Ref,
    },
}

impl Intent {
    /// The intent's ref, for those that have one.
    pub fn reference(&self) -> Option<&str> {
        match self {
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
            | Intent::ClaimDraw { reference, .. }
            | Intent::CheckHolding { reference, .. } => Some(reference),
            _ => None,
        }
    }
}

/// What the chain did. Players are game names when the address is one of our wallets, otherwise the `0x…` address.
/// `tx` is the transaction hash.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum Observation {
    WalletReady {
        player: AccountId,
        address: String,
    },
    /// `MealCounter.MealEaten`. `from_ration` is the FOOD sold from the ration reserve.
    MealEaten {
        player: AccountId,
        item: String,
        usdc: Usdc,
        food: Food,
        from_ration: Food,
        #[serde(rename = "ref")]
        reference: Ref,
        tx: String,
    },
    /// `Farm.HarvestSold`.
    HarvestSold {
        offered: Food,
        sold: Food,
        usdc: Usdc,
        #[serde(rename = "ref")]
        reference: Ref,
        tx: String,
    },
    /// FoodHook `TradeCounted`.
    FoodTrade {
        day: u64,
        usdc: Usdc,
        food: Food,
        price_after: Usdc,
        tx: String,
    },
    /// FoodHook `DayOpened`.
    FoodDayOpened {
        day: u64,
        open_price: Usdc,
    },
    /// `Treasury.Split`.
    Split {
        total: Usdc,
        fixed: Usdc,
        safety: Usdc,
        ops: Usdc,
        team: Usdc,
        tx: String,
    },
    /// `HousePool.Paid`.
    Paid {
        bucket: Bucket,
        player: AccountId,
        human_id: HumanId,
        amount: Usdc,
        #[serde(rename = "ref")]
        reference: Ref,
        tx: String,
    },
    /// `CampaignEscrow.CampaignCreated`. `template` is the template's name (`spice_run`, `paint_sign`, `town_pass` or
    /// `hold_line`), decoded from its bytes32 by the chain. `kind` is 0 Sponsored, 1 Boosted. `start` and `end` are
    /// unix seconds. `budget` is the spendable budget, after the platform fee.
    CampaignCreated {
        id: u64,
        sponsor: String,
        template: String,
        meta_hash: String,
        budget: Usdc,
        payout_per_claim: Usdc,
        energy_cost: u32,
        max_claims: u32,
        per_human_cap: u16,
        start: u64,
        end: u64,
        kind: u8,
        deliver_to: String,
    },
    /// `CampaignEscrow.Claimed`.
    Claimed {
        campaign: u64,
        player: AccountId,
        human_id: HumanId,
        amount: Usdc,
        advance_repaid: Usdc,
        #[serde(rename = "ref")]
        reference: Ref,
        tx: String,
    },
    /// `CampaignEscrow.Advanced`.
    Advanced {
        campaign: u64,
        player: AccountId,
        human_id: HumanId,
        amount: Usdc,
        #[serde(rename = "ref")]
        reference: Ref,
        tx: String,
    },
    /// `CampaignEscrow.Refunded`: the campaign is over and its unspent budget went back.
    Refunded {
        campaign: u64,
        amount: Usdc,
        tx: String,
    },
    /// A campaign paused by the admin or cancelled by its sponsor: no new claims.
    CampaignClosed {
        campaign: u64,
        tx: String,
    },
    /// A withdrawal's USDC transfer, confirmed.
    Withdrawn {
        player: AccountId,
        to: String,
        amount: Usdc,
        #[serde(rename = "ref")]
        reference: Ref,
        tx: String,
    },
    /// `SpiceMerchant.Delivered`.
    Delivered {
        campaign: u64,
        player: AccountId,
        token: String,
        #[serde(with = "big")]
        amount: u128,
        #[serde(rename = "ref")]
        reference: Ref,
        tx: String,
    },
    /// A Uniswap `Swap` in a quest pool whose `tx.from` is the player.
    QuestSwap {
        player: AccountId,
        token_in: String,
        token_out: String,
        #[serde(with = "big")]
        amount_in: u128,
        #[serde(with = "big")]
        amount_out: u128,
        tx: String,
    },
    /// The answer to `QuoteSwap`: `usdc_in` buys `amount_out` of the quest token (`token`, `symbol`, `decimals`) in a
    /// pool whose fee is `fee_bps` (3000 = 0.30%).
    SwapQuoted {
        player: AccountId,
        campaign: u64,
        usdc_in: Usdc,
        #[serde(with = "big")]
        amount_out: u128,
        fee_bps: u32,
        token: String,
        symbol: String,
        decimals: u8,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    /// The player's USDC balance, read from the chain.
    Balances {
        player: AccountId,
        usdc: Usdc,
    },
    /// HousePool's buckets: balances, and `budget_*`, what each bucket may still pay today (4% of its balance at the
    /// day's first payout, less what it has paid today).
    PoolBalances {
        fixed: Usdc,
        surprise: Usdc,
        safety: Usdc,
        budget_fixed: Usdc,
        budget_surprise: Usdc,
        budget_safety: Usdc,
    },
    /// FloatManager's books.
    FloatState {
        total_assets: Usdc,
        liquid: Usdc,
        invested: Usdc,
        buffer: Usdc,
        liabilities: Usdc,
        loss_reserve: Usdc,
        yield_earned: Usdc,
    },
    NameRegistered {
        player: AccountId,
        label: String,
        name: String,
        tx: String,
    },
    RecordsSet {
        player: AccountId,
        records: BTreeMap<String, String>,
        tx: String,
    },
    DrawCommitted {
        week: u64,
        seed_hash: String,
        root: String,
        count: u64,
        prize: Usdc,
        tx: String,
    },
    DrawRevealed {
        week: u64,
        seed: String,
        winner_index: u64,
        tx: String,
    },
    DrawClaimed {
        week: u64,
        player: AccountId,
        prize: Usdc,
        tx: String,
    },
    /// The answer to `CheckHolding`.
    Holding {
        player: AccountId,
        campaign: u64,
        #[serde(with = "big")]
        amount: u128,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    /// The chain refused an intent, or it couldn't be sent. Nothing moved. `ref` is the intent's ref, or for intents
    /// without one: `wallet:<player>`, `name:<player>`, `records:<player>`, `split`, `rebalance`, `harvest-yield`,
    /// `draw-commit:<week>` or `draw-reveal:<week>`.
    IntentFailed {
        #[serde(rename = "ref")]
        reference: Ref,
        reason: String,
    },
}

/// Where an observation happened, ready to become `Input::Chain`. Log-derived observations come in (block, log_index)
/// order, once confirmed. Ones that don't come from a log (wallets, balances, failures) use `log_index` = `u64::MAX`.
/// `time` is the block's timestamp in unix seconds, or 0 if unknown.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Observed {
    pub block: u64,
    pub log_index: u64,
    #[serde(default)]
    pub time: u64,
    pub observed: Observation,
}

/// The `log_index` for an observation that isn't from a log.
pub const NOT_A_LOG: u64 = u64::MAX;

/// Where the money settles: nowhere (the town plays it out in its own pool and an in-process ledger), a local anvil,
/// or Sepolia. Fixed for a save's whole life, since it decides whether the food market follows the chain.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ChainMode {
    #[default]
    Offline,
    Anvil,
    Sepolia,
}

impl ChainMode {
    pub fn name(self) -> &'static str {
        match self {
            ChainMode::Offline => "offline",
            ChainMode::Anvil => "anvil",
            ChainMode::Sepolia => "sepolia",
        }
    }

    pub fn parse(text: &str) -> Option<ChainMode> {
        match text {
            "offline" => Some(ChainMode::Offline),
            "anvil" => Some(ChainMode::Anvil),
            "sepolia" => Some(ChainMode::Sepolia),
            _ => None,
        }
    }

    /// Whether the food market follows a real pool, rather than playing out in the town's own.
    pub fn on_chain(self) -> bool {
        self != ChainMode::Offline
    }
}
