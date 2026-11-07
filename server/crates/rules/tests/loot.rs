//! The loot crate: a meal bought with your own money drops one, the first to reach it gets its prize as a house reward, a
//! second claim is refused, and a crate nobody reaches is gone when its time is up.

mod common;

use common::{intents, World, USDC};
use rules::chain::{Bucket, Intent, Observation};
use rules::{Command, Event, Refusal};

const SAM: &str = "sam";
const ASHA: &str = "asha";

/// Sam buys and eats a chai: what the town says when it's eaten.
fn paid_meal(w: &mut World, reference: &str) -> Vec<Event> {
    w.run(Command::BuyMeal {
        account: SAM.into(),
        item: "chai".into(),
        voucher: false,
        reference: reference.into(),
    })
    .unwrap();
    w.observe(Observation::MealEaten {
        player: SAM.into(),
        item: "chai".into(),
        usdc: 1000,
        food: 1_000_000,
        from_ration: 0,
        reference: reference.into(),
        tx: "0x".into(),
    })
    .unwrap()
}

fn dropped(events: &[Event]) -> Option<(u64, u64)> {
    events.iter().find_map(|e| match e {
        Event::LootDropped { id, spot, prize, .. } if *prize == 2 * USDC => Some((*id, *spot)),
        _ => None,
    })
}

fn claim(w: &mut World, account: &str, id: u64) -> Result<Vec<Event>, Refusal> {
    let reference = w.fresh_ref();
    w.run(Command::ClaimLoot {
        account: account.into(),
        id,
        reference,
    })
}

#[test]
fn a_paid_meal_drops_a_crate_and_the_first_there_is_paid() {
    let mut w = World::new();
    w.arrive(ASHA);
    w.pools(100 * USDC, 100 * USDC, 20 * USDC);
    w.verify(SAM);
    w.fund(SAM, USDC);
    w.set_energy(SAM, 10);
    let (id, spot) = dropped(&paid_meal(&mut w, "m1")).expect("a crate falls after a paid meal");
    assert!(spot < 6);
    assert!(dropped(&paid_meal(&mut w, "m2")).is_none(), "one crate at a time");
    let events = claim(&mut w, SAM, id).unwrap();
    assert!(events.iter().any(|e| matches!(e, Event::LootClaimed { account, .. } if account == SAM)));
    assert!(intents(&events)
        .iter()
        .any(|i| matches!(i, Intent::PayHouse { bucket: Bucket::Surprise, amount, .. } if *amount == 2 * USDC)));
    assert_eq!(claim(&mut w, ASHA, id), Err(Refusal::LootGone), "only the first one there");
}

#[test]
fn a_crate_nobody_reaches_is_gone() {
    let mut w = World::new();
    w.fund(SAM, USDC);
    w.set_energy(SAM, 10);
    let (id, _) = dropped(&paid_meal(&mut w, "m1")).unwrap();
    let events = w.later(120_000);
    assert!(events.iter().any(|e| matches!(e, Event::LootGone { id: gone } if *gone == id)));
    assert_eq!(claim(&mut w, SAM, id), Err(Refusal::LootGone));
    assert!(dropped(&paid_meal(&mut w, "m2")).is_some(), "the next paid meal drops a new one");
}
