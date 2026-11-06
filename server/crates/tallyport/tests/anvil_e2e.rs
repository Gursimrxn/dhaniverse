//! End to end on a running dev chain: the real `tallyport` binary in anvil mode, a scripted protocol-3 WebSocket
//! client, and real transactions on anvil. Off by default.
//!
//! ```bash
//! # 1. A dev chain (once; it keeps running): contracts/script/dev_chain.sh   (anvil on :8545, deployments/anvil.json)
//! # 2. Then, from server/:
//! export PATH=/d/foundry:$PATH HOME=/d/foundry/home
//! cargo test -p tallyport --features anvil-tests --test anvil_e2e -- --nocapture
//! ```
//!
//! The keys come from the environment `dev_chain.sh` prints, or, when they aren't set, from its saved output
//! (`contracts/.anvil/dev_chain.out`). Player wallets come from a fresh seed each run (`cast wallet new-mnemonic`), so
//! the test never shares a wallet with a server you're running against the same chain, or with an earlier run.

#![cfg(feature = "anvil-tests")]

use serde_json::{json, Value};
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpStream;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};
use tungstenite::stream::MaybeTlsStream;
use tungstenite::{connect, Message, WebSocket};

const RPC: &str = "http://127.0.0.1:8545";
/// anvil's first dev key: the deployer, which holds the MockUSDC the deploy script minted.
const DEPLOYER_KEY: &str = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

fn repo() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../..")
}

fn cast(args: &[&str]) -> Result<String, String> {
    let out = Command::new("cast")
        .args(args)
        .output()
        .map_err(|e| e.to_string())?;
    if out.status.success() {
        Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
    } else {
        Err(String::from_utf8_lossy(&out.stderr).trim().to_string())
    }
}

/// The server environment `dev_chain.sh` printed: from the process if set, else from its saved output.
fn chain_env() -> HashMap<String, String> {
    let mut env = HashMap::new();
    let saved =
        std::fs::read_to_string(repo().join("contracts/.anvil/dev_chain.out")).unwrap_or_default();
    for line in saved.lines() {
        if let Some((k, v)) = line.strip_prefix("export ").and_then(|l| l.split_once('=')) {
            env.insert(k.to_string(), v.trim_matches('"').to_string());
        }
    }
    for k in [
        "KEEPER_KEY",
        "TICKET_SIGNER_KEY",
        "VOUCHER_SIGNER_KEY",
        "GAS_STATION_KEY",
        "NAMES_KEY",
    ] {
        if let Ok(v) = std::env::var(k) {
            env.insert(k.to_string(), v);
        }
    }
    for k in [
        "KEEPER_KEY",
        "TICKET_SIGNER_KEY",
        "VOUCHER_SIGNER_KEY",
        "GAS_STATION_KEY",
    ] {
        assert!(
            env.contains_key(k),
            "{k} isn't set and contracts/.anvil/dev_chain.out has no export for it"
        );
    }
    env
}

struct Server {
    child: Child,
    addr: String,
}

impl Drop for Server {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

/// A new BIP-39 phrase for this run's player wallets.
fn fresh_seed() -> String {
    let out = cast(&["wallet", "new-mnemonic", "--words", "12"]).unwrap();
    let mut lines = out.lines().skip_while(|l| !l.starts_with("Phrase:"));
    lines.next();
    lines.next().unwrap().trim().to_string()
}

fn start_server(save: &Path) -> Server {
    let deployments = repo().join("contracts/deployments/anvil.json");
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_tallyport"));
    cmd.args([
        "--chain",
        "anvil",
        "--debug",
        "--addr",
        "127.0.0.1:0",
        "--heartbeat-ms",
        "1000",
    ])
    .arg("--rules")
    .arg(repo().join("server/rules.toml"))
    .arg("--quests")
    .arg(repo().join("server/quests.toml"))
    .arg("--save")
    .arg(save)
    .arg("--deployments")
    .arg(&deployments)
    .env_remove("CHAIN_DATA_DIR")
    .env_remove("CHAIN_DEPLOYMENTS")
    .env_remove("DEPLOYMENTS")
    .env("RPC_URL", RPC)
    .env("WALLET_SEED", fresh_seed())
    .env("CHAIN_POLL_MS", "300")
    .env("CHAIN_BALANCE_MS", "1000")
    .stdout(Stdio::piped());
    for (k, v) in chain_env() {
        if k.ends_with("_KEY") {
            cmd.env(k, v);
        }
    }
    let mut child = cmd.spawn().expect("tallyport starts");
    let mut reader = BufReader::new(child.stdout.take().unwrap());
    let addr = loop {
        let mut line = String::new();
        if reader.read_line(&mut line).unwrap() == 0 {
            panic!("tallyport exited before listening (see its stderr above)");
        }
        print!("server: {line}");
        if let Some(a) = line.trim().strip_prefix("listening on ") {
            break a.to_string();
        }
    };
    // Keep draining stdout so the server never blocks on a full pipe.
    std::thread::spawn(move || {
        for line in reader.lines().map_while(Result::ok) {
            println!("server: {line}");
        }
    });
    Server { child, addr }
}

struct Client {
    socket: WebSocket<MaybeTlsStream<TcpStream>>,
    inbox: Vec<Value>,
    refs: u64,
    you: Value,
    city: Value,
}

impl Client {
    fn connect(addr: &str) -> Client {
        let (socket, _) = connect(format!("ws://{addr}")).expect("the socket opens");
        if let MaybeTlsStream::Plain(s) = socket.get_ref() {
            s.set_read_timeout(Some(Duration::from_millis(500)))
                .unwrap();
        }
        Client {
            socket,
            inbox: vec![],
            refs: 0,
            you: Value::Null,
            city: Value::Null,
        }
    }

    fn send(&mut self, m: Value) {
        self.socket.send(Message::text(m.to_string())).unwrap();
    }

    /// One message, or None after the read timeout. Tracks the latest `you` and `city`.
    fn read(&mut self) -> Option<Value> {
        match self.socket.read() {
            Ok(Message::Text(t)) => {
                let m: Value = serde_json::from_str(t.as_str()).unwrap();
                match m["type"].as_str() {
                    Some("you") => self.you = m["you"].clone(),
                    Some("city") => self.city = m["city"].clone(),
                    Some("snapshot") => {
                        self.you = m["you"].clone();
                        self.city = m["city"].clone();
                    }
                    Some("event") => println!("  event: {}", m["event"]),
                    _ => {}
                }
                Some(m)
            }
            Ok(_) => None,
            Err(tungstenite::Error::Io(e))
                if matches!(
                    e.kind(),
                    std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
                ) =>
            {
                None
            }
            Err(e) => panic!("socket: {e}"),
        }
    }

    /// Reads until `want` matches a message (searching what's already in the inbox first), up to `secs`.
    fn wait(&mut self, what: &str, secs: u64, want: impl Fn(&Value) -> bool) -> Value {
        if let Some(i) = self.inbox.iter().position(&want) {
            return self.inbox.remove(i);
        }
        let start = Instant::now();
        while start.elapsed() < Duration::from_secs(secs) {
            if let Some(m) = self.read() {
                if want(&m) {
                    return m;
                }
                self.inbox.push(m);
            }
        }
        panic!(
            "timed out waiting for {what}\nyou: {}\nlast messages: {:#?}",
            self.you,
            self.inbox.iter().rev().take(15).collect::<Vec<_>>()
        );
    }

    /// Waits until the latest `you` satisfies `want`.
    fn wait_you(&mut self, what: &str, secs: u64, want: impl Fn(&Value) -> bool) -> Value {
        let start = Instant::now();
        while start.elapsed() < Duration::from_secs(secs) {
            if want(&self.you) {
                return self.you.clone();
            }
            if let Some(m) = self.read() {
                self.inbox.push(m);
            }
        }
        panic!("timed out waiting for you: {what}\nyou: {}", self.you);
    }

    fn wait_city(&mut self, what: &str, secs: u64, want: impl Fn(&Value) -> bool) -> Value {
        let start = Instant::now();
        while start.elapsed() < Duration::from_secs(secs) {
            if want(&self.city) {
                return self.city.clone();
            }
            if let Some(m) = self.read() {
                self.inbox.push(m);
            }
        }
        panic!("timed out waiting for city: {what}\ncity: {}", self.city);
    }

    fn event(&mut self, name: &str, secs: u64) -> Value {
        let n = name.to_string();
        self.wait(name, secs, move |m| {
            m["type"] == "event" && m["event"]["type"] == n.as_str()
        })["event"]
            .clone()
    }

    fn command(&mut self, command: Value) -> Value {
        self.refs += 1;
        let r = format!("c{}", self.refs);
        self.send(json!({"type": "command", "ref": r, "command": command}));
        let rr = r.clone();
        self.wait("result", 30, move |m| {
            m["type"] == "result" && m["ref"] == rr.as_str()
        })
    }

    fn must(&mut self, command: Value) -> Value {
        let what = command.clone();
        let result = self.command(command);
        assert_eq!(result["ok"], true, "{what}: {result}");
        println!("ok: {what}");
        result
    }

    fn debug(&mut self, action: Value) {
        self.send(json!({"type": "debug", "action": action}));
        self.wait("debug_done", 30, |m| m["type"] == "debug_done");
    }
}

/// A plain HTTP/1.1 POST of JSON, returning (status, body).
fn http_post(addr: &str, path: &str, body: &Value) -> (u16, Value) {
    let body = body.to_string();
    let mut s = TcpStream::connect(addr).unwrap();
    write!(
        s,
        "POST {path} HTTP/1.1\r\nHost: {addr}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    )
    .unwrap();
    let mut raw = String::new();
    s.read_to_string(&mut raw).unwrap();
    let status = raw
        .split_whitespace()
        .nth(1)
        .and_then(|c| c.parse().ok())
        .unwrap_or(0);
    let json = raw
        .split("\r\n\r\n")
        .nth(1)
        .and_then(|b| serde_json::from_str(b).ok())
        .unwrap_or(Value::Null);
    (status, json)
}

/// The swap step of a quest in `you.quests`.
fn swap_step<'a>(you: &'a Value, quest: &str) -> Option<&'a Value> {
    you["quests"]
        .as_array()?
        .iter()
        .find(|q| q["quest"] == quest)?["steps"]
        .as_array()?
        .iter()
        .find(|s| s["kind"] == "swap")
}

fn tx_of(event: &Value) -> String {
    event["tx"].as_str().unwrap_or("").to_string()
}

#[test]
fn a_player_on_anvil_from_hello_to_payouts() {
    if cast(&["chain-id", "--rpc-url", RPC]).as_deref() != Ok("31337") {
        eprintln!("skip: no dev chain on {RPC} (run contracts/script/dev_chain.sh)");
        return;
    }
    let deployments: Value = serde_json::from_str(
        &std::fs::read_to_string(repo().join("contracts/deployments/anvil.json")).unwrap(),
    )
    .unwrap();
    let usdc = deployments["usdc"].as_str().unwrap().to_string();
    let dir = std::env::temp_dir().join(format!("tallyport-e2e-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let save = dir.join("town.jsonl");
    let start_block: u64 = cast(&["block-number", "--rpc-url", RPC])
        .unwrap()
        .parse()
        .unwrap();
    let server = start_server(&save);
    let mut txs: Vec<(String, String)> = vec![];

    // ---- hello → a wallet from the chain
    let name = format!("e2e{}", std::process::id() % 100_000);
    let mut c = Client::connect(&server.addr);
    c.send(json!({"type": "hello", "protocol": 3, "player": name, "secret": format!("secret-of-{name}-0123456789")}));
    c.wait("snapshot", 30, |m| m["type"] == "snapshot");
    assert_eq!(c.city["chain"], "anvil");
    let you = c.wait_you("wallet", 30, |y| y["wallet"].is_string());
    let wallet = you["wallet"].as_str().unwrap().to_string();
    println!("wallet: {wallet}");

    // ---- Fund: a real USDC transfer from an anvil key (not the offline faucet)
    let out = cast(&[
        "send",
        "--rpc-url",
        RPC,
        "--private-key",
        DEPLOYER_KEY,
        "--json",
        &usdc,
        "transfer(address,uint256)",
        &wallet,
        "300000",
    ])
    .unwrap();
    let fund_tx = serde_json::from_str::<Value>(&out).unwrap()["transactionHash"]
        .as_str()
        .unwrap()
        .to_string();
    txs.push(("fund 0.30 USDC".into(), fund_tx));
    c.wait_you("usdc 0.30", 30, |y| y["usdc"] == 300_000);

    // ---- Town Pass through the rehearsal verifier (World ID isn't configured on this dev chain)
    let pass = c.must(json!({"type": "TownPass"}));
    let url = pass["url"].as_str().unwrap().to_string();
    let token = url.split("token=").nth(1).unwrap().to_string();
    let (status, body) = http_post(
        &server.addr,
        "/verify",
        &json!({"token": token, "result": {"offline": true}}),
    );
    assert_eq!(status, 200, "{body}");
    assert_eq!(body["rehearsal"], true);
    c.event("HumanVerified", 30);
    c.wait_you("human", 30, |y| y["human"] == true);

    // ---- a paid meal: MealCounter on anvil, energy up, and the live food price ticks
    c.must(json!({"type": "TakeQuest", "quest": "errand:chai_round"}));
    // Only what this meal causes from here on (the indexer replays the chain's history first).
    while c.read().is_some() {}
    c.inbox.clear();
    let price_before = c.city["price"].as_u64().unwrap();
    let energy_before = c.you["energy"].as_u64().unwrap();
    c.must(json!({"type": "BuyMeal", "item": "thali"}));
    let meal = c.event("MealEaten", 60);
    assert!(tx_of(&meal).starts_with("0x"), "{meal}");
    assert_eq!(meal["food"], 6_000_000);
    txs.push((
        format!(
            "BuyMeal thali {} USDC base units (MealCounter.buyMeal)",
            meal["usdc"]
        ),
        tx_of(&meal),
    ));
    c.wait_you("energy up", 30, |y| {
        y["energy"].as_u64().unwrap() > energy_before
    });
    // The meal's own trade through the FoodHook pool comes back as TradeCounted, and the price moved with it.
    let trade = c.wait("the meal's TradeCounted", 30, |m| {
        m["type"] == "event"
            && m["event"]["type"] == "TradeCounted"
            && m["event"]["food"] == 6_000_000
    })["event"]
        .clone();
    let price_after = trade["price_after"].as_u64().unwrap();
    assert_ne!(
        price_after, price_before,
        "a thali moves the live food price: {trade}"
    );
    let city = c.wait_city("city.food.price after the meal", 30, |city| {
        city["food"]["price"]
            .as_u64()
            .is_some_and(|p| p != price_before)
    });
    println!(
        "price before the thali {price_before}, after {price_after} (city.food.price {})",
        city["food"]["price"]
    );

    // ---- an errand paid from the house (FIXED): a real HousePool.pay
    c.must(json!({"type": "QuestStep", "quest": "errand:chai_round", "step": "collect"}));
    c.must(json!({"type": "QuestStep", "quest": "errand:chai_round", "step": "serve"}));
    let paid = c.event("RewardPaid", 60);
    txs.push((
        format!("errand reward {} (HousePool.pay)", paid["amount"]),
        tx_of(&paid),
    ));

    // ---- the demo Spice Run: cargo advanced (the wallet is short), a real Uniswap swap, delivery, claim
    let campaign = deployments["demoCampaignId"].as_u64().unwrap();
    c.wait_city("the demo campaign on the board", 60, |city| {
        city["bounty"]
            .as_array()
            .is_some_and(|b| b.iter().any(|x| x["id"] == campaign))
    });
    let quest = format!("campaign:{campaign}");
    c.must(json!({"type": "TakeQuest", "quest": quest}));
    c.must(json!({"type": "QuestStep", "quest": quest, "step": "cargo"}));
    let step = c.wait("cargo step done", 90, |m| {
        m["type"] == "event"
            && (m["event"]["type"] == "QuestStepDone" || m["event"]["type"] == "QuestStepFailed")
            && m["event"]["step"] == "cargo"
    });
    assert_eq!(step["event"]["type"], "QuestStepDone", "{step}");
    // Reaching the swap step asks the kiosk for a quote by itself: V4Quoter on the quest pool, answered by SwapQuoted.
    let q = quest.clone();
    let you = c.wait_you("a quote on the swap step", 60, move |y| {
        swap_step(y, &q).is_some_and(|s| s["quote"].is_object())
    });
    let quote = swap_step(&you, &quest).unwrap()["quote"].clone();
    let amount_out: u128 = quote["amount_out"].as_str().unwrap().parse().unwrap();
    let min_out: u128 = quote["min_out"].as_str().unwrap().parse().unwrap();
    assert!(amount_out > 0, "{quote}");
    assert_eq!(min_out, amount_out * 9_900 / 10_000, "a 1% floor: {quote}");
    assert_eq!(quote["fee_bps"], 3_000);
    println!(
        "quote: {} USDC base units buy {amount_out} {} ({} decimals), floor {min_out}, pool fee {} pips",
        quote["usdc_in"], quote["symbol"], quote["decimals"], quote["fee_bps"]
    );
    let mango = deployments["contracts"]["QuestToken"]
        .as_str()
        .unwrap()
        .to_string();
    let held = |who: &str| -> u128 {
        let out = cast(&[
            "call",
            "--rpc-url",
            RPC,
            &mango,
            "balanceOf(address)(uint256)",
            who,
        ])
        .unwrap();
        out.split_whitespace().next().unwrap().parse().unwrap()
    };
    let before = held(&wallet);
    c.must(json!({"type": "Swap", "quest": quest}));
    let step = c.wait("swap step done", 90, |m| {
        m["type"] == "event"
            && (m["event"]["type"] == "QuestStepDone" || m["event"]["type"] == "QuestStepFailed")
            && m["event"]["step"] == "swap"
    });
    assert_eq!(step["event"]["type"], "QuestStepDone", "{step}");
    let received = held(&wallet) - before;
    assert!(received >= min_out, "received {received} < floor {min_out}");
    println!("swap received {received} MANGO base units (quote {amount_out}, floor {min_out})");
    c.must(json!({"type": "Deliver", "quest": quest}));
    let step = c.wait("deliver step done", 90, |m| {
        m["type"] == "event"
            && (m["event"]["type"] == "QuestStepDone" || m["event"]["type"] == "QuestStepFailed")
            && m["event"]["step"] == "deliver"
    });
    assert_eq!(step["event"]["type"], "QuestStepDone", "{step}");
    c.event("QuestDone", 30);
    let paid = c.event("RewardPaid", 90);
    assert_eq!(paid["amount"], 1_000_000, "the card's payout: {paid}");
    txs.push((
        format!("campaign claim {} (CampaignEscrow.claim)", paid["amount"]),
        tx_of(&paid),
    ));

    // ---- the daily chest (golden drops and meal vouchers come from SURPRISE)
    c.debug(json!({"type": "ReadyChest"}));
    let chest = c.must(json!({"type": "OpenChest"}));
    let opened = c.event("ChestOpened", 30);
    println!("chest: {chest} {opened}");

    // ---- the city day closes: the keeper splits food revenue, rebalances the float, harvests yield.
    // The Treasury's revenue is Kofi's real harvest sales (Farm.sell, proceeds to the Treasury) since this town started.
    let treasury = deployments["contracts"]["Treasury"]
        .as_str()
        .unwrap()
        .to_string();
    let day = c.city["day"].as_u64().unwrap();
    let split_at_before = c.city["treasury"]["last_split_at"].clone();
    c.debug(json!({"type": "Skip", "ms": 3_600_000}));
    c.wait_city("next day", 30, |city| {
        city["day"].as_u64().unwrap_or(0) > day
    });
    // The keeper's three transactions landed after this run started (repeatable intents aren't in the intents table,
    // so read the contracts' own events).
    let float = deployments["contracts"]["FloatManager"]
        .as_str()
        .unwrap()
        .to_string();
    let logs_since = |address: &str, event: &str| -> Vec<String> {
        let out = cast(&[
            "logs",
            "--rpc-url",
            RPC,
            "--from-block",
            &start_block.to_string(),
            "--address",
            address,
            event,
        ])
        .unwrap_or_default();
        out.lines()
            .filter_map(|l| {
                l.trim()
                    .strip_prefix("transactionHash:")
                    .map(|h| h.trim().to_string())
            })
            .collect()
    };
    let mut start = Instant::now();
    let mut second_close = false;
    let (mut split, mut rebalanced, mut harvested) = (vec![], vec![], vec![]);
    while start.elapsed() < Duration::from_secs(60)
        && (split.is_empty() || rebalanced.is_empty() || harvested.is_empty())
    {
        // On a fresh chain nothing is invested before the first rebalance, so the first close has no yield to harvest
        // (harvestYield is refused). One more city day lets the mock vault's drip accrue, and that close harvests it.
        if !second_close
            && !split.is_empty()
            && !rebalanced.is_empty()
            && start.elapsed() > Duration::from_secs(10)
        {
            second_close = true;
            println!("no yield at the first close; closing one more city day");
            c.debug(json!({"type": "Skip", "ms": 3_600_000}));
            start = Instant::now();
        }
        if c.read().is_none() {
            split = logs_since(&treasury, "Split(uint256,uint256,uint256,uint256,uint256)");
            rebalanced = logs_since(&float, "Rebalanced(uint256,uint256,uint256,uint256)");
            harvested = logs_since(&float, "YieldHarvested(uint256,uint256,uint256)");
        }
    }
    assert!(!split.is_empty(), "no Treasury.Split this run");
    assert!(
        !rebalanced.is_empty(),
        "no FloatManager.Rebalanced this run"
    );
    assert!(
        !harvested.is_empty(),
        "no FloatManager.YieldHarvested this run"
    );
    txs.push(("keeper Treasury.split".into(), split[0].clone()));
    txs.push((
        "keeper FloatManager.rebalance".into(),
        rebalanced[0].clone(),
    ));
    txs.push((
        "keeper FloatManager.harvestYield".into(),
        harvested[0].clone(),
    ));
    // ...and the city took this run's Split from the indexer.
    c.wait_city("the city saw this run's Split", 60, |city| {
        city["treasury"]["last_split_at"] != split_at_before
    });
    c.wait_city("the float rebalanced", 60, |city| {
        city["float"]["invested"].as_u64().unwrap_or(0) > 0
    });
    println!(
        "treasury: {}\nhouse: {}\nfloat: {}",
        c.city["treasury"], c.city["house"], c.city["float"]
    );

    // The chain crate's sent-intents table has every transaction it sent, by ref.
    let intents =
        std::fs::read_to_string(dir.join("town.chain-anvil/intents.jsonl")).unwrap_or_default();
    for line in intents.lines() {
        let row: Value = serde_json::from_str(line).unwrap_or(Value::Null);
        if row["state"] == "done" {
            let key = row["key"].as_str().unwrap_or("").to_string();
            txs.push((
                format!("intent {key}"),
                row["tx"].as_str().unwrap_or("").to_string(),
            ));
        }
    }

    println!("\n==== transactions ====");
    for (what, tx) in &txs {
        println!("{what}: {tx}");
    }
    let rpc_txs: Vec<_> = txs.iter().filter(|(_, t)| t.starts_with("0x")).collect();
    for (what, tx) in rpc_txs {
        let status = cast(&["receipt", "--rpc-url", RPC, tx, "status"]).unwrap_or_default();
        assert!(
            status == "true" || status.contains('1'),
            "{what}: {tx} status {status}"
        );
    }
    drop(server);
    let _ = std::fs::remove_dir_all(&dir);
}
