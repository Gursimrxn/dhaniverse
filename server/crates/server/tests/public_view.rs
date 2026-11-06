//! The public view over real HTTP: what anyone on the internet can read, which must never include anything private.

mod common;

use common::*;
use serde_json::{json, Value};
use std::io::{Read, Write};
use std::net::TcpStream;
use std::time::{Duration, Instant};

const SECRET_AMOUNT: u64 = 7_654_321;

/// One raw request. Returns (status, headers and all, body).
fn request(addr: &str, head: &str) -> (u32, String, String) {
    let mut stream = TcpStream::connect(addr).unwrap();
    stream
        .set_read_timeout(Some(Duration::from_secs(10)))
        .unwrap();
    stream.write_all(head.as_bytes()).unwrap();
    let mut text = String::new();
    stream.read_to_string(&mut text).unwrap();
    let (headers, body) = text.split_once("\r\n\r\n").unwrap_or((&text, ""));
    let status = headers.split_whitespace().nth(1).unwrap().parse().unwrap();
    (status, headers.to_string(), body.to_string())
}

fn get(addr: &str, path: &str) -> (u32, String, String) {
    request(addr, &format!("GET {path} HTTP/1.1\r\nHost: town\r\n\r\n"))
}

fn city(addr: &str) -> Value {
    let (status, _, body) = get(addr, "/city");
    assert_eq!(status, 200, "{body}");
    serde_json::from_str(&body).unwrap()
}

/// Waits for the view to be rebuilt until this is true of it. It's rebuilt every few seconds.
fn until(addr: &str, what: impl Fn(&Value) -> bool) -> Value {
    let start = Instant::now();
    loop {
        let view = city(addr);
        if what(&view) {
            return view;
        }
        assert!(start.elapsed() < Duration::from_secs(12), "{view}");
        std::thread::sleep(Duration::from_millis(500));
    }
}

#[test]
fn anyone_can_read_the_town_and_nothing_private_is_in_it() {
    let save = fresh_save("public_city");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut sam = Client::connect(&server.addr);
    let wallet = sam.hello("sam")["you"]["wallet"]
        .as_str()
        .unwrap()
        .to_string();
    let paid = sam.meal("chai")["usdc"].as_u64().unwrap();
    sam.must(json!({"type": "StartRush"}));
    sam.must(json!({"type": "ServeOrder"}));
    sam.must(json!({"type": "EndRush"}));

    let view = until(&server.addr, |v| {
        v["boards"]["rush"]
            .as_array()
            .is_some_and(|b| !b.is_empty())
    });
    let mut keys: Vec<&str> = view
        .as_object()
        .unwrap()
        .keys()
        .map(String::as_str)
        .collect();
    keys.sort_unstable();
    assert_eq!(
        keys,
        [
            "boards",
            "bounty",
            "chain",
            "day",
            "day_ms",
            "draw",
            "feed",
            "float",
            "food",
            "house",
            "online",
            "paper",
            "people",
            "price",
            "protocol",
            "residents",
            "season",
            "town_goal",
            "treasury",
            "world_app_id"
        ]
    );
    assert_eq!(view["protocol"], 3);
    assert_eq!(view["chain"], "offline");
    assert!(view["bounty"]
        .as_array()
        .unwrap()
        .iter()
        .any(|c| c["template"] == "spice_run" && c["status"] == "live"));
    assert!(
        view["house"]["surprise"]["balance"].as_u64().unwrap() > 0,
        "the offline pools are seeded"
    );
    assert_eq!(view["online"], 1);
    assert_eq!(view["residents"], 20);
    assert_eq!(view["people"][0]["name"], "sam");
    assert_eq!(view["boards"]["rush"][0]["name"], "sam");
    assert_eq!(view["food"]["menu"][0]["name"], "chai");

    let text = view.to_string();
    assert!(!text.contains(&SECRET_AMOUNT.to_string()), "{text}");
    assert!(!text.contains(&wallet), "a wallet is private: {text}");
    let private_keys = [
        "\"in_rush\"",
        "\"served\"",
        "\"best_run\"",
        "\"you\"",
        "\"pending\"",
        "\"wallet\"",
        "\"vouchers\"",
    ];
    for private in private_keys.iter().copied().chain(["secret", "resident:"]) {
        assert!(!text.contains(private), "{private} in {text}");
    }
    for person in view["people"].as_array().unwrap() {
        let mut keys: Vec<&String> = person.as_object().unwrap().keys().collect();
        keys.sort();
        assert_eq!(
            keys,
            ["ens", "name", "stamps", "title"],
            "only public things about a person: {person}"
        );
    }
    assert_eq!(
        view["food"]["usdc_today"], paid,
        "the town's food money is a total, not anyone's"
    );
    for row in view["boards"]["rush"].as_array().unwrap() {
        assert_eq!(row.as_object().unwrap().len(), 3, "{row}");
    }

    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn it_says_it_can_be_cached_and_read_from_any_site() {
    let save = fresh_save("public_headers");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    until(&server.addr, |_| true);
    let (status, headers, body) = get(&server.addr, "/city");
    assert_eq!(status, 200);
    let headers = headers.to_lowercase();
    assert!(
        headers.contains("access-control-allow-origin: *"),
        "{headers}"
    );
    assert!(
        headers.contains("cache-control: public, max-age=5"),
        "{headers}"
    );
    assert!(
        headers.contains("content-type: application/json"),
        "{headers}"
    );
    assert!(
        headers.contains(&format!("content-length: {}", body.len())),
        "{headers}"
    );

    let (status, _, body) = request(&server.addr, "HEAD /city HTTP/1.1\r\nHost: town\r\n\r\n");
    assert_eq!(status, 200);
    assert_eq!(body, "");

    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn other_paths_and_methods_are_refused() {
    let save = fresh_save("public_paths");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    assert_eq!(get(&server.addr, "/save.jsonl").0, 404);
    assert_eq!(get(&server.addr, "/city/../rules.toml").0, 404);
    assert_eq!(get(&server.addr, "/").0, 404);
    let post = "POST /city HTTP/1.1\r\nHost: town\r\nContent-Length: 0\r\n\r\n";
    assert_eq!(request(&server.addr, post).0, 405);

    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn health_says_the_server_is_alive() {
    let save = fresh_save("public_health");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    until(&server.addr, |_| true);
    let (status, _, body) = get(&server.addr, "/health");
    assert_eq!(status, 200);
    let health: Value = serde_json::from_str(&body).unwrap();
    assert_eq!(health["ok"], true);
    assert!(health["seq"].is_number());

    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn too_many_requests_from_one_address_get_a_429_and_the_game_goes_on() {
    let save = fresh_save("public_limit");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut limited = false;
    for _ in 0..125 {
        limited |= get(&server.addr, "/city").0 == 429;
    }
    assert!(limited);
    // Health and the game itself aren't affected.
    assert_eq!(get(&server.addr, "/health").0, 200);
    let mut sam = Client::connect(&server.addr);
    sam.hello("sam");
    sam.must(json!({"type": "StartRush"}));

    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn behind_a_proxy_the_limit_counts_each_visitor_and_not_the_proxy() {
    let save = fresh_save("public_proxy");
    let server = Server::start(&save, &["--heartbeat-ms", "0", "--behind-proxy"]);
    let from = |who: &str| {
        request(
            &server.addr,
            &format!("GET /city HTTP/1.1\r\nHost: t\r\nX-Forwarded-For: fake, {who}\r\n\r\n"),
        )
        .0
    };
    let mut limited = false;
    for _ in 0..125 {
        limited |= from("1.1.1.1") == 429;
    }
    assert!(limited);
    assert_ne!(from("2.2.2.2"), 429, "another visitor is fine");

    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn a_half_sent_request_doesnt_stop_anything() {
    let save = fresh_save("public_slow");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut stuck = TcpStream::connect(&server.addr).unwrap();
    stuck.write_all(b"GET /city HT").unwrap();
    let mut sam = Client::connect(&server.addr);
    sam.hello("sam");
    assert_eq!(get(&server.addr, "/health").0, 200);
    drop(stuck);

    drop(server);
    let _ = std::fs::remove_file(&save);
}
