//! What happened, and why something didn't. The food market's names and fields follow FoodHook's and FoodRouter's
//! events and errors, without the contract prefixes, so the client needs no translation when the chain replaces them.

use crate::chain::Intent;
use crate::house::Waiting;
use crate::life::Call;
use crate::{AccountId, First, Food, Ref, Role, Usdc};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// A chest's tier, from the streak.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Tier {
    Wood,
    Brass,
    Gold,
}

impl Tier {
    pub fn up(self) -> Tier {
        match self {
            Tier::Wood => Tier::Brass,
            _ => Tier::Gold,
        }
    }
}

/// What a chest held. `golden_drop` is USDC from the SURPRISE bucket, 0 for none.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChestContents {
    pub energy: u32,
    pub tickets: u32,
    pub voucher: bool,
    pub golden_drop: Usdc,
}

/// What a finished quest paid. `usdc` is paid now, or owed until the Town Pass.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct QuestReward {
    pub usdc: Usdc,
    pub tickets: u32,
    pub title: Option<String>,
    pub stamp: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum Event {
    // A player's own day. Off-chain, so no contract has these.
    Arrived {
        account: AccountId,
        energy: u32,
    },
    /// The first visit of a real day.
    LoggedIn {
        account: AccountId,
        day: u64,
        streak: u32,
        week_days: u32,
    },
    RushStarted {
        account: AccountId,
        ends_at: u64,
        runs_left: u32,
    },
    /// `served` counts this run's orders so far.
    OrderServed {
        account: AccountId,
        served: u32,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    /// The server's clock ended the run. A `RushEnded` follows.
    RushTimeUp {
        account: AccountId,
        served: u32,
    },
    RushEnded {
        account: AccountId,
        served: u32,
    },
    FreeMealEaten {
        account: AccountId,
        energy: u32,
        next_at: u64,
    },
    /// A meal ticket went to the chain. `max_usdc` is the most it can cost.
    MealOrdered {
        account: AccountId,
        item: String,
        food: Food,
        max_usdc: Usdc,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    /// Paid for on chain, in USDC base units. `food` is what was burned for it, `from_ration` the part from the
    /// ration reserve.
    MealEaten {
        account: AccountId,
        item: String,
        usdc: Usdc,
        food: Food,
        energy: u32,
        from_ration: Food,
        #[serde(rename = "ref")]
        reference: Ref,
        tx: String,
    },
    MealFailed {
        account: AccountId,
        item: String,
        #[serde(rename = "ref")]
        reference: Ref,
        reason: String,
    },
    /// A chest's meal voucher is being turned into a meal: the house pays, then the meal is bought.
    VoucherUsed {
        account: AccountId,
        item: String,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    WalletReady {
        account: AccountId,
        address: String,
    },
    BalanceChanged {
        account: AccountId,
        usdc: Usdc,
    },
    HumanVerified {
        account: AccountId,
    },
    NameRegistered {
        account: AccountId,
        name: String,
    },
    /// The shop sign is going on chain.
    SignPainting {
        account: AccountId,
        text: String,
    },
    /// A paid meal dropped an urgent crate at one of the town's spots, for anyone to reach first before `ends_at`.
    LootDropped {
        id: u64,
        spot: u64,
        prize: Usdc,
        ends_at: u64,
    },
    /// Someone reached the crate first; its prize follows as a reward.
    LootClaimed {
        id: u64,
        account: AccountId,
        prize: Usdc,
    },
    /// Nobody reached the crate in time.
    LootGone {
        id: u64,
    },
    /// A withdrawal left for the chain.
    WithdrawSent {
        account: AccountId,
        to: String,
        amount: Usdc,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    /// A withdrawal landed: the USDC is at `to`.
    Withdrawn {
        account: AccountId,
        to: String,
        amount: Usdc,
        tx: String,
    },
    /// A withdrawal the chain refused. The USDC never left.
    WithdrawFailed {
        account: AccountId,
        amount: Usdc,
        reason: String,
    },
    RecordsSet {
        account: AccountId,
        records: BTreeMap<String, String>,
    },
    QuestTaken {
        account: AccountId,
        quest: String,
        energy: u32,
    },
    /// A step went to the chain, and waits to be seen there.
    QuestStepSent {
        account: AccountId,
        quest: String,
        step: String,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    QuestStepDone {
        account: AccountId,
        quest: String,
        step: String,
    },
    /// The player's Uniswap swap for a quest landed: what actually arrived, in the quest token's base units.
    QuestSwapped {
        account: AccountId,
        quest: String,
        #[serde(with = "crate::chain::big")]
        received: u128,
    },
    /// The chain refused a step. It can be tried again.
    QuestStepFailed {
        account: AccountId,
        quest: String,
        step: String,
        reason: String,
    },
    /// The exchange kiosk's quote: the cargo buys `amount_out` of the quest token, and the swap will take at least
    /// `min_out`. Both are decimal strings in the token's base units.
    SwapQuoted {
        account: AccountId,
        quest: String,
        usdc_in: Usdc,
        #[serde(with = "crate::chain::big")]
        amount_out: u128,
        #[serde(with = "crate::chain::big")]
        min_out: u128,
        fee_bps: u32,
        slippage_bps: u32,
        symbol: String,
        decimals: u8,
    },
    QuoteFailed {
        account: AccountId,
        quest: String,
        reason: String,
    },
    QuestDone {
        account: AccountId,
        quest: String,
        title: String,
        reward: QuestReward,
    },
    QuestAbandoned {
        account: AccountId,
        quest: String,
    },
    QuestFailed {
        account: AccountId,
        quest: String,
        reason: String,
    },
    ChestOpened {
        account: AccountId,
        weekly: bool,
        tier: Tier,
        contents: ChestContents,
    },
    TicketsEarned {
        account: AccountId,
        tickets: u32,
        why: String,
        total: u32,
    },
    /// A USDC reward that hasn't gone yet, and why.
    RewardPending {
        account: AccountId,
        amount: Usdc,
        why: String,
        #[serde(rename = "ref")]
        reference: Ref,
        waiting: Waiting,
    },
    /// A reward paid. `amount` is the reward; `advance_repaid` of it went back to the campaign for an advance the player had
    /// (the Spice Run's cargo), so `amount - advance_repaid` is what reached their wallet.
    RewardPaid {
        account: AccountId,
        amount: Usdc,
        #[serde(default)]
        advance_repaid: Usdc,
        why: String,
        #[serde(rename = "ref")]
        reference: Ref,
        tx: String,
    },
    PriceCalled {
        account: AccountId,
        day: u64,
        call: Call,
    },
    PriceCallSettled {
        account: AccountId,
        day: u64,
        call: Call,
        moved: Call,
        right: bool,
    },
    TownGoalReached {
        week: u64,
        meals: u32,
        target: u32,
    },
    /// A neighbour is on the way with a thali, arriving at `at`.
    RescueComing {
        account: AccountId,
        at: u64,
    },
    /// `direct` when the safety net was empty, so the energy was given straight away.
    RescueMeal {
        account: AccountId,
        energy: u32,
        direct: bool,
    },
    Referred {
        account: AccountId,
        by: AccountId,
    },
    ReferralRewarded {
        account: AccountId,
        friend: AccountId,
        tickets: u32,
    },
    DrawCommitted {
        week: u64,
        tickets: u64,
        prize: Usdc,
    },
    DrawRevealed {
        week: u64,
    },
    DrawWon {
        account: AccountId,
        week: u64,
        prize: Usdc,
        tx: String,
    },
    BountyPosted {
        campaign: u64,
        template: String,
    },
    BountyClosed {
        campaign: u64,
    },
    /// The chain reported new numbers for `part`: `house`, `treasury` or `float`.
    LedgerUpdated {
        part: String,
    },
    /// Something asked of the chain. The server carries it out; clients never see it.
    Intent {
        intent: Intent,
    },
    FirstEarned {
        account: AccountId,
        first: First,
    },
    FirstCarved {
        account: AccountId,
        first: First,
    },
    SeasonChanged {
        season: u32,
        shock: String,
    },
    // The mentor. Only ever to that player.
    MentorAsked {
        account: AccountId,
        question: String,
    },
    MentorSays {
        account: AccountId,
        about: String,
        text: String,
    },
    // The feed.
    FeedPost {
        id: u64,
        day: u64,
        kind: String,
        text: String,
        about: Option<AccountId>,
    },
    Reacted {
        post: u64,
        account: AccountId,
        emote: String,
    },
    Followed {
        account: AccountId,
        player: AccountId,
    },
    Unfollowed {
        account: AccountId,
        player: AccountId,
    },
    /// Not a contract event: The Tally's front page for the day.
    PaperPublished {
        day: u64,
        headline: String,
        stories: Vec<String>,
    },
    // FoodHook.
    DayOpened {
        day: u64,
        open_price: Usdc,
    },
    TradeCounted {
        day: u64,
        usdc: Usdc,
        food: Food,
        price_after: Usdc,
    },
    // FoodRouter. `bought < wanted` or `sold < offered` means today's limit was reached.
    FoodBought {
        day: u64,
        wanted: Food,
        bought: Food,
        usdc_paid: Usdc,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    FoodSold {
        day: u64,
        offered: Food,
        sold: Food,
        usdc_got: Usdc,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    /// The server's price reader, not a contract event. `day_price` is 0 for a quiet day, which keeps the last index.
    FoodIndexSet {
        day: u64,
        day_price: Usdc,
        food_index_bps: u32,
    },
    /// Not a contract event: a festival, a harvest or a drought, on the record for the paper.
    CityEventStarted {
        day: u64,
        kind: String,
        days: u32,
    },
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(tag = "type")]
pub enum Refusal {
    NotAllowed {
        has: Role,
        needs: Role,
    },
    RefUsed {
        #[serde(rename = "ref")]
        reference: Ref,
    },
    ZeroAmount,
    // FoodHook's deploy checks.
    BadSettings {
        floor: Usdc,
        ceiling: Usdc,
    },
    StartOutsideBounds {
        price: Usdc,
        floor: Usdc,
        ceiling: Usdc,
    },
    // No contract has the rest.
    BadQuestBook {
        problem: String,
    },
    /// The chain's clock can't run backwards, and a server's can be told to.
    WrongDay {
        expected: u64,
        got: u64,
    },
    WrongTime {
        now: u64,
        got: u64,
    },
    UnknownPlayer {
        account: AccountId,
    },
    AlreadyArrived {
        account: AccountId,
    },
    AlreadyInRush,
    NotInRush,
    /// A run only has so many customers, however fast a client asks.
    RushFull {
        most: u32,
    },
    /// The run's 90 seconds are up.
    RushOver,
    NoRunsLeft {
        most: u32,
        resets_at: u64,
    },
    UnknownItem {
        item: String,
    },
    NotEarned {
        first: First,
    },
    AlreadyCarved {
        first: First,
    },
    QuestionTooLong {
        max: usize,
    },
    UnknownPost {
        post: u64,
    },
    UnknownEmote {
        emote: String,
    },
    AlreadyReacted {
        post: u64,
    },
    FollowingYourself,
    NotFollowing {
        player: AccountId,
    },
    NotEnoughEnergy {
        have: u32,
        need: u32,
    },
    EnergyFull {
        energy: u32,
    },
    FreeMealNotReady {
        ready_at: u64,
    },
    MealPending {
        #[serde(rename = "ref")]
        reference: Ref,
    },
    NoWallet,
    NotEnoughUsdc {
        have: Usdc,
        need: Usdc,
    },
    NoVoucher,
    /// The house can't pay this today. Try tomorrow.
    BudgetSpent,
    /// Payouts, advances and vouchers need the Town Pass.
    NeedsTownPass,
    UnknownQuest {
        quest: String,
    },
    AlreadyOnQuest {
        quest: String,
    },
    NotOnQuest {
        quest: String,
    },
    /// That step isn't the one to do now, or isn't one this command does.
    WrongStep {
        quest: String,
        step: String,
    },
    /// The step is waiting for the chain.
    StepWaiting {
        quest: String,
        step: String,
    },
    NotAShockDay,
    /// A quote was asked for less than `quote_every_ms` ago.
    QuoteTooSoon {
        ready_at: u64,
    },
    /// The swap needs a kiosk quote under a minute old: ask for one with `QuoteSwap`.
    QuoteStale {
        quest: String,
    },
    NoErrandsLeft {
        most: u32,
        resets_at: u64,
    },
    NoMysteryLeft {
        most: u32,
        resets_at: u64,
    },
    QuestDoneBefore {
        quest: String,
    },
    NoSlotsLeft {
        campaign: u64,
    },
    CampaignClosed {
        campaign: u64,
    },
    PerHumanCap {
        campaign: u64,
        cap: u16,
    },
    ChestNotReady {
        ready_at: u64,
    },
    WeeklyChestNotReady {
        days: u32,
        need: u32,
    },
    AlreadyCalled {
        day: u64,
    },
    AlreadyHuman,
    /// That World ID already holds a different player.
    HumanTaken,
    NoName,
    /// Not an Ethereum address, or the player's own.
    BadAddress,
    /// Nothing to send.
    BadAmount,
    /// The crate was claimed, or ran out, before you reached it.
    LootGone,
    BadSign {
        most: usize,
    },
    AlreadyReferred,
    ReferringYourself,
    /// Referrals are named before your first quest is done.
    TooLateToRefer,
    UnknownRef {
        #[serde(rename = "ref")]
        reference: Ref,
    },
    AlreadyObserved {
        block: u64,
        log_index: u64,
    },
    /// An observation that changes nothing, so it isn't worth a line in the save.
    NothingNew,
    /// An observation about another town's refs, from a chain more than one town has used.
    NotOurs,
    NoDrawDue {
        week: u64,
    },
}
