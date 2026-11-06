//! The mentor in a live city: it speaks only after the real thing, once, only to that player, and moves nothing.

mod common;

use common::*;
use rules::{Command, Event, Role};
use serde_json::json;
use server::log::Log;
use server::world::{Input, World};

const RULES: &str = include_str!("../../../rules.toml");

fn city() -> World {
    World::new(RULES, 1).unwrap()
}

fn connect(world: &mut World, player: &str) {
    let player = player.to_string();
    world.step(Input::Connect { player }).unwrap();
}

fn ask(world: &mut World, account: &str, question: &str) -> Vec<Event> {
    let command = Command::AskMentor {
        account: account.into(),
        question: question.into(),
    };
    let input = Input::Command {
        by: Role::Player,
        command,
    };
    world.step(input).unwrap()
}

/// A meal paid for on chain, at this price.
fn meal(world: &mut World, account: &str, usdc: u64, reference: &str) -> Vec<Event> {
    eat(world, account, "chai", usdc, reference)
}

/// What the mentor said to this player: their `about` fields, in order.
fn said_to(events: &[Event], player: &str) -> Vec<String> {
    events
        .iter()
        .filter_map(|e| match e {
            Event::MentorSays { account, about, .. } if account == player => Some(about.clone()),
            _ => None,
        })
        .collect()
}

#[test]
fn eating_at_a_steady_price_names_nothing() {
    let mut world = city();
    connect(&mut world, "sam");
    for n in 0..3 {
        let events = meal(&mut world, "sam", 1000, &format!("m{n}"));
        assert_eq!(said_to(&events, "sam"), Vec::<String>::new());
    }
}

#[test]
fn a_dearer_meal_is_named_once_and_only_to_the_one_who_paid_it() {
    let mut world = city();
    connect(&mut world, "sam");
    connect(&mut world, "priya");
    meal(&mut world, "sam", 1000, "a");
    meal(&mut world, "priya", 1000, "b");
    let events = meal(&mut world, "sam", 1100, "c");
    assert_eq!(said_to(&events, "sam"), ["inflation"]);
    assert_eq!(said_to(&events, "priya"), Vec::<String>::new());
    let again = meal(&mut world, "sam", 1200, "d");
    assert_eq!(said_to(&again, "sam"), Vec::<String>::new(), "said once");
}

#[test]
fn it_answers_only_what_youve_met_and_moves_nothing() {
    let mut world = city();
    connect(&mut world, "sam");
    connect(&mut world, "priya");
    let before = world.state.clone();
    let events = ask(&mut world, "sam", "what is inflation?");
    assert_eq!(said_to(&events, "sam"), ["reply"]);
    assert_eq!(said_to(&events, "priya"), Vec::<String>::new());
    for event in &events {
        if let Event::MentorSays { text, .. } = event {
            assert!(!text.to_lowercase().contains("inflation"), "{text}");
        }
    }
    assert_eq!(
        world.state.life, before.life,
        "nobody's energy or firsts moved"
    );
    assert_eq!(world.state.market, before.market, "the market didn't move");
}

#[test]
fn residents_never_hear_from_it() {
    let mut world = city();
    let events = world.step(Input::Advance { ms: 24 * 3_600_000 }).unwrap();
    assert!(
        !events.iter().any(|e| matches!(e, Event::MentorSays { .. })),
        "nobody is here to hear it"
    );
}

#[test]
fn a_long_question_is_refused_and_a_client_cant_put_words_in_its_mouth() {
    let save = fresh_save("mentor_socket");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut sam = Client::connect(&server.addr);
    sam.hello("sam");
    let mut priya = Client::connect(&server.addr);
    priya.hello("priya");
    priya.take_events();

    sam.must(json!({"type": "AskMentor", "question": "what's inflation?"}));
    let events = sam.take_events();
    let says = find(&events, "MentorSays");
    assert_eq!(says["about"], "reply");
    let long = "x".repeat(201);
    let refused = sam.command(json!({"type": "AskMentor", "question": long}));
    assert_eq!(refused["refusal"]["type"], "QuestionTooLong");

    // The mentor's own command isn't one a client can send, and nor is reporting a meal.
    let fake = json!({"type": "MentorSay", "account": "priya", "about": "x", "text": "x"});
    sam.send(json!({"type": "command", "ref": "x", "command": fake}));
    sam.until("error");
    let free_lunch = json!({"type": "MealEaten", "item": "chai", "usdc": 0});
    sam.send(json!({"type": "command", "ref": "y", "command": free_lunch}));
    sam.until("error");

    // Priya heard none of it.
    priya.must(json!({"type": "StartRush"}));
    let heard = priya.take_events();
    assert!(heard.iter().all(|e| e["type"] != "MentorSays"), "{heard:?}");

    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn what_it_has_said_survives_a_restart_so_it_doesnt_repeat_itself() {
    let path = fresh_save("mentor_replay");
    let (mut log, mut world) = Log::open(&path, RULES, 7).unwrap();
    let mut take = |world: &mut World, input: Input| {
        let events = world.step(input.clone()).unwrap();
        log.append(&input, &events).unwrap();
        events
    };
    take(
        &mut world,
        Input::Connect {
            player: "sam".into(),
        },
    );
    for input in meal_inputs(&world, "sam", "chai", 1000, "a") {
        take(&mut world, input);
    }
    let mut events = Vec::new();
    for input in meal_inputs(&world, "sam", "chai", 1100, "b") {
        events = take(&mut world, input);
    }
    assert_eq!(said_to(&events, "sam"), ["inflation"]);
    drop(log);

    let (_, mut rebuilt) = Log::open(&path, RULES, 7).unwrap();
    let events = meal(&mut rebuilt, "sam", 1200, "c");
    assert_eq!(said_to(&events, "sam"), Vec::<String>::new());
    let _ = std::fs::remove_file(&path);
}
