//! The house: a mirror of HousePool, the Treasury and FloatManager as the chain reported them, and the way every USDC
//! reward is paid. A reward is never promised past what the pool holds: each day's spending is a share of the day's
//! budget, which is a share of the balance, and nothing is sent that the observed budget can't cover.
//!
//! A reward for someone without the Town Pass waits, owed, until they get it. One the pool can't pay today waits for
//! tomorrow. Either way it keeps its ref, so the chain can never pay it twice.

use crate::chain::{Bucket, HumanId, Intent};
use crate::observe::Purpose;
use crate::{AccountId, Config, Event, Ref, State, Usdc};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

const BPS: u64 = 10_000;

/// `amount` × `bps` ÷ 10,000, rounded down.
pub fn share(amount: Usdc, bps: u32) -> Usdc {
    (u128::from(amount) * u128::from(bps) / u128::from(BPS)) as Usdc
}

/// What a day's house budget is spent on. Each has a share of one bucket's day budget, in rules.toml.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Category {
    Rush,
    Streak,
    Errands,
    Chest,
    Mystery,
}

impl Category {
    pub fn bucket(self) -> Bucket {
        match self {
            Category::Rush | Category::Streak | Category::Errands => Bucket::Fixed,
            Category::Chest | Category::Mystery => Bucket::Surprise,
        }
    }

    pub fn share_bps(self, c: &Config) -> u32 {
        match self {
            Category::Rush => c.rush.pot_bps,
            Category::Streak => c.streak.budget_bps,
            Category::Errands => c.errands.budget_bps,
            Category::Chest => c.chest.budget_bps,
            Category::Mystery => c.mystery.budget_bps,
        }
    }
}

/// Where a reward comes from.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "from", rename_all = "snake_case")]
pub enum Payout {
    House { bucket: Bucket },
    Campaign { campaign: u64 },
}

/// Why an owed reward hasn't gone yet.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Waiting {
    /// Payouts need the Town Pass.
    TownPass,
    /// The pool's budget for today is spent, or the per-person daily cap is reached. Tried again tomorrow.
    Budget,
    /// The chain refused it. Tried again tomorrow.
    Chain,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Owed {
    pub account: AccountId,
    pub amount: Usdc,
    pub payout: Payout,
    pub why: String,
    pub waiting: Waiting,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize)]
pub struct BucketBook {
    /// The balance the chain last reported, less what's been paid since.
    pub balance: Usdc,
    /// What it may still pay today, as the chain last reported it, less what's been paid since.
    pub budget_left: Usdc,
    /// Sent and not yet seen paid or refused.
    pub in_flight: Usdc,
    /// Today's whole budget, for the categories' shares: `budget_bps` of the balance when the town's day began.
    pub day_budget: Usdc,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize)]
pub struct Treasury {
    /// Food revenue on this real day, and ever.
    pub revenue_today: Usdc,
    pub revenue_total: Usdc,
    /// What the Treasury has split so far, and where it went.
    pub split_total: Usdc,
    pub to_fixed: Usdc,
    pub to_safety: Usdc,
    pub to_ops: Usdc,
    pub to_team: Usdc,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize)]
pub struct Float {
    pub total_assets: Usdc,
    pub liquid: Usdc,
    pub invested: Usdc,
    pub buffer: Usdc,
    pub liabilities: Usdc,
    pub loss_reserve: Usdc,
    pub yield_earned: Usdc,
}

/// Town-wide counts for the dashboard. No player's own numbers.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize)]
pub struct Stats {
    pub meals_today: u32,
    pub usdc_today: Usdc,
    pub rescues_today: u32,
    pub rescues_total: u32,
    pub rescue_usdc_total: Usdc,
    /// HousePool payouts seen on this town day.
    pub paid_today: Usdc,
    /// The chain's time of the Treasury's last split, unix seconds.
    pub last_split_at: u64,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct House {
    pub stats: Stats,
    pub buckets: BTreeMap<Bucket, BucketBook>,
    /// Whether the chain has reported the pool at all. Until it has, nothing is paid.
    pub seen: bool,
    /// Spent or promised today, by category.
    pub spent: BTreeMap<Category, Usdc>,
    /// Paid or sent today, per human, against HousePool's per-human daily cap.
    pub human_paid: BTreeMap<HumanId, Usdc>,
    /// The weekly draw's prize, promised until it's claimed.
    pub draw_reserved: Usdc,
    pub owed: BTreeMap<Ref, Owed>,
    pub treasury: Treasury,
    pub float: Float,
}

impl House {
    pub fn book(&self, bucket: Bucket) -> BucketBook {
        self.buckets.get(&bucket).copied().unwrap_or_default()
    }

    fn book_mut(&mut self, bucket: Bucket) -> &mut BucketBook {
        self.buckets.entry(bucket).or_default()
    }

    /// What this bucket could pay right now, keeping what's already on its way and the draw's prize.
    pub fn available(&self, bucket: Bucket) -> Usdc {
        if !self.seen {
            return 0;
        }
        let book = self.book(bucket);
        let reserved = if bucket == Bucket::Surprise {
            self.draw_reserved
        } else {
            0
        };
        let balance = book.balance.saturating_sub(reserved);
        book.budget_left.min(balance).saturating_sub(book.in_flight)
    }

    /// The balance not yet promised to anything.
    pub fn free_balance(&self, bucket: Bucket) -> Usdc {
        let book = self.book(bucket);
        let reserved = if bucket == Bucket::Surprise {
            self.draw_reserved
        } else {
            0
        };
        book.balance.saturating_sub(book.in_flight + reserved)
    }

    /// What's left of a category's share of today's budget.
    pub fn category_left(&self, category: Category, c: &Config) -> Usdc {
        let whole = share(
            self.book(category.bucket()).day_budget,
            category.share_bps(c),
        );
        whole.saturating_sub(self.spent.get(&category).copied().unwrap_or(0))
    }

    /// Takes up to `want` from a category's share. Returns what it got.
    pub fn take(&mut self, category: Category, want: Usdc, c: &Config) -> Usdc {
        let got = want.min(self.category_left(category, c));
        *self.spent.entry(category).or_insert(0) += got;
        got
    }

    /// A new town day: shares start over, from a budget worked out from the balances now.
    pub fn new_day(&mut self, c: &Config) {
        self.spent.clear();
        self.human_paid.clear();
        self.treasury.revenue_today = 0;
        self.stats.meals_today = 0;
        self.stats.usdc_today = 0;
        self.stats.rescues_today = 0;
        self.stats.paid_today = 0;
        for bucket in Bucket::ALL {
            let book = self.book_mut(bucket);
            book.day_budget = share(book.balance, c.house.budget_bps);
        }
    }

    /// The pool as the chain reports it. Returns whether anything changed.
    pub fn observe_pools(&mut self, balances: [Usdc; 3], budgets: [Usdc; 3], c: &Config) -> bool {
        let before = self.buckets.clone();
        let first = !self.seen;
        self.seen = true;
        for (i, bucket) in Bucket::ALL.into_iter().enumerate() {
            let book = self.book_mut(bucket);
            book.balance = balances[i];
            book.budget_left = budgets[i];
            if first || book.day_budget == 0 {
                book.day_budget = share(book.balance, c.house.budget_bps);
            }
        }
        first || before != self.buckets
    }

    /// A payout seen on chain: it leaves the balance and today's budget, and is no longer on its way.
    pub(crate) fn paid(&mut self, bucket: Bucket, amount: Usdc, sent: Usdc) {
        self.stats.paid_today += amount;
        let book = self.book_mut(bucket);
        book.in_flight = book.in_flight.saturating_sub(sent);
        book.balance = book.balance.saturating_sub(amount);
        book.budget_left = book.budget_left.saturating_sub(amount);
    }

    /// A payout the chain refused: nothing moved.
    pub(crate) fn unsent(&mut self, bucket: Bucket, amount: Usdc, human: Option<&HumanId>) {
        let book = self.book_mut(bucket);
        book.in_flight = book.in_flight.saturating_sub(amount);
        if let Some(human) = human {
            if let Some(paid) = self.human_paid.get_mut(human) {
                *paid = paid.saturating_sub(amount);
            }
        }
    }

    /// USDC owed to this player, waiting for the Town Pass or for tomorrow.
    pub fn owed_to(&self, account: &str) -> Usdc {
        self.owed
            .values()
            .filter(|o| o.account == account)
            .map(|o| o.amount)
            .sum()
    }
}

impl State {
    /// Pays a reward, or holds it owed. A zero reward is nothing at all.
    pub(crate) fn reward(
        &mut self,
        account: &str,
        payout: Payout,
        amount: Usdc,
        why: &str,
        reference: Ref,
        events: &mut Vec<Event>,
    ) {
        if amount == 0 || self.ref_known(&reference) {
            return;
        }
        let owed = Owed {
            account: account.to_string(),
            amount,
            payout,
            why: why.to_string(),
            waiting: Waiting::TownPass,
        };
        self.house.owed.insert(reference.clone(), owed);
        self.try_pay(&reference, true, events);
    }

    /// Sends one owed reward if it can go now; otherwise says why it's waiting, when it's `fresh` or the reason
    /// changed. Returns whether it went.
    pub(crate) fn try_pay(
        &mut self,
        reference: &Ref,
        fresh: bool,
        events: &mut Vec<Event>,
    ) -> bool {
        let Some(owed) = self.house.owed.get(reference).cloned() else {
            return false;
        };
        let human = self
            .life
            .player(&owed.account)
            .and_then(|p| p.human.clone());
        let waiting = match (&human, owed.payout) {
            (None, _) => Some(Waiting::TownPass),
            (Some(human), Payout::House { bucket }) => {
                let paid_today = self.house.human_paid.get(human).copied().unwrap_or(0);
                let cap = self.config.house.per_human_daily_cap;
                let over_cap = paid_today + owed.amount > cap;
                (over_cap || self.house.available(bucket) < owed.amount).then_some(Waiting::Budget)
            }
            (Some(_), Payout::Campaign { campaign }) => {
                let open = self.campaigns.get(campaign).is_some_and(|c| !c.closed);
                (!open).then_some(Waiting::Chain)
            }
        };
        if let Some(waiting) = waiting {
            let changed = owed.waiting != waiting;
            if let Some(entry) = self.house.owed.get_mut(reference) {
                entry.waiting = waiting;
            }
            // Said once when it starts waiting, and again only if the reason changes.
            if changed || fresh {
                events.push(Event::RewardPending {
                    account: owed.account,
                    amount: owed.amount,
                    why: owed.why,
                    reference: reference.clone(),
                    waiting,
                });
            }
            return false;
        }
        let human_id = human.expect("checked above");
        self.house.owed.remove(reference);
        let player = owed.account.clone();
        let intent = match owed.payout {
            Payout::House { bucket } => {
                self.house.book_mut(bucket).in_flight += owed.amount;
                *self.house.human_paid.entry(human_id.clone()).or_insert(0) += owed.amount;
                Intent::PayHouse {
                    player,
                    human_id,
                    bucket,
                    amount: owed.amount,
                    reference: reference.clone(),
                }
            }
            Payout::Campaign { campaign } => Intent::ClaimCampaign {
                campaign,
                player,
                human_id,
                amount: owed.amount,
                reference: reference.clone(),
            },
        };
        let purpose = Purpose::Reward {
            account: owed.account,
            amount: owed.amount,
            payout: owed.payout,
            why: owed.why,
        };
        self.send(purpose, intent, events);
        true
    }

    /// Tries every owed reward again, or just one player's.
    pub(crate) fn retry_owed(&mut self, only: Option<&str>, events: &mut Vec<Event>) {
        let refs: Vec<Ref> = self
            .house
            .owed
            .iter()
            .filter(|(_, o)| only.is_none_or(|a| o.account == a))
            .map(|(r, _)| r.clone())
            .collect();
        for reference in refs {
            self.try_pay(&reference, false, events);
        }
    }

    /// Today's errand pay: errands' share of the FIXED day budget, split over the errands the town expects.
    pub fn errand_rate(&self) -> Usdc {
        let c = &self.config;
        let whole = share(
            self.house.book(Bucket::Fixed).day_budget,
            c.errands.budget_bps,
        );
        whole / c.errands.expected_per_day.max(1)
    }
}
