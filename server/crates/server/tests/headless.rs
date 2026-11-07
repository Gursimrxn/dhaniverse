//! A headless client against the real binary over a real WebSocket: a player's session, a crash, and a reconnect to
//! the same state. Run with `--nocapture` to read the transcript.

mod common;

use common::*;
use serde_json::{json, Value};
use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::Duration;
use tungstenite::Message;

#[test]
fn a_session_a_crash_and_the_same_state_after() {
    let save = fresh_save("headless");
    // No heartbeat: time moves only by skips, so the two snapshots can be compared exactly.
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut sam = Client::connect(&server.addr);

    println!("connect");
    let snapshot = sam.hello("sam");
    assert_eq!(snapshot["you"]["energy"], 100);
    assert_eq!(snapshot["you"]["in_rush"], false);
    assert_eq!(snapshot["city"]["menu"][0]["name"], "chai");
    // Kofi's first slice has already sold, so the price is a little under the launch 0.10 USDC.
    let price = snapshot["city"]["price"].as_u64().unwrap();
    assert!((60_000..=100_000).contains(&price), "{price}");
    let chai = snapshot["city"]["menu"][0].clone();
    assert_eq!(
        chai["price"].as_u64().unwrap(),
        price,
        "one FOOD at the live price"
    );
    assert_eq!(
        chai["max_usdc"].as_u64().unwrap(),
        (price * 102).div_ceil(100),
        "with 2% headroom"
    );
    assert!(
        snapshot["you"]["wallet"]
            .as_str()
            .unwrap()
            .starts_with("0x"),
        "offline, the wallet is there at once"
    );
    println!("  snapshot: energy {}", snapshot["you"]["energy"]);

    println!("a Market Rush run");
    sam.must(json!({"type": "StartRush"}));
    for _ in 0..3 {
        sam.must(json!({"type": "ServeOrder"}));
    }
    assert_eq!(sam.latest_you()["served"], 3);
    sam.must(json!({"type": "EndRush"}));
    assert_eq!(sam.latest_you()["best_run"], 3);
    let events = sam.take_events();
    assert_eq!(find(&events, "RushEnded")["served"], 3);

    println!("a meal, paid on the offline chain");
    sam.meal("chai");
    let events = sam.take_events();
    let meal = find(&events, "MealEaten");
    assert_eq!(
        meal["usdc"], price,
        "the offline chain charges the quote, not the headroom"
    );
    assert_eq!(meal["energy"], 100, "the errand's 10 back");
    assert_eq!(find(&events, "FirstEarned")["first"], "first_meal");
    println!("  {meal}");

    println!("a refusal names its numbers");
    let refused = sam.command(json!({"type": "ServeOrder"}));
    assert_eq!(refused["ok"], false);
    assert_eq!(refused["refusal"]["type"], "NotInRush");

    println!("a retry can't count twice");
    sam.must(json!({"type": "StartRush"}));
    let serve = json!({"type": "command", "ref": "order-9", "command": {"type": "ServeOrder"}});
    sam.send(serve.clone());
    assert_eq!(sam.until("result")["ok"], true);
    sam.send(serve);
    let retry = sam.until("result");
    assert_eq!(retry["refusal"]["type"], "RefUsed");
    assert_eq!(retry["refusal"]["ref"], "sam:order-9");
    println!("  {}", retry["refusal"]);
    sam.must(json!({"type": "EndRush"}));
    sam.debug(json!({"type": "Skip", "ms": 2 * 3_600_000}));
    sam.take_events();

    println!("restart");
    // A new connection takes over, and the old one is told. Its snapshot is the state to compare.
    let mut again = Client::connect(&server.addr);
    let before = again.hello("sam");
    assert_eq!(sam.until("kicked")["type"], "kicked");

    // The hard way: no goodbye, no Disconnect. The next start has to work it out from the log.
    drop(server);
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut back = Client::connect(&server.addr);
    let after = back.hello("sam");
    assert_eq!(after["you"], before["you"], "the same player");
    assert_eq!(after["city"], before["city"], "the same city");
    println!(
        "  same state: best run {}, day {}, price {}",
        after["you"]["best_run"], after["city"]["day"], after["city"]["price"]
    );

    // And the old refs are still used, across the restart.
    back.must(json!({"type": "StartRush"}));
    back.send(json!({"type": "command", "ref": "order-9", "command": {"type": "ServeOrder"}}));
    assert_eq!(back.until("result")["ok"], false);

    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn the_live_clock_runs_the_city_with_nobody_asking() {
    let save = fresh_save("live_clock");
    // 50 ms beats at 2,000× speed: a five-minute slice about every 150 ms.
    let server = Server::start(&save, &["--heartbeat-ms", "50", "--speed", "2000"]);
    std::thread::sleep(Duration::from_millis(1500));

    // Nobody has connected in all that time, and the city has been trading.
    let mut sam = Client::connect(&server.addr);
    let snapshot = sam.hello("sam");
    assert!(snapshot["seq"].as_u64().unwrap() > 5);
    println!(
        "after 1.5 s with nobody connected: {}",
        snapshot["city"]["day_elapsed_ms"]
    );
    assert_ne!(snapshot["city"]["price"], 1000);

    // The clock keeps telling everyone the time, and the paper comes out each morning.
    let time = sam.until("time");
    assert!(time["day_ms"].as_u64().unwrap() > 0);
    let paper = loop {
        let message = sam.read();
        if message["type"] == "event" && message["event"]["type"] == "PaperPublished" {
            break message;
        }
    };
    assert!(paper["event"]["day"].as_u64().unwrap() > 0);

    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn the_morning_paper_reaches_everyone_and_waits_for_latecomers() {
    let save = fresh_save("paper");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut sam = Client::connect(&server.addr);
    let snapshot = sam.hello("sam");
    assert_eq!(
        snapshot["city"]["paper"],
        Value::Null,
        "nothing to report yet"
    );

    sam.debug(json!({"type": "Skip", "ms": 3_600_000}));
    let events = sam.take_events();
    let paper = find(&events, "PaperPublished");
    assert_eq!(paper["day"], 1);
    assert!(!paper["headline"].as_str().unwrap().is_empty());
    println!("  {paper}");

    // Someone arriving later gets today's paper in their snapshot.
    let mut priya = Client::connect(&server.addr);
    let later = priya.hello("priya");
    assert_eq!(later["city"]["paper"]["headline"], paper["headline"]);
    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn the_menu_is_the_live_quote_and_says_what_it_cost_at_yesterdays_average() {
    let save = fresh_save("menu_was");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut sam = Client::connect(&server.addr);
    let first = sam.hello("sam");
    for item in first["city"]["menu"].as_array().unwrap() {
        assert_eq!(item["was"], item["price"], "no yesterday yet: {item}");
    }
    let mut moved = false;
    for _ in 0..6 {
        sam.debug(json!({"type": "Skip", "ms": 3_600_000}));
        let city = sam.hello("sam")["city"].clone();
        let price = city["price"].as_u64().unwrap();
        for item in city["menu"].as_array().unwrap() {
            let food = item["food"].as_u64().unwrap();
            assert_eq!(
                item["price"].as_u64().unwrap(),
                (food * price).div_ceil(1_000_000),
                "{item}"
            );
            moved |= item["was"] != item["price"];
        }
    }
    assert!(
        moved,
        "in 6 days, yesterday's average differed from the live price"
    );
    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn a_server_with_the_flag_moves_a_bad_save_aside_and_one_without_refuses() {
    let save = fresh_save("flag");
    std::fs::write(&save, "this is not a save").unwrap();
    let run = |flags: &[&str]| {
        Command::new(env!("CARGO_BIN_EXE_server"))
            .args([
                "--addr",
                "127.0.0.1:0",
                "--heartbeat-ms",
                "0",
                "--rules",
                RULES,
            ])
            .arg("--save")
            .arg(&save)
            .args(flags)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap()
    };
    let refused = run(&[]).wait_with_output().unwrap();
    assert!(!refused.status.success());
    assert_eq!(
        std::fs::read_to_string(&save).unwrap(),
        "this is not a save"
    );

    let mut started = run(&["--new-if-incompatible"]);
    let mut line = String::new();
    BufReader::new(started.stdout.take().unwrap())
        .read_line(&mut line)
        .unwrap();
    assert!(line.starts_with("listening on "), "{line}");
    let _ = started.kill();
    let output = started.wait_with_output().unwrap();
    let said = String::from_utf8_lossy(&output.stderr).to_string();
    assert!(said.contains("NEW CITY"), "{said}");
    println!("  {said}");

    let folder = save.parent().unwrap();
    let moved: Vec<PathBuf> = std::fs::read_dir(folder)
        .unwrap()
        .filter_map(|entry| entry.ok().map(|e| e.path()))
        .filter(|p| p.to_string_lossy().contains("flag.jsonl.old-"))
        .collect();
    assert_eq!(moved.len(), 1, "{moved:?}");
    assert_eq!(
        std::fs::read_to_string(&moved[0]).unwrap(),
        "this is not a save"
    );
    let _ = std::fs::remove_file(&moved[0]);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn bad_messages_get_an_error_and_change_nothing() {
    let save = fresh_save("bad_messages");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut client = Client::connect(&server.addr);

    client.send(json!({"type": "command", "ref": "a", "command": {"type": "StartRush"}}));
    assert_eq!(client.until("error")["message"], "say hello first");

    client.send(json!({"type": "hello", "protocol": 99, "player": "sam"}));
    client.until("error");
    client.send(json!({"type": "hello", "protocol": 3, "player": "not a name!", "secret": "a-good-long-secret"}));
    client.until("hello_refused");

    client.socket.send(Message::text("not json")).unwrap();
    client.until("error");

    client.hello("sam");
    let negative = json!({"type": "command", "ref": "n", "command": {"type": "React", "post": -5, "emote": "clap"}});
    client.send(negative);
    client.until("error");
    // Meals, the market and the clock aren't commands a client can send.
    for cheat in [
        json!({"type": "MealEaten", "item": "chai", "usdc": 0}),
        json!({"type": "BuyFood", "wanted": 1000000}),
        json!({"type": "NewDay", "day": 9}),
    ] {
        client.send(json!({"type": "command", "ref": "x", "command": cheat}));
        client.until("error");
    }

    let snapshot = client.hello("sam");
    assert_eq!(snapshot["you"]["energy"], 100);
    assert_eq!(snapshot["you"]["firsts"], json!([]));
    assert_eq!(snapshot["city"]["day"], 0);

    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn without_debug_the_rehearsal_commands_are_off() {
    let save = fresh_save("no_debug");
    let mut child = Command::new(env!("CARGO_BIN_EXE_server"))
        .args([
            "--addr",
            "127.0.0.1:0",
            "--heartbeat-ms",
            "0",
            "--rules",
            RULES,
        ])
        .arg("--save")
        .arg(&save)
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut line = String::new();
    BufReader::new(child.stdout.take().unwrap())
        .read_line(&mut line)
        .unwrap();
    let addr = line
        .trim()
        .strip_prefix("listening on ")
        .unwrap()
        .to_string();
    let mut client = Client::connect(&addr);
    let snapshot = client.hello("sam");
    assert_eq!(snapshot["debug"], false);
    client.send(json!({"type": "debug", "action": {"type": "Skip", "ms": 1}}));
    assert!(client.until("error")["message"]
        .as_str()
        .unwrap()
        .contains("debug is off"));
    let _ = child.kill();
    let _ = child.wait();
    let _ = std::fs::remove_file(&save);
}

#[test]
fn help_and_mistyped_flags_stop_before_anything_starts_or_is_written() {
    let save = fresh_save("flags");
    let run = |flags: &[&str]| {
        Command::new(env!("CARGO_BIN_EXE_server"))
            .args(["--addr", "127.0.0.1:0", "--rules", RULES])
            .arg("--save")
            .arg(&save)
            .args(flags)
            .output()
            .unwrap()
    };

    let help = run(&["--help"]);
    assert!(help.status.success());
    let text = String::from_utf8_lossy(&help.stdout).to_string();
    assert!(text.contains("--new-if-incompatible"), "{text}");
    assert!(!save.exists(), "help wrote a save");

    for bad in [&["--helpp"][..], &["--debugg"], &["stray"], &["--seed"]] {
        let refused = run(bad);
        assert!(!refused.status.success(), "{bad:?} started a server");
        let said = String::from_utf8_lossy(&refused.stderr).to_string();
        assert!(said.contains("server [flags]"), "{bad:?}: {said}");
        assert!(!save.exists(), "{bad:?} wrote a save");
    }
}
