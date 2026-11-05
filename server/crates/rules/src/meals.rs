//! Food and energy. A meal is bought on chain with the player's own USDC, at the live pool price with a little headroom
//! for the price moving, and its FOOD is burned: energy only fills when the chain says it was eaten. There's a free
//! thali once a day, energy comes back by itself below a line, and a neighbour brings a meal to someone stuck.

use crate::chain::{Bucket, Intent};
use crate::market::with_slippage;
use crate::observe::Purpose;
use crate::{AccountId, Event, Food, Ref, Refusal, State, Usdc};

impl State {
    pub(crate) fn free_meal(&mut self, account: AccountId) -> Result<Vec<Event>, Refusal> {
        let now = self.now_ms;
        let (m, e) = (self.config.meals, self.config.energy);
        let player = self.life.get_mut(&account)?;
        if let Some(at) = player.free_meal_at {
            if now < at + m.free_meal_every_ms {
                return Err(Refusal::FreeMealNotReady {
                    ready_at: at + m.free_meal_every_ms,
                });
            }
        }
        let energy = player.energy_now(now, &e);
        if energy >= e.max {
            return Err(Refusal::EnergyFull { energy });
        }
        player.free_meal_at = Some(now);
        let energy = player.add_energy(m.free_meal_energy, now, &e);
        Ok(vec![Event::FreeMealEaten {
            account,
            energy,
            next_at: now + m.free_meal_every_ms,
        }])
    }

    /// When the free thali is next ready: now or earlier means it's ready.
    pub fn free_meal_at(&self, account: &str) -> u64 {
        let every = self.config.meals.free_meal_every_ms;
        self.life
            .player(account)
            .and_then(|p| p.free_meal_at)
            .map_or(0, |at| at + every)
    }

    /// A meal ticket's price and most: the live quote, and the quote with headroom.
    pub fn meal_ticket(&self, food: Food) -> (Usdc, Usdc) {
        let quote = self.market.quote(food);
        (quote, with_slippage(quote, self.config.meals.slippage_bps))
    }

    pub(crate) fn buy_meal(
        &mut self,
        account: AccountId,
        item: String,
        voucher: bool,
        reference: Ref,
    ) -> Result<Vec<Event>, Refusal> {
        let Some(meal) = self.menu_item(&item).cloned() else {
            return Err(Refusal::UnknownItem { item });
        };
        if self.ref_known(&reference) {
            return Err(Refusal::RefUsed { reference });
        }
        let (now, e) = (self.now_ms, self.config.energy);
        let (_, max_usdc) = self.meal_ticket(meal.food);
        let player = self.life.get(&account)?;
        let energy = player.energy_now(now, &e);
        if energy >= e.max {
            return Err(Refusal::EnergyFull { energy });
        }
        if let Some(pending) = &player.pending_meal {
            return Err(Refusal::MealPending {
                reference: pending.clone(),
            });
        }
        if player.wallet.is_none() {
            return Err(Refusal::NoWallet);
        }
        if voucher {
            return self.use_voucher(account, item, max_usdc, reference);
        }
        let have = player.usdc.unwrap_or(0);
        if have < max_usdc {
            return Err(Refusal::NotEnoughUsdc {
                have,
                need: max_usdc,
            });
        }
        self.life.get_mut(&account)?.pending_meal = Some(reference.clone());
        let mut events = vec![Event::MealOrdered {
            account: account.clone(),
            item: item.clone(),
            food: meal.food,
            max_usdc,
            reference: reference.clone(),
        }];
        let intent = Intent::BuyMeal {
            player: account.clone(),
            item: item.clone(),
            food: meal.food,
            max_usdc,
            reference,
        };
        let purpose = Purpose::Meal {
            account,
            item,
            voucher: false,
        };
        self.send(purpose, intent, &mut events);
        Ok(events)
    }

    /// A chest's voucher: the SURPRISE bucket pays the meal's most to the player's wallet, and when that lands the
    /// meal is bought with it.
    fn use_voucher(
        &mut self,
        account: AccountId,
        item: String,
        amount: Usdc,
        reference: Ref,
    ) -> Result<Vec<Event>, Refusal> {
        let player = self.life.get(&account)?;
        if player.vouchers == 0 {
            return Err(Refusal::NoVoucher);
        }
        let Some(human_id) = player.human.clone() else {
            return Err(Refusal::NeedsTownPass);
        };
        let paid_today = self.house.human_paid.get(&human_id).copied().unwrap_or(0);
        let over_cap = paid_today + amount > self.config.house.per_human_daily_cap;
        if over_cap || self.house.available(Bucket::Surprise) < amount {
            return Err(Refusal::BudgetSpent);
        }
        let player = self.life.get_mut(&account)?;
        player.vouchers -= 1;
        player.pending_meal = Some(reference.clone());
        if let Some(book) = self.house.buckets.get_mut(&Bucket::Surprise) {
            book.in_flight += amount;
        }
        *self.house.human_paid.entry(human_id.clone()).or_insert(0) += amount;
        let mut events = vec![Event::VoucherUsed {
            account: account.clone(),
            item: item.clone(),
            reference: reference.clone(),
        }];
        let intent = Intent::PayHouse {
            player: account.clone(),
            human_id,
            bucket: Bucket::Surprise,
            amount,
            reference,
        };
        self.send(Purpose::Voucher { account, item }, intent, &mut events);
        Ok(events)
    }

    /// A voucher's money has landed: now the meal is bought with it, under its own ticket.
    pub(crate) fn voucher_paid(
        &mut self,
        account: &str,
        item: &str,
        reference: &str,
        events: &mut Vec<Event>,
    ) {
        let Some(meal) = self.menu_item(item).cloned() else {
            return;
        };
        let (_, max_usdc) = self.meal_ticket(meal.food);
        let meal_ref = format!("{reference}:meal");
        if let Ok(player) = self.life.get_mut(account) {
            player.pending_meal = Some(meal_ref.clone());
        }
        events.push(Event::MealOrdered {
            account: account.to_string(),
            item: item.to_string(),
            food: meal.food,
            max_usdc,
            reference: meal_ref.clone(),
        });
        let intent = Intent::BuyMeal {
            player: account.to_string(),
            item: item.to_string(),
            food: meal.food,
            max_usdc,
            reference: meal_ref,
        };
        let purpose = Purpose::Meal {
            account: account.to_string(),
            item: item.to_string(),
            voucher: true,
        };
        self.send(purpose, intent, events);
    }

    /// A meal the chain says was eaten. Energy fills; a meal the player paid for counts towards Grandma's page; every
    /// meal counts towards the Town Goal. Offline, its FOOD is bought from the town's own pool now, as MealCounter
    /// would on chain.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn meal_eaten(
        &mut self,
        account: &str,
        item: &str,
        usdc: Usdc,
        food: Food,
        from_ration: Food,
        reference: Ref,
        tx: String,
        rescue: bool,
        own_money: bool,
    ) -> Vec<Event> {
        let now = self.now_ms;
        let (e, gain) = (
            self.config.energy,
            self.menu_item(item).map_or(0, |m| m.energy),
        );
        let mut events = Vec::new();
        let Ok(player) = self.life.get_mut(account) else {
            return events;
        };
        if player.pending_meal.as_deref() == Some(reference.as_str()) {
            player.pending_meal = None;
        }
        let energy = player.add_energy(gain, now, &e);
        if own_money {
            player.paid_meals += 1;
            if let Some(usdc_now) = player.usdc.as_mut() {
                *usdc_now = usdc_now.saturating_sub(usdc);
            }
        }
        events.push(Event::MealEaten {
            account: account.to_string(),
            item: item.to_string(),
            usdc,
            food,
            energy,
            from_ration,
            reference: reference.clone(),
            tx,
        });
        self.house.stats.meals_today += 1;
        self.house.stats.usdc_today += usdc;
        if rescue {
            self.house.stats.rescues_today += 1;
            self.house.stats.rescues_total += 1;
            self.house.stats.rescue_usdc_total += usdc;
            events.push(Event::RescueMeal {
                account: account.to_string(),
                energy,
                direct: false,
            });
        }
        if !self.mode.on_chain() {
            self.house.treasury.revenue_today += usdc;
            self.house.treasury.revenue_total += usdc;
            // Its own ref, with no name in it: the pool's trades are public, whose meal it was isn't.
            let n = self.house.stats.meals_today;
            let bought = self.market.buy_food(
                food,
                format!("meal-{}-{}-{n}", self.real_day(), self.now_ms),
            );
            events.extend(bought.unwrap_or_default());
        }
        self.count_meal_for_goal(&mut events);
        if own_money {
            self.check_meal_steps(account, &mut events);
        }
        events
    }

    /// The cheapest meal on the menu at the live price.
    pub fn cheapest_meal(&self) -> Usdc {
        self.config
            .menu
            .iter()
            .map(|m| self.market.quote(m.food))
            .min()
            .unwrap_or(0)
    }

    /// Someone stuck: almost no energy, too little USDC for the cheapest meal, today's free thali gone. A neighbour
    /// sets off with a thali, once a day per person, and only for people with the Town Pass.
    pub(crate) fn notice_the_stuck(&mut self, events: &mut Vec<Event>) {
        let now = self.now_ms;
        let (r, e) = (self.config.rescue.clone(), self.config.energy);
        let cheapest = self.cheapest_meal();
        let free_every = self.config.meals.free_meal_every_ms;
        let mut coming = Vec::new();
        for (name, p) in self.life.players() {
            // The rescue meal is sent from their own wallet, so they need one.
            let stuck = p.human.is_some()
                && p.wallet.is_some()
                && p.rescue_at.is_none()
                && p.pending_meal.is_none()
                && p.rescued_at.is_none_or(|at| now >= at + r.every_ms)
                && p.energy_now(now, &e) < r.below_energy
                && p.usdc.is_some_and(|usdc| usdc < cheapest)
                && p.free_meal_at.is_some_and(|at| now < at + free_every);
            if stuck {
                coming.push(name.clone());
            }
        }
        for account in coming {
            let at = now + r.delay_ms;
            if let Ok(player) = self.life.get_mut(&account) {
                player.rescue_at = Some(at);
            }
            events.push(Event::RescueComing { account, at });
        }
    }

    /// Neighbours who've arrived. The SAFETY bucket pays for the thali; if it can't, the energy is given straight
    /// away, so nobody is ever stuck.
    pub(crate) fn deliver_rescues(&mut self, events: &mut Vec<Event>) {
        let now = self.now_ms;
        let due: Vec<AccountId> = self
            .life
            .players()
            .filter(|(_, p)| p.rescue_at.is_some_and(|at| now >= at))
            .map(|(name, _)| name.clone())
            .collect();
        let item = self.config.rescue.item.clone();
        let Some(meal) = self.menu_item(&item).cloned() else {
            return;
        };
        let (_, max_usdc) = self.meal_ticket(meal.food);
        for account in due {
            let e = self.config.energy;
            let below = self.config.rescue.below_energy;
            let Ok(player) = self.life.get_mut(&account) else {
                continue;
            };
            player.rescue_at = None;
            // They found food in the meantime.
            if player.energy_now(now, &e) >= below {
                continue;
            }
            player.rescued_at = Some(now);
            let n = player.chests + player.paid_meals;
            let Some(human_id) = player.human.clone() else {
                continue;
            };
            if self.house.available(Bucket::Safety) < max_usdc {
                self.rescue_directly(&account, events);
                continue;
            }
            if let Some(book) = self.house.buckets.get_mut(&Bucket::Safety) {
                book.in_flight += max_usdc;
            }
            let reference = format!("rescue:{account}:{now}:{n}");
            let intent = Intent::PayRescueMeal {
                player: account.clone(),
                human_id,
                item: item.clone(),
                food: meal.food,
                max_usdc,
                reference,
            };
            self.send(Purpose::Rescue { account, max_usdc }, intent, events);
        }
    }

    /// The last resort: the thali's energy, given without a meal.
    pub(crate) fn rescue_directly(&mut self, account: &str, events: &mut Vec<Event>) {
        let now = self.now_ms;
        let e = self.config.energy;
        let gain = self
            .menu_item(&self.config.rescue.item)
            .map_or(0, |m| m.energy);
        if let Ok(player) = self.life.get_mut(account) {
            let energy = player.add_energy(gain, now, &e);
            events.push(Event::RescueMeal {
                account: account.to_string(),
                energy,
                direct: true,
            });
        }
    }
}
