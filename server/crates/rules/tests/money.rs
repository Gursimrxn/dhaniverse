//! The money rules that must always hold: nothing is paid without the Town Pass, no payout is sent past what the pool's
//! budget and balance can cover or past the per-person cap, and a ref is paid once.

mod common;

use common::{intents, Rand, World, DAY, USDC};
use rules::chain::{Bucket, Intent, Observation};
use rules::house::Waiting;
use rules::{Command, Config, Event, Refusal};

const SAM: &str = "sam";

/// No chests' luck: only the pity rule gives a golden drop.
fn no_luck() -> Config {
    let mut config = common::config();
    for tier in [
        &mut config.chest.wood,
        &mut config.chest.brass,
        &mut config.chest.gold,
    ] {
        tier.drop_bps = 0;
        tier.voucher_bps = 0;
    }
    config
}

fn chest(w: &mut World, account: &str) -> Vec<Event> {
    w.run(Command::ReadyChest {
        account: account.into(),
    })
    .unwrap();
    w.run(Command::OpenChest {
        account: account.into(),
        weekly: false,
    })
    .unwrap()
}

fn pay_intents(events: &[Event]) -> Vec<(String, u64)> {
    intents(events)
        .into_iter()
        .filter_map(|i| match i {
            Intent::PayHouse {
                reference, amount, ..
            } => Some((reference, amount)),
            _ => None,
        })
        .collect()
}

/// A golden drop: every 10th chest has one, so this opens ten.
fn tenth_chest(w: &mut World, account: &str) -> Vec<Event> {
    let mut events = Vec::new();
    for _ in 0..10 {
        events = chest(w, account);
    }
    events
}

#[test]
fn a_reward_without_the_town_pass_is_owed_and_paid_with_its_own_ref_on_verifying() {
    let mut w = World::with(no_luck());
    w.pools(100 * USDC, 100 * USDC, 20 * USDC);
    let events = tenth_chest(&mut w, SAM);
    assert!(matches!(
        events.iter().find(|e| matches!(e, Event::ChestOpened { .. })),
        Some(Event::ChestOpened { contents, .. }) if contents.golden_drop == 50_000
    ));
    assert!(
        pay_intents(&events).is_empty(),
        "never paid without the Town Pass"
    );
    assert!(events.iter().any(|e| matches!(
        e,
        Event::RewardPending {
            waiting: Waiting::TownPass,
            amount: 50_000,
            ..
        }
    )));
    assert_eq!(w.state.house.owed_to(SAM), 50_000);
    let events = w.verify(SAM);
    let pays = pay_intents(&events);
    assert_eq!(pays, [("chest:sam:9".to_string(), 50_000)]);
    assert_eq!(w.state.house.owed_to(SAM), 0);
    let paid = Observation::Paid {
        bucket: Bucket::Surprise,
        player: SAM.into(),
        human_id: World::human(SAM),
        amount: 50_000,
        reference: "chest:sam:9".into(),
        tx: "0xp".into(),
    };
    let events = w.observe(paid.clone()).unwrap();
    assert!(events
        .iter()
        .any(|e| matches!(e, Event::RewardPaid { amount: 50_000, .. })));
    assert_eq!(
        w.observe(paid),
        Err(Refusal::RefUsed {
            reference: "chest:sam:9".into()
        }),
        "paid once"
    );
    assert_eq!(w.state.house.book(Bucket::Surprise).in_flight, 0);
}

#[test]
fn nothing_is_promised_before_the_chain_has_reported_the_pool() {
    let mut w = World::with(no_luck());
    w.verify(SAM);
    let events = tenth_chest(&mut w, SAM);
    assert!(
        matches!(
            events.iter().find(|e| matches!(e, Event::ChestOpened { .. })),
            Some(Event::ChestOpened { contents, .. }) if contents.golden_drop == 0 && !contents.voucher
        ),
        "no budget, no drop, and no voucher either"
    );
    assert!(pay_intents(&events).is_empty());
}

#[test]
fn a_payout_waits_when_the_pools_budget_for_today_is_spent_and_goes_tomorrow() {
    let mut w = World::with(no_luck());
    w.verify(SAM);
    w.verify("priya");
    // A big pool for the chest's share, but only 60,000 the chain says it may still pay today.
    w.observe(Observation::PoolBalances {
        fixed: 0,
        surprise: 100 * USDC,
        safety: 0,
        budget_fixed: 0,
        budget_surprise: 60_000,
        budget_safety: 0,
    })
    .unwrap();
    let first = tenth_chest(&mut w, SAM);
    assert_eq!(pay_intents(&first).len(), 1);
    let second = tenth_chest(&mut w, "priya");
    assert!(
        pay_intents(&second).is_empty(),
        "50,000 is on its way, so 10,000 is left"
    );
    assert!(second.iter().any(|e| matches!(
        e,
        Event::RewardPending {
            waiting: Waiting::Budget,
            ..
        }
    )));
    assert_eq!(w.state.house.book(Bucket::Surprise).in_flight, 50_000);
    // The next day the chain reports a fresh budget, and the owed drop goes at the close.
    w.observe(Observation::PoolBalances {
        fixed: 0,
        surprise: 100 * USDC,
        safety: 0,
        budget_fixed: 0,
        budget_surprise: 4 * USDC,
        budget_safety: 0,
    })
    .unwrap();
    let events = w.at(DAY);
    assert_eq!(
        pay_intents(&events),
        [("chest:priya:9".to_string(), 50_000)]
    );
}

#[test]
fn the_per_person_daily_cap_holds_back_the_rest_until_tomorrow() {
    let mut config = no_luck();
    config.house.per_human_daily_cap = 80_000;
    let mut w = World::with(config);
    w.pools(100 * USDC, 100 * USDC, 20 * USDC);
    w.verify(SAM);
    assert_eq!(pay_intents(&tenth_chest(&mut w, SAM)).len(), 1);
    let events = tenth_chest(&mut w, SAM);
    assert!(
        pay_intents(&events).is_empty(),
        "50,000 + 50,000 is over the 80,000 cap"
    );
    assert!(events.iter().any(|e| matches!(
        e,
        Event::RewardPending {
            waiting: Waiting::Budget,
            ..
        }
    )));
    assert_eq!(pay_intents(&w.at(DAY)).len(), 1);
}

#[test]
fn a_payout_the_chain_refused_is_owed_again_with_the_same_ref_and_retried_at_the_close() {
    let mut w = World::with(no_luck());
    w.pools(100 * USDC, 100 * USDC, 20 * USDC);
    w.verify(SAM);
    let events = tenth_chest(&mut w, SAM);
    let (reference, _) = pay_intents(&events)[0].clone();
    let events = w
        .observe(Observation::IntentFailed {
            reference: reference.clone(),
            reason: "HousePool__OverDailyBudget".into(),
        })
        .unwrap();
    assert!(matches!(
        &events[0],
        Event::RewardPending {
            waiting: Waiting::Chain,
            ..
        }
    ));
    assert_eq!(w.state.house.book(Bucket::Surprise).in_flight, 0);
    assert_eq!(
        pay_intents(&w.at(DAY)),
        [(reference, 50_000)],
        "the same ref, so it can never pay twice"
    );
}

#[test]
fn the_chests_drops_never_spend_more_than_their_share_of_the_day() {
    let mut w = World::with(no_luck());
    // 20% of 4% of 10 USDC is 80,000: room for one 50,000 drop a day.
    w.pools(10 * USDC, 10 * USDC, 10 * USDC);
    w.verify(SAM);
    w.verify("priya");
    assert_eq!(pay_intents(&tenth_chest(&mut w, SAM)).len(), 1);
    let events = tenth_chest(&mut w, "priya");
    assert!(
        matches!(
            events.iter().find(|e| matches!(e, Event::ChestOpened { .. })),
            Some(Event::ChestOpened { contents, .. }) if contents.golden_drop == 0
        ),
        "the day's drops are gone"
    );
    assert!(
        events
            .iter()
            .any(|e| matches!(e, Event::ChestOpened { contents, .. } if contents.voucher)),
        "pity with no drops left gives a meal voucher, if the share still covers one"
    );
}

/// Whatever is earned and answered, in any order, nothing is ever sent past the pool's budget or balance, nobody
/// without the Town Pass is ever paid, and no ref is paid twice.
#[test]
fn money_invariants_hold_through_any_order_of_play_and_answers() {
    for seed in 0..20 {
        let mut w = World::new();
        let mut rand = Rand(seed);
        w.pools(5 * USDC, 5 * USDC, USDC);
        for name in ["asha", "bilal", "chen"] {
            w.arrive(name);
        }
        let people = ["sam", "priya", "asha", "bilal", "chen"];
        let mut out: Vec<Intent> = Vec::new();
        let mut paid_refs = std::collections::BTreeSet::new();
        for _ in 0..300 {
            let before: Vec<u64> = Bucket::ALL
                .iter()
                .map(|b| w.state.house.available(*b))
                .collect();
            let who = people[rand.below(people.len() as u64) as usize];
            let events = match rand.below(7) {
                0 => {
                    w.run(Command::ReadyChest {
                        account: who.into(),
                    })
                    .unwrap();
                    w.run(Command::OpenChest {
                        account: who.into(),
                        weekly: false,
                    })
                    .unwrap_or_default()
                }
                1 => w.later(rand.below(DAY / 3)),
                2 if w.player(who).human.is_none() => w.verify(who),
                3 => {
                    let errand =
                        format!("errand:{}", w.state.book.errands[rand.below(4) as usize].id);
                    let mut events = w
                        .run(Command::TakeQuest {
                            account: who.into(),
                            quest: errand.clone(),
                        })
                        .unwrap_or_default();
                    let steps: Vec<String> = w
                        .state
                        .book
                        .errand(&errand[7..])
                        .unwrap()
                        .steps
                        .iter()
                        .map(|s| s.id.clone())
                        .collect();
                    for step in steps {
                        events.extend(
                            w.run(Command::QuestStep {
                                account: who.into(),
                                quest: errand.clone(),
                                step,
                            })
                            .unwrap_or_default(),
                        );
                    }
                    events
                }
                4 | 5 if !out.is_empty() => {
                    let intent = out.remove(rand.below(out.len() as u64) as usize);
                    let Intent::PayHouse {
                        player,
                        human_id,
                        bucket,
                        amount,
                        reference,
                    } = intent
                    else {
                        continue;
                    };
                    let observed = if rand.below(4) == 0 {
                        Observation::IntentFailed {
                            reference,
                            reason: "nope".into(),
                        }
                    } else {
                        assert!(
                            paid_refs.insert(reference.clone()),
                            "{reference} paid twice"
                        );
                        Observation::Paid {
                            bucket,
                            player,
                            human_id,
                            amount,
                            reference,
                            tx: "0x".into(),
                        }
                    };
                    w.observe(observed).unwrap()
                }
                _ => {
                    let budgets = rand.below(2 * USDC);
                    w.observe(Observation::PoolBalances {
                        fixed: 5 * USDC,
                        surprise: 5 * USDC,
                        safety: USDC,
                        budget_fixed: budgets,
                        budget_surprise: budgets,
                        budget_safety: budgets,
                    })
                    .unwrap_or_default()
                }
            };
            let mut sent = [0u64; 3];
            for intent in intents(&events) {
                if let Intent::PayHouse {
                    player,
                    bucket,
                    amount,
                    ..
                } = &intent
                {
                    assert!(
                        w.player(player).human.is_some(),
                        "paid {player} without the Town Pass"
                    );
                    sent[Bucket::ALL.iter().position(|b| b == bucket).unwrap()] += amount;
                    out.push(intent);
                }
            }
            for (i, bucket) in Bucket::ALL.iter().enumerate() {
                assert!(
                    sent[i] <= before[i],
                    "seed {seed}: sent {} from {bucket:?} with {} available",
                    sent[i],
                    before[i]
                );
                let book = w.state.house.book(*bucket);
                assert!(
                    book.in_flight <= book.balance,
                    "seed {seed}: more on its way than the pool holds: {book:?}"
                );
            }
        }
    }
}
