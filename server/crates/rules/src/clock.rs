//! The real clock. Everything timed happens here, in a fixed order, so a replay times it the same: runs end, neighbours
//! arrive, balance checks go out, draws are revealed, and real days and weeks close.

use crate::{Event, Refusal, State};

impl State {
    pub(crate) fn tick(&mut self, now_ms: u64) -> Result<Vec<Event>, Refusal> {
        if now_ms < self.now_ms {
            return Err(Refusal::WrongTime {
                now: self.now_ms,
                got: now_ms,
            });
        }
        let mut events = Vec::new();
        let day_ms = self.config.clock.real_day_ms.max(1);
        // Close each real day up to now at its own end, so a long skip plays out like the time passing.
        while now_ms / day_ms > self.now_ms / day_ms {
            let closing = self.now_ms / day_ms;
            self.now_ms = (closing + 1) * day_ms;
            self.end_timed_out_runs(&mut events);
            self.close_day(closing, &mut events);
        }
        self.now_ms = now_ms;
        self.end_timed_out_runs(&mut events);
        self.deliver_rescues(&mut events);
        self.notice_the_stuck(&mut events);
        self.ask_holding_checks(&mut events);
        self.reveal_due_draws(&mut events);
        self.expire_loot(&mut events);
        Ok(events)
    }

    /// A real day's close: the Rush pot is paid, the house's day starts over, and what's owed is tried again. A week's
    /// last day closes the week too.
    fn close_day(&mut self, day: u64, events: &mut Vec<Event>) {
        self.pay_rush_pot(day, events);
        self.house.new_day(&self.config);
        self.retry_owed(None, events);
        if (day + 1).is_multiple_of(7) {
            self.close_week(day / 7);
        }
    }
}
