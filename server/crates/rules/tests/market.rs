//! The food market's rules, checked with the numbers from `contracts/test/food/` and the architecture's table.

mod common;

use common::{food, seen, Rand, World};
use rules::market::{day_price, food_index_bps, meal_price};
use rules::{apply, Command, Event, FoodConfig, Refusal, Role, State};

/// Hundreds of USDC base units: the pool's prices are about 1,000 a FOOD.
const fn hundreds(n: u64) -> u64 {
    n * 100
}

const START: u64 = 1000;
const FLOOR: u64 = 500;
const CEILING: u64 = 3000;

impl World {
    fn buy(&mut self, wanted: u64) -> (u64, u64) {
        self.buy_food(wanted)
    }

    fn sell(&mut self, offered: u64) -> (u64, u64) {
        let reference = self.fresh_ref();
        let events = self.run(Command::SellFood { offered, reference }).unwrap();
        match events.last() {
            Some(Event::FoodSold { sold, usdc_got, .. }) => (*sold, *usdc_got),
            other => panic!("expected FoodSold, got {other:?}"),
        }
    }

    fn next_day(&mut self) -> Vec<Event> {
        let day = self.state.market.today() + 1;
        self.run(Command::NewDay { day }).unwrap()
    }

    fn price(&self) -> u64 {
        self.state.market.price()
    }
}

fn assert_within(value: u64, target: u64, tolerance: u64, what: &str) {
    assert!(
        value.abs_diff(target) <= tolerance,
        "{what}: {value} is not {target} ± {tolerance}"
    );
}

// ---------------------------------------------------------------- buying and selling

#[test]
fn about_120_food_moves_a_5000_food_pool_the_full_5_percent() {
    let mut w = World::new();
    let (bought, paid) = w.buy(food(1000));
    assert_within(bought, food(120), food(1), "bought");
    assert!(bought < food(1000), "only part filled: today's limit");
    assert!(w.price() <= START * 105 / 100, "never above +5%");
    assert!(
        w.price() >= START * 104 / 100,
        "and it got close to the limit"
    );
    assert_within(
        paid,
        bought * START / food(1) * 102 / 100,
        hundreds(20),
        "about 1,025 a FOOD",
    );
}

#[test]
fn a_batch_under_the_limit_fills_in_full_at_about_10_hundreds() {
    let mut w = World::new();
    let (bought, paid) = w.buy(food(50));
    assert_eq!(bought, food(50));
    assert_within(paid, hundreds(500), hundreds(25), "about 1,000 a FOOD");
    let (sold, got) = w.sell(food(50));
    assert_eq!(sold, food(50));
    assert_within(got, hundreds(500), hundreds(25), "about 1,000 a FOOD");
    assert!(got <= paid, "a round trip never makes money from the pool");
}

#[test]
fn at_the_limit_a_buy_fills_nothing_and_still_succeeds() {
    let mut w = World::new();
    w.buy(food(1000));
    assert_eq!(w.buy(food(10)), (0, 0));
}

#[test]
fn a_sell_stops_at_minus_5_percent_and_reports_what_sold() {
    let mut w = World::new();
    let (sold, _) = w.sell(food(10_000));
    assert!(sold < food(10_000), "only part sold: today's limit");
    assert_within(
        sold,
        food(130),
        food(2),
        "sqrt(1/0.95) of 5,000 FOOD is about 130 more",
    );
    assert!(w.price() >= START * 95 / 100, "never below -5%");
    assert!(
        w.price() <= START * 96 / 100,
        "and it got close to the limit"
    );
}

#[test]
fn a_buy_reports_wanted_and_bought() {
    let mut w = World::new();
    let events = w
        .run(Command::BuyFood {
            wanted: food(1000),
            reference: "b1".into(),
        })
        .unwrap();
    assert_eq!(
        events[0],
        Event::DayOpened {
            day: 0,
            open_price: START
        }
    );
    assert!(matches!(events[1], Event::TradeCounted { day: 0, .. }));
    let Event::FoodBought {
        wanted,
        bought,
        reference,
        ..
    } = &events[2]
    else {
        panic!("expected FoodBought");
    };
    assert_eq!(*wanted, food(1000));
    assert!(*bought < *wanted, "bought < wanted: the stall runs out");
    assert_eq!(reference, "b1");
}

// ---------------------------------------------------------------- refs and roles

#[test]
fn a_ref_works_once_across_buying_and_selling() {
    let mut w = World::new();
    w.run(Command::BuyFood {
        wanted: food(10),
        reference: "one ref".into(),
    })
    .unwrap();
    let retry = Command::SellFood {
        offered: food(10),
        reference: "one ref".into(),
    };
    assert_eq!(
        w.run(retry),
        Err(Refusal::RefUsed {
            reference: "one ref".into()
        })
    );
}

#[test]
fn only_the_buyer_buys_and_only_the_seller_sells() {
    let mut w = World::new();
    let buy = Command::BuyFood {
        wanted: food(1),
        reference: "a".into(),
    };
    assert_eq!(
        apply(&mut w.state, Role::Seller, buy),
        Err(Refusal::NotAllowed {
            has: Role::Seller,
            needs: Role::Buyer
        })
    );
    let sell = Command::SellFood {
        offered: food(1),
        reference: "b".into(),
    };
    assert_eq!(
        apply(&mut w.state, Role::Buyer, sell),
        Err(Refusal::NotAllowed {
            has: Role::Buyer,
            needs: Role::Seller
        })
    );
}

#[test]
fn zero_amounts_are_refused() {
    let mut w = World::new();
    let zero = Command::BuyFood {
        wanted: 0,
        reference: "z".into(),
    };
    assert_eq!(w.run(zero), Err(Refusal::ZeroAmount));
}

// ---------------------------------------------------------------- the day

#[test]
fn the_next_day_allows_another_5_percent_from_yesterdays_close() {
    let mut w = World::new();
    w.buy(food(1000));
    let close = w.price();
    w.next_day();
    let events = w
        .run(Command::BuyFood {
            wanted: food(1000),
            reference: "day two".into(),
        })
        .unwrap();
    assert_eq!(
        events[0],
        Event::DayOpened {
            day: 1,
            open_price: close
        }
    );
    assert!(
        w.price() <= close * 105 / 100 + 1,
        "at most 5% above yesterday's close"
    );
    assert!(w.price() > close * 104 / 100, "and it got there");
}

#[test]
fn the_ceiling_holds_over_many_days() {
    let mut w = World::new();
    for _ in 0..40 {
        w.buy(food(1000));
        w.next_day();
    }
    assert!(w.price() <= CEILING, "never above the ceiling");
    assert!(
        w.price() >= CEILING - 10,
        "and it reached it: {}",
        w.price()
    );
    assert_eq!(
        w.buy(food(1)),
        (0, 0),
        "pinned at the ceiling, nothing fills"
    );
}

#[test]
fn the_floor_holds_over_many_days() {
    let mut w = World::new();
    for _ in 0..40 {
        w.sell(food(10_000));
        w.next_day();
    }
    assert!(w.price() >= FLOOR, "never below the floor");
    assert!(w.price() <= FLOOR + 10, "and it reached it: {}", w.price());
    assert_eq!(
        w.sell(food(1)),
        (0, 0),
        "pinned at the floor, nothing fills"
    );
}

#[test]
fn a_day_must_move_forward() {
    let mut w = World::new();
    w.next_day();
    assert_eq!(
        w.run(Command::NewDay { day: 1 }),
        Err(Refusal::WrongDay {
            expected: 2,
            got: 1
        })
    );
}

#[test]
fn the_days_totals_add_up_both_sides() {
    let mut w = World::new();
    let (food1, paid) = w.buy(food(40));
    let (food2, got) = w.sell(food(15));
    let day = w.state.market.day(0);
    assert_eq!(day.usdc_total, paid + got);
    assert_eq!(day.food_total, food1 + food2);
    assert_eq!(day.price(), day_price(paid + got, food1 + food2));
    assert_within(day.price(), START, 20, "about 1,000 a FOOD");
    assert_eq!(w.state.market.day(7).price(), 0, "a quiet day has no price");
}

// ---------------------------------------------------------------- the day's price, the index, the menu

#[test]
fn day_price_is_1020_and_the_food_index_is_1_02() {
    // 101,000 for 100 FOOD + 52,000 for 50 FOOD → 153,000 ÷ 150.
    let price = day_price(hundreds(1010 + 520), food(100 + 50));
    assert_eq!(price, 1020);
    assert_eq!(food_index_bps(price, 1000), 10_200);
}

#[test]
fn a_meal_costs_its_food_at_the_base_price_moved_by_the_index() {
    assert_eq!(meal_price(food(1), 1000, 10_000), 1000, "a chai at 1.00");
    assert_eq!(
        meal_price(4_500_000, 1000, 10_200),
        4590,
        "a burger at 1.02"
    );
    assert_eq!(
        meal_price(food(8), 1000, 9_500),
        7600,
        "a restaurant meal at 0.95"
    );
}

#[test]
fn new_day_reads_yesterdays_price_and_a_quiet_day_keeps_it() {
    let mut w = World::new();
    assert_eq!(w.state.market.food_index_bps(), 10_000);
    w.buy(food(100));
    let price = w.state.market.day(0).price();
    assert_eq!(
        seen(&w.next_day()),
        [Event::FoodIndexSet {
            day: 1,
            day_price: price,
            food_index_bps: (price * 10) as u32
        }]
    );
    let index = w.state.market.food_index_bps();
    assert!(index > 10_000, "people bought, so food costs more");
    assert_eq!(
        seen(&w.next_day()),
        [Event::FoodIndexSet {
            day: 2,
            day_price: 0,
            food_index_bps: index
        }],
        "a quiet day keeps the last price"
    );
}

#[test]
fn yesterdays_index_is_kept_for_the_price_tags_arrows() {
    let mut w = World::new();
    assert_eq!(
        w.state.market.yesterday_index_bps(),
        10_000,
        "same as today, before a yesterday"
    );
    w.buy(food(100));
    w.next_day();
    let index = w.state.market.food_index_bps();
    assert_ne!(index, 10_000);
    assert_eq!(w.state.market.yesterday_index_bps(), 10_000);

    // A quiet day keeps the price, so it was the same yesterday.
    w.next_day();
    assert_eq!(w.state.market.food_index_bps(), index);
    assert_eq!(w.state.market.yesterday_index_bps(), index);
}

// ---------------------------------------------------------------- deploy checks

#[test]
fn bad_settings_are_refused() {
    let mut config = common::config();
    let good: FoodConfig = config.food;

    config.food.floor = 0;
    assert_eq!(
        State::new(&config).err(),
        Some(Refusal::BadSettings {
            floor: 0,
            ceiling: CEILING
        })
    );
    config.food = FoodConfig {
        floor: CEILING,
        ceiling: FLOOR,
        ..good
    };
    assert_eq!(
        State::new(&config).err(),
        Some(Refusal::BadSettings {
            floor: CEILING,
            ceiling: FLOOR
        })
    );
    config.food = FoodConfig {
        start_price: 400,
        ..good
    };
    assert_eq!(
        State::new(&config).err(),
        Some(Refusal::StartOutsideBounds {
            price: 400,
            floor: FLOOR,
            ceiling: CEILING
        })
    );
}

// ---------------------------------------------------------------- the property that matters most

/// Whatever anyone tries, in any order, across days: the price never leaves the floor and ceiling, and never moves
/// more than 5% from the day's opening price. No in-role trade ever fails.
#[test]
fn price_never_leaves_its_band() {
    for seed in 0..50 {
        let mut w = World::new();
        let mut rand = Rand(seed);
        for _ in 0..400 {
            if rand.below(4) == 0 {
                w.next_day();
            }
            let amount = 1 + rand.below(food(5000));
            if rand.below(2) == 0 {
                w.buy(amount);
            } else {
                w.sell(amount);
            }
            let price = w.price();
            assert!((FLOOR..=CEILING).contains(&price), "{price}");
            let open = w.state.market.open_price(w.state.market.today());
            if open != 0 {
                assert!(
                    price <= open * 105 / 100 + 1,
                    "at most +5%: {price} from {open}"
                );
                assert!(
                    price + 1 >= open * 95 / 100,
                    "at most -5%: {price} from {open}"
                );
            }
        }
    }
}

#[test]
fn the_shipped_rules_toml_starts_a_world() {
    let text = include_str!("../../../rules.toml");
    let config: rules::Config = toml::from_str(text).unwrap();
    let state = State::new(&config).unwrap();
    assert!(!config.menu.is_empty(), "there's something to eat");
    for item in &config.menu {
        assert!(item.food > 0 && item.energy > 0, "{item:?}");
        assert!(
            state.market.quote(item.food) > 0,
            "{item:?} costs something"
        );
    }
}

#[test]
fn the_shipped_quest_book_passes_its_checks() {
    let book: rules::QuestBook = toml::from_str(include_str!("../../../quests.toml")).unwrap();
    book.check().unwrap();
    assert!(book.errands.len() >= 3, "a day's worth of errands");
    assert!(!book.mysteries.is_empty());
    assert!(book.grandma.is_some());
}

#[test]
fn a_meal_ticket_quotes_the_live_price_with_two_percent_of_headroom() {
    use rules::market::{quote, with_slippage};
    assert_eq!(quote(food(6), 4000), 24_000, "a thali at base: 0.024 USDC");
    assert_eq!(quote(1, 4000), 1, "rounded up, as the pool takes");
    assert_eq!(with_slippage(24_000, 200), 24_480);
    assert_eq!(with_slippage(1, 200), 2, "rounded up");
}
