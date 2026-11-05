//! The numbers fixed when the world starts, read from `rules.toml`. Every one is there, with a comment saying where it
//! comes from: nothing tunable is written in code.

use crate::{Food, Usdc};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
pub struct Config {
    pub food: FoodConfig,
    pub menu: Vec<MenuItem>,
    pub social: SocialConfig,
    pub clock: ClockConfig,
    pub energy: EnergyConfig,
    pub meals: MealsConfig,
    pub rush: RushConfig,
    pub chest: ChestConfig,
    pub streak: StreakConfig,
    pub errands: ErrandsConfig,
    pub mystery: MysteryConfig,
    pub grandma: GrandmaConfig,
    pub quests: QuestsConfig,
    pub templates: TemplatesConfig,
    pub price_call: PriceCallConfig,
    pub town_goal: TownGoalConfig,
    pub draw: DrawConfig,
    pub rescue: RescueConfig,
    pub referral: ReferralConfig,
    pub house: HouseConfig,
    pub treasury: TreasuryConfig,
    pub ens: EnsConfig,
}

/// FoodHook's settings. Prices are USDC base units per whole FOOD.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
pub struct FoodConfig {
    pub base_price: Usdc,
    pub start_price: Usdc,
    pub floor: Usdc,
    pub ceiling: Usdc,
    pub band_bps: u32,
    /// FOOD in the pool at the start, in whole FOOD.
    pub pool_food: Food,
}

/// One thing on the menu. Eating it burns `food` of the town's FOOD and gives `energy`.
#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
pub struct MenuItem {
    pub name: String,
    pub food: Food,
    pub energy: u32,
}

/// The feed.
#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
pub struct SocialConfig {
    pub emotes: Vec<String>,
    /// Older posts are dropped, and can't be reacted to.
    pub posts_kept: usize,
}

/// The real clock. A city day, the market's, is an hour; a real day is 24 hours, and a week is 7 of them.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
pub struct ClockConfig {
    pub real_day_ms: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
pub struct EnergyConfig {
    pub max: u32,
    pub start: u32,
    /// Below this, energy comes back by itself: one point every `regen_every_ms`.
    pub regen_below: u32,
    pub regen_every_ms: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
pub struct MealsConfig {
    /// Headroom on a meal ticket's `max_usdc` over the live quote, for the price moving before it's eaten.
    pub slippage_bps: u32,
    /// The community thali at the Common Table: free, once every `free_meal_every_ms`.
    pub free_meal_energy: u32,
    pub free_meal_every_ms: u64,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
pub struct RushConfig {
    pub run_ms: u64,
    pub runs_per_day: u32,
    /// A run only has so many customers, however fast a client asks.
    pub most_orders_per_run: u32,
    /// The day's pot: this share of the FIXED bucket's day budget.
    pub pot_bps: u32,
    /// How the pot splits between the day's top places, as weights, first place first.
    pub pot_shares: Vec<u32>,
    pub tickets_per_run: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
pub struct ChestTier {
    pub energy: u32,
    pub tickets: u32,
    /// Chance of a meal voucher, in basis points.
    pub voucher_bps: u32,
    /// Chance of a golden drop, in basis points.
    pub drop_bps: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
pub struct ChestConfig {
    pub every_ms: u64,
    pub brass_streak: u32,
    pub gold_streak: u32,
    /// Every this-many-th chest without a golden drop has one, or a meal voucher if the day's drops are gone.
    pub pity_every: u32,
    pub golden_drop: Usdc,
    /// Chests' share of the SURPRISE bucket's day budget.
    pub budget_bps: u32,
    pub wood: ChestTier,
    pub brass: ChestTier,
    pub gold: ChestTier,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
pub struct StreakConfig {
    pub window_days: u32,
    pub days_needed: u32,
    /// The weekly chest's share of the FIXED bucket's day budget.
    pub budget_bps: u32,
    pub weekly_bonus: Usdc,
    pub weekly_tickets: u32,
    pub weekly_energy: u32,
    /// Tickets for the first visit of each real day.
    pub login_tickets: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
pub struct ErrandsConfig {
    pub per_day: u32,
    pub energy: u32,
    /// Errands' share of the FIXED bucket's day budget, split over `expected_per_day` errands.
    pub budget_bps: u32,
    pub expected_per_day: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
pub struct MysteryConfig {
    pub energy: u32,
    pub per_day: u32,
    /// Mystery quests', events' and Grandma's share of the SURPRISE bucket's day budget.
    pub budget_bps: u32,
    pub payout: Usdc,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
pub struct GrandmaConfig {
    pub energy: u32,
    pub meals: u32,
    pub strongbox: Usdc,
    pub tickets: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
pub struct QuestsConfig {
    /// Tickets for finishing any quest.
    pub tickets: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
pub struct TemplatesConfig {
    pub spice_run: SpiceRunConfig,
    pub hold_line: HoldLineConfig,
    pub paint_sign: PaintSignConfig,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
pub struct SpiceRunConfig {
    /// The cargo money carried to the spice market, and swapped there.
    pub cargo: Usdc,
    /// The swap accepts this much less than the quote, at the most.
    pub slippage_bps: u32,
    /// A player may ask the kiosk for a new quote this often.
    pub quote_every_ms: u64,
    /// A swap needs a quote at most this old.
    pub quote_fresh_ms: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
pub struct HoldLineConfig {
    pub days: u32,
    /// Balance checks at random moments, the first when the quest is taken.
    pub checks: u32,
    /// The least of the quest token to hold, in its base units.
    pub min_amount: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
pub struct PaintSignConfig {
    pub most_chars: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
pub struct PriceCallConfig {
    /// A move smaller than this either way counts as flat.
    pub flat_bps: u32,
    pub tickets: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
pub struct TownGoalConfig {
    /// Meals eaten town-wide in a week that reach the goal.
    pub meals: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
pub struct DrawConfig {
    /// The week's prize: this share of the SURPRISE bucket's balance at the commit.
    pub prize_bps: u32,
    pub reveal_after_ms: u64,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
pub struct RescueConfig {
    pub below_energy: u32,
    pub delay_ms: u64,
    pub every_ms: u64,
    pub item: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
pub struct ReferralConfig {
    pub tickets: u32,
}

/// HousePool's settings, mirrored so the town never promises what the pool won't pay.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
pub struct HouseConfig {
    pub budget_bps: u32,
    pub per_human_daily_cap: Usdc,
}

/// The Treasury's split of food revenue, as its constructor fixed it. For showing; the chain does the split.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct TreasuryConfig {
    pub fixed_bps: u32,
    pub safety_bps: u32,
    pub ops_bps: u32,
    pub team_bps: u32,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
pub struct EnsConfig {
    pub parent: String,
}
