//! Each player's own record: energy, the wallet and Town Pass the chain told us about, their quests, chest, streak,
//! tickets and firsts. Energy comes back by itself below a line, worked out from the clock when it's read, so it
//! needs no ticking. There's no in-game money: the only money is the USDC in their wallet.

use crate::chain::HumanId;
use crate::quests::ActiveQuest;
use crate::{AccountId, EnergyConfig, Event, Ref, Refusal, Usdc};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

/// The firsts a player can carve on the Ledger Wall.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum First {
    FirstMeal,
    FirstQuest,
    TownPass,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub struct EarnedFirst {
    pub first: First,
    pub carved: bool,
}

/// A guess at tomorrow's food price.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Call {
    Up,
    Flat,
    Down,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Player {
    pub energy: u32,
    /// When `energy` was last worked out. Energy below the regen line has been coming back since then.
    pub energy_at: u64,

    pub in_rush: bool,
    /// Orders served in the run under way, or in the last one.
    pub served: u32,
    pub rush_ends_at: u64,
    /// Runs started on real day `runs.0`: `runs.1`.
    pub runs: (u64, u32),
    /// The best run on real day `rush_best.0`: `rush_best.1` orders.
    pub rush_best: (u64, u32),

    pub firsts: Vec<EarnedFirst>,

    /// When the free thali was last eaten.
    pub free_meal_at: Option<u64>,
    /// A meal ticket out on the chain, by its ref. One at a time, so nobody can stack tickets.
    pub pending_meal: Option<Ref>,
    /// Meals they paid for themselves, ever.
    pub paid_meals: u32,
    pub vouchers: u32,

    pub wallet: Option<String>,
    /// The last balance the chain reported. None until it has.
    pub usdc: Option<Usdc>,
    pub human: Option<HumanId>,
    pub ens: Option<String>,
    pub sign: String,
    /// Quest tokens this wallet got from quest swaps and hasn't delivered, as the chain reported them.
    pub quest_tokens: u128,

    /// Real days they came to town, the last few.
    pub login_days: Vec<u64>,
    /// Real days in a row they came.
    pub streak: u32,

    pub chest_at: Option<u64>,
    pub chests: u32,
    /// Chests opened since the last golden drop.
    pub since_drop: u32,
    pub weekly_at: Option<u64>,
    /// The week whose Town Goal upgrade they've used.
    pub upgrade_week: Option<u64>,
    /// Tickets for week `tickets.0`: `tickets.1`.
    pub tickets: (u64, u32),

    pub quests: BTreeMap<String, ActiveQuest>,
    /// Errands taken on real day `errands.0`: `errands.1`.
    pub errands: (u64, u32),
    /// Mysteries taken on real day `mysteries.0`: `mysteries.1`.
    pub mysteries: (u64, u32),
    /// The season they opened Grandma's strongbox.
    pub grandma_season: Option<u32>,
    /// Finished quests per campaign, against its per-human cap.
    pub campaigns_done: BTreeMap<u64, u32>,
    pub quests_done: u32,

    /// Their call on city day `price_call.0`'s close.
    pub price_call: Option<(u64, Call)>,

    /// When a neighbour arrives with a thali.
    pub rescue_at: Option<u64>,
    pub rescued_at: Option<u64>,

    pub referrer: Option<AccountId>,
    pub referral_paid: bool,
    /// Titles earned, the latest last. The latest is the one shown.
    pub titles: Vec<String>,
    pub stamps: BTreeSet<String>,
}

impl Player {
    pub fn new(energy: u32, now: u64) -> Self {
        Player {
            energy,
            energy_at: now,
            ..Player::default()
        }
    }

    /// Energy right now, with whatever has come back by itself.
    pub fn energy_now(&self, now: u64, c: &EnergyConfig) -> u32 {
        if self.energy >= c.regen_below || c.regen_every_ms == 0 {
            return self.energy;
        }
        let ticks = now.saturating_sub(self.energy_at) / c.regen_every_ms;
        let gained = ticks.min(u64::from(c.regen_below - self.energy)) as u32;
        self.energy + gained
    }

    /// When the next point comes back by itself, or None when it isn't coming back.
    pub fn next_regen_at(&self, now: u64, c: &EnergyConfig) -> Option<u64> {
        if self.energy_now(now, c) >= c.regen_below || c.regen_every_ms == 0 {
            return None;
        }
        let ticks = now.saturating_sub(self.energy_at) / c.regen_every_ms;
        Some(self.energy_at + (ticks + 1) * c.regen_every_ms)
    }

    /// Writes down what's come back, keeping the part of a point that's on its way.
    fn settle(&mut self, now: u64, c: &EnergyConfig) {
        if self.energy >= c.regen_below || c.regen_every_ms == 0 {
            self.energy_at = now;
            return;
        }
        let ticks = now.saturating_sub(self.energy_at) / c.regen_every_ms;
        let gained = ticks.min(u64::from(c.regen_below - self.energy));
        self.energy += gained as u32;
        self.energy_at = if self.energy >= c.regen_below {
            now
        } else {
            self.energy_at + ticks * c.regen_every_ms
        };
    }

    /// Adds energy, up to the most a player can hold. Returns the new energy.
    pub fn add_energy(&mut self, gain: u32, now: u64, c: &EnergyConfig) -> u32 {
        self.settle(now, c);
        self.energy = (self.energy + gain).min(c.max);
        self.energy_at = now;
        self.energy
    }

    /// Spends energy, or refuses with what they have. Returns the energy left.
    pub fn spend_energy(&mut self, cost: u32, now: u64, c: &EnergyConfig) -> Result<u32, Refusal> {
        let have = self.energy_now(now, c);
        if have < cost {
            return Err(Refusal::NotEnoughEnergy { have, need: cost });
        }
        self.settle(now, c);
        let was_regenerating = self.energy < c.regen_below;
        self.energy -= cost;
        if !was_regenerating {
            self.energy_at = now;
        }
        Ok(self.energy)
    }

    /// Tickets for this week.
    pub fn tickets_in(&self, week: u64) -> u32 {
        if self.tickets.0 == week {
            self.tickets.1
        } else {
            0
        }
    }

    /// Days they came in the last `window` real days, today included.
    pub fn days_in_window(&self, today: u64, window: u32) -> u32 {
        let from = today.saturating_sub(u64::from(window.max(1)) - 1);
        self.login_days.iter().filter(|d| **d >= from).count() as u32
    }

    pub fn has_first(&self, first: First) -> bool {
        self.firsts.iter().any(|e| e.first == first)
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Life {
    players: BTreeMap<AccountId, Player>,
    /// Refs of orders served. A ref works once.
    refs: BTreeSet<Ref>,
}

impl Life {
    pub fn arrive(
        &mut self,
        account: AccountId,
        energy: u32,
        now: u64,
    ) -> Result<Vec<Event>, Refusal> {
        if self.players.contains_key(&account) {
            return Err(Refusal::AlreadyArrived { account });
        }
        self.players
            .insert(account.clone(), Player::new(energy, now));
        Ok(vec![Event::Arrived { account, energy }])
    }

    pub fn carve_first(&mut self, account: AccountId, first: First) -> Result<Vec<Event>, Refusal> {
        let player = self.get_mut(&account)?;
        let Some(earned) = player.firsts.iter_mut().find(|e| e.first == first) else {
            return Err(Refusal::NotEarned { first });
        };
        if earned.carved {
            return Err(Refusal::AlreadyCarved { first });
        }
        earned.carved = true;
        Ok(vec![Event::FirstCarved { account, first }])
    }

    pub(crate) fn check_arrived(&self, account: &str) -> Result<(), Refusal> {
        self.get(account).map(|_| ())
    }

    pub(crate) fn get(&self, account: &str) -> Result<&Player, Refusal> {
        self.players
            .get(account)
            .ok_or_else(|| Refusal::UnknownPlayer {
                account: account.to_string(),
            })
    }

    pub(crate) fn get_mut(&mut self, account: &str) -> Result<&mut Player, Refusal> {
        self.players
            .get_mut(account)
            .ok_or_else(|| Refusal::UnknownPlayer {
                account: account.to_string(),
            })
    }

    pub(crate) fn use_ref(&mut self, reference: &Ref) -> Result<(), Refusal> {
        if !self.refs.insert(reference.clone()) {
            return Err(Refusal::RefUsed {
                reference: reference.clone(),
            });
        }
        Ok(())
    }

    pub(crate) fn ref_used(&self, reference: &str) -> bool {
        self.refs.contains(reference)
    }

    /// Adds `FirstEarned` for anything these events earned for the first time.
    pub(crate) fn award_firsts(&mut self, events: &mut Vec<Event>) {
        let mut earned = Vec::new();
        for event in events.iter() {
            match event {
                Event::MealEaten { account, .. } => {
                    earned.push((account.clone(), First::FirstMeal))
                }
                Event::QuestDone { account, .. } => {
                    earned.push((account.clone(), First::FirstQuest));
                }
                Event::HumanVerified { account } => earned.push((account.clone(), First::TownPass)),
                _ => {}
            }
        }
        for (account, first) in earned {
            if !crate::is_person(&account) {
                continue;
            }
            let Some(player) = self.players.get_mut(&account) else {
                continue;
            };
            if !player.has_first(first) {
                player.firsts.push(EarnedFirst {
                    first,
                    carved: false,
                });
                events.push(Event::FirstEarned { account, first });
            }
        }
    }

    // ------------------------------------------------------------ reads

    pub fn player(&self, account: &str) -> Option<&Player> {
        self.players.get(account)
    }

    /// Everyone with an account here, by name.
    pub fn players(&self) -> impl Iterator<Item = (&AccountId, &Player)> {
        self.players.iter()
    }
}
