//! Towns sharing a chain: every ref and draw week a town sends carries its own id, so two saves on one chain never
//! collide, and what the chain says about another town's refs is ignored.

use rules::chain::{ChainMode, Intent, Observation};
use rules::{Event, Refusal};
use server::log::Log;
use server::world::{Input, Setup, World};
use std::collections::BTreeSet;
use std::path::PathBuf;

const RULES: &str = include_str!("../../../rules.toml");

fn town(id: &str) -> World {
    let mut setup = Setup::offline(RULES, 7);
    setup.chain = ChainMode::Anvil;
    setup.town_id = id.to_string();
    World::start(&setup).unwrap()
}

/// Every ref in the intents of an hour of trading.
fn refs_of_an_hour(world: &mut World) -> Vec<String> {
    let events = world.step(Input::Advance { ms: 3_600_000 }).unwrap();
    events
        .iter()
        .filter_map(|e| match e {
            Event::Intent { intent } => intent.reference().map(str::to_string),
            _ => None,
        })
        .collect()
}

fn harvest_sold(reference: &str) -> Input {
    Input::Chain {
        block: 10,
        log_index: 0,
        time: 0,
        observed: Observation::HarvestSold {
            offered: 1_000_000,
            sold: 1_000_000,
            usdc: 4000,
            reference: reference.into(),
            tx: "0x".into(),
        },
    }
}

#[test]
fn two_towns_on_one_chain_never_share_a_ref_and_a_foreign_harvest_sale_is_ignored() {
    let mut a = town("aaaaaaaa00000001");
    let mut b = town("bbbbbbbb00000002");
    let a_refs = refs_of_an_hour(&mut a);
    let b_refs = refs_of_an_hour(&mut b);
    assert!(!a_refs.is_empty(), "Kofi offered his harvest to the keeper");
    assert!(
        a_refs.iter().all(|r| r.starts_with("aaaaaaaa00000001:")),
        "{a_refs:?}"
    );
    let a_set: BTreeSet<&String> = a_refs.iter().collect();
    assert!(
        b_refs.iter().all(|r| !a_set.contains(r)),
        "the same Kofi slices, different refs on chain"
    );

    let before = a.clone();
    let foreign = b_refs[0].clone();
    assert_eq!(
        a.step(harvest_sold(&foreign)),
        Err(Refusal::NotOurs),
        "b's sale isn't a's"
    );
    assert_eq!(a, before, "and it changed nothing");
    let plain = foreign.split_once(':').unwrap().1.to_string();
    assert_eq!(
        a.step(harvest_sold(&plain)),
        Err(Refusal::NotOurs),
        "a ref with no town is nobody's"
    );

    let events = a.step(harvest_sold(&a_refs[0])).unwrap();
    let own = a_refs[0].split_once(':').unwrap().1;
    assert!(
        events
            .iter()
            .any(|e| matches!(e, Event::FoodSold { reference, .. } if reference == own)),
        "a's own sale lands, under its plain ref: {events:?}"
    );
}

#[test]
fn draw_weeks_carry_the_town_too_and_a_new_save_picks_its_own_id() {
    let a = town("aaaaaaaa00000001");
    let b = town("bbbbbbbb00000002");
    assert_ne!(a.state.chain_week(0), b.state.chain_week(0));
    assert_eq!(a.state.own_week(b.state.chain_week(0)), None);
    let commit = a.state.outward(Intent::RevealDraw {
        week: 3,
        seed: "0x".into(),
    });
    assert!(matches!(commit, Intent::RevealDraw { week, .. } if a.state.own_week(week) == Some(3)));

    let dir = PathBuf::from(env!("CARGO_TARGET_TMPDIR"));
    let (one, two) = (dir.join("town_one.jsonl"), dir.join("town_two.jsonl"));
    for path in [&one, &two] {
        let _ = std::fs::remove_file(path);
    }
    let (_, first) = Log::open(&one, RULES, 7).unwrap();
    let (_, second) = Log::open(&two, RULES, 7).unwrap();
    assert_eq!(first.state.town_id.len(), 16);
    assert_ne!(
        first.state.town_id, second.state.town_id,
        "same rules and seed, different towns"
    );
    let (_, again) = Log::open(&one, RULES, 7).unwrap();
    assert_eq!(
        again.state.town_id, first.state.town_id,
        "kept in the save's first line"
    );
    for path in [&one, &two] {
        let _ = std::fs::remove_file(path);
    }
}
