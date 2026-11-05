//! What the chain did, coming into the town. Each observation is one logged input, so a replay sees the chain exactly
//! as it was. Intents the rules sent wait in the outbox by ref until the chain answers; an answer for a ref that was
//! never sent, or was answered already, changes nothing.

use crate::book::StepKind;
use crate::campaigns::Campaign;
use crate::chain::{Bucket, HumanId, Intent, Observation, NOT_A_LOG};
use crate::house::{Payout, Waiting};
use crate::{AccountId, Event, Food, Ref, Refusal, State, Usdc};
use serde::Serialize;
use std::collections::{BTreeMap, BTreeSet};

/// What an intent in the outbox was for, so its answer lands in the right place.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(tag = "type")]
pub enum Purpose {
    Meal {
        account: AccountId,
        item: String,
        voucher: bool,
    },
    Rescue {
        account: AccountId,
        max_usdc: Usdc,
    },
    Reward {
        account: AccountId,
        amount: Usdc,
        payout: Payout,
        why: String,
    },
    Voucher {
        account: AccountId,
        item: String,
    },
    Advance {
        account: AccountId,
        quest: String,
    },
    Swap {
        account: AccountId,
        quest: String,
    },
    Deliver {
        account: AccountId,
        quest: String,
    },
    Harvest,
    DrawClaim {
        week: u64,
        account: AccountId,
    },
    Holding {
        account: AccountId,
        quest: String,
    },
    Quote {
        account: AccountId,
        quest: String,
    },
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Outbound {
    pub intent: Intent,
    pub purpose: Purpose,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ChainBook {
    /// The last log seen, so a log seen twice is dropped.
    pub cursor: Option<(u64, u64)>,
    /// The latest block seen, logs or not.
    pub block: u64,
    /// Refs the chain has answered. Each is answered once.
    pub settled: BTreeSet<Ref>,
    /// Intents the chain said failed. A success seen later for the same ref wins: after a crash a resent intent can
    /// fail on chain because the first try went through.
    pub failed: BTreeMap<Ref, Outbound>,
    /// Each World ID, and the one player it holds.
    pub humans: BTreeMap<HumanId, AccountId>,
    /// USDC into, and quest tokens out of, the quest pools through this town's swaps.
    pub quest_usdc_in: Usdc,
    pub quest_tokens_out: u128,
}

impl State {
    /// Sends an intent with a ref, keeping it until the chain answers.
    pub(crate) fn send(&mut self, purpose: Purpose, intent: Intent, events: &mut Vec<Event>) {
        if let Some(reference) = intent.reference() {
            let outbound = Outbound {
                intent: intent.clone(),
                purpose,
            };
            self.outbox.insert(reference.to_string(), outbound);
        }
        let intent = self.outward(intent);
        events.push(Event::Intent { intent });
    }

    /// Sends an intent that has no ref: the chain makes it idempotent by what it says.
    pub(crate) fn ask(&mut self, intent: Intent, events: &mut Vec<Event>) {
        let intent = self.outward(intent);
        events.push(Event::Intent { intent });
    }

    /// Everything still owed an answer by the chain, for sending again after a restart. All of it is safe to send
    /// twice.
    pub fn open_intents(&self) -> Vec<Intent> {
        let mut intents: Vec<Intent> = self.outbox.values().map(|o| o.intent.clone()).collect();
        for (name, p) in self.life.players() {
            if crate::is_person(name) && p.wallet.is_none() {
                intents.push(Intent::EnsureWallet {
                    player: name.clone(),
                });
            }
            if p.human.is_some() && p.ens.is_none() {
                intents.push(Intent::RegisterName {
                    player: name.clone(),
                    label: name.clone(),
                });
            }
        }
        for draw in self.games.draws.values() {
            if !draw.committed {
                intents.push(Intent::CommitDraw {
                    week: draw.week,
                    seed_hash: draw.seed_hash.clone(),
                    root: String::new(),
                    count: draw.count,
                    prize: draw.prize,
                    tickets: draw.tickets.clone(),
                });
            } else if draw.reveal_sent && draw.winner.is_none() {
                intents.push(Intent::RevealDraw {
                    week: draw.week,
                    seed: draw.seed.clone(),
                });
            }
        }
        intents.into_iter().map(|i| self.outward(i)).collect()
    }

    /// On a chain, the farm's harvest is sold by the keeper. Offline, Kofi sells into the town's own pool instead.
    pub(crate) fn offer_harvest(
        &mut self,
        offered: Food,
        reference: Ref,
    ) -> Result<Vec<Event>, Refusal> {
        if offered == 0 {
            return Err(Refusal::ZeroAmount);
        }
        if self.ref_known(&reference) {
            return Err(Refusal::RefUsed { reference });
        }
        let mut events = Vec::new();
        let intent = Intent::SellHarvest {
            food: offered,
            reference,
        };
        self.send(Purpose::Harvest, intent, &mut events);
        Ok(events)
    }

    /// Takes the outbox entry that this success settles, refusing one that was never sent or is already settled. A
    /// success for an intent the chain said had failed wins, and what the failure undid is put right.
    fn settle(&mut self, reference: &Ref) -> Result<Outbound, Refusal> {
        if self.chain.settled.contains(reference) {
            return Err(Refusal::RefUsed {
                reference: reference.clone(),
            });
        }
        if let Some(outbound) = self.outbox.remove(reference) {
            self.chain.settled.insert(reference.clone());
            self.chain.failed.remove(reference);
            return Ok(outbound);
        }
        let outbound = self
            .chain
            .failed
            .remove(reference)
            .ok_or_else(|| Refusal::UnknownRef {
                reference: reference.clone(),
            })?;
        self.chain.settled.insert(reference.clone());
        self.undo_failure(reference, &outbound);
        Ok(outbound)
    }

    /// The failure was wrong: take back what it gave back, so the success counts once.
    fn undo_failure(&mut self, reference: &Ref, outbound: &Outbound) {
        match &outbound.purpose {
            Purpose::Reward {
                payout,
                amount,
                account,
                ..
            } => {
                self.house.owed.remove(reference);
                // It was taken off what's on its way when it failed; `paid` takes it off again, so put it back first.
                if let Payout::House { bucket } = payout {
                    if let Some(book) = self.house.buckets.get_mut(bucket) {
                        book.in_flight += amount;
                    }
                    let human = self.life.player(account).and_then(|p| p.human.clone());
                    if let Some(human) = human {
                        *self.house.human_paid.entry(human).or_insert(0) += amount;
                    }
                }
            }
            Purpose::Voucher { account, .. } => {
                if let Ok(p) = self.life.get_mut(account) {
                    p.vouchers = p.vouchers.saturating_sub(1);
                }
                if let Intent::PayHouse { amount, .. } = &outbound.intent {
                    if let Some(book) = self.house.buckets.get_mut(&Bucket::Surprise) {
                        book.in_flight += amount;
                    }
                }
            }
            Purpose::Rescue { max_usdc, .. } => {
                if let Some(book) = self.house.buckets.get_mut(&Bucket::Safety) {
                    book.in_flight += max_usdc;
                }
            }
            Purpose::Advance { account, quest }
            | Purpose::Swap { account, quest }
            | Purpose::Deliver { account, quest } => {
                // The step stopped waiting when it failed; it waits on this ref again, so the success finds it.
                let kind = match outbound.purpose {
                    Purpose::Advance { .. } => StepKind::Cargo,
                    Purpose::Swap { .. } => StepKind::Swap,
                    _ => StepKind::Deliver,
                };
                if let Ok(p) = self.life.get_mut(account) {
                    if let Some(q) = p.quests.get_mut(quest) {
                        if let Some(step) = q.steps.iter_mut().find(|s| s.kind == kind && !s.done) {
                            step.waiting = Some(reference.clone());
                        }
                    }
                }
            }
            Purpose::Meal { .. }
            | Purpose::Harvest
            | Purpose::DrawClaim { .. }
            | Purpose::Holding { .. }
            | Purpose::Quote { .. } => {}
        }
    }

    pub(crate) fn observe(
        &mut self,
        block: u64,
        log_index: u64,
        time: u64,
        observed: Observation,
    ) -> Result<Vec<Event>, Refusal> {
        // A log seen already is dropped: the indexer can send one twice across a crash. Observations that aren't logs
        // are settled by their refs, or change nothing the second time.
        let seen = self.chain.cursor;
        if log_index != NOT_A_LOG && seen.is_some_and(|seen| (block, log_index) <= seen) {
            return Err(Refusal::AlreadyObserved { block, log_index });
        }
        let observed = self.inward(observed)?;
        let time_before = self.campaigns.time;
        if time > 0 {
            self.campaigns.time = time_before.max(time);
        }
        let events = match self.take_observation(observed) {
            Ok(events) => events,
            Err(refusal) => {
                self.campaigns.time = time_before;
                return Err(refusal);
            }
        };
        if log_index != NOT_A_LOG {
            self.chain.cursor = Some((block, log_index));
        }
        self.chain.block = self.chain.block.max(block);
        Ok(events)
    }

    fn take_observation(&mut self, observed: Observation) -> Result<Vec<Event>, Refusal> {
        let mut events = Vec::new();
        match observed {
            Observation::WalletReady { player, address } => {
                let p = self.life.get_mut(&player)?;
                if p.wallet.as_deref() == Some(address.as_str()) {
                    return Err(Refusal::NothingNew);
                }
                p.wallet = Some(address.clone());
                events.push(Event::WalletReady {
                    account: player,
                    address,
                });
            }
            Observation::Balances { player, usdc } => {
                let p = self.life.get_mut(&player)?;
                if p.usdc == Some(usdc) {
                    return Err(Refusal::NothingNew);
                }
                p.usdc = Some(usdc);
                events.push(Event::BalanceChanged {
                    account: player,
                    usdc,
                });
            }
            Observation::MealEaten {
                player,
                item,
                usdc,
                food,
                from_ration,
                reference,
                tx,
            } => {
                let out = self.settle(&reference)?;
                match out.purpose {
                    Purpose::Meal { voucher, .. } => {
                        events = self.meal_eaten(
                            &player,
                            &item,
                            usdc,
                            food,
                            from_ration,
                            reference,
                            tx,
                            false,
                            !voucher,
                        );
                    }
                    Purpose::Rescue { max_usdc, .. } => {
                        self.house.paid(Bucket::Safety, usdc, max_usdc);
                        events = self.meal_eaten(
                            &player,
                            &item,
                            usdc,
                            food,
                            from_ration,
                            reference,
                            tx,
                            true,
                            false,
                        );
                    }
                    _ => {}
                }
            }
            Observation::HarvestSold {
                offered,
                sold,
                usdc,
                reference,
                tx: _,
            } => {
                self.settle(&reference)?;
                self.house.treasury.revenue_today += usdc;
                self.house.treasury.revenue_total += usdc;
                events.push(Event::FoodSold {
                    day: self.market.today(),
                    offered,
                    sold,
                    usdc_got: usdc,
                    reference,
                });
            }
            Observation::FoodTrade {
                usdc,
                food,
                price_after,
                ..
            } => {
                if !self.mode.on_chain() {
                    return Err(Refusal::NothingNew);
                }
                events = self.market.observe_trade(usdc, food, price_after);
            }
            Observation::FoodDayOpened { open_price, .. } => {
                if !self.mode.on_chain() {
                    return Err(Refusal::NothingNew);
                }
                events = self.market.observe_open(open_price);
            }
            Observation::Split {
                total,
                fixed,
                safety,
                ops,
                team,
                tx: _,
            } => {
                let t = &mut self.house.treasury;
                t.split_total += total;
                t.to_fixed += fixed;
                t.to_safety += safety;
                t.to_ops += ops;
                t.to_team += team;
                self.house.stats.last_split_at = self.campaigns.time;
                events.push(Event::LedgerUpdated {
                    part: "treasury".to_string(),
                });
            }
            Observation::Paid {
                bucket,
                player,
                amount,
                reference,
                tx,
                ..
            } => {
                let out = self.settle(&reference)?;
                match out.purpose {
                    Purpose::Reward {
                        account,
                        why,
                        amount: sent,
                        ..
                    } => {
                        self.house.paid(bucket, amount, sent);
                        events.push(Event::RewardPaid {
                            account,
                            amount,
                            why,
                            reference,
                            tx,
                        });
                    }
                    Purpose::Voucher { account, item } => {
                        self.house.paid(bucket, amount, amount);
                        self.voucher_paid(&account, &item, &reference, &mut events);
                    }
                    _ => {}
                }
                let _ = player;
            }
            Observation::CampaignCreated {
                id,
                sponsor,
                template,
                meta_hash,
                budget,
                payout_per_claim,
                energy_cost,
                max_claims,
                per_human_cap,
                start,
                end,
                kind,
                deliver_to,
            } => {
                let campaign = Campaign {
                    id,
                    sponsor,
                    template: template.clone(),
                    meta_hash,
                    budget,
                    payout: payout_per_claim,
                    energy: energy_cost,
                    max_claims,
                    per_human_cap,
                    start,
                    end,
                    kind,
                    deliver_to,
                    claims: 0,
                    spent: 0,
                    held: 0,
                    humans: Default::default(),
                    closed: false,
                };
                if !self.campaigns.add(campaign) {
                    return Err(Refusal::NothingNew);
                }
                events.push(Event::BountyPosted {
                    campaign: id,
                    template,
                });
            }
            Observation::Claimed {
                campaign,
                player,
                amount,
                advance_repaid,
                reference,
                tx,
                ..
            } => {
                let out = self.settle(&reference)?;
                if let Some(c) = self.campaigns.get_mut(campaign) {
                    c.claims += 1;
                    c.held = c.held.saturating_sub(1);
                    c.spent += amount;
                    c.humans.insert(player);
                }
                if let Purpose::Reward { account, why, .. } = out.purpose {
                    events.push(Event::RewardPaid {
                        account,
                        amount: amount + advance_repaid,
                        why,
                        reference,
                        tx,
                    });
                }
            }
            Observation::Advanced {
                campaign,
                amount,
                reference,
                ..
            } => {
                let out = self.settle(&reference)?;
                if let Some(c) = self.campaigns.get_mut(campaign) {
                    c.spent += amount;
                }
                if let Purpose::Advance { account, quest } = out.purpose {
                    if let Ok(p) = self.life.get_mut(&account) {
                        if let Some(usdc) = p.usdc.as_mut() {
                            *usdc += amount;
                        }
                    }
                    if let Some(index) = self.step_waiting_on(&account, &quest, &reference) {
                        self.step_done(&account, &quest, index, &mut events);
                    }
                }
            }
            Observation::Refunded { campaign, .. }
            | Observation::CampaignClosed { campaign, .. } => {
                let Some(c) = self.campaigns.get_mut(campaign) else {
                    return Err(Refusal::NothingNew);
                };
                if c.closed {
                    return Err(Refusal::NothingNew);
                }
                c.closed = true;
                events.push(Event::BountyClosed { campaign });
            }
            Observation::QuestSwap {
                player,
                amount_in,
                amount_out,
                ..
            } => {
                // A swap carries no ref: it settles the player's quest that's waiting on one.
                let waiting = self.life.get(&player)?.quests.iter().find_map(|(id, q)| {
                    q.steps
                        .iter()
                        .position(|s| s.kind == StepKind::Swap && s.waiting.is_some())
                        .map(|i| {
                            (
                                id.clone(),
                                i,
                                q.steps[i].waiting.clone().unwrap_or_default(),
                            )
                        })
                });
                let Some((quest, index, reference)) = waiting else {
                    return Err(Refusal::NothingNew);
                };
                self.settle(&reference)?;
                self.chain.quest_usdc_in += amount_in as Usdc;
                self.chain.quest_tokens_out += amount_out;
                let p = self.life.get_mut(&player)?;
                p.quest_tokens += amount_out;
                if let Some(q) = p.quests.get_mut(&quest) {
                    q.swapped += amount_out;
                }
                events.push(Event::QuestSwapped {
                    account: player.clone(),
                    quest: quest.clone(),
                    received: amount_out,
                });
                self.step_done(&player, &quest, index, &mut events);
            }
            Observation::Delivered {
                player,
                amount,
                reference,
                ..
            } => {
                let out = self.settle(&reference)?;
                let p = self.life.get_mut(&player)?;
                p.quest_tokens = p.quest_tokens.saturating_sub(amount);
                if let Purpose::Deliver { account, quest } = out.purpose {
                    if let Some(index) = self.step_waiting_on(&account, &quest, &reference) {
                        self.step_done(&account, &quest, index, &mut events);
                    }
                }
            }
            Observation::PoolBalances {
                fixed,
                surprise,
                safety,
                budget_fixed,
                budget_surprise,
                budget_safety,
            } => {
                let balances = [fixed, surprise, safety];
                let budgets = [budget_fixed, budget_surprise, budget_safety];
                if !self.house.observe_pools(balances, budgets, &self.config) {
                    return Err(Refusal::NothingNew);
                }
                events.push(Event::LedgerUpdated {
                    part: "house".to_string(),
                });
            }
            Observation::FloatState {
                total_assets,
                liquid,
                invested,
                buffer,
                liabilities,
                loss_reserve,
                yield_earned,
            } => {
                let float = crate::house::Float {
                    total_assets,
                    liquid,
                    invested,
                    buffer,
                    liabilities,
                    loss_reserve,
                    yield_earned,
                };
                if self.house.float == float {
                    return Err(Refusal::NothingNew);
                }
                self.house.float = float;
                events.push(Event::LedgerUpdated {
                    part: "float".to_string(),
                });
            }
            Observation::NameRegistered { player, name, .. } => {
                let p = self.life.get_mut(&player)?;
                if p.ens.as_deref() == Some(name.as_str()) {
                    return Err(Refusal::NothingNew);
                }
                p.ens = Some(name.clone());
                events.push(Event::NameRegistered {
                    account: player.clone(),
                    name,
                });
                self.write_profile_records(&player, &mut events);
            }
            Observation::RecordsSet {
                player, records, ..
            } => {
                let p = self.life.get_mut(&player)?;
                let signed = records.get("description").cloned();
                if let Some(sign) = &signed {
                    p.sign = sign.clone();
                }
                events.push(Event::RecordsSet {
                    account: player.clone(),
                    records,
                });
                if signed.is_some() {
                    self.finish_steps_of(&player, StepKind::Sign, &mut events);
                }
            }
            Observation::DrawCommitted { week, .. } => {
                if self.games.draws.get(&week).is_none_or(|d| d.committed) {
                    return Err(Refusal::NothingNew);
                }
                events = self.draw_committed(week);
            }
            Observation::DrawRevealed {
                week, winner_index, ..
            } => {
                if self
                    .games
                    .draws
                    .get(&week)
                    .is_none_or(|d| d.winner.is_some())
                {
                    return Err(Refusal::NothingNew);
                }
                events = self.draw_revealed(week, winner_index);
            }
            Observation::DrawClaimed {
                week,
                player,
                prize,
                tx,
            } => {
                let reference = format!("draw:{week}");
                self.chain.settled.insert(reference);
                events = self.draw_claimed(week, &player, prize, tx);
                if events.is_empty() {
                    return Err(Refusal::NothingNew);
                }
            }
            Observation::Holding {
                player,
                amount,
                reference,
                ..
            } => {
                let out = self.settle(&reference)?;
                if let Purpose::Holding { account, quest } = out.purpose {
                    self.holding_seen(&account, &quest, amount, &reference, &mut events);
                }
                let _ = player;
            }
            Observation::SwapQuoted {
                usdc_in,
                amount_out,
                fee_bps,
                token,
                symbol,
                decimals,
                reference,
                ..
            } => {
                let out = self.settle(&reference)?;
                if let Purpose::Quote { account, quest } = out.purpose {
                    let quote = crate::quests::Quote {
                        usdc_in,
                        amount_out,
                        fee_bps,
                        token,
                        symbol,
                        decimals,
                        quoted_at: self.now_ms,
                    };
                    self.quote_seen(&account, &quest, quote, &mut events);
                }
            }
            Observation::IntentFailed { reference, reason } => {
                events = self.intent_failed(reference, reason)?;
            }
        }
        Ok(events)
    }

    /// The chain refused an intent, and nothing moved. Each kind is put back the way it was, or tried again later.
    fn intent_failed(&mut self, reference: Ref, reason: String) -> Result<Vec<Event>, Refusal> {
        let mut events = Vec::new();
        let Some(out) = self.outbox.remove(&reference) else {
            return self.failed_without_ref(&reference);
        };
        // Kept, so a success seen later for this ref still counts. A ref works once even when it failed; a reward keeps
        // its ref, owed, to try again.
        self.chain.failed.insert(reference.clone(), out.clone());
        match out.purpose {
            Purpose::Meal { account, item, .. } => {
                if let Ok(p) = self.life.get_mut(&account) {
                    if p.pending_meal.as_deref() == Some(reference.as_str()) {
                        p.pending_meal = None;
                    }
                }
                events.push(Event::MealFailed {
                    account,
                    item,
                    reference,
                    reason,
                });
            }
            Purpose::Rescue { account, max_usdc } => {
                self.house.unsent(Bucket::Safety, max_usdc, None);
                self.rescue_directly(&account, &mut events);
            }
            Purpose::Reward {
                account,
                amount,
                payout,
                why,
            } => {
                if let Payout::House { bucket } = payout {
                    let human = self.life.player(&account).and_then(|p| p.human.clone());
                    self.house.unsent(bucket, amount, human.as_ref());
                }
                let owed = crate::house::Owed {
                    account: account.clone(),
                    amount,
                    payout,
                    why: why.clone(),
                    waiting: Waiting::Chain,
                };
                self.house.owed.insert(reference.clone(), owed);
                events.push(Event::RewardPending {
                    account,
                    amount,
                    why,
                    reference,
                    waiting: Waiting::Chain,
                });
            }
            Purpose::Voucher { account, item } => {
                let amount = match &out.intent {
                    Intent::PayHouse { amount, .. } => *amount,
                    _ => 0,
                };
                let human = self.life.player(&account).and_then(|p| p.human.clone());
                self.house.unsent(Bucket::Surprise, amount, human.as_ref());
                if let Ok(p) = self.life.get_mut(&account) {
                    p.vouchers += 1;
                    p.pending_meal = None;
                }
                events.push(Event::MealFailed {
                    account,
                    item,
                    reference,
                    reason,
                });
            }
            Purpose::Advance { account, quest }
            | Purpose::Swap { account, quest }
            | Purpose::Deliver { account, quest } => {
                self.step_failed(&account, &quest, &reference, &reason, &mut events);
            }
            Purpose::Holding { account, quest } => {
                // A balance read that failed isn't the player's fault: it counts as held.
                self.holding_seen(&account, &quest, u128::MAX, &reference, &mut events);
            }
            Purpose::Quote { account, quest } => {
                self.quote_failed(&account, &quest, &reason, &mut events);
            }
            Purpose::Harvest | Purpose::DrawClaim { .. } => {}
        }
        Ok(events)
    }

    /// Failures of intents without a ref. A draw that didn't commit gets a new seed; one that didn't reveal tries again.
    fn failed_without_ref(&mut self, reference: &str) -> Result<Vec<Event>, Refusal> {
        if let Some(week) = reference
            .strip_prefix("draw-commit:")
            .and_then(|w| w.parse().ok())
        {
            if let Some(draw) = self.games.draws.remove(&week) {
                self.house.draw_reserved = self.house.draw_reserved.saturating_sub(draw.prize);
                self.games.draw_due = Some(week);
                return Ok(Vec::new());
            }
        }
        if let Some(week) = reference
            .strip_prefix("draw-reveal:")
            .and_then(|w| w.parse::<u64>().ok())
        {
            let wait = self.config.draw.reveal_after_ms;
            if let Some(draw) = self.games.draws.get_mut(&week) {
                draw.reveal_sent = false;
                draw.reveal_at = Some(self.now_ms + wait);
                return Ok(Vec::new());
            }
        }
        // Wallets and names are asked for again on the next start; keepers' housekeeping runs again each day.
        Err(Refusal::NothingNew)
    }

    /// Whether an owed reward or a sent one with this ref exists. For tests and the money invariants.
    pub fn reward_known(&self, reference: &str) -> bool {
        self.house.owed.contains_key(reference) || self.outbox.contains_key(reference)
    }
}
