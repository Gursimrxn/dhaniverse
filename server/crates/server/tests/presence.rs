//! Seeing each other: names held by a secret, positions relayed over real sockets, and none of it in the save.

mod common;

use common::*;
use serde_json::{json, Value};

const SAM_SECRET: &str = "sam-secret-0123456789";

fn hello(player: &str, secret: &str) -> Value {
    json!({"type": "hello", "protocol": 3, "player": player, "secret": secret})
}

fn walk(client: &mut Client, x: f64) {
    client.send(json!({"type": "move", "x": x, "y": 0.0, "z": -3.25, "yaw": 1.5, "anim": "walk"}));
}

/// Reads presence messages until one has this name on it.
fn until_seen(client: &mut Client, name: &str) -> Value {
    loop {
        let message = client.until("presence");
        let players = message["players"].as_array().unwrap();
        if let Some(found) = players.iter().find(|p| p["name"] == name) {
            return found.clone();
        }
    }
}

#[test]
fn two_players_see_each_other_and_a_taken_name_is_refused() {
    let save = fresh_save("presence_two");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut sam = Client::connect(&server.addr);
    sam.hello("sam");
    let mut priya = Client::connect(&server.addr);
    priya.hello("priya");

    walk(&mut sam, 12.5);
    walk(&mut priya, 40.0);
    let seen_by_priya = until_seen(&mut priya, "sam");
    assert_eq!(seen_by_priya["x"], 12.5);
    assert_eq!(seen_by_priya["z"], -3.25);
    assert_eq!(seen_by_priya["yaw"], 1.5);
    assert_eq!(seen_by_priya["anim"], "walk");
    assert_eq!(seen_by_priya["title"], "Newcomer");
    assert_eq!(until_seen(&mut sam, "priya")["x"], 40.0);

    // A stranger with sam's name is refused, and sam isn't disturbed.
    let mut stranger = Client::connect(&server.addr);
    stranger.send(hello("sam", "not-sams-secret-at-all"));
    let refused = stranger.until("hello_refused");
    assert_eq!(refused["refusal"]["type"], "NameTaken");
    assert_eq!(refused["refusal"]["name"], "sam");
    sam.must(json!({"type": "StartRush"}));

    // The stranger's connection is still good for trying another name.
    stranger.send(hello("not good", "another-secret-0123456"));
    assert_eq!(
        stranger.until("hello_refused")["refusal"]["type"],
        "BadName"
    );
    stranger.send(hello("stranger", ""));
    assert_eq!(
        stranger.until("hello_refused")["refusal"]["type"],
        "BadSecret"
    );
    stranger.send(hello("stranger", "another-secret-0123456"));
    assert_eq!(stranger.until("snapshot")["you"]["name"], "stranger");

    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn someone_who_leaves_is_announced_and_comes_off_the_list() {
    let save = fresh_save("presence_left");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut sam = Client::connect(&server.addr);
    sam.hello("sam");
    let mut priya = Client::connect(&server.addr);
    priya.hello("priya");
    walk(&mut sam, 1.0);
    until_seen(&mut priya, "sam");

    drop(sam);
    assert_eq!(priya.until("left")["name"], "sam");
    // Priya moves, so a fresh list comes: sam isn't on it.
    walk(&mut priya, 2.0);
    let players = |message: &Value| {
        let all = message["players"].as_array().unwrap().clone();
        all.into_iter()
            .filter(|p| p.get("resident").is_none())
            .collect::<Vec<_>>()
    };
    let still_here = loop {
        let list = players(&priya.until("presence"));
        if list.len() == 1 {
            break list;
        }
    };
    assert_eq!(still_here[0]["name"], "priya");

    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn a_takeover_by_the_same_player_isnt_a_leaving() {
    let save = fresh_save("presence_takeover");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut watcher = Client::connect(&server.addr);
    watcher.hello("watcher");
    let mut first = Client::connect(&server.addr);
    first.hello("sam");
    walk(&mut first, 1.0);
    until_seen(&mut watcher, "sam");

    let mut second = Client::connect(&server.addr);
    second.hello("sam");
    assert_eq!(first.until("kicked")["type"], "kicked");
    walk(&mut second, 7.0);
    loop {
        let message = watcher.read();
        assert_ne!(message["type"], "left", "{message}");
        if message["type"] == "presence" && message["players"][0]["x"] == 7.0 {
            break;
        }
    }

    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn the_name_survives_a_restart_and_the_log_holds_a_hash_and_no_positions() {
    let save = fresh_save("presence_log");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut sam = Client::connect(&server.addr);
    sam.send(hello("sam", SAM_SECRET));
    let seq = sam.until("snapshot")["seq"].clone();
    for x in 0..20 {
        walk(&mut sam, f64::from(x));
    }
    until_seen(&mut sam, "sam");
    sam.send(hello("sam", SAM_SECRET));
    assert_eq!(sam.until("snapshot")["seq"], seq, "moving writes nothing");

    drop(sam);
    drop(server);
    let text = std::fs::read_to_string(&save).unwrap();
    assert!(!text.contains(SAM_SECRET), "the secret is never saved");
    assert!(text.contains("secret_hash"));
    assert!(!text.contains("\"anim\""), "positions are never saved");

    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut stranger = Client::connect(&server.addr);
    stranger.send(hello("sam", "not-sams-secret-at-all"));
    assert_eq!(
        stranger.until("hello_refused")["refusal"]["type"],
        "NameTaken"
    );
    let mut back = Client::connect(&server.addr);
    back.send(hello("sam", SAM_SECRET));
    assert_eq!(back.until("snapshot")["you"]["name"], "sam");

    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn a_new_player_connects_nameless_and_writes_their_name_on_the_ticket() {
    let save = fresh_save("presence_ticket");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut holder = Client::connect(&server.addr);
    holder.hello("sam");
    let ticket = |name: &str| json!({"type": "command", "ref": "t", "command": {"type": "ClaimName", "name": name}});

    let mut new = Client::connect(&server.addr);
    new.send(json!({"type": "hello", "protocol": 3, "secret": SAM_SECRET}));
    new.until("nameless");
    new.send(json!({"type": "command", "ref": "n", "command": {"type": "StartRush"}}));
    assert_eq!(new.until("error")["message"], "say hello first");

    new.send(ticket("sam"));
    let result = new.until("result");
    assert_eq!(result["ok"], false);
    assert_eq!(result["refusal"]["type"], "NameTaken");
    new.send(ticket("Bad Name"));
    assert_eq!(new.until("result")["refusal"]["type"], "BadName");

    new.send(ticket("priya"));
    assert_eq!(new.until("snapshot")["you"]["name"], "priya");
    assert_eq!(new.until("result")["ok"], true);
    // Now it's a normal connection.
    new.must(json!({"type": "StartRush"}));
    drop(new);

    // A drop mid-claim: the same secret and name just lets them in, once.
    let mut again = Client::connect(&server.addr);
    again.send(json!({"type": "hello", "protocol": 3, "secret": SAM_SECRET}));
    again.until("nameless");
    again.send(ticket("priya"));
    assert_eq!(again.until("snapshot")["you"]["name"], "priya");
    assert_eq!(again.until("result")["ok"], true);

    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn too_many_name_tries_from_one_address_are_slowed_down() {
    let save = fresh_save("presence_slow");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut client = Client::connect(&server.addr);
    for _ in 0..60 {
        client.send(hello("x", "a-good-long-secret"));
        assert_eq!(client.until("hello_refused")["refusal"]["type"], "BadName");
    }
    client.send(hello("x", "a-good-long-secret"));
    assert_eq!(client.until("hello_refused")["refusal"]["type"], "SlowDown");

    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn a_bad_move_gets_an_error_and_needs_a_hello_first() {
    let save = fresh_save("presence_bad");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut client = Client::connect(&server.addr);
    walk(&mut client, 1.0);
    assert_eq!(client.until("error")["message"], "say hello first");
    client.hello("sam");
    let long = "x".repeat(25);
    client.send(json!({"type": "move", "x": 1, "y": 0, "z": 0, "yaw": 0, "anim": long}));
    client.until("error");
    client.send(json!({"type": "move", "x": "here", "y": 0, "z": 0, "yaw": 0, "anim": "idle"}));
    client.until("error");

    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn residents_are_on_the_list_with_named_places_and_stay_off_a_players_screen_otherwise() {
    let save = fresh_save("presence_residents");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut sam = Client::connect(&server.addr);
    sam.hello("sam");
    // Nobody has moved, and the townspeople are still there.
    let message = sam.until("presence");
    let players = message["players"].as_array().unwrap();
    assert!(players.len() >= 20, "{message}");
    let places = ["market", "table", "bank", "homes", "square"];
    for resident in players {
        assert_eq!(resident["resident"], true);
        assert!(places.contains(&resident["place"].as_str().unwrap()));
        assert!(places.contains(&resident["from"].as_str().unwrap()));
        assert!(resident.get("x").is_none());
    }
    // A player's own entry isn't marked, and they keep working alongside.
    walk(&mut sam, 3.0);
    let me = until_seen(&mut sam, "sam");
    assert!(me.get("resident").is_none());

    // A skip moves the town on, and everyone can be replayed to the same place.
    sam.debug(json!({"type": "Skip", "ms": 7200000}));
    drop(sam);
    drop(server);
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut back = Client::connect(&server.addr);
    back.hello("sam");

    drop(server);
    let _ = std::fs::remove_file(&save);
}
