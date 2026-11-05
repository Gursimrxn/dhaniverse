//! Coming back: the streak, the daily chest, the weekly chest and tickets for the weekly draw. A chest costs nothing,
//! is never sold, and its USDC, the golden drop, comes only from the SURPRISE bucket, which player money never funds.

use crate::chain::Bucket;
use crate::house::{Category, Payout};
use crate::market::with_slippage;
use crate::{dice, AccountId, ChestContents, ChestTier, Event, Refusal, State, Tier};

impl State {
    /// The first visit of a real day: the streak moves on, and a ticket.
    pub(crate) fn login(&mut self, account: AccountId) -> Result<Vec<Event>, Refusal> {
        let today = self.real_day();
        let window = self.config.streak.window_days;
        let player = self.life.get_mut(&account)?;
        let last = player.login_days.last().copied();
        if last == Some(today) {
            return Ok(Vec::new());
        }
        player.streak = if last.is_some_and(|d| d + 1 == today) {
            player.streak + 1
        } else {
            1
        };
        player.login_days.push(today);
        let from = today.saturating_sub(u64::from(window.max(1)) - 1);
        player.login_days.retain(|d| *d >= from);
        let mut events = vec![Event::LoggedIn {
            account: account.clone(),
            day: today,
            streak: player.streak,
            week_days: player.login_days.len() as u32,
        }];
        let tickets = self.config.streak.login_tickets;
        self.add_tickets(&account, tickets, "streak", &mut events);
        Ok(events)
    }

    /// Tickets for this week's draw.
    pub(crate) fn add_tickets(
        &mut self,
        account: &str,
        tickets: u32,
        why: &str,
        events: &mut Vec<Event>,
    ) {
        if tickets == 0 || !crate::is_person(account) {
            return;
        }
        let week = self.week();
        let Ok(player) = self.life.get_mut(account) else {
            return;
        };
        let total = player.tickets_in(week) + tickets;
        player.tickets = (week, total);
        events.push(Event::TicketsEarned {
            account: account.to_string(),
            tickets,
            why: why.to_string(),
            total,
        });
    }

    /// The tier the next daily chest will be: brass and gold for a streak, and one better after a Town Goal week.
    pub fn chest_tier(&self, account: &str) -> Tier {
        let c = &self.config.chest;
        let Some(player) = self.life.player(account) else {
            return Tier::Wood;
        };
        let tier = if player.streak >= c.gold_streak {
            Tier::Gold
        } else if player.streak >= c.brass_streak {
            Tier::Brass
        } else {
            Tier::Wood
        };
        if self.games.goal_upgrade(self.week()) && player.upgrade_week != Some(self.week()) {
            tier.up()
        } else {
            tier
        }
    }

    /// When the daily chest is next ready: now or earlier means it's ready.
    pub fn chest_ready_at(&self, account: &str) -> u64 {
        let every = self.config.chest.every_ms;
        self.life
            .player(account)
            .and_then(|p| p.chest_at)
            .map_or(0, |at| at + every)
    }

    /// When the weekly chest may next be opened, given enough days in the window.
    pub fn weekly_ready_at(&self, account: &str) -> u64 {
        let week_ms = 7 * self.config.clock.real_day_ms;
        self.life
            .player(account)
            .and_then(|p| p.weekly_at)
            .map_or(0, |at| at + week_ms)
    }

    pub(crate) fn open_chest(
        &mut self,
        account: AccountId,
        weekly: bool,
    ) -> Result<Vec<Event>, Refusal> {
        if weekly {
            return self.open_weekly_chest(account);
        }
        let now = self.now_ms;
        self.life.check_arrived(&account)?;
        let ready_at = self.chest_ready_at(&account);
        if now < ready_at {
            return Err(Refusal::ChestNotReady { ready_at });
        }
        let tier = self.chest_tier(&account);
        let c = self.config.chest;
        let odds: ChestTier = match tier {
            Tier::Wood => c.wood,
            Tier::Brass => c.brass,
            Tier::Gold => c.gold,
        };
        let player = self.life.get(&account)?;
        let n = u64::from(player.chests);
        let pity = player.since_drop + 1 >= c.pity_every;
        let rolled_drop = dice::chance(self.seed, "chest-drop", &account, n, odds.drop_bps);
        let mut voucher = dice::chance(self.seed, "chest-voucher", &account, n, odds.voucher_bps);
        let mut golden_drop = 0;
        if (pity || rolled_drop)
            && self.house.category_left(Category::Chest, &self.config) >= c.golden_drop
        {
            golden_drop = self
                .house
                .take(Category::Chest, c.golden_drop, &self.config);
        } else if pity {
            // The pity rule with no drops left today: a meal voucher instead.
            voucher = true;
        }
        if voucher {
            let thali = self.voucher_value();
            voucher = thali > 0 && self.house.category_left(Category::Chest, &self.config) >= thali;
            if voucher {
                self.house.take(Category::Chest, thali, &self.config);
            }
        }
        let week = self.week();
        let upgraded = self.games.goal_upgrade(week);
        let energy_config = self.config.energy;
        let player = self.life.get_mut(&account)?;
        player.chest_at = Some(now);
        player.chests += 1;
        player.since_drop = if golden_drop > 0 {
            0
        } else {
            player.since_drop + 1
        };
        if upgraded {
            player.upgrade_week = Some(week);
        }
        if voucher {
            player.vouchers += 1;
        }
        player.add_energy(odds.energy, now, &energy_config);
        let contents = ChestContents {
            energy: odds.energy,
            tickets: odds.tickets,
            voucher,
            golden_drop,
        };
        let mut events = vec![Event::ChestOpened {
            account: account.clone(),
            weekly: false,
            tier,
            contents,
        }];
        self.add_tickets(&account, odds.tickets, "chest", &mut events);
        let payout = Payout::House {
            bucket: Bucket::Surprise,
        };
        let reference = format!("chest:{account}:{n}");
        self.reward(
            &account,
            payout,
            golden_drop,
            "golden drop",
            reference,
            &mut events,
        );
        Ok(events)
    }

    /// What a voucher is worth when given: a thali at the live price, with the meal ticket's headroom.
    pub(crate) fn voucher_value(&self) -> u64 {
        let item = &self.config.rescue.item;
        self.menu_item(item).map_or(0, |m| {
            with_slippage(self.market.quote(m.food), self.config.meals.slippage_bps)
        })
    }

    fn open_weekly_chest(&mut self, account: AccountId) -> Result<Vec<Event>, Refusal> {
        let (now, today, week) = (self.now_ms, self.real_day(), self.week());
        let s = self.config.streak;
        let player = self.life.get(&account)?;
        let days = player.days_in_window(today, s.window_days);
        if days < s.days_needed {
            return Err(Refusal::WeeklyChestNotReady {
                days,
                need: s.days_needed,
            });
        }
        let ready_at = self.weekly_ready_at(&account);
        if now < ready_at {
            return Err(Refusal::ChestNotReady { ready_at });
        }
        let bonus = self
            .house
            .take(Category::Streak, s.weekly_bonus, &self.config);
        let energy_config = self.config.energy;
        let player = self.life.get_mut(&account)?;
        player.weekly_at = Some(now);
        player.add_energy(s.weekly_energy, now, &energy_config);
        let contents = ChestContents {
            energy: s.weekly_energy,
            tickets: s.weekly_tickets,
            voucher: false,
            golden_drop: bonus,
        };
        let mut events = vec![Event::ChestOpened {
            account: account.clone(),
            weekly: true,
            tier: Tier::Gold,
            contents,
        }];
        self.add_tickets(&account, s.weekly_tickets, "weekly chest", &mut events);
        let payout = Payout::House {
            bucket: Bucket::Fixed,
        };
        let reference = format!("weekly:{account}:{week}");
        self.reward(
            &account,
            payout,
            bonus,
            "weekly chest",
            reference,
            &mut events,
        );
        Ok(events)
    }
}
