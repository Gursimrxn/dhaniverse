//! The food market: FoodRouter's door and FoodHook's day records, around one pool. At today's limit a trade fills
//! what fits instead of failing, and every trade carries a ref that works once.

use crate::pool::{Limits, Pool, UNIT};
use crate::{Event, Food, FoodConfig, Ref, Refusal, Usdc};
use std::collections::{HashMap, HashSet};

const BPS: u64 = 10_000;

/// The day's price ÷ the base price, in basis points: 1,020 over a base of 1,000 is 10,200.
pub fn food_index_bps(day_price: Usdc, base_price: Usdc) -> u32 {
    (day_price * BPS / base_price) as u32
}

/// What a meal of `food` costs at this index: the base price moved by the index, in USDC base units, rounded down.
/// The paper uses it to say how a day's average moved the menu.
pub fn meal_price(food: Food, base_price: Usdc, index_bps: u32) -> Usdc {
    let per_food = u128::from(base_price) * u128::from(index_bps) / u128::from(BPS);
    (per_food * u128::from(food) / UNIT) as Usdc
}

/// What `food` costs at `price` (USDC base units per whole FOOD), rounded up, as the pool rounds what it takes.
pub fn quote(food: Food, price: Usdc) -> Usdc {
    (u128::from(food) * u128::from(price)).div_ceil(UNIT) as Usdc
}

/// A meal ticket's most: the quote plus `slippage_bps` of headroom, rounded up.
pub fn with_slippage(quote: Usdc, slippage_bps: u32) -> Usdc {
    let most = u128::from(quote) * u128::from(BPS + u64::from(slippage_bps));
    most.div_ceil(u128::from(BPS)) as Usdc
}

/// One city day's record. `open_stock` is unset until the day's first trade. On a chain, `open_seen` is the opening
/// price FoodHook reported instead.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Day {
    pub open_stock: Option<Food>,
    pub open_seen: Option<Usdc>,
    pub usdc_total: Usdc,
    pub food_total: Food,
}

impl Day {
    /// Total USDC ÷ total FOOD, in USDC base units per FOOD, rounded down. Zero if nothing traded.
    pub fn price(&self) -> Usdc {
        day_price(self.usdc_total, self.food_total)
    }
}

/// FoodHook.dayPrice.
pub fn day_price(usdc_total: Usdc, food_total: Food) -> Usdc {
    if food_total == 0 {
        return 0;
    }
    (u128::from(usdc_total) * UNIT / u128::from(food_total)) as Usdc
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Market {
    pool: Pool,
    limits: Limits,
    base_price: Usdc,
    today: u64,
    food_index_bps: u32,
    /// Yesterday's index, for showing which way a price moved. The same as today's until there's a yesterday.
    yesterday_index_bps: u32,
    /// On a chain, the live price is the real pool's last `TradeCounted`, not this pool's.
    seen_price: Option<Usdc>,
    days: HashMap<u64, Day>,
    refs: HashSet<Ref>,
}

impl Market {
    pub fn new(config: &FoodConfig) -> Result<Self, Refusal> {
        if config.floor == 0 || config.floor >= config.ceiling {
            return Err(Refusal::BadSettings {
                floor: config.floor,
                ceiling: config.ceiling,
            });
        }
        if config.start_price < config.floor || config.start_price > config.ceiling {
            return Err(Refusal::StartOutsideBounds {
                price: config.start_price,
                floor: config.floor,
                ceiling: config.ceiling,
            });
        }
        Ok(Market {
            pool: Pool::new(config.pool_food * UNIT as Food, config.start_price),
            limits: Limits {
                band_bps: config.band_bps,
                floor: config.floor,
                ceiling: config.ceiling,
            },
            base_price: config.base_price,
            today: 0,
            food_index_bps: food_index_bps(config.start_price, config.base_price),
            yesterday_index_bps: food_index_bps(config.start_price, config.base_price),
            seen_price: None,
            days: HashMap::new(),
            refs: HashSet::new(),
        })
    }

    /// Buys up to `wanted` FOOD, stopping at today's limit. Already at the limit: buys nothing, and still succeeds.
    pub fn buy_food(&mut self, wanted: Food, reference: Ref) -> Result<Vec<Event>, Refusal> {
        self.check_ref(wanted, &reference)?;
        let (least, _) = self.bounds();
        let mut events = Vec::new();
        let (mut bought, mut usdc_paid) = (0, 0);
        if self.pool.stock() > least {
            self.open_day(&mut events);
            (bought, usdc_paid) = self.pool.buy(wanted, least);
            self.count_trade(usdc_paid, bought, &mut events);
        }
        self.refs.insert(reference.clone());
        events.push(Event::FoodBought {
            day: self.today,
            wanted,
            bought,
            usdc_paid,
            reference,
        });
        Ok(events)
    }

    /// Sells up to `offered` FOOD, stopping at today's limit. Already at the limit: sells nothing, and still succeeds.
    pub fn sell_food(&mut self, offered: Food, reference: Ref) -> Result<Vec<Event>, Refusal> {
        self.check_ref(offered, &reference)?;
        let (_, most) = self.bounds();
        let mut events = Vec::new();
        let (mut sold, mut usdc_got) = (0, 0);
        if self.pool.stock() < most {
            self.open_day(&mut events);
            (sold, usdc_got) = self.pool.sell(offered, most);
            self.count_trade(usdc_got, sold, &mut events);
        }
        self.refs.insert(reference.clone());
        events.push(Event::FoodSold {
            day: self.today,
            offered,
            sold,
            usdc_got,
            reference,
        });
        Ok(events)
    }

    /// Moves to a new day and reads the one that ended. A day with no trades keeps the last index.
    pub fn new_day(&mut self, day: u64) -> Result<Vec<Event>, Refusal> {
        if day <= self.today {
            return Err(Refusal::WrongDay {
                expected: self.today + 1,
                got: day,
            });
        }
        let day_price = self.day(self.today).price();
        self.yesterday_index_bps = self.food_index_bps;
        if day_price != 0 {
            self.food_index_bps = food_index_bps(day_price, self.base_price);
        }
        self.today = day;
        Ok(vec![Event::FoodIndexSet {
            day,
            day_price,
            food_index_bps: self.food_index_bps,
        }])
    }

    /// A trade FoodHook counted on chain. The chain's pool is the market, so its price is the live price.
    pub fn observe_trade(&mut self, usdc: Usdc, food: Food, price_after: Usdc) -> Vec<Event> {
        let record = self.days.entry(self.today).or_default();
        record.usdc_total += usdc;
        record.food_total += food;
        self.seen_price = Some(price_after);
        vec![Event::TradeCounted {
            day: self.today,
            usdc,
            food,
            price_after,
        }]
    }

    /// The day FoodHook opened on chain, at this price.
    pub fn observe_open(&mut self, open_price: Usdc) -> Vec<Event> {
        let record = self.days.entry(self.today).or_default();
        if record.open_seen.is_some() {
            return Vec::new();
        }
        record.open_seen = Some(open_price);
        self.seen_price.get_or_insert(open_price);
        vec![Event::DayOpened {
            day: self.today,
            open_price,
        }]
    }

    // ------------------------------------------------------------ reads

    pub fn today(&self) -> u64 {
        self.today
    }

    /// The live price, USDC base units per FOOD.
    pub fn price(&self) -> Usdc {
        self.seen_price.unwrap_or(self.pool.price())
    }

    /// What a meal of `food` costs now, at the live price.
    pub fn quote(&self, food: Food) -> Usdc {
        quote(food, self.price())
    }

    /// What it cost at yesterday's average price, for an arrow on the tag. The live quote after a quiet day.
    pub fn quote_yesterday(&self, food: Food) -> Usdc {
        let yesterday = match self.today {
            0 => 0,
            today => self.day(today - 1).price(),
        };
        match yesterday {
            0 => self.quote(food),
            price => quote(food, price),
        }
    }

    pub fn food_index_bps(&self) -> u32 {
        self.food_index_bps
    }

    pub fn yesterday_index_bps(&self) -> u32 {
        self.yesterday_index_bps
    }

    pub fn base_price(&self) -> Usdc {
        self.base_price
    }

    pub fn day(&self, day: u64) -> Day {
        self.days.get(&day).copied().unwrap_or_default()
    }

    /// That day's opening price (USDC base units per FOOD); zero before its first trade.
    pub fn open_price(&self, day: u64) -> Usdc {
        let record = self.day(day);
        record
            .open_seen
            .or(record.open_stock.map(|stock| self.pool.price_at(stock)))
            .unwrap_or(0)
    }

    // ------------------------------------------------------------ internals

    /// Today's stock limits. Before today's first trade, the live price is what the day will open at.
    fn bounds(&self) -> (Food, Food) {
        let open = self.day(self.today).open_stock.unwrap_or(self.pool.stock());
        self.pool.bounds(open, self.limits)
    }

    fn check_ref(&self, amount: Food, reference: &Ref) -> Result<(), Refusal> {
        if amount == 0 {
            return Err(Refusal::ZeroAmount);
        }
        if self.refs.contains(reference) {
            return Err(Refusal::RefUsed {
                reference: reference.clone(),
            });
        }
        Ok(())
    }

    fn open_day(&mut self, events: &mut Vec<Event>) {
        let record = self.days.entry(self.today).or_default();
        if record.open_stock.is_none() {
            record.open_stock = Some(self.pool.stock());
            events.push(Event::DayOpened {
                day: self.today,
                open_price: self.pool.price(),
            });
        }
    }

    fn count_trade(&mut self, usdc: Usdc, food: Food, events: &mut Vec<Event>) {
        let record = self.days.entry(self.today).or_default();
        record.usdc_total += usdc;
        record.food_total += food;
        events.push(Event::TradeCounted {
            day: self.today,
            usdc,
            food,
            price_after: self.pool.price(),
        });
    }
}
