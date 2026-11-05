//! Market Rush: a 90-second run behind the stall, timed by the server. Three free runs a real day. A run costs no
//! energy and pays nothing by itself: the day's best runs share the Rush pot when the day closes.

use crate::chain::Bucket;
use crate::house::{share, Category, Payout};
use crate::{is_person, AccountId, Event, Ref, Refusal, State};

impl State {
    pub(crate) fn start_rush(&mut self, account: AccountId) -> Result<Vec<Event>, Refusal> {
        let (now, today, resets_at) = (self.now_ms, self.real_day(), self.next_real_day_at());
        let c = self.config.rush.clone();
        let player = self.life.get_mut(&account)?;
        if player.in_rush {
            return Err(Refusal::AlreadyInRush);
        }
        let used = if player.runs.0 == today {
            player.runs.1
        } else {
            0
        };
        if used >= c.runs_per_day {
            return Err(Refusal::NoRunsLeft {
                most: c.runs_per_day,
                resets_at,
            });
        }
        player.runs = (today, used + 1);
        player.in_rush = true;
        player.served = 0;
        player.rush_ends_at = now + c.run_ms;
        Ok(vec![Event::RushStarted {
            account,
            ends_at: player.rush_ends_at,
            runs_left: c.runs_per_day - used - 1,
        }])
    }

    /// One order handed over. The run's count is what matters.
    pub(crate) fn serve_order(
        &mut self,
        account: AccountId,
        reference: Ref,
    ) -> Result<Vec<Event>, Refusal> {
        if self.life.ref_used(&reference) {
            return Err(Refusal::RefUsed { reference });
        }
        let most = self.config.rush.most_orders_per_run;
        let now = self.now_ms;
        let player = self.life.get_mut(&account)?;
        if !player.in_rush {
            return Err(Refusal::NotInRush);
        }
        if now >= player.rush_ends_at {
            return Err(Refusal::RushOver);
        }
        if player.served >= most {
            return Err(Refusal::RushFull { most });
        }
        player.served += 1;
        let served = player.served;
        self.life.use_ref(&reference)?;
        Ok(vec![Event::OrderServed {
            account,
            served,
            reference,
        }])
    }

    /// Ends a run, early or because time's up. It counts towards today's best, and earns its tickets.
    pub(crate) fn end_rush(
        &mut self,
        account: AccountId,
        time_up: bool,
    ) -> Result<Vec<Event>, Refusal> {
        let today = self.real_day();
        let player = self.life.get_mut(&account)?;
        if !player.in_rush {
            return Err(Refusal::NotInRush);
        }
        player.in_rush = false;
        let served = player.served;
        let best = if player.rush_best.0 == today {
            player.rush_best.1
        } else {
            0
        };
        player.rush_best = (today, best.max(served));
        let mut events = Vec::new();
        if time_up {
            events.push(Event::RushTimeUp {
                account: account.clone(),
                served,
            });
        }
        events.push(Event::RushEnded {
            account: account.clone(),
            served,
        });
        if served > 0 {
            let tickets = self.config.rush.tickets_per_run;
            self.add_tickets(&account, tickets, "rush", &mut events);
        }
        Ok(events)
    }

    /// Runs whose 90 seconds are up.
    pub(crate) fn end_timed_out_runs(&mut self, events: &mut Vec<Event>) {
        let now = self.now_ms;
        let due: Vec<AccountId> = self
            .life
            .players()
            .filter(|(_, p)| p.in_rush && now >= p.rush_ends_at)
            .map(|(name, _)| name.clone())
            .collect();
        for account in due {
            events.extend(self.end_rush(account, true).unwrap_or_default());
        }
    }

    /// Real day `day`'s top runs, best first, names breaking ties.
    pub fn rush_standings(&self, day: u64) -> Vec<(AccountId, u32)> {
        let mut scored: Vec<(AccountId, u32)> = self
            .life
            .players()
            .filter(|(name, p)| is_person(name) && p.rush_best.0 == day && p.rush_best.1 > 0)
            .map(|(name, p)| (name.clone(), p.rush_best.1))
            .collect();
        scored.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
        scored.truncate(self.config.rush.pot_shares.len());
        scored
    }

    /// The Rush pot for the day that just closed, split by the weights among whoever placed. Paid from the FIXED
    /// bucket, never more than its share of the day's budget.
    pub(crate) fn pay_rush_pot(&mut self, day: u64, events: &mut Vec<Event>) {
        let placed = self.rush_standings(day);
        if placed.is_empty() {
            return;
        }
        let shares = self.config.rush.pot_shares.clone();
        let weight: u64 = shares
            .iter()
            .take(placed.len())
            .map(|w| u64::from(*w))
            .sum();
        let pot = self.house.category_left(Category::Rush, &self.config);
        if weight == 0 || pot == 0 {
            return;
        }
        for (place, (account, _)) in placed.iter().enumerate() {
            let bps = u64::from(shares[place]) * 10_000 / weight;
            let want = share(pot, bps as u32);
            let amount = self.house.take(Category::Rush, want, &self.config);
            let payout = Payout::House {
                bucket: Bucket::Fixed,
            };
            let reference = format!("rush:{day}:{account}");
            self.reward(account, payout, amount, "rush pot", reference, events);
        }
    }
}
