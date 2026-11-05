//! Coming back and playing together: the streak and chests, meal vouchers, Price Call, the Town Goal, the weekly draw,
//! the rescue meal and referrals.

mod common;

use common::{intents, World, DAY, MINUTE, USDC};
use rules::chain::{Bucket, Intent, Observation};
use rules::{Call, Command, Config, Event, Refusal, Tier};

const SAM: &str = "sam";

fn open(w: &mut World, weekly: bool) -> Result<Vec<Event>, Refusal> {
    w.run(Command::OpenChest {
        account: SAM.into(),
        weekly,
    })
}

fn opened(events: &[Event]) -> (Tier, rules::ChestContents) {
    events
        .iter()
        .find_map(|e| match e {
            Event::ChestOpened { tier, contents, .. } => Some((*tier, *contents)),
            _ => None,
        })
        .expect("a chest")
}

/// Comes to town on each of the next `days` real days.
fn visit_daily(w: &mut World, days: u64) {
    for _ in 0..days {
        let next = (w.state.real_day() + 1) * DAY;
        w.at(next);
        w.run(Command::Login {
            account: SAM.into(),
        })
        .unwrap();
    }
}

#[test]
fn the_daily_chest_is_ready_once_a_day_and_its_tier_follows_the_streak() {
    let mut w = World::new();
    let events = open(&mut w, false).unwrap();
    let (tier, contents) = opened(&events);
    assert_eq!(tier, Tier::Wood);
    assert_eq!((contents.energy, contents.tickets), (10, 1));
    assert_eq!(
        open(&mut w, false),
        Err(Refusal::ChestNotReady { ready_at: DAY })
    );
    visit_daily(&mut w, 2);
    assert_eq!(w.player(SAM).streak, 3);
    assert_eq!(opened(&open(&mut w, false).unwrap()).0, Tier::Brass);
    visit_daily(&mut w, 4);
    assert_eq!(opened(&open(&mut w, false).unwrap()).0, Tier::Gold);
    w.at(w.state.now_ms + 3 * DAY);
    w.run(Command::Login {
        account: SAM.into(),
    })
    .unwrap();
    assert_eq!(
        w.player(SAM).streak,
        1,
        "a missed day starts the streak again"
    );
}

#[test]
fn five_visits_in_seven_days_open_the_weekly_chest_paid_from_the_fixed_bucket() {
    let mut w = World::new();
    w.pools(100 * USDC, 100 * USDC, 20 * USDC);
    w.verify(SAM);
    assert_eq!(
        open(&mut w, true),
        Err(Refusal::WeeklyChestNotReady { days: 1, need: 5 })
    );
    visit_daily(&mut w, 4);
    let events = open(&mut w, true).unwrap();
    let (_, contents) = opened(&events);
    assert_eq!(contents.golden_drop, 250_000);
    assert!(intents(&events).iter().any(|i| matches!(
        i,
        Intent::PayHouse {
            bucket: Bucket::Fixed,
            amount: 250_000,
            ..
        }
    )));
    assert!(
        matches!(open(&mut w, true), Err(Refusal::ChestNotReady { .. })),
        "once a week"
    );
}

#[test]
fn a_meal_voucher_is_paid_by_the_house_and_then_bought_as_a_meal_that_isnt_counted_as_paid() {
    let mut config: Config = common::config();
    config.chest.wood.voucher_bps = 10_000;
    let mut w = World::with(config);
    w.pools(100 * USDC, 100 * USDC, 20 * USDC);
    assert!(opened(&open(&mut w, false).unwrap()).1.voucher);
    w.set_energy(SAM, 30);
    let buy = |w: &mut World, reference: &str| {
        w.run(Command::BuyMeal {
            account: SAM.into(),
            item: "thali".into(),
            voucher: true,
            reference: reference.into(),
        })
    };
    assert_eq!(buy(&mut w, "v0"), Err(Refusal::NeedsTownPass));
    w.verify(SAM);
    let events = buy(&mut w, "v1").unwrap();
    let Intent::PayHouse { amount, bucket, .. } = intents(&events)[0].clone() else {
        panic!()
    };
    assert_eq!((bucket, amount), (Bucket::Surprise, 6120));
    assert_eq!(
        buy(&mut w, "v2"),
        Err(Refusal::MealPending {
            reference: "v1".into()
        })
    );
    let events = w
        .observe(Observation::Paid {
            bucket,
            player: SAM.into(),
            human_id: World::human(SAM),
            amount,
            reference: "v1".into(),
            tx: "0x".into(),
        })
        .unwrap();
    let Intent::BuyMeal {
        reference,
        max_usdc,
        ..
    } = intents(&events)[0].clone()
    else {
        panic!()
    };
    assert_eq!((reference.as_str(), max_usdc), ("v1:meal", 6120));
    w.observe(Observation::MealEaten {
        player: SAM.into(),
        item: "thali".into(),
        usdc: 6000,
        food: 6_000_000,
        from_ration: 0,
        reference,
        tx: "0x".into(),
    })
    .unwrap();
    assert_eq!(w.energy(SAM), 100);
    assert_eq!(
        w.player(SAM).paid_meals,
        0,
        "the house paid, so it isn't a page of Grandma's ledger"
    );
    assert_eq!(buy(&mut w, "v3"), Err(Refusal::EnergyFull { energy: 100 }));
}

#[test]
fn a_right_price_call_earns_tickets_when_the_day_closes() {
    let mut w = World::new();
    w.run(Command::PriceCall {
        account: SAM.into(),
        call: Call::Up,
    })
    .unwrap();
    assert_eq!(
        w.run(Command::PriceCall {
            account: SAM.into(),
            call: Call::Down
        }),
        Err(Refusal::AlreadyCalled { day: 0 })
    );
    w.run(Command::PriceCall {
        account: "priya".into(),
        call: Call::Down,
    })
    .unwrap();
    w.buy_food(50_000_000);
    let events = w.run(Command::NewDay { day: 1 }).unwrap();
    assert!(events.contains(&Event::PriceCallSettled {
        account: SAM.into(),
        day: 0,
        call: Call::Up,
        moved: Call::Up,
        right: true
    }));
    assert!(events
        .iter()
        .any(|e| matches!(e, Event::TicketsEarned { account, tickets: 2, .. } if account == SAM)));
    assert!(events
        .iter()
        .any(|e| matches!(e, Event::PriceCallSettled { right: false, .. })));
    let keepers: Vec<Intent> = intents(&events);
    assert_eq!(
        keepers,
        [Intent::Split, Intent::Rebalance, Intent::HarvestYield],
        "the keepers' day"
    );
}

#[test]
fn the_town_goal_upgrades_everyones_next_chest_once() {
    let mut config = common::config();
    config.town_goal.meals = 2;
    let mut w = World::with(config);
    w.fund(SAM, USDC);
    w.set_energy(SAM, 10);
    let mut reached = false;
    for n in 0..2 {
        let reference = format!("m{n}");
        w.run(Command::BuyMeal {
            account: SAM.into(),
            item: "chai".into(),
            voucher: false,
            reference: reference.clone(),
        })
        .unwrap();
        let events = w
            .observe(Observation::MealEaten {
                player: SAM.into(),
                item: "chai".into(),
                usdc: 1000,
                food: 1_000_000,
                from_ration: 0,
                reference,
                tx: "0x".into(),
            })
            .unwrap();
        reached |= events
            .iter()
            .any(|e| matches!(e, Event::TownGoalReached { meals: 2, .. }));
    }
    assert!(reached);
    assert_eq!(
        opened(&open(&mut w, false).unwrap()).0,
        Tier::Brass,
        "one better than wood"
    );
    w.run(Command::ReadyChest {
        account: SAM.into(),
    })
    .unwrap();
    assert_eq!(
        opened(&open(&mut w, false).unwrap()).0,
        Tier::Wood,
        "the upgrade is used"
    );
    assert_eq!(
        opened(
            &w.run(Command::OpenChest {
                account: "priya".into(),
                weekly: false
            })
            .unwrap()
        )
        .0,
        Tier::Brass
    );
}

#[test]
fn the_weekly_draw_commits_a_seed_reveals_it_after_and_pays_the_winner() {
    let mut w = World::new();
    w.pools(100 * USDC, 100 * USDC, 20 * USDC);
    w.verify(SAM);
    // Priya has tickets but no Town Pass, so she isn't in the draw.
    w.run(Command::OpenChest {
        account: "priya".into(),
        weekly: false,
    })
    .unwrap();
    open(&mut w, false).unwrap();
    assert_eq!(w.state.games.draw_due, None);
    w.at(7 * DAY);
    assert_eq!(w.state.games.draw_due, Some(0));
    let ranges = w.state.ticket_ranges(0);
    assert_eq!(ranges.len(), 1);
    assert_eq!(ranges[0].player, SAM);
    assert_eq!(
        w.run(Command::CommitDraw {
            week: 3,
            seed: "0x01".into(),
            seed_hash: "0xh".into()
        }),
        Err(Refusal::NoDrawDue { week: 3 })
    );
    let events = w
        .run(Command::CommitDraw {
            week: 0,
            seed: "0x01".into(),
            seed_hash: "0xh".into(),
        })
        .unwrap();
    // 5% of the 100 USDC SURPRISE bucket.
    assert!(events.contains(&Event::DrawCommitted {
        week: 0,
        tickets: ranges[0].to + 1,
        prize: 5 * USDC
    }));
    assert!(
        matches!(&intents(&events)[0], Intent::CommitDraw { seed_hash, prize, tickets, .. }
        if seed_hash == "0xh" && *prize == 5 * USDC && tickets.len() == 1)
    );
    assert_eq!(w.state.house.draw_reserved, 5 * USDC);
    assert!(
        !intents(&events)
            .iter()
            .any(|i| matches!(i, Intent::RevealDraw { .. })),
        "the seed stays secret"
    );
    w.observe(Observation::DrawCommitted {
        week: 0,
        seed_hash: "0xh".into(),
        root: "0xroot".into(),
        count: ranges[0].to + 1,
        prize: 5 * USDC,
        tx: "0x".into(),
    })
    .unwrap();
    assert!(intents(&w.later(9 * MINUTE)).is_empty(), "not yet");
    let reveal = intents(&w.later(MINUTE));
    assert_eq!(
        reveal,
        [Intent::RevealDraw {
            week: 0,
            seed: "0x01".into()
        }]
    );
    let events = w
        .observe(Observation::DrawRevealed {
            week: 0,
            seed: "0x01".into(),
            winner_index: 0,
            tx: "0x".into(),
        })
        .unwrap();
    assert!(
        matches!(&intents(&events)[0], Intent::ClaimDraw { player, from: 0, .. } if player == SAM)
    );
    let events = w
        .observe(Observation::DrawClaimed {
            week: 0,
            player: SAM.into(),
            prize: 5 * USDC,
            tx: "0xw".into(),
        })
        .unwrap();
    assert_eq!(
        events,
        [Event::DrawWon {
            account: SAM.into(),
            week: 0,
            prize: 5 * USDC,
            tx: "0xw".into()
        }]
    );
    assert_eq!(w.state.house.draw_reserved, 0);
}

#[test]
fn a_neighbour_brings_a_stuck_person_a_thali_once_a_day() {
    let mut w = World::new();
    w.pools(100 * USDC, 100 * USDC, 20 * USDC);
    w.set_energy(SAM, 50);
    w.run(Command::FreeMeal {
        account: SAM.into(),
    })
    .unwrap();
    w.set_energy(SAM, 5);
    assert!(
        !w.later(MINUTE)
            .iter()
            .any(|e| matches!(e, Event::RescueComing { .. })),
        "only for the Town Pass"
    );
    w.verify(SAM);
    let events = w.later(MINUTE);
    let at = events
        .iter()
        .find_map(|e| match e {
            Event::RescueComing { at, .. } => Some(*at),
            _ => None,
        })
        .expect("a neighbour sets off");
    assert_eq!(at, w.state.now_ms + 2 * MINUTE);
    let events = w.at(at);
    let Intent::PayRescueMeal {
        reference,
        item,
        max_usdc,
        ..
    } = intents(&events)[0].clone()
    else {
        panic!()
    };
    assert_eq!((item.as_str(), max_usdc), ("thali", 6120));
    let events = w
        .observe(Observation::MealEaten {
            player: SAM.into(),
            item,
            usdc: 6000,
            food: 6_000_000,
            from_ration: 0,
            reference,
            tx: "0x".into(),
        })
        .unwrap();
    assert!(events
        .iter()
        .any(|e| matches!(e, Event::RescueMeal { direct: false, .. })));
    assert!(w.energy(SAM) >= 70);
    w.set_energy(SAM, 5);
    assert!(
        !w.later(MINUTE)
            .iter()
            .any(|e| matches!(e, Event::RescueComing { .. })),
        "once a day"
    );
}

#[test]
fn with_the_safety_net_empty_the_thalis_energy_is_given_straight_away() {
    let mut w = World::new();
    w.pools(100 * USDC, 100 * USDC, 0);
    w.verify(SAM);
    w.set_energy(SAM, 50);
    w.run(Command::FreeMeal {
        account: SAM.into(),
    })
    .unwrap();
    w.set_energy(SAM, 5);
    w.later(MINUTE);
    let events = w.later(2 * MINUTE);
    assert!(events
        .iter()
        .any(|e| matches!(e, Event::RescueMeal { direct: true, .. })));
    assert!(intents(&events).is_empty());
}

#[test]
fn both_get_tickets_when_a_referred_friend_has_the_pass_and_a_finished_quest() {
    let mut w = World::new();
    assert_eq!(
        w.run(Command::Refer {
            account: SAM.into(),
            player: SAM.into()
        }),
        Err(Refusal::ReferringYourself)
    );
    assert_eq!(
        w.run(Command::Refer {
            account: SAM.into(),
            player: "nobody".into()
        }),
        Err(Refusal::UnknownPlayer {
            account: "nobody".into()
        })
    );
    w.run(Command::Refer {
        account: SAM.into(),
        player: "priya".into(),
    })
    .unwrap();
    assert_eq!(
        w.run(Command::Refer {
            account: SAM.into(),
            player: "priya".into()
        }),
        Err(Refusal::AlreadyReferred)
    );
    w.verify(SAM);
    let errand = format!("errand:{}", w.state.book.errands[0].id);
    w.run(Command::TakeQuest {
        account: SAM.into(),
        quest: errand.clone(),
    })
    .unwrap();
    let steps: Vec<String> = w.state.book.errands[0]
        .steps
        .iter()
        .map(|s| s.id.clone())
        .collect();
    let mut events = Vec::new();
    for step in steps {
        events = w
            .run(Command::QuestStep {
                account: SAM.into(),
                quest: errand.clone(),
                step,
            })
            .unwrap();
    }
    assert!(events.iter().any(
        |e| matches!(e, Event::ReferralRewarded { account, tickets: 5, .. } if account == "priya")
    ));
    assert_eq!(
        w.run(Command::Refer {
            account: SAM.into(),
            player: "priya".into()
        }),
        Err(Refusal::AlreadyReferred)
    );
    w.arrive("mira");
    w.verify("mira");
    let errand = format!("errand:{}", w.state.book.errands[1].id);
    w.run(Command::TakeQuest {
        account: "mira".into(),
        quest: errand.clone(),
    })
    .unwrap();
    for step in w.state.book.errands[1].steps.clone() {
        w.run(Command::QuestStep {
            account: "mira".into(),
            quest: errand.clone(),
            step: step.id,
        })
        .unwrap();
    }
    assert_eq!(
        w.run(Command::Refer {
            account: "mira".into(),
            player: SAM.into()
        }),
        Err(Refusal::TooLateToRefer)
    );
}

#[test]
fn one_world_id_holds_one_player() {
    let mut w = World::new();
    w.verify(SAM);
    assert_eq!(
        w.run(Command::VerifyHuman {
            account: SAM.into(),
            human_id: World::human(SAM)
        }),
        Err(Refusal::AlreadyHuman)
    );
    assert_eq!(
        w.run(Command::VerifyHuman {
            account: "priya".into(),
            human_id: World::human(SAM)
        }),
        Err(Refusal::HumanTaken)
    );
    assert_eq!(
        w.run(Command::Observe {
            block: 1,
            log_index: 0,
            time: 0,
            observed: Observation::Balances {
                player: SAM.into(),
                usdc: 1
            }
        })
        .map(|_| ()),
        Err(Refusal::AlreadyObserved {
            block: 1,
            log_index: 0
        }),
        "the test world's own blocks went past 1"
    );
}
