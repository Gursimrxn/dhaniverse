//! The feed, the boards and profiles, in a live city: real events go in, and only what's allowed comes out.

mod common;

use common::*;
use rules::{apply, Command, Event, Role};
use serde_json::{json, Value};
use server::boards;
use server::world::{Input, World};

const RULES: &str = include_str!("../../../rules.toml");
const DAY: u64 = 3_600_000;

fn city() -> World {
    World::new(RULES, 1).unwrap()
}

fn connect(world: &mut World, player: &str) {
    let player = player.to_string();
    world.step(Input::Connect { player }).unwrap();
}

fn play(world: &mut World, command: Command) -> Vec<Event> {
    let input = Input::Command {
        by: Role::Player,
        command,
    };
    world.step(input).unwrap()
}

/// One Market Rush run of this many orders.
fn rush(world: &mut World, account: &str, orders: u32, stamp: &str) -> Vec<Event> {
    let mut events = play(
        world,
        Command::StartRush {
            account: account.into(),
        },
    );
    for n in 0..orders {
        let serve = Command::ServeOrder {
            account: account.into(),
            reference: format!("{stamp}-{n}"),
        };
        events.extend(play(world, serve));
    }
    events.extend(play(
        world,
        Command::EndRush {
            account: account.into(),
        },
    ));
    events
}

fn eat(world: &mut World, account: &str, reference: &str) -> Vec<Event> {
    common::eat(world, account, "chai", 987_654, reference)
}

fn posts(events: &[Event]) -> Vec<(String, String)> {
    events
        .iter()
        .filter_map(|e| match e {
            Event::FeedPost { kind, text, .. } => Some((kind.clone(), text.clone())),
            _ => None,
        })
        .collect()
}

fn board_names(world: &World, board: &str) -> Vec<String> {
    let standings = world.boards();
    standings[board].clone()
}

#[test]
fn a_first_meal_reaches_the_feed_and_what_it_cost_never_does() {
    let mut world = city();
    connect(&mut world, "sam");
    let events = eat(&mut world, "sam", "m1");
    assert_eq!(
        posts(&events),
        [("first".to_string(), "sam bought a first meal.".to_string())]
    );
    let feed = server::protocol::feed(&world).to_string();
    assert!(!feed.contains("987654"), "{feed}");
    assert!(
        posts(&eat(&mut world, "sam", "m2")).is_empty(),
        "a first is once"
    );
}

#[test]
fn the_best_rush_run_ranks_and_a_new_leader_is_posted() {
    let mut world = city();
    connect(&mut world, "sam");
    connect(&mut world, "priya");
    assert!(
        board_names(&world, "rush").is_empty(),
        "nobody ranks before a run"
    );
    let events = rush(&mut world, "sam", 5, "s1");
    assert!(posts(&events)
        .iter()
        .any(|(_, text)| text == "sam is now the fastest at the stall in town."));
    rush(&mut world, "priya", 3, "p1");
    assert_eq!(board_names(&world, "rush"), ["sam", "priya"]);
    let events = rush(&mut world, "priya", 8, "p2");
    assert_eq!(board_names(&world, "rush"), ["priya", "sam"]);
    assert!(posts(&events)
        .iter()
        .any(|(_, text)| text == "priya is now the fastest at the stall in town."));
    rush(&mut world, "priya", 1, "p3");
    assert_eq!(
        board_names(&world, "rush"),
        ["priya", "sam"],
        "a worse run keeps the best"
    );
}

#[test]
fn boards_hold_only_rank_name_and_title() {
    let mut world = city();
    for name in ["sam", "priya"] {
        connect(&mut world, name);
    }
    rush(&mut world, "sam", 6, "a");
    rush(&mut world, "priya", 2, "b");
    let city_view = server::protocol::city(&world);
    let board = city_view["boards"]["rush"].as_array().unwrap();
    assert_eq!(board.len(), 2);
    assert_eq!(board[0]["name"], "sam");
    assert_eq!(board[0]["rank"], 1);
    for board in boards::BOARDS {
        for row in city_view["boards"][board].as_array().unwrap() {
            let row = row.as_object().unwrap();
            let mut keys: Vec<&str> = row.keys().map(String::as_str).collect();
            keys.sort_unstable();
            assert_eq!(keys, ["name", "rank", "title"], "{row:?}");
        }
    }
    let you = server::protocol::you(&world, "priya");
    assert_eq!(you["ranks"]["rush"], 2);
    assert_eq!(you["best_run"], 2);
}

#[test]
fn a_profile_shows_only_whats_public_and_a_resident_has_none() {
    let mut world = city();
    connect(&mut world, "sam");
    eat(&mut world, "sam", "m");
    let profile = server::protocol::profile(&world, "sam");
    assert_eq!(profile["found"], true);
    assert_eq!(profile["title"], "Regular");
    assert_eq!(profile["firsts"], json!(["first_meal"]));
    assert!(profile["days_active"].as_u64().unwrap() >= 1);
    assert_eq!(profile["reputation"], "New in town");
    let text = profile.to_string();
    for banned in ["usdc", "energy", "987654"] {
        assert!(!text.contains(banned), "{text}");
    }
    assert_eq!(server::protocol::profile(&world, "nobody")["found"], false);
    assert_eq!(
        server::protocol::profile(&world, "resident:asha")["found"],
        false
    );
}

#[test]
fn reputation_grows_with_days_in_town() {
    let mut world = city();
    connect(&mut world, "sam");
    for _ in 0..3 {
        world.step(Input::Advance { ms: DAY }).unwrap();
    }
    assert_eq!(
        server::protocol::profile(&world, "sam")["reputation"],
        "Known around town"
    );
}

#[test]
fn over_a_socket_the_feed_reactions_follows_and_profiles_all_work() {
    let save = fresh_save("social");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut sam = Client::connect(&server.addr);
    let snapshot = sam.hello("sam");
    assert!(snapshot["feed"].is_array());
    assert_eq!(snapshot["you"]["following"], json!([]));
    assert_eq!(snapshot["city"]["emotes"][0], "clap");
    let mut priya = Client::connect(&server.addr);
    priya.hello("priya");
    priya.take_events();

    sam.meal("chai");
    let post = loop {
        let message: Value = priya.until("event");
        if message["event"]["type"] == "FeedPost" {
            break message["event"].clone();
        }
    };
    assert_eq!(post["text"], "sam bought a first meal.");
    assert_eq!(post["about"], "sam");

    let id = post["id"].clone();
    priya.must(json!({"type": "React", "post": id, "emote": "clap"}));
    let again = priya.command(json!({"type": "React", "post": id, "emote": "clap"}));
    assert_eq!(again["refusal"]["type"], "AlreadyReacted");
    let bad = priya.command(json!({"type": "React", "post": id, "emote": "rude"}));
    assert_eq!(bad["refusal"]["type"], "UnknownEmote");
    let gone = priya.command(json!({"type": "React", "post": 99999, "emote": "clap"}));
    assert_eq!(gone["refusal"]["type"], "UnknownPost");
    let later = priya.hello("priya");
    let posts = later["feed"].as_array().unwrap();
    let found = posts.iter().find(|p| p["id"] == id).unwrap();
    assert_eq!(found["reactions"]["clap"], 1);

    priya.must(json!({"type": "Follow", "player": "sam"}));
    assert_eq!(priya.latest_you()["following"], json!(["sam"]));
    let me = priya.command(json!({"type": "Follow", "player": "priya"}));
    assert_eq!(me["refusal"]["type"], "FollowingYourself");
    let resident = priya.command(json!({"type": "Follow", "player": "resident:asha"}));
    assert_eq!(resident["refusal"]["type"], "UnknownPlayer");
    priya.must(json!({"type": "Unfollow", "player": "sam"}));
    let not = priya.command(json!({"type": "Unfollow", "player": "sam"}));
    assert_eq!(not["refusal"]["type"], "NotFollowing");

    priya.send(json!({"type": "profile", "name": "sam"}));
    let profile = priya.until("profile");
    assert_eq!(profile["found"], true);
    assert_eq!(profile["title"], "Regular");
    priya.send(json!({"type": "profile", "name": "nobody"}));
    assert_eq!(priya.until("profile")["found"], false);

    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn the_feed_and_boards_replay_exactly_so_a_save_can_be_reloaded() {
    let save = fresh_save("social_replay");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut sam = Client::connect(&server.addr);
    sam.hello("sam");
    sam.meal("chai");
    sam.must(json!({"type": "StartRush"}));
    sam.must(json!({"type": "ServeOrder"}));
    sam.must(json!({"type": "EndRush"}));
    sam.debug(json!({"type": "Skip", "ms": 3 * DAY}));
    let before = sam.hello("sam");
    drop(sam);
    drop(server);
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut back = Client::connect(&server.addr);
    let after = back.hello("sam");
    assert_eq!(before["feed"], after["feed"]);
    assert_eq!(before["city"]["boards"], after["city"]["boards"]);
    assert_eq!(after["city"]["boards"]["rush"][0]["name"], "sam");

    drop(server);
    let _ = std::fs::remove_file(&save);
}

// The rules' own feed checks, without a world around them.
#[test]
fn only_the_paper_role_can_publish_a_post() {
    let mut world = city();
    let post = Command::PublishPost {
        kind: "x".into(),
        text: "made up".into(),
        about: None,
    };
    let refused = apply(&mut world.state, Role::Player, post);
    assert!(refused.is_err());
}

#[test]
fn your_neighbours_are_the_people_either_side_with_rank_name_and_title_only() {
    let mut world = city();
    let names = ["aaa", "bbb", "ccc", "ddd", "eee", "fff", "ggg"];
    for (i, name) in names.iter().enumerate() {
        connect(&mut world, name);
        // Faster as the alphabet goes on.
        rush(&mut world, name, i as u32 + 1, name);
    }
    let you = server::protocol::you(&world, "ddd");
    let near = you["neighbours"]["rush"].as_array().unwrap();
    let ranks: Vec<u64> = near.iter().map(|r| r["rank"].as_u64().unwrap()).collect();
    assert_eq!(ranks, [2, 3, 4, 5, 6]);
    assert_eq!(near[2]["name"], "ddd", "you're in the middle");
    assert_eq!(near[0]["name"], "fff");
    for row in near {
        assert_eq!(row.as_object().unwrap().len(), 3, "{row}");
    }
    let top = server::protocol::you(&world, "ggg");
    assert_eq!(top["neighbours"]["rush"].as_array().unwrap().len(), 3);
}

#[test]
fn your_best_board_is_where_you_rank_and_null_before_you_rank() {
    let mut world = city();
    connect(&mut world, "sam");
    assert_eq!(
        server::protocol::you(&world, "sam")["best_board"],
        json!(null)
    );
    rush(&mut world, "sam", 2, "r");
    assert_eq!(server::protocol::you(&world, "sam")["best_board"], "rush");
}
