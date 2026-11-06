//! The log is the save: stopping anywhere and replaying it must rebuild exactly the same world, agents and all.

mod common;

use rules::{Command, Event, Refusal, Role};
use server::log::Log;
use server::world::{Input, World};
use std::path::PathBuf;

const RULES: &str = include_str!("../../../rules.toml");
const MINUTE: u64 = 60_000;

fn fresh_save(name: &str) -> PathBuf {
    let path = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join(format!("{name}.jsonl"));
    let _ = std::fs::remove_file(&path);
    path
}

/// Takes an input and writes it to the log, as the hub does. Refused inputs aren't logged.
fn take(world: &mut World, log: &mut Log, input: Input) -> Result<Vec<Event>, Refusal> {
    let events = world.step(input.clone())?;
    log.append(&input, &events).unwrap();
    Ok(events)
}

fn player(command: Command) -> Input {
    Input::Command {
        by: Role::Player,
        command,
    }
}

fn play_a_while(world: &mut World, log: &mut Log) {
    let sam = || "sam".to_string();
    let connect = Input::Connect { player: sam() };
    take(world, log, connect).unwrap();
    take(world, log, player(Command::StartRush { account: sam() })).unwrap();
    for order in 0..5 {
        let serve = Command::ServeOrder {
            account: sam(),
            reference: format!("order-{order}"),
        };
        take(world, log, player(serve)).unwrap();
    }
    take(world, log, player(Command::EndRush { account: sam() })).unwrap();
    for input in common::meal_inputs(world, "sam", "thali", 24_000, "meal") {
        take(world, log, input).unwrap();
    }
    // Two and a half city days, with the town trading all the while.
    take(world, log, Input::Advance { ms: 150 * MINUTE }).unwrap();
}

#[test]
fn a_restart_mid_day_rebuilds_the_identical_world() {
    let path = fresh_save("mid_day");
    let (mut log, mut world) = Log::open(&path, RULES, 7).unwrap();
    play_a_while(&mut world, &mut log);
    assert_eq!(world.today(), 2);
    assert_eq!(world.day_elapsed_ms(), 30 * MINUTE, "mid-day");
    let seq = log.seq();
    drop(log);

    let (log, rebuilt) =
        Log::open(&path, "this text is ignored: a save keeps its rules", 999).unwrap();
    assert_eq!(
        rebuilt, world,
        "rules, agents, generator and clocks all match"
    );
    assert_eq!(log.seq(), seq);
    let _ = std::fs::remove_file(&path);
}

#[test]
fn a_restarted_world_goes_on_exactly_as_if_it_had_never_stopped() {
    let path = fresh_save("goes_on");
    let (mut log, mut world) = Log::open(&path, RULES, 7).unwrap();
    play_a_while(&mut world, &mut log);
    drop(log);

    let (mut log, mut rebuilt) = Log::open(&path, RULES, 7).unwrap();
    let days = Input::Advance { ms: 180 * MINUTE };
    let never_stopped = world.step(days.clone()).unwrap();
    let restarted = take(&mut rebuilt, &mut log, days).unwrap();
    assert_eq!(restarted, never_stopped);
    assert_eq!(rebuilt, world);
    let _ = std::fs::remove_file(&path);
}

#[test]
fn half_a_line_from_a_crash_is_dropped_and_the_save_still_opens() {
    let path = fresh_save("half_line");
    let (mut log, mut world) = Log::open(&path, RULES, 7).unwrap();
    play_a_while(&mut world, &mut log);
    let seq = log.seq();
    drop(log);

    let whole = std::fs::read(&path).unwrap();
    let mut torn = whole.clone();
    torn.extend_from_slice(b"{\"seq\":999,\"inpu");
    std::fs::write(&path, torn).unwrap();

    let (mut log, rebuilt) = Log::open(&path, RULES, 7).unwrap();
    assert_eq!(rebuilt, world);
    assert_eq!(log.seq(), seq);
    assert_eq!(
        std::fs::read(&path).unwrap(),
        whole,
        "the torn line is gone"
    );

    // New lines go after the good ones, and the save still replays.
    let mut rebuilt = rebuilt;
    take(&mut rebuilt, &mut log, Input::Advance { ms: MINUTE }).unwrap();
    drop(log);
    let (_, again) = Log::open(&path, RULES, 7).unwrap();
    assert_eq!(again, rebuilt);
    let _ = std::fs::remove_file(&path);
}

#[test]
fn an_incompatible_save_is_moved_aside_whole_and_a_good_one_is_left_alone() {
    let path = fresh_save("new_if_incompatible");
    let aside = PathBuf::from(format!("{}.old-1000", path.display()));
    let same_second = PathBuf::from(format!("{}.old-1000-1", path.display()));
    let _ = std::fs::remove_file(&aside);
    let _ = std::fs::remove_file(&same_second);

    let (mut log, mut world) = Log::open(&path, RULES, 7).unwrap();
    play_a_while(&mut world, &mut log);
    drop(log);
    let (log, rebuilt, moved) = Log::open_or_start_new(&path, RULES, 7, 1000).unwrap();
    assert_eq!(moved, None, "a save that replays is just opened");
    assert_eq!(rebuilt, world);
    drop(log);

    let text = std::fs::read_to_string(&path).unwrap();
    let doctored = text.replacen("\\nstart = 100", "\\nstart = 90", 1);
    assert_ne!(text, doctored);
    std::fs::write(&path, &doctored).unwrap();
    assert!(
        Log::open(&path, RULES, 7).is_err(),
        "without the flag it still refuses"
    );
    assert_eq!(
        std::fs::read_to_string(&path).unwrap(),
        doctored,
        "and leaves it be"
    );

    let (log, new_city, moved) = Log::open_or_start_new(&path, RULES, 7, 1000).unwrap();
    assert_eq!(moved, Some(aside.clone()));
    assert_eq!(
        std::fs::read_to_string(&aside).unwrap(),
        doctored,
        "kept whole"
    );
    assert_eq!(
        new_city.state.town_id.len(),
        16,
        "a new save picks a town id"
    );
    let mut setup = server::world::Setup::offline(RULES, 7);
    setup.town_id = new_city.state.town_id.clone();
    assert_eq!(
        new_city,
        World::start(&setup).unwrap(),
        "and a new city started"
    );
    assert_eq!(log.seq(), 0);
    drop(log);

    // Never overwrites an earlier one, even in the same second.
    std::fs::write(&path, "not a save").unwrap();
    let (log, _, moved) = Log::open_or_start_new(&path, RULES, 7, 1000).unwrap();
    assert_eq!(moved, Some(same_second.clone()));
    assert_eq!(std::fs::read_to_string(&aside).unwrap(), doctored);
    drop(log);

    for file in [&path, &aside, &same_second] {
        let _ = std::fs::remove_file(file);
    }
}

#[test]
fn a_save_written_by_other_rules_is_refused_rather_than_quietly_changing() {
    let path = fresh_save("other_rules");
    let (mut log, mut world) = Log::open(&path, RULES, 7).unwrap();
    play_a_while(&mut world, &mut log);
    drop(log);

    let text = std::fs::read_to_string(&path).unwrap();
    let doctored = text.replacen("\\nstart = 100", "\\nstart = 90", 1);
    assert_ne!(
        text, doctored,
        "the save carries its rules in its first line"
    );
    std::fs::write(&path, doctored).unwrap();
    let refused = Log::open(&path, RULES, 7).unwrap_err();
    assert!(refused.contains("replays differently"), "{refused}");
    let _ = std::fs::remove_file(&path);
}
