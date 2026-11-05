//! The town's shared games: Price Call, the weekly Town Goal and the weekly draw. Tickets are earned, never bought.
//! The draw's seed is fixed and its hash committed on chain before anyone can know the winner, and revealed after; only
//! people with the Town Pass are in it, one entry per person.

use crate::chain::{Bucket, Intent, TicketRange};
use crate::house::share;
use crate::observe::Purpose;
use crate::{AccountId, Call, Event, Refusal, State, Usdc};
use serde::Serialize;
use std::collections::BTreeMap;

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize)]
pub struct TownGoal {
    pub week: u64,
    pub meals: u32,
    pub reached: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Draw {
    pub week: u64,
    pub tickets: Vec<TicketRange>,
    pub count: u64,
    pub prize: Usdc,
    #[serde(skip)]
    pub seed: String,
    pub seed_hash: String,
    /// Seen committed on chain.
    pub committed: bool,
    pub reveal_at: Option<u64>,
    pub reveal_sent: bool,
    pub winner: Option<AccountId>,
    pub claimed: bool,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Games {
    pub goal: TownGoal,
    /// A closed week waiting for the server to draw its seed.
    pub draw_due: Option<u64>,
    pub draws: BTreeMap<u64, Draw>,
}

impl Games {
    /// Whether this week's Town Goal was reached, which upgrades everyone's next chest.
    pub fn goal_upgrade(&self, week: u64) -> bool {
        self.goal.week == week && self.goal.reached
    }
}

impl State {
    pub(crate) fn price_call(
        &mut self,
        account: AccountId,
        call: Call,
    ) -> Result<Vec<Event>, Refusal> {
        let day = self.market.today();
        let player = self.life.get_mut(&account)?;
        if player.price_call.is_some_and(|(d, _)| d == day) {
            return Err(Refusal::AlreadyCalled { day });
        }
        player.price_call = Some((day, call));
        Ok(vec![Event::PriceCalled { account, day, call }])
    }

    /// A new city day: the market reads the day that closed, Price Calls on it are settled, and the keepers'
    /// housekeeping goes to the chain.
    pub(crate) fn new_city_day(&mut self, day: u64) -> Result<Vec<Event>, Refusal> {
        let closed = self.market.today();
        let before = self.market.food_index_bps();
        let mut events = self.market.new_day(day)?;
        let after = self.market.food_index_bps();
        let change = (i64::from(after) - i64::from(before)) * 10_000 / i64::from(before.max(1));
        let flat = i64::from(self.config.price_call.flat_bps);
        let moved = if change > flat {
            Call::Up
        } else if change < -flat {
            Call::Down
        } else {
            Call::Flat
        };
        let calls: Vec<(AccountId, Call)> = self
            .life
            .players()
            .filter_map(|(name, p)| match p.price_call {
                Some((d, call)) if d == closed => Some((name.clone(), call)),
                _ => None,
            })
            .collect();
        let tickets = self.config.price_call.tickets;
        for (account, call) in calls {
            let right = call == moved;
            events.push(Event::PriceCallSettled {
                account: account.clone(),
                day: closed,
                call,
                moved,
                right,
            });
            if right {
                self.add_tickets(&account, tickets, "price call", &mut events);
            }
        }
        self.ask(Intent::Split, &mut events);
        self.ask(Intent::Rebalance, &mut events);
        self.ask(Intent::HarvestYield, &mut events);
        Ok(events)
    }

    pub(crate) fn count_meal_for_goal(&mut self, events: &mut Vec<Event>) {
        let week = self.week();
        let goal = &mut self.games.goal;
        if goal.week != week {
            *goal = TownGoal {
                week,
                ..TownGoal::default()
            };
        }
        goal.meals += 1;
        let target = self.config.town_goal.meals;
        if !goal.reached && goal.meals >= target {
            goal.reached = true;
            events.push(Event::TownGoalReached {
                week,
                meals: goal.meals,
                target,
            });
        }
    }

    /// The week that closed: its tickets, one range per person with the Town Pass, wait for a seed.
    pub(crate) fn close_week(&mut self, week: u64) {
        let ranges = self.ticket_ranges(week);
        if !ranges.is_empty() && !self.games.draws.contains_key(&week) {
            self.games.draw_due = Some(week);
        }
    }

    /// Week `week`'s tickets, as ranges, by name.
    pub fn ticket_ranges(&self, week: u64) -> Vec<TicketRange> {
        let mut next = 0;
        let mut ranges = Vec::new();
        for (name, p) in self.life.players() {
            let tickets = u64::from(p.tickets_in(week));
            if p.human.is_none() || tickets == 0 {
                continue;
            }
            ranges.push(TicketRange {
                player: name.clone(),
                from: next,
                to: next + tickets - 1,
            });
            next += tickets;
        }
        ranges
    }

    /// The server's seed for a closed week. The prize is a share of the SURPRISE balance, never more than what isn't
    /// already promised, and is held until it's claimed.
    pub(crate) fn commit_draw(
        &mut self,
        week: u64,
        seed: String,
        seed_hash: String,
    ) -> Result<Vec<Event>, Refusal> {
        if self.games.draw_due != Some(week) {
            return Err(Refusal::NoDrawDue { week });
        }
        self.games.draw_due = None;
        let tickets = self.ticket_ranges(week);
        let count = tickets.last().map_or(0, |r| r.to + 1);
        let book = self.house.book(Bucket::Surprise);
        let prize = share(book.balance, self.config.draw.prize_bps)
            .min(self.house.free_balance(Bucket::Surprise));
        if count == 0 || prize == 0 {
            return Ok(Vec::new());
        }
        self.house.draw_reserved += prize;
        let draw = Draw {
            week,
            tickets: tickets.clone(),
            count,
            prize,
            seed,
            seed_hash: seed_hash.clone(),
            committed: false,
            reveal_at: None,
            reveal_sent: false,
            winner: None,
            claimed: false,
        };
        self.games.draws.insert(week, draw);
        let mut events = vec![Event::DrawCommitted {
            week,
            tickets: count,
            prize,
        }];
        let intent = Intent::CommitDraw {
            week,
            seed_hash,
            root: String::new(),
            count,
            prize,
            tickets,
        };
        self.ask(intent, &mut events);
        Ok(events)
    }

    /// Reveals each committed draw once its wait is over.
    pub(crate) fn reveal_due_draws(&mut self, events: &mut Vec<Event>) {
        let now = self.now_ms;
        let due: Vec<u64> = self
            .games
            .draws
            .values()
            .filter(|d| d.committed && !d.reveal_sent && d.reveal_at.is_some_and(|at| now >= at))
            .map(|d| d.week)
            .collect();
        for week in due {
            let Some(draw) = self.games.draws.get_mut(&week) else {
                continue;
            };
            draw.reveal_sent = true;
            let seed = draw.seed.clone();
            self.ask(Intent::RevealDraw { week, seed }, events);
        }
    }

    pub(crate) fn draw_committed(&mut self, week: u64) -> Vec<Event> {
        let reveal_at = self.now_ms + self.config.draw.reveal_after_ms;
        if let Some(draw) = self.games.draws.get_mut(&week) {
            draw.committed = true;
            draw.reveal_at = Some(reveal_at);
        }
        Vec::new()
    }

    /// The chain picked the winning ticket. The winner's claim goes to the chain with their range.
    pub(crate) fn draw_revealed(&mut self, week: u64, winner_index: u64) -> Vec<Event> {
        let mut events = Vec::new();
        let Some(draw) = self.games.draws.get_mut(&week) else {
            return events;
        };
        let Some(range) = draw
            .tickets
            .iter()
            .find(|r| r.from <= winner_index && winner_index <= r.to)
            .cloned()
        else {
            return events;
        };
        draw.winner = Some(range.player.clone());
        events.push(Event::DrawRevealed { week });
        let intent = Intent::ClaimDraw {
            week,
            player: range.player.clone(),
            from: range.from,
            to: range.to,
            reference: format!("draw:{week}"),
        };
        let purpose = Purpose::DrawClaim {
            week,
            account: range.player,
        };
        self.send(purpose, intent, &mut events);
        events
    }

    pub(crate) fn draw_claimed(
        &mut self,
        week: u64,
        account: &str,
        prize: Usdc,
        tx: String,
    ) -> Vec<Event> {
        let Some(draw) = self.games.draws.get_mut(&week) else {
            return Vec::new();
        };
        if draw.claimed {
            return Vec::new();
        }
        draw.claimed = true;
        self.house.draw_reserved = self.house.draw_reserved.saturating_sub(draw.prize);
        if let Some(book) = self.house.buckets.get_mut(&Bucket::Surprise) {
            book.balance = book.balance.saturating_sub(prize);
        }
        self.outbox.remove(&format!("draw:{week}"));
        vec![Event::DrawWon {
            account: account.to_string(),
            week,
            prize,
            tx,
        }]
    }
}
