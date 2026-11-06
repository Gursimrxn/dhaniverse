//! Nobody learns what someone else paid, and nobody acts for someone else.

mod common;

use common::*;
use serde_json::{json, Value};

/// Reads everything until this client's next result, and returns the events that came in.
fn events_seen(client: &mut Client) -> Vec<Value> {
    client.must(json!({"type": "StartRush"}));
    client.must(json!({"type": "EndRush"}));
    client.take_events()
}

fn start() -> (Server, std::path::PathBuf) {
    let save = fresh_save(&format!("privacy_{:?}", std::thread::current().id()));
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    (server, save)
}

#[test]
fn a_players_meal_and_runs_stay_private_and_the_board_still_moves() {
    let (server, save) = start();
    let mut sam = Client::connect(&server.addr);
    sam.hello("sam");
    let mut priya = Client::connect(&server.addr);
    priya.hello("priya");
    priya.take_events();

    sam.meal("thali");
    sam.must(json!({"type": "StartRush"}));
    sam.must(json!({"type": "ServeOrder"}));
    sam.must(json!({"type": "EndRush"}));
    let mine = sam.take_events();
    assert_eq!(find(&mine, "MealEaten")["item"], "thali");
    assert_eq!(find(&mine, "RushEnded")["served"], 1);

    let seen = events_seen(&mut priya);
    for event in &seen {
        let about_sam = event["account"] == "sam";
        assert!(!about_sam, "priya saw sam's own event: {event}");
    }
    let city = priya.hello("priya")["city"].clone();
    assert_eq!(
        city["boards"]["rush"][0]["name"], "sam",
        "the board still moves"
    );

    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn a_client_cant_act_for_someone_else() {
    let (server, save) = start();
    let mut sam = Client::connect(&server.addr);
    sam.hello("sam");
    let mut priya = Client::connect(&server.addr);
    priya.hello("priya");
    // The account always comes from the connection, so sam's EndRush can only ever be sam's.
    priya.must(json!({"type": "StartRush"}));
    let refused = sam.command(json!({"type": "EndRush"}));
    assert_eq!(
        refused["refusal"]["type"], "NotInRush",
        "sam never started one"
    );
    assert_eq!(
        priya.hello("priya")["you"]["in_rush"],
        true,
        "priya's run goes on"
    );

    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn a_season_change_refreshes_everyones_ranks() {
    let (server, save) = start();
    let mut sam = Client::connect(&server.addr);
    sam.hello("sam");
    sam.must(json!({"type": "StartRush"}));
    sam.must(json!({"type": "ServeOrder"}));
    sam.must(json!({"type": "EndRush"}));
    assert_eq!(sam.hello("sam")["you"]["ranks"]["rush"], 1);
    sam.inbox.clear();
    sam.debug(json!({"type": "NextSeason"}));
    assert_eq!(sam.latest_you()["ranks"]["rush"], json!(null));

    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn a_public_title_and_the_paper_say_nothing_about_money() {
    let (server, save) = start();
    let mut sam = Client::connect(&server.addr);
    sam.hello("sam");
    sam.meal("vada_pav");
    sam.debug(json!({"type": "Skip", "ms": 3_600_000}));
    let snapshot = sam.hello("sam");
    let paper = snapshot["city"]["paper"].to_string();
    assert!(!paper.contains("vada pav for"), "{paper}");
    sam.send(json!({"type": "profile", "name": "sam"}));
    let profile = sam.until("profile");
    assert_eq!(profile["title"], "Regular");
    assert!(!profile.to_string().contains("usdc"), "{profile}");

    drop(server);
    let _ = std::fs::remove_file(&save);
}
