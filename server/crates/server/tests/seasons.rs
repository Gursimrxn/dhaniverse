//! Seasons on the calendar and their shocks.

mod common;

use common::*;
use rules::{Command, Event, Role};
use serde_json::json;
use server::world::{Input, World};

const RULES: &str = include_str!("../../../rules.toml");
const HOUR: u64 = 3_600_000;

/// A city whose seasons are this many days long.
fn city_with_seasons(days: u64) -> World {
    let rules = RULES.replace("season_days = 168", &format!("season_days = {days}"));
    World::new(&rules, 1).unwrap()
}

fn season_changes(events: &[Event]) -> Vec<(u32, String)> {
    events
        .iter()
        .filter_map(|e| match e {
            Event::SeasonChanged { season, shock } => Some((*season, shock.clone())),
            _ => None,
        })
        .collect()
}

#[test]
fn seasons_come_round_on_the_calendar_each_with_the_next_shock() {
    let mut world = city_with_seasons(2);
    let events = world.step(Input::Advance { ms: 9 * HOUR }).unwrap();
    assert_eq!(
        season_changes(&events),
        [
            (2, "harvest".to_string()),
            (3, "festival".to_string()),
            (4, "drought".to_string()),
            (5, "harvest".to_string()),
        ]
    );
    assert_eq!(world.season.number, 5);
    assert_eq!(world.town.refusals, []);
}

#[test]
fn every_seasons_shock_starts_the_real_event() {
    for (skip, kind) in [(1, "harvest"), (2, "festival"), (3, "drought")] {
        let mut world = World::new(RULES, 1).unwrap();
        let mut events = Vec::new();
        for _ in 0..skip {
            events = world.step(Input::NextSeason).unwrap();
        }
        let started = events
            .iter()
            .any(|e| matches!(e, Event::CityEventStarted { kind: k, .. } if k == kind));
        assert!(started, "{kind}: {events:?}");
    }
}

#[test]
fn a_new_season_clears_the_rush_board_and_keeps_names_and_firsts() {
    let mut world = World::new(RULES, 1).unwrap();
    let sam = || "sam".to_string();
    world.step(Input::Connect { player: sam() }).unwrap();
    let play = |command| Input::Command {
        by: Role::Player,
        command,
    };
    world
        .step(play(Command::StartRush { account: sam() }))
        .unwrap();
    let serve = Command::ServeOrder {
        account: sam(),
        reference: "o".into(),
    };
    world.step(play(serve)).unwrap();
    world
        .step(play(Command::EndRush { account: sam() }))
        .unwrap();
    eat(&mut world, "sam", "chai", 4000, "m");
    assert_eq!(world.boards()["rush"], [sam()]);

    world.step(Input::NextSeason).unwrap();
    assert!(world.boards()["rush"].is_empty(), "everyone starts level");
    assert_eq!(world.season.best_run("sam"), 0);
    let firsts = &world.state.life.player("sam").unwrap().firsts;
    assert_eq!(firsts.len(), 1, "firsts stay");
    assert_eq!(world.state.title("sam"), "Regular");
}

#[test]
fn the_season_shows_in_city_and_a_debug_action_starts_the_next() {
    let save = fresh_save("season_debug");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut sam = Client::connect(&server.addr);
    let snapshot = sam.hello("sam");
    assert_eq!(snapshot["city"]["season"]["number"], 1);
    assert_eq!(snapshot["city"]["season"]["shock"], "");
    assert_eq!(snapshot["city"]["season"]["ends_day"], 168);

    sam.debug(json!({"type": "NextSeason"}));
    let events = sam.take_events();
    assert_eq!(find(&events, "SeasonChanged")["season"], 2);
    assert_eq!(find(&events, "SeasonChanged")["shock"], "harvest");
    let later = sam.hello("sam");
    assert_eq!(later["city"]["season"]["number"], 2);

    drop(server);
    let _ = std::fs::remove_file(&save);
}
