//! A player's own day: arriving, energy and its free floor, meals bought on chain, timed Market Rush runs and the Rush
//! pot, and firsts.

mod common;

use common::{intents, seen, World, DAY, MINUTE, USDC};
use rules::chain::{Bucket, Intent, Observation};
use rules::house::Waiting;
use rules::{Command, Event, First, Refusal};

const SAM: &str = "sam";

fn cmd_buy(w: &mut World, item: &str) -> Result<Vec<Event>, Refusal> {
    let reference = w.fresh_ref();
    w.run(Command::BuyMeal {
        account: SAM.into(),
        item: item.into(),
        voucher: false,
        reference,
    })
}

fn meal_ref(events: &[Event]) -> (String, u64, u64) {
    match intents(events).first() {
        Some(Intent::BuyMeal {
            reference,
            max_usdc,
            food,
            ..
        }) => (reference.clone(), *max_usdc, *food),
        other => panic!("no meal ticket: {other:?}"),
    }
}

fn eaten(
    w: &mut World,
    item: &str,
    usdc: u64,
    food: u64,
    reference: &str,
) -> Result<Vec<Event>, Refusal> {
    w.observe(Observation::MealEaten {
        player: SAM.into(),
        item: item.into(),
        usdc,
        food,
        from_ration: 0,
        reference: reference.into(),
        tx: "0xtx".into(),
    })
}

fn start(w: &mut World) -> Result<Vec<Event>, Refusal> {
    w.run(Command::StartRush {
        account: SAM.into(),
    })
}

fn serve(w: &mut World) -> Result<Vec<Event>, Refusal> {
    let reference = w.fresh_ref();
    w.run(Command::ServeOrder {
        account: SAM.into(),
        reference,
    })
}

// ---------------------------------------------------------------- arriving and energy

#[test]
fn a_new_player_arrives_once_with_full_energy_and_is_given_a_wallet() {
    let mut w = World::new();
    let events = w
        .run(Command::Arrive {
            account: "mira".into(),
        })
        .unwrap();
    assert_eq!(
        seen(&events),
        [Event::Arrived {
            account: "mira".into(),
            energy: 100
        }]
    );
    assert_eq!(
        intents(&events),
        [Intent::EnsureWallet {
            player: "mira".into()
        }]
    );
    assert_eq!(
        w.run(Command::Arrive {
            account: "mira".into()
        }),
        Err(Refusal::AlreadyArrived {
            account: "mira".into()
        })
    );
}

#[test]
fn energy_comes_back_one_point_every_four_minutes_up_to_forty_and_no_further() {
    let mut w = World::new();
    w.set_energy(SAM, 20);
    w.later(4 * MINUTE - 1);
    assert_eq!(w.energy(SAM), 20, "not a whole four minutes yet");
    w.later(1);
    assert_eq!(w.energy(SAM), 21);
    w.later(10 * 4 * MINUTE);
    assert_eq!(w.energy(SAM), 31);
    w.later(DAY);
    assert_eq!(w.energy(SAM), 40, "the free floor stops at 40");
    let mut full = World::new();
    full.set_energy(SAM, 60);
    full.later(DAY);
    assert_eq!(
        full.energy(SAM),
        60,
        "above 40 nothing comes back by itself"
    );
}

#[test]
fn a_part_of_a_point_on_its_way_isnt_lost_when_energy_is_spent() {
    let mut w = World::new();
    w.set_energy(SAM, 30);
    w.later(3 * MINUTE);
    w.set_energy(SAM, 25);
    w.later(MINUTE);
    assert_eq!(
        w.energy(SAM),
        26,
        "the point that was 3 minutes along arrived on time"
    );
}

#[test]
fn the_free_thali_is_forty_energy_once_a_day_and_not_when_full() {
    let mut w = World::new();
    assert_eq!(
        w.run(Command::FreeMeal {
            account: SAM.into()
        }),
        Err(Refusal::EnergyFull { energy: 100 })
    );
    w.set_energy(SAM, 50);
    let events = w
        .run(Command::FreeMeal {
            account: SAM.into(),
        })
        .unwrap();
    assert_eq!(
        events,
        [Event::FreeMealEaten {
            account: SAM.into(),
            energy: 90,
            next_at: DAY
        }]
    );
    w.set_energy(SAM, 10);
    assert_eq!(
        w.run(Command::FreeMeal {
            account: SAM.into()
        }),
        Err(Refusal::FreeMealNotReady { ready_at: DAY })
    );
    w.at(DAY);
    w.run(Command::FreeMeal {
        account: SAM.into(),
    })
    .unwrap();
    assert_eq!(
        w.energy(SAM),
        80,
        "back to the free floor of 40 overnight, and the thali on top"
    );
}

// ---------------------------------------------------------------- meals

#[test]
fn a_meal_ticket_is_the_live_quote_with_headroom_and_energy_fills_only_when_the_chain_says() {
    let mut w = World::new();
    w.set_energy(SAM, 20);
    w.fund(SAM, USDC);
    let events = cmd_buy(&mut w, "thali").unwrap();
    let (reference, max_usdc, food) = meal_ref(&events);
    // 6 FOOD at 1,000 a FOOD is 6,000, plus 2%.
    assert_eq!((max_usdc, food), (6120, 6_000_000));
    assert!(matches!(
        events[0],
        Event::MealOrdered { max_usdc: 6120, .. }
    ));
    assert_eq!(w.energy(SAM), 20, "nothing until it's eaten on chain");
    assert_eq!(
        cmd_buy(&mut w, "chai"),
        Err(Refusal::MealPending {
            reference: reference.clone()
        }),
        "one ticket at a time"
    );
    let events = eaten(&mut w, "thali", 6000, food, &reference).unwrap();
    assert!(events.iter().any(|e| matches!(
        e,
        Event::MealEaten {
            energy: 90,
            usdc: 6000,
            ..
        }
    )));
    assert!(events.contains(&Event::FirstEarned {
        account: SAM.into(),
        first: First::FirstMeal
    }));
    assert!(
        events.iter().any(|e| matches!(e, Event::FoodBought { .. })),
        "offline, its FOOD is bought from the town's own pool at once"
    );
    assert_eq!(w.player(SAM).paid_meals, 1);
    assert_eq!(
        eaten(&mut w, "thali", 6000, food, &reference),
        Err(Refusal::RefUsed { reference }),
        "a meal is eaten once"
    );
}

#[test]
fn a_meal_is_refused_without_a_wallet_money_or_hunger_and_off_the_menu() {
    let mut w = World::new();
    assert_eq!(
        cmd_buy(&mut w, "thali"),
        Err(Refusal::EnergyFull { energy: 100 })
    );
    w.set_energy(SAM, 50);
    assert_eq!(
        cmd_buy(&mut w, "burger"),
        Err(Refusal::UnknownItem {
            item: "burger".into()
        })
    );
    assert_eq!(
        cmd_buy(&mut w, "thali"),
        Err(Refusal::NotEnoughUsdc {
            have: 0,
            need: 6120
        })
    );
    w.run(Command::Arrive {
        account: "mira".into(),
    })
    .unwrap();
    let reference = w.fresh_ref();
    let mira = Command::BuyMeal {
        account: "mira".into(),
        item: "chai".into(),
        voucher: false,
        reference,
    };
    assert_eq!(w.run(mira), Err(Refusal::EnergyFull { energy: 100 }));
}

#[test]
fn a_meal_the_chain_refused_clears_the_ticket_and_one_never_sent_changes_nothing() {
    let mut w = World::new();
    w.set_energy(SAM, 50);
    w.fund(SAM, USDC);
    let (reference, _, _) = meal_ref(&cmd_buy(&mut w, "chai").unwrap());
    let events = w
        .observe(Observation::IntentFailed {
            reference: reference.clone(),
            reason: "MealCounter__TooDear".into(),
        })
        .unwrap();
    assert!(
        matches!(&events[0], Event::MealFailed { reason, .. } if reason == "MealCounter__TooDear")
    );
    assert_eq!(w.player(SAM).pending_meal, None);
    assert_eq!(
        eaten(&mut w, "chai", 1, 1, "never-sent"),
        Err(Refusal::UnknownRef {
            reference: "never-sent".into()
        })
    );
    cmd_buy(&mut w, "chai").unwrap();
}

#[test]
fn a_log_seen_twice_is_dropped_and_a_balance_that_didnt_change_isnt_news() {
    let mut w = World::new();
    let at = |block, log_index| Command::Observe {
        block,
        log_index,
        time: 0,
        observed: Observation::FoodDayOpened {
            day: 0,
            open_price: 1,
        },
    };
    w.run(at(1000, 3)).unwrap_err(); // offline: a chain's market isn't followed
    w.fund(SAM, 5);
    assert_eq!(
        w.observe(Observation::Balances {
            player: SAM.into(),
            usdc: 5
        }),
        Err(Refusal::NothingNew)
    );
    let paid = Command::Observe {
        block: 2000,
        log_index: 4,
        time: 0,
        observed: Observation::Split {
            total: 10,
            fixed: 6,
            safety: 1,
            ops: 2,
            team: 1,
            tx: "0x".into(),
        },
    };
    w.run(paid.clone()).unwrap();
    assert_eq!(
        w.run(paid),
        Err(Refusal::AlreadyObserved {
            block: 2000,
            log_index: 4
        })
    );
}

// ---------------------------------------------------------------- Market Rush

#[test]
fn a_run_is_ninety_seconds_and_the_clock_ends_it() {
    let mut w = World::new();
    let events = start(&mut w).unwrap();
    assert_eq!(
        events,
        [Event::RushStarted {
            account: SAM.into(),
            ends_at: 90_000,
            runs_left: 2
        }]
    );
    serve(&mut w).unwrap();
    serve(&mut w).unwrap();
    assert_eq!(start(&mut w), Err(Refusal::AlreadyInRush));
    let events = w.later(90_000);
    assert!(events.contains(&Event::RushTimeUp {
        account: SAM.into(),
        served: 2
    }));
    assert!(events.contains(&Event::RushEnded {
        account: SAM.into(),
        served: 2
    }));
    assert_eq!(serve(&mut w), Err(Refusal::NotInRush));
    assert_eq!(w.player(SAM).energy, 100, "a run costs no energy");
}

#[test]
fn three_free_runs_a_day() {
    let mut w = World::new();
    for _ in 0..3 {
        start(&mut w).unwrap();
        w.run(Command::EndRush {
            account: SAM.into(),
        })
        .unwrap();
    }
    assert_eq!(
        start(&mut w),
        Err(Refusal::NoRunsLeft {
            most: 3,
            resets_at: DAY
        })
    );
    w.at(DAY);
    start(&mut w).unwrap();
}

#[test]
fn an_order_ref_works_once_and_a_run_has_so_many_customers() {
    let mut w = World::new();
    start(&mut w).unwrap();
    let order = Command::ServeOrder {
        account: SAM.into(),
        reference: "o".into(),
    };
    w.run(order.clone()).unwrap();
    assert_eq!(
        w.run(order),
        Err(Refusal::RefUsed {
            reference: "o".into()
        })
    );
    for _ in 1..40 {
        serve(&mut w).unwrap();
    }
    assert_eq!(serve(&mut w), Err(Refusal::RushFull { most: 40 }));
    assert_eq!(w.player(SAM).served, 40);
}

#[test]
fn the_days_best_runs_split_the_rush_pot_at_the_close_and_unverified_winners_are_owed() {
    let mut w = World::new();
    w.pools(100 * USDC, 100 * USDC, 20 * USDC);
    w.verify(SAM);
    start(&mut w).unwrap();
    for _ in 0..5 {
        serve(&mut w).unwrap();
    }
    w.run(Command::EndRush {
        account: SAM.into(),
    })
    .unwrap();
    w.run(Command::StartRush {
        account: "priya".into(),
    })
    .unwrap();
    for n in 0..3 {
        w.run(Command::ServeOrder {
            account: "priya".into(),
            reference: format!("p{n}"),
        })
        .unwrap();
    }
    w.run(Command::EndRush {
        account: "priya".into(),
    })
    .unwrap();
    let events = w.at(DAY);
    // The pot is 30% of the FIXED day budget: 4% of 100 USDC is 4 USDC, so 1.2 USDC, split 25:18.
    let pays = intents(&events);
    assert!(
        pays.contains(&Intent::PayHouse {
            player: SAM.into(),
            human_id: World::human(SAM),
            bucket: Bucket::Fixed,
            amount: 697_560,
            reference: "rush:0:sam".into(),
        }),
        "{pays:?}"
    );
    assert!(events.iter().any(|e| matches!(
        e,
        Event::RewardPending { account, amount: 502_320, waiting: Waiting::TownPass, .. } if account == "priya"
    )));
    assert_eq!(w.state.house.owed_to("priya"), 502_320);
}

// ---------------------------------------------------------------- firsts

#[test]
fn firsts_are_earned_once_each_and_carved_once() {
    let mut w = World::new();
    let carve = Command::CarveFirst {
        account: SAM.into(),
        first: First::FirstMeal,
    };
    assert_eq!(
        w.run(carve.clone()),
        Err(Refusal::NotEarned {
            first: First::FirstMeal
        })
    );
    w.set_energy(SAM, 50);
    w.fund(SAM, USDC);
    for _ in 0..2 {
        let (reference, _, food) = meal_ref(&cmd_buy(&mut w, "chai").unwrap());
        eaten(&mut w, "chai", 1000, food, &reference).unwrap();
    }
    assert_eq!(w.player(SAM).firsts.len(), 1);
    w.run(carve.clone()).unwrap();
    assert_eq!(
        w.run(carve),
        Err(Refusal::AlreadyCarved {
            first: First::FirstMeal
        })
    );
    assert_eq!(w.state.title(SAM), "Regular");
    assert_eq!(w.state.title("priya"), "Newcomer");
}

#[test]
fn a_resident_has_no_wallet_and_earns_no_firsts() {
    let mut w = World::new();
    let events = w
        .run(Command::Arrive {
            account: "resident:asha".into(),
        })
        .unwrap();
    assert!(intents(&events).is_empty(), "residents have no wallet");
}
