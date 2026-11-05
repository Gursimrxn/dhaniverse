//! Quests: errands, sponsored quests from live campaigns, Grandma's Ledger and the day's mystery. A quest costs its
//! energy when it's taken. Steps the client sees happen it reports itself; steps that are real on-chain actions are
//! only done when the chain is seen doing them. A finished quest pays in USDC, through the house or the campaign, and
//! in tickets, titles and ENS stamps.
//!
//! Quest ids: `errand:<id>`, `campaign:<id>`, `grandma`, `mystery:<id>`.

use crate::book::{QuestText, StepKind};
use crate::chain::{Bucket, Intent};
use crate::house::{Category, Payout};
use crate::observe::Purpose;
use crate::{dice, AccountId, Event, QuestReward, Ref, Refusal, State, Usdc};
use serde::Serialize;
use std::collections::BTreeMap;

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum QuestKind {
    Errand {
        template: String,
    },
    Campaign {
        campaign: u64,
        template: String,
    },
    Grandma,
    Mystery {
        template: String,
        boosted_by: Option<u64>,
    },
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct StepState {
    pub id: String,
    pub kind: StepKind,
    pub done: bool,
    /// The ref of what went to the chain for this step, while it waits to be seen there.
    pub waiting: Option<Ref>,
    /// A swap step's latest Uniswap quote, and when one was last asked for.
    pub quote: Option<Quote>,
    pub quote_asked_at: Option<u64>,
}

/// What the exchange kiosk shows: the cargo buys `amount_out` of the quest token now, in a pool with this fee.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Quote {
    pub usdc_in: Usdc,
    #[serde(with = "crate::chain::big")]
    pub amount_out: u128,
    pub fee_bps: u32,
    pub token: String,
    pub symbol: String,
    pub decimals: u8,
    pub quoted_at: u64,
}

/// The least a swap takes for a quote: `slippage_bps` under it, rounded down, without overflowing.
pub fn min_out(amount_out: u128, slippage_bps: u32) -> u128 {
    let keep = u128::from(10_000u32.saturating_sub(slippage_bps));
    amount_out / 10_000 * keep + amount_out % 10_000 * keep / 10_000
}

/// Hold the Line's checks: when each is due, and how many have passed.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Hold {
    pub ends: u64,
    pub due: Vec<u64>,
    pub asked: u32,
    pub passed: u32,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct ActiveQuest {
    pub quest: String,
    pub kind: QuestKind,
    pub title: String,
    pub any_order: bool,
    pub steps: Vec<StepState>,
    pub taken_at: u64,
    pub energy: u32,
    /// Paid meals before it was taken, for a `Meals` step.
    pub meals_before: u32,
    /// Quest tokens the swap got, for the delivery.
    pub swapped: u128,
    pub hold: Option<Hold>,
}

impl ActiveQuest {
    fn campaign(&self) -> Option<u64> {
        match &self.kind {
            QuestKind::Campaign { campaign, .. } => Some(*campaign),
            QuestKind::Mystery { boosted_by, .. } => *boosted_by,
            _ => None,
        }
    }

    /// Whether this step may be done now: the first undone step, or in an any-order quest any undone step, except
    /// that a strongbox waits for everything else.
    fn can_do(&self, index: usize) -> bool {
        let step = &self.steps[index];
        if step.done {
            return false;
        }
        let others_done = self
            .steps
            .iter()
            .enumerate()
            .all(|(i, s)| i == index || s.done);
        if step.kind == StepKind::Strongbox {
            return others_done;
        }
        self.any_order || self.steps[..index].iter().all(|s| s.done)
    }

    fn waiting(&self) -> Option<&StepState> {
        self.steps.iter().find(|s| s.waiting.is_some())
    }

    fn all_done(&self) -> bool {
        self.steps.iter().all(|s| s.done)
    }
}

/// The template's ENS stamp and title.
fn honours(template: &str) -> (Option<&'static str>, Option<&'static str>) {
    match template {
        "spice_run" => (Some("spice-run"), Some("Spice Runner")),
        "paint_sign" => (Some("shop-sign"), None),
        "town_pass" => (Some("town-pass"), None),
        "hold_line" => (Some("held-the-line"), Some("Steady Hand")),
        _ => (None, None),
    }
}

impl State {
    /// Today's mystery quest, and the campaign boosting it if there is one.
    pub fn todays_mystery(&self) -> Option<(&QuestText, Option<u64>)> {
        let all = &self.book.mysteries;
        if all.is_empty() {
            return None;
        }
        let at = dice::below(self.seed, "mystery", "", self.real_day(), all.len() as u64) as usize;
        Some((&all[at], self.campaigns.booster().map(|c| c.id)))
    }

    /// What finishing today's mystery would pay now.
    pub fn mystery_payout(&self) -> Usdc {
        match self.todays_mystery() {
            Some((_, Some(id))) => self.campaigns.get(id).map_or(0, |c| c.payout),
            Some((_, None)) => {
                let left = self.house.category_left(Category::Mystery, &self.config);
                self.config.mystery.payout.min(left)
            }
            None => 0,
        }
    }

    pub(crate) fn take_quest(
        &mut self,
        account: AccountId,
        quest: String,
    ) -> Result<Vec<Event>, Refusal> {
        let (now, today, season) = (self.now_ms, self.real_day(), self.season);
        let resets_at = self.next_real_day_at();
        let player = self.life.get(&account)?;
        if player.quests.contains_key(&quest) {
            return Err(Refusal::AlreadyOnQuest { quest });
        }
        let unknown = || Refusal::UnknownQuest {
            quest: quest.clone(),
        };
        let (kind, text, energy) = if let Some(id) = quest.strip_prefix("errand:") {
            let text = self.book.errand(id).ok_or_else(unknown)?.clone();
            let c = self.config.errands;
            let taken = if player.errands.0 == today {
                player.errands.1
            } else {
                0
            };
            if taken >= c.per_day {
                return Err(Refusal::NoErrandsLeft {
                    most: c.per_day,
                    resets_at,
                });
            }
            let kind = QuestKind::Errand {
                template: id.to_string(),
            };
            (kind, text, c.energy)
        } else if let Some(id) = quest.strip_prefix("campaign:") {
            let id: u64 = id.parse().map_err(|_| unknown())?;
            let campaign = self.campaigns.get(id).ok_or_else(unknown)?;
            if campaign.boosted() {
                return Err(unknown());
            }
            if !campaign.live(self.campaigns.time) {
                return Err(Refusal::CampaignClosed { campaign: id });
            }
            if campaign.slots_left() == 0 {
                return Err(Refusal::NoSlotsLeft { campaign: id });
            }
            let done = player.campaigns_done.get(&id).copied().unwrap_or(0);
            if done >= u32::from(campaign.per_human_cap) {
                return Err(Refusal::PerHumanCap {
                    campaign: id,
                    cap: campaign.per_human_cap,
                });
            }
            let text = self
                .book
                .templates
                .get(&campaign.template)
                .ok_or_else(unknown)?
                .clone();
            let kind = QuestKind::Campaign {
                campaign: id,
                template: campaign.template.clone(),
            };
            (kind, text, campaign.energy)
        } else if quest == "grandma" {
            let text = self.book.grandma.clone().ok_or_else(unknown)?;
            if player.grandma_season == Some(season) {
                return Err(Refusal::QuestDoneBefore { quest });
            }
            (QuestKind::Grandma, text, self.config.grandma.energy)
        } else if let Some(id) = quest.strip_prefix("mystery:") {
            let (text, boosted_by) = self.todays_mystery().ok_or_else(unknown)?;
            if text.id != id {
                return Err(unknown());
            }
            let c = self.config.mystery;
            let taken = if player.mysteries.0 == today {
                player.mysteries.1
            } else {
                0
            };
            if taken >= c.per_day {
                return Err(Refusal::NoMysteryLeft {
                    most: c.per_day,
                    resets_at,
                });
            }
            let kind = QuestKind::Mystery {
                template: id.to_string(),
                boosted_by,
            };
            (kind, text.clone(), c.energy)
        } else {
            return Err(unknown());
        };

        let e = self.config.energy;
        let player = self.life.get_mut(&account)?;
        player.spend_energy(energy, now, &e)?;
        match &kind {
            QuestKind::Errand { .. } => {
                let taken = if player.errands.0 == today {
                    player.errands.1
                } else {
                    0
                };
                player.errands = (today, taken + 1);
            }
            QuestKind::Mystery { .. } => {
                let taken = if player.mysteries.0 == today {
                    player.mysteries.1
                } else {
                    0
                };
                player.mysteries = (today, taken + 1);
            }
            _ => {}
        }
        let steps = text
            .steps
            .iter()
            .map(|s| StepState {
                id: s.id.clone(),
                kind: s.kind,
                done: false,
                waiting: None,
                quote: None,
                quote_asked_at: None,
            })
            .collect();
        let active = ActiveQuest {
            quest: quest.clone(),
            title: text.title.clone(),
            any_order: text.any_order,
            steps,
            taken_at: now,
            energy,
            meals_before: player.paid_meals,
            swapped: 0,
            hold: None,
            kind,
        };
        if let Some(id) = active.campaign() {
            if let Some(c) = self.campaigns.get_mut(id) {
                c.held += 1;
            }
        }
        let player = self.life.get_mut(&account)?;
        player.quests.insert(quest.clone(), active);
        let mut events = vec![Event::QuestTaken {
            account: account.clone(),
            quest: quest.clone(),
            energy,
        }];
        self.start_automatic_steps(&account, &quest, &mut events);
        Ok(events)
    }

    /// Steps nobody has to report: the Town Pass if they already have it, Hold the Line's first check.
    fn start_automatic_steps(&mut self, account: &str, quest: &str, events: &mut Vec<Event>) {
        let human = self.life.player(account).is_some_and(|p| p.human.is_some());
        if human {
            self.finish_steps_of(account, StepKind::Verify, events);
        }
        let Some(active) = self.quest(account, quest) else {
            return;
        };
        if active.steps.iter().any(|s| s.kind == StepKind::Hold) {
            self.start_hold(account, quest);
            self.ask_holding_checks(events);
        }
    }

    pub(crate) fn quest(&self, account: &str, quest: &str) -> Option<&ActiveQuest> {
        self.life.player(account)?.quests.get(quest)
    }

    fn quest_mut(&mut self, account: &str, quest: &str) -> Result<&mut ActiveQuest, Refusal> {
        self.life
            .get_mut(account)?
            .quests
            .get_mut(quest)
            .ok_or_else(|| Refusal::NotOnQuest {
                quest: quest.to_string(),
            })
    }

    /// The index of a step this command may do now, or why not.
    fn step_to_do(
        &self,
        account: &str,
        quest: &str,
        check: impl Fn(&StepState) -> bool,
    ) -> Result<usize, Refusal> {
        let player = self.life.get(account)?;
        let active = player
            .quests
            .get(quest)
            .ok_or_else(|| Refusal::NotOnQuest {
                quest: quest.to_string(),
            })?;
        if let Some(waiting) = active.waiting() {
            return Err(Refusal::StepWaiting {
                quest: quest.to_string(),
                step: waiting.id.clone(),
            });
        }
        let found = (0..active.steps.len()).find(|i| check(&active.steps[*i]) && active.can_do(*i));
        found.ok_or_else(|| {
            let next = active
                .steps
                .iter()
                .find(|s| !s.done)
                .map_or("", |s| s.id.as_str());
            Refusal::WrongStep {
                quest: quest.to_string(),
                step: next.to_string(),
            }
        })
    }

    pub(crate) fn quest_step(
        &mut self,
        account: AccountId,
        quest: String,
        step: String,
    ) -> Result<Vec<Event>, Refusal> {
        let index = self.step_to_do(&account, &quest, |s| s.id == step && s.kind.client_says())?;
        let kind = self.quest(&account, &quest).map(|q| q.steps[index].kind);
        let mut events = Vec::new();
        match kind {
            Some(StepKind::Paper) if self.city_event_today().is_empty() => {
                return Err(Refusal::NotAShockDay);
            }
            Some(StepKind::Cargo) => return self.collect_cargo(account, quest, index),
            _ => {}
        }
        self.step_done(&account, &quest, index, &mut events);
        Ok(events)
    }

    /// The harbourmaster's cargo. A wallet that holds it is ready to go; a short one gets an advance from the
    /// campaign, which needs the Town Pass.
    fn collect_cargo(
        &mut self,
        account: AccountId,
        quest: String,
        index: usize,
    ) -> Result<Vec<Event>, Refusal> {
        let cargo = self.config.templates.spice_run.cargo;
        let player = self.life.get(&account)?;
        if player.wallet.is_none() {
            return Err(Refusal::NoWallet);
        }
        let have = player.usdc.unwrap_or(0);
        let mut events = Vec::new();
        if have >= cargo {
            self.step_done(&account, &quest, index, &mut events);
            return Ok(events);
        }
        let Some(human_id) = player.human.clone() else {
            return Err(Refusal::NeedsTownPass);
        };
        let Some(campaign) = self.quest(&account, &quest).and_then(|q| q.campaign()) else {
            return Err(Refusal::NotEnoughUsdc { have, need: cargo });
        };
        let reference = format!("advance:{campaign}:{account}:{}", self.now_ms);
        let step = self.set_waiting(&account, &quest, index, &reference)?;
        events.push(Event::QuestStepSent {
            account: account.clone(),
            quest: quest.clone(),
            step,
            reference: reference.clone(),
        });
        let intent = Intent::Advance {
            campaign,
            player: account.clone(),
            human_id,
            amount: cargo - have,
            reference,
        };
        self.send(Purpose::Advance { account, quest }, intent, &mut events);
        Ok(events)
    }

    fn set_waiting(
        &mut self,
        account: &str,
        quest: &str,
        index: usize,
        reference: &str,
    ) -> Result<String, Refusal> {
        let active = self.quest_mut(account, quest)?;
        active.steps[index].waiting = Some(reference.to_string());
        Ok(active.steps[index].id.clone())
    }

    pub(crate) fn swap(
        &mut self,
        account: AccountId,
        quest: String,
        reference: Ref,
    ) -> Result<Vec<Event>, Refusal> {
        if self.ref_known(&reference) {
            return Err(Refusal::RefUsed { reference });
        }
        let index = self.step_to_do(&account, &quest, |s| s.kind == StepKind::Swap)?;
        let cargo = self.config.templates.spice_run.cargo;
        let player = self.life.get(&account)?;
        if player.wallet.is_none() {
            return Err(Refusal::NoWallet);
        }
        let have = player.usdc.unwrap_or(0);
        if have < cargo {
            return Err(Refusal::NotEnoughUsdc { have, need: cargo });
        }
        let campaign = self
            .quest(&account, &quest)
            .and_then(|q| q.campaign())
            .ok_or_else(|| Refusal::WrongStep {
                quest: quest.clone(),
                step: "swap".to_string(),
            })?;
        // The swap takes at least the kiosk's quote less the slippage, so the quote must be fresh.
        let c = self.config.templates.spice_run;
        let now = self.now_ms;
        let quote = self
            .quest(&account, &quest)
            .and_then(|q| q.steps[index].quote.clone())
            .filter(|q| q.usdc_in == cargo && now <= q.quoted_at + c.quote_fresh_ms);
        let Some(quote) = quote else {
            return Err(Refusal::QuoteStale { quest });
        };
        let step = self.set_waiting(&account, &quest, index, &reference)?;
        let mut events = vec![Event::QuestStepSent {
            account: account.clone(),
            quest: quest.clone(),
            step,
            reference: reference.clone(),
        }];
        let intent = Intent::SwapForQuest {
            player: account.clone(),
            campaign,
            usdc_in: cargo,
            min_out: min_out(quote.amount_out, c.slippage_bps),
            reference,
        };
        self.send(Purpose::Swap { account, quest }, intent, &mut events);
        Ok(events)
    }

    /// The kiosk asks Uniswap what the cargo buys now. At most once every `quote_every_ms` per quest.
    pub(crate) fn quote_swap(
        &mut self,
        account: AccountId,
        quest: String,
    ) -> Result<Vec<Event>, Refusal> {
        let index = self.step_to_do(&account, &quest, |s| s.kind == StepKind::Swap)?;
        let every = self.config.templates.spice_run.quote_every_ms;
        let asked = self
            .quest(&account, &quest)
            .and_then(|q| q.steps[index].quote_asked_at);
        if let Some(at) = asked {
            if self.now_ms < at + every {
                return Err(Refusal::QuoteTooSoon {
                    ready_at: at + every,
                });
            }
        }
        let mut events = Vec::new();
        self.ask_quote(&account, &quest, index, &mut events);
        Ok(events)
    }

    fn ask_quote(&mut self, account: &str, quest: &str, index: usize, events: &mut Vec<Event>) {
        let (now, cargo) = (self.now_ms, self.config.templates.spice_run.cargo);
        let Some(campaign) = self.quest(account, quest).and_then(|q| q.campaign()) else {
            return;
        };
        let Ok(active) = self.quest_mut(account, quest) else {
            return;
        };
        active.steps[index].quote_asked_at = Some(now);
        let reference = format!("quote:{campaign}:{account}:{now}");
        let intent = Intent::QuoteSwap {
            player: account.to_string(),
            campaign,
            usdc_in: cargo,
            reference,
        };
        let purpose = Purpose::Quote {
            account: account.to_string(),
            quest: quest.to_string(),
        };
        self.send(purpose, intent, events);
    }

    /// A swap step that's just been reached asks for its first quote by itself.
    fn quote_reached_swaps(&mut self, account: &str, events: &mut Vec<Event>) {
        let reached: Vec<(String, usize)> = match self.life.player(account) {
            Some(p) => p
                .quests
                .iter()
                .filter_map(|(id, q)| {
                    let i = (0..q.steps.len()).find(|i| {
                        let s = &q.steps[*i];
                        s.kind == StepKind::Swap && s.quote_asked_at.is_none() && q.can_do(*i)
                    })?;
                    Some((id.clone(), i))
                })
                .collect(),
            None => return,
        };
        for (quest, index) in reached {
            self.ask_quote(account, &quest, index, events);
        }
    }

    /// The quote came back: it's kept on the swap step, for the kiosk and for the swap's least.
    pub(crate) fn quote_seen(
        &mut self,
        account: &str,
        quest: &str,
        quote: Quote,
        events: &mut Vec<Event>,
    ) {
        let slippage_bps = self.config.templates.spice_run.slippage_bps;
        let Ok(active) = self.quest_mut(account, quest) else {
            return;
        };
        let Some(step) = active.steps.iter_mut().find(|s| s.kind == StepKind::Swap) else {
            return;
        };
        events.push(Event::SwapQuoted {
            account: account.to_string(),
            quest: quest.to_string(),
            usdc_in: quote.usdc_in,
            amount_out: quote.amount_out,
            min_out: min_out(quote.amount_out, slippage_bps),
            fee_bps: quote.fee_bps,
            slippage_bps,
            symbol: quote.symbol.clone(),
            decimals: quote.decimals,
        });
        step.quote = Some(quote);
    }

    /// The quote couldn't be had: it may be asked for again at once.
    pub(crate) fn quote_failed(
        &mut self,
        account: &str,
        quest: &str,
        reason: &str,
        events: &mut Vec<Event>,
    ) {
        let Ok(active) = self.quest_mut(account, quest) else {
            return;
        };
        if let Some(step) = active.steps.iter_mut().find(|s| s.kind == StepKind::Swap) {
            step.quote_asked_at = None;
        }
        events.push(Event::QuoteFailed {
            account: account.to_string(),
            quest: quest.to_string(),
            reason: reason.to_string(),
        });
    }

    pub(crate) fn deliver(
        &mut self,
        account: AccountId,
        quest: String,
        reference: Ref,
    ) -> Result<Vec<Event>, Refusal> {
        if self.ref_known(&reference) {
            return Err(Refusal::RefUsed { reference });
        }
        let index = self.step_to_do(&account, &quest, |s| s.kind == StepKind::Deliver)?;
        let campaign = self
            .quest(&account, &quest)
            .and_then(|q| q.campaign())
            .ok_or_else(|| Refusal::WrongStep {
                quest: quest.clone(),
                step: "deliver".to_string(),
            })?;
        let step = self.set_waiting(&account, &quest, index, &reference)?;
        let mut events = vec![Event::QuestStepSent {
            account: account.clone(),
            quest: quest.clone(),
            step,
            reference: reference.clone(),
        }];
        let intent = Intent::Deliver {
            player: account.clone(),
            campaign,
            reference,
        };
        self.send(Purpose::Deliver { account, quest }, intent, &mut events);
        Ok(events)
    }

    pub(crate) fn abandon_quest(
        &mut self,
        account: AccountId,
        quest: String,
    ) -> Result<Vec<Event>, Refusal> {
        let active = self
            .quest(&account, &quest)
            .ok_or_else(|| Refusal::NotOnQuest {
                quest: quest.clone(),
            })?;
        if let Some(waiting) = active.waiting() {
            return Err(Refusal::StepWaiting {
                quest,
                step: waiting.id.clone(),
            });
        }
        self.drop_quest(&account, &quest);
        Ok(vec![Event::QuestAbandoned { account, quest }])
    }

    /// Takes a quest off a player, letting go of any campaign slot it held.
    fn drop_quest(&mut self, account: &str, quest: &str) -> Option<ActiveQuest> {
        let active = self.life.get_mut(account).ok()?.quests.remove(quest)?;
        if let Some(id) = active.campaign() {
            self.campaigns.release(id);
        }
        Some(active)
    }

    pub(crate) fn fail_quest(
        &mut self,
        account: &str,
        quest: &str,
        reason: &str,
        events: &mut Vec<Event>,
    ) {
        if self.drop_quest(account, quest).is_some() {
            events.push(Event::QuestFailed {
                account: account.to_string(),
                quest: quest.to_string(),
                reason: reason.to_string(),
            });
        }
    }

    /// A step done. The last one finishes the quest.
    pub(crate) fn step_done(
        &mut self,
        account: &str,
        quest: &str,
        index: usize,
        events: &mut Vec<Event>,
    ) {
        let Ok(active) = self.quest_mut(account, quest) else {
            return;
        };
        let step = &mut active.steps[index];
        if step.done {
            return;
        }
        step.done = true;
        step.waiting = None;
        events.push(Event::QuestStepDone {
            account: account.to_string(),
            quest: quest.to_string(),
            step: step.id.clone(),
        });
        if active.all_done() {
            self.finish_quest(account, quest, events);
            return;
        }
        // The next step may be one that's done already: the Town Pass they hold, meals they've eaten.
        if self.life.player(account).is_some_and(|p| p.human.is_some()) {
            self.finish_steps_of(account, StepKind::Verify, events);
        }
        self.check_meal_steps(account, events);
        self.quote_reached_swaps(account, events);
    }

    /// A step the chain refused: it can be tried again.
    pub(crate) fn step_failed(
        &mut self,
        account: &str,
        quest: &str,
        reference: &str,
        reason: &str,
        events: &mut Vec<Event>,
    ) {
        let Ok(active) = self.quest_mut(account, quest) else {
            return;
        };
        let Some(step) = active
            .steps
            .iter_mut()
            .find(|s| s.waiting.as_deref() == Some(reference))
        else {
            return;
        };
        step.waiting = None;
        events.push(Event::QuestStepFailed {
            account: account.to_string(),
            quest: quest.to_string(),
            step: step.id.clone(),
            reason: reason.to_string(),
        });
    }

    /// The step waiting on this ref, if this player still has it.
    pub(crate) fn step_waiting_on(
        &self,
        account: &str,
        quest: &str,
        reference: &str,
    ) -> Option<usize> {
        let active = self.quest(account, quest)?;
        active
            .steps
            .iter()
            .position(|s| s.waiting.as_deref() == Some(reference))
    }

    /// Every step of this kind that may be done now, in all of a player's quests.
    pub(crate) fn finish_steps_of(
        &mut self,
        account: &str,
        kind: StepKind,
        events: &mut Vec<Event>,
    ) {
        let quests: Vec<String> = match self.life.player(account) {
            Some(p) => p.quests.keys().cloned().collect(),
            None => return,
        };
        for quest in quests {
            let ready = self.quest(account, &quest).and_then(|q| {
                (0..q.steps.len()).find(|i| q.steps[*i].kind == kind && q.can_do(*i))
            });
            if let Some(index) = ready {
                self.step_done(account, &quest, index, events);
            }
        }
    }

    /// A paid meal: any `Meals` step whose count it reaches is done.
    pub(crate) fn check_meal_steps(&mut self, account: &str, events: &mut Vec<Event>) {
        let need = self.config.grandma.meals;
        let Some(player) = self.life.player(account) else {
            return;
        };
        let eaten = player.paid_meals;
        let ready: Vec<(String, usize)> = player
            .quests
            .iter()
            .filter_map(|(id, q)| {
                let i = (0..q.steps.len())
                    .find(|i| q.steps[*i].kind == StepKind::Meals && q.can_do(*i))?;
                (eaten.saturating_sub(q.meals_before) >= need).then(|| (id.clone(), i))
            })
            .collect();
        for (quest, index) in ready {
            self.step_done(account, &quest, index, events);
        }
    }

    /// The quest is done: it pays, and the town hears.
    fn finish_quest(&mut self, account: &str, quest: &str, events: &mut Vec<Event>) {
        let Some(active) = self
            .life
            .get_mut(account)
            .ok()
            .and_then(|p| p.quests.remove(quest))
        else {
            return;
        };
        let (today, season) = (self.real_day(), self.season);
        let player = self.life.get_mut(account).expect("has the quest");
        player.quests_done += 1;
        let done_count = player.quests_done;
        let mut tickets = self.config.quests.tickets;
        let (mut stamp, mut title) = (None, None);
        let (payout, amount, why, reference) = match &active.kind {
            QuestKind::Errand { .. } => {
                let rate = self.errand_rate();
                let amount = self.house.take(Category::Errands, rate, &self.config);
                let payout = Payout::House {
                    bucket: Bucket::Fixed,
                };
                (
                    payout,
                    amount,
                    "errand",
                    format!("errand:{account}:{today}:{done_count}"),
                )
            }
            QuestKind::Campaign { campaign, template } => {
                let n = player.campaigns_done.entry(*campaign).or_insert(0);
                *n += 1;
                let n = *n;
                (stamp, title) = honours(template);
                let amount = self.campaigns.get(*campaign).map_or(0, |c| c.payout);
                let payout = Payout::Campaign {
                    campaign: *campaign,
                };
                (
                    payout,
                    amount,
                    "sponsored quest",
                    format!("claim:{campaign}:{account}:{n}"),
                )
            }
            QuestKind::Grandma => {
                player.grandma_season = Some(season);
                tickets += self.config.grandma.tickets;
                stamp = Some("grandmas-ledger");
                title = Some("Grandma's Heir");
                let want = self.config.grandma.strongbox;
                let amount = self.house.take(Category::Mystery, want, &self.config);
                let payout = Payout::House {
                    bucket: Bucket::Surprise,
                };
                (
                    payout,
                    amount,
                    "grandma's strongbox",
                    format!("grandma:{account}:{season}"),
                )
            }
            QuestKind::Mystery {
                boosted_by: Some(campaign),
                ..
            } => {
                let n = player.campaigns_done.entry(*campaign).or_insert(0);
                *n += 1;
                let n = *n;
                let amount = self.campaigns.get(*campaign).map_or(0, |c| c.payout);
                let payout = Payout::Campaign {
                    campaign: *campaign,
                };
                (
                    payout,
                    amount,
                    "mystery quest",
                    format!("claim:{campaign}:{account}:{n}"),
                )
            }
            QuestKind::Mystery {
                boosted_by: None, ..
            } => {
                let want = self.config.mystery.payout;
                let amount = self.house.take(Category::Mystery, want, &self.config);
                let payout = Payout::House {
                    bucket: Bucket::Surprise,
                };
                (
                    payout,
                    amount,
                    "mystery quest",
                    format!("mystery:{account}:{today}:{done_count}"),
                )
            }
        };
        let player = self.life.get_mut(account).expect("has the quest");
        let mut honoured = false;
        if let Some(stamp) = stamp {
            honoured |= player.stamps.insert(stamp.to_string());
        }
        if let Some(title) = title {
            if !player.titles.iter().any(|t| t == title) {
                player.titles.push(title.to_string());
                honoured = true;
            }
        }
        events.push(Event::QuestDone {
            account: account.to_string(),
            quest: quest.to_string(),
            title: active.title.clone(),
            reward: QuestReward {
                usdc: amount,
                tickets,
                title: title.map(str::to_string),
                stamp: stamp.map(str::to_string),
            },
        });
        self.add_tickets(account, tickets, "quest", events);
        if amount == 0 {
            // Nothing to claim: the campaign slot it held is free again.
            if let Payout::Campaign { campaign } = payout {
                self.campaigns.release(campaign);
            }
        }
        self.reward(account, payout, amount, why, reference, events);
        if honoured {
            self.write_profile_records(account, events);
        }
        self.check_referral(account, events);
    }

    // ------------------------------------------------------------ Hold the Line

    fn start_hold(&mut self, account: &str, quest: &str) {
        let (now, day_ms, seed) = (self.now_ms, self.config.clock.real_day_ms, self.seed);
        let c = self.config.templates.hold_line;
        let ends = now + u64::from(c.days) * day_ms;
        let mut due = vec![now];
        for k in 1..c.checks {
            let span = ends - now;
            let who = format!("{account}/{quest}/{now}");
            due.push(now + dice::below(seed, "hold-check", &who, u64::from(k), span.max(1)));
        }
        due.sort_unstable();
        if let Ok(active) = self.quest_mut(account, quest) {
            active.hold = Some(Hold {
                ends,
                due,
                asked: 0,
                passed: 0,
            });
        }
    }

    /// Sends the balance checks that are due, one at a time per quest, and finishes holds that have run their days.
    pub(crate) fn ask_holding_checks(&mut self, events: &mut Vec<Event>) {
        let now = self.now_ms;
        let mut asks: Vec<(AccountId, String, u64, usize)> = Vec::new();
        let mut finished: Vec<(AccountId, String, usize)> = Vec::new();
        for (name, p) in self.life.players() {
            for (id, q) in &p.quests {
                let (Some(hold), Some(campaign)) = (&q.hold, q.campaign()) else {
                    continue;
                };
                let Some(index) = q.steps.iter().position(|s| s.kind == StepKind::Hold) else {
                    continue;
                };
                if q.steps[index].waiting.is_some() || q.steps[index].done {
                    continue;
                }
                if hold.due.first().is_some_and(|at| *at <= now) {
                    asks.push((name.clone(), id.clone(), campaign, index));
                } else if hold.due.is_empty() && now >= hold.ends && q.can_do(index) {
                    finished.push((name.clone(), id.clone(), index));
                }
            }
        }
        for (account, quest, campaign, index) in asks {
            let Ok(active) = self.quest_mut(&account, &quest) else {
                continue;
            };
            let Some(hold) = active.hold.as_mut() else {
                continue;
            };
            hold.due.remove(0);
            hold.asked += 1;
            let reference = format!(
                "hold:{campaign}:{account}:{}:{}",
                active.taken_at, hold.asked
            );
            active.steps[index].waiting = Some(reference.clone());
            let intent = Intent::CheckHolding {
                player: account.clone(),
                campaign,
                reference,
            };
            self.send(Purpose::Holding { account, quest }, intent, events);
        }
        for (account, quest, index) in finished {
            self.step_done(&account, &quest, index, events);
        }
    }

    /// A balance check's answer. Holding less than the line fails the quest.
    pub(crate) fn holding_seen(
        &mut self,
        account: &str,
        quest: &str,
        amount: u128,
        reference: &str,
        events: &mut Vec<Event>,
    ) {
        let least = u128::from(self.config.templates.hold_line.min_amount);
        let Some(index) = self.step_waiting_on(account, quest, reference) else {
            return;
        };
        if amount < least {
            self.fail_quest(account, quest, "the balance dropped below the line", events);
            return;
        }
        if let Ok(active) = self.quest_mut(account, quest) {
            active.steps[index].waiting = None;
            if let Some(hold) = active.hold.as_mut() {
                hold.passed += 1;
            }
        }
    }

    /// Every quest anyone is on, for the clock's checks.
    pub fn quests_of(&self, account: &str) -> BTreeMap<String, ActiveQuest> {
        self.life
            .player(account)
            .map(|p| p.quests.clone())
            .unwrap_or_default()
    }
}
