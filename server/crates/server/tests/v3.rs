//! Protocol 3 over real sockets: meals, quests, chests and the Town Pass against the offline chain, the HTTP endpoints
//! beside them, and nothing meant for the chain ever reaching a client.

mod common;

use common::*;
use serde_json::{json, Value};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::PathBuf;
use std::time::Duration;

/// One raw request. Returns (status, head, body).
fn request(addr: &str, raw: &str) -> (u32, String, String) {
    let mut stream = TcpStream::connect(addr).unwrap();
    stream
        .set_read_timeout(Some(Duration::from_secs(15)))
        .unwrap();
    stream.write_all(raw.as_bytes()).unwrap();
    let mut text = String::new();
    stream.read_to_string(&mut text).unwrap();
    let (head, body) = text.split_once("\r\n\r\n").unwrap_or((&text, ""));
    let status = head.split_whitespace().nth(1).unwrap().parse().unwrap();
    (status, head.to_string(), body.to_string())
}

fn get(addr: &str, path: &str) -> (u32, String, String) {
    request(addr, &format!("GET {path} HTTP/1.1\r\nHost: town\r\n\r\n"))
}

fn post(addr: &str, path: &str, body: &str) -> (u32, Value) {
    let raw = format!(
        "POST {path} HTTP/1.1\r\nHost: town\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{body}",
        body.len()
    );
    let (status, _, body) = request(addr, &raw);
    (status, serde_json::from_str(&body).unwrap_or(Value::Null))
}

fn json_get(addr: &str, path: &str) -> (u32, Value) {
    let (status, _, body) = get(addr, path);
    (status, serde_json::from_str(&body).unwrap_or(Value::Null))
}

/// Every message a client got, read until a profile round trip shows nothing more is coming.
fn drain(client: &mut Client) -> Vec<Value> {
    client.send(json!({"type": "profile", "name": "nobody"}));
    client.until("profile");
    std::mem::take(&mut client.inbox)
}

fn token_of(url: &str) -> String {
    url.split("token=").nth(1).unwrap().to_string()
}

#[test]
fn a_meal_is_bought_on_the_offline_chain_and_no_intent_ever_reaches_a_client() {
    let save = fresh_save("v3_meal");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut sam = Client::connect(&server.addr);
    let snapshot = sam.hello("sam");
    assert_eq!(
        snapshot["you"]["usdc"], 0,
        "nobody deposits anything to start"
    );
    assert_eq!(snapshot["city"]["chain"], "offline");
    let mut priya = Client::connect(&server.addr);
    priya.hello("priya");

    let refused = sam.command(json!({"type": "BuyMeal", "item": "thali"}));
    assert_eq!(refused["refusal"]["type"], "EnergyFull");
    let meal = sam.meal("thali");
    assert_eq!(meal["item"], "thali");
    assert!(meal["tx"].as_str().unwrap().starts_with("0x"));
    let messages = drain(&mut sam);
    let you = messages.iter().rev().find(|m| m["type"] == "you").unwrap();
    assert!(
        you["you"]["usdc"].as_u64().unwrap() < 1_000_000,
        "the meal was paid for"
    );
    assert_eq!(you["you"]["meal_pending"], Value::Null);

    for message in messages.iter().chain(drain(&mut priya).iter()) {
        assert_ne!(message["event"]["type"], "Intent", "{message}");
        let text = message.to_string();
        assert!(
            !text.contains("\"BuyMeal\"") || message["type"] == "result",
            "{text}"
        );
    }
    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn the_town_pass_link_works_once_and_a_rehearsal_proof_verifies_on_a_debug_server() {
    let save = fresh_save("v3_town_pass");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut sam = Client::connect(&server.addr);
    sam.hello("sam");
    let result = sam.command(json!({"type": "TownPass"}));
    assert_eq!(result["ok"], true, "{result}");
    let url = result["url"].as_str().unwrap();
    assert!(
        url.starts_with(&format!("http://{}/verify?token=", server.addr)),
        "{url}"
    );
    let token = token_of(url);

    let (status, session) = json_get(&server.addr, &format!("/verify/session?token={token}"));
    assert_eq!(status, 200, "{session}");
    assert_eq!(session["player"], "sam");
    assert!(session["wallet"].as_str().unwrap().starts_with("0x"));
    assert_eq!(session["action"], "tallyport-town-pass");
    assert_eq!(session["rehearsal"], true);
    assert_eq!(session["verified"], false);
    assert_eq!(json_get(&server.addr, "/verify/session?token=nope").0, 404);

    let (status, bad) = post(
        &server.addr,
        "/verify",
        &json!({"token": token, "result": {"proof": "x"}}).to_string(),
    );
    assert_eq!(
        (status, bad["error"].clone()),
        (400, json!("invalid_proof"))
    );
    let (status, ok) = post(
        &server.addr,
        "/verify",
        &json!({"token": token, "result": {"offline": true}}).to_string(),
    );
    assert_eq!(status, 200, "{ok}");
    assert_eq!(ok["ok"], true);
    assert_eq!(ok["rehearsal"], true);
    assert!(ok["human_id"].as_str().unwrap().starts_with("0x"));
    assert_eq!(
        ok["ens"], "sam.tallyport.eth",
        "the name is registered on the Town Pass"
    );
    let (status, used) = post(
        &server.addr,
        "/verify",
        &json!({"token": token, "result": {"offline": true}}).to_string(),
    );
    assert_eq!((status, used["error"].clone()), (410, json!("token_used")));

    let events = sam.take_events();
    let _ = events;
    let messages = drain(&mut sam);
    let you = messages.iter().rev().find(|m| m["type"] == "you").unwrap();
    assert_eq!(you["you"]["human"], true);
    assert_eq!(you["you"]["ens"], "sam.tallyport.eth");
    let again = sam.command(json!({"type": "TownPass"}));
    assert_eq!(again["refusal"]["type"], "AlreadyHuman");
    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn without_debug_a_rehearsal_proof_is_refused() {
    let save = fresh_save("v3_no_debug_pass");
    let mut child = std::process::Command::new(env!("CARGO_BIN_EXE_server"))
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
        .stdout(std::process::Stdio::piped())
        .spawn()
        .unwrap();
    let mut line = String::new();
    std::io::BufRead::read_line(
        &mut std::io::BufReader::new(child.stdout.take().unwrap()),
        &mut line,
    )
    .unwrap();
    let addr = line
        .trim()
        .strip_prefix("listening on ")
        .unwrap()
        .to_string();
    let mut sam = Client::connect(&addr);
    sam.hello("sam");
    let url = sam.command(json!({"type": "TownPass"}))["url"]
        .as_str()
        .unwrap()
        .to_string();
    let (status, refused) = post(
        &addr,
        "/verify",
        &json!({"token": token_of(&url), "result": {"offline": true}}).to_string(),
    );
    assert_eq!(
        (status, refused["error"].clone()),
        (400, json!("invalid_proof"))
    );
    let _ = child.kill();
    let _ = child.wait();
    let _ = std::fs::remove_file(&save);
}

#[test]
fn a_sponsored_quest_runs_over_the_socket_and_pays_once_the_town_pass_is_held() {
    let save = fresh_save("v3_quest");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut sam = Client::connect(&server.addr);
    let snapshot = sam.hello("sam");
    let card = snapshot["city"]["bounty"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["template"] == "paint_sign")
        .unwrap()
        .clone();
    let quest = card["quest"].as_str().unwrap().to_string();
    sam.must(json!({"type": "TakeQuest", "quest": quest}));
    let you = sam.latest_you();
    assert_eq!(you["quests"][0]["quest"], quest.as_str());
    assert_eq!(you["quests"][0]["steps"][0]["id"], "painter");
    assert_eq!(you["energy"], 100 - card["energy"].as_u64().unwrap());
    let wrong = sam.command(json!({"type": "QuestStep", "quest": quest, "step": "sign"}));
    assert_eq!(wrong["refusal"]["type"], "WrongStep");
    sam.must(json!({"type": "QuestStep", "quest": quest, "step": "painter"}));
    let no_name = sam.command(json!({"type": "PaintSign", "text": "Sam's chai"}));
    assert_eq!(no_name["refusal"]["type"], "NoName");
    sam.debug(json!({"type": "PassTown"}));
    sam.must(json!({"type": "PaintSign", "text": "Sam's chai"}));
    let messages = drain(&mut sam);
    let events: Vec<&Value> = messages
        .iter()
        .filter(|m| m["type"] == "event")
        .map(|m| &m["event"])
        .collect();
    let done = events
        .iter()
        .find(|e| e["type"] == "QuestDone")
        .expect("done");
    assert_eq!(done["reward"]["usdc"], card["payout"]);
    assert!(
        events
            .iter()
            .any(|e| e["type"] == "RewardPaid" && e["amount"] == card["payout"]),
        "{events:?}"
    );
    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn chests_the_free_thali_price_calls_and_referrals_answer_with_their_numbers() {
    let save = fresh_save("v3_daily");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut sam = Client::connect(&server.addr);
    sam.hello("sam");
    sam.must(json!({"type": "OpenChest"}));
    let events = sam.take_events();
    let opened = find(&events, "ChestOpened");
    assert_eq!(opened["tier"], "wood");
    let again = sam.command(json!({"type": "OpenChest"}));
    assert_eq!(again["refusal"]["type"], "ChestNotReady");
    assert!(again["refusal"]["ready_at"].as_u64().unwrap() > 0);
    let weekly = sam.command(json!({"type": "OpenChest", "weekly": true}));
    assert_eq!(weekly["refusal"]["type"], "WeeklyChestNotReady");
    assert_eq!(weekly["refusal"]["need"], 5);
    sam.debug(json!({"type": "ReadyChest"}));
    sam.must(json!({"type": "OpenChest"}));

    assert_eq!(
        sam.command(json!({"type": "FreeMeal"}))["refusal"]["type"],
        "EnergyFull"
    );
    sam.must(json!({"type": "PriceCall", "call": "up"}));
    assert_eq!(
        sam.command(json!({"type": "PriceCall", "call": "down"}))["refusal"]["type"],
        "AlreadyCalled"
    );
    assert_eq!(sam.latest_you()["price_call"]["call"], "up");
    let mut priya = Client::connect(&server.addr);
    priya.hello("priya");
    priya.must(json!({"type": "Refer", "player": "sam"}));
    assert_eq!(
        priya.command(json!({"type": "Refer", "player": "sam"}))["refusal"]["type"],
        "AlreadyReferred"
    );

    sam.must(json!({"type": "StartRush"}));
    let you = sam.latest_you();
    assert_eq!(you["runs_left"], 2);
    assert!(you["rush_ends_at"].as_u64().unwrap() >= 90_000);
    sam.debug(json!({"type": "Skip", "ms": 90_000}));
    let events = sam.take_events();
    find(&events, "RushTimeUp");
    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn a_rehearsal_campaign_and_bucket_funding_show_in_the_city() {
    let save = fresh_save("v3_rehearsal");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut sam = Client::connect(&server.addr);
    let before = sam.hello("sam")["city"].clone();
    sam.debug(json!({"type": "NewCampaign", "template": "hold_line", "payout": 500000, "energy": 20, "slots": 5}));
    sam.debug(json!({"type": "FundBucket", "bucket": "safety", "usdc": 5_000_000}));
    let city = sam.hello("sam")["city"].clone();
    let cards = city["bounty"].as_array().unwrap();
    assert!(cards
        .iter()
        .any(|c| c["template"] == "hold_line" && c["slots_left"] == 5));
    let safety = |c: &Value| c["house"]["safety"]["balance"].as_u64().unwrap();
    assert_eq!(safety(&city), safety(&before) + 5_000_000);
    // A campaign that breaks the 25% rule is refused, as CampaignEscrow would.
    sam.send(json!({"type": "debug", "action": {"type": "NewCampaign", "template": "spice_run", "payout": 150000, "energy": 50, "slots": 5}}));
    assert!(sam.until("error")["message"]
        .as_str()
        .unwrap()
        .contains("25%"));
    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn the_web_pages_are_served_and_the_dev_and_tools_folders_never_are() {
    let web = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("v3_web");
    let _ = std::fs::remove_dir_all(&web);
    for folder in ["js", "dev", "tools", "fonts"] {
        std::fs::create_dir_all(web.join(folder)).unwrap();
    }
    std::fs::write(web.join("verify.html"), "<!doctype html>verify").unwrap();
    std::fs::write(web.join("console.html"), "<!doctype html>console").unwrap();
    std::fs::write(web.join("js/core.js"), "export {}").unwrap();
    std::fs::write(web.join("fonts/a.otf"), "font").unwrap();
    std::fs::write(web.join("dev/city.json"), "{}").unwrap();
    std::fs::write(web.join("tools/sync.mjs"), "x").unwrap();
    let deployments = web.join("sepolia.json");
    std::fs::write(&deployments, r#"{"chainId": 11155111, "contracts": {}}"#).unwrap();

    let save = fresh_save("v3_web");
    let web_arg = web.to_string_lossy().to_string();
    let deployments_arg = deployments.to_string_lossy().to_string();
    let server = Server::start(
        &save,
        &[
            "--heartbeat-ms",
            "0",
            "--web",
            &web_arg,
            "--deployments",
            &deployments_arg,
            "--public-rpc-url",
            "https://rpc.example",
            "--publisher-url",
            "http://127.0.0.1:9",
        ],
    );
    let (status, head, body) = get(&server.addr, "/verify?token=abc");
    assert_eq!((status, body.as_str()), (200, "<!doctype html>verify"));
    assert!(head.to_lowercase().contains("content-type: text/html"));
    assert_eq!(get(&server.addr, "/console").0, 200);
    let (status, head, _) = get(&server.addr, "/js/core.js");
    assert_eq!(status, 200);
    assert!(
        head.to_lowercase()
            .contains("content-type: text/javascript"),
        "{head}"
    );
    assert!(get(&server.addr, "/fonts/a.otf")
        .1
        .to_lowercase()
        .contains("font/otf"));
    for hidden in [
        "/dev/city.json",
        "/tools/sync.mjs",
        "/../rules.toml",
        "/js/../dev/city.json",
        "/%2e%2e/x",
    ] {
        assert_eq!(get(&server.addr, hidden).0, 404, "{hidden}");
    }
    let (status, file) = json_get(&server.addr, "/deployments.json");
    assert_eq!(status, 200);
    assert_eq!(file["chainId"], 11155111);
    assert_eq!(file["rpcUrl"], "https://rpc.example");
    let (status, down) = json_get(&server.addr, "/arkiv/campaigns");
    assert_eq!((status, down["error"].clone()), (503, json!("unavailable")));
    drop(server);
    let _ = std::fs::remove_file(&save);
    let _ = std::fs::remove_dir_all(&web);
}

#[test]
fn arkiv_campaigns_are_passed_through_from_the_publisher_and_cached() {
    let publisher = TcpListener::bind("127.0.0.1:0").unwrap();
    let publisher_addr = publisher.local_addr().unwrap().to_string();
    let served = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let count = std::sync::Arc::clone(&served);
    std::thread::spawn(move || {
        for stream in publisher.incoming().flatten() {
            let mut stream = stream;
            let mut buffer = [0; 2048];
            let _ = stream.read(&mut buffer);
            count.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            let body =
                r#"{"cards":[{"id":1,"title":"The Mango Run"}],"source":"arkiv","stale":false}"#;
            // Chunked, as a Node server may answer.
            let reply = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n{:x}\r\n{body}\r\n0\r\n\r\n",
                body.len()
            );
            let _ = stream.write_all(reply.as_bytes());
        }
    });
    let save = fresh_save("v3_arkiv");
    let url = format!("http://{publisher_addr}");
    let server = Server::start(&save, &["--heartbeat-ms", "0", "--publisher-url", &url]);
    let (status, cards) = json_get(&server.addr, "/arkiv/campaigns");
    assert_eq!(status, 200, "{cards}");
    assert_eq!(cards["cards"][0]["title"], "The Mango Run");
    json_get(&server.addr, "/arkiv/campaigns");
    assert_eq!(
        served.load(std::sync::atomic::Ordering::SeqCst),
        1,
        "cached for 10 seconds"
    );
    drop(server);
    let _ = std::fs::remove_file(&save);
}

#[test]
fn the_exchange_kiosk_shows_the_quote_on_the_swap_step_and_the_swap_uses_it() {
    let save = fresh_save("v3_quote");
    let server = Server::start(&save, &["--heartbeat-ms", "0"]);
    let mut sam = Client::connect(&server.addr);
    sam.hello("sam");
    sam.debug(json!({"type": "Fund", "usdc": 1_000_000}));
    sam.must(json!({"type": "TakeQuest", "quest": "campaign:1"}));
    let early = sam.command(json!({"type": "QuoteSwap", "quest": "campaign:1"}));
    assert_eq!(early["refusal"]["type"], "WrongStep");
    sam.must(json!({"type": "QuestStep", "quest": "campaign:1", "step": "cargo"}));
    let messages = drain(&mut sam);
    let quoted = messages
        .iter()
        .find(|m| m["event"]["type"] == "SwapQuoted")
        .expect("the kiosk quoted");
    assert!(
        quoted["event"]["amount_out"].is_string(),
        "big amounts are decimal strings"
    );
    let you = messages.iter().rev().find(|m| m["type"] == "you").unwrap();
    let quote = you["you"]["quests"][0]["steps"][1]["quote"].clone();
    assert_eq!(quote["symbol"], "MANGO");
    assert_eq!(quote["fee_bps"], 3000);
    assert_eq!(quote["slippage_bps"], 100);
    let out: u128 = quote["amount_out"].as_str().unwrap().parse().unwrap();
    let least: u128 = quote["min_out"].as_str().unwrap().parse().unwrap();
    assert_eq!(least, out / 10_000 * 9_900 + out % 10_000 * 9_900 / 10_000);
    let soon = sam.command(json!({"type": "QuoteSwap", "quest": "campaign:1"}));
    assert_eq!(soon["refusal"]["type"], "QuoteTooSoon");
    sam.must(json!({"type": "Swap", "quest": "campaign:1"}));
    let messages = drain(&mut sam);
    assert!(messages
        .iter()
        .any(|m| m["event"]["type"] == "QuestStepDone" && m["event"]["step"] == "swap"));
    drop(server);
    let _ = std::fs::remove_file(&save);
}
