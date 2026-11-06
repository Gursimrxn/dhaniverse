//! End-to-end tests against a local anvil. Off by default; they need Foundry (`anvil`, `cast`, and for the full flow
//! `forge`) on PATH and compiled contracts in `contracts/out` (`forge build` in `contracts/`).
//!
//! ```bash
//! export PATH=/d/foundry:$PATH HOME=/d/foundry/home      # this machine; anywhere else: Foundry on PATH
//! cd server
//! cargo test -p chain --features anvil-tests --test anvil -- --nocapture --test-threads=1
//! ```
//!
//! - `executor_wallets_balances_and_failures` needs only the compiled `MockUSDC`: it deploys it, then checks wallets,
//!   balance observations, intent failures, retries, the per-key queue (nonces under load, decoded reverts) and
//!   restart persistence.
//! - `full_flow_through_deploy_script` runs `contracts/script/Deploy.s.sol` against the anvil and drives intents →
//!   observations through the real contracts. It says so and returns early if the deploy script isn't there yet.
//!
//! Each test starts its own anvil on a free port and kills it at the end. Keys are anvil's public dev keys.

#![cfg(feature = "anvil-tests")]

use alloy::primitives::{Address, Bytes, U256};
use alloy::sol_types::SolCall;
use chain::bindings::IERC20;
use chain::config::{ChainConfig, Network};
use chain::revert::ErrorBook;
use chain::sender::{SendConfig, SenderHandle, TxError};
use chain::{ChainLedger, Intent, Observation, Observed};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::Arc;
use std::time::{Duration, Instant};

const KEYS: [&str; 6] = [
    "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", // deployer / gas station
    "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d", // ticket signer
    "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a", // voucher signer
    "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6", // keeper
    "0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a", // names
    "0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba", // ops/team
];
/// The player wallets' seed: a public test phrase, deliberately not anvil's, so players don't share the dev keys.
const PLAYER_SEED: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

fn contracts_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../contracts")
}

struct Anvil {
    child: Child,
    url: String,
}

impl Drop for Anvil {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn free_port() -> u16 {
    std::net::TcpListener::bind("127.0.0.1:0")
        .unwrap()
        .local_addr()
        .unwrap()
        .port()
}

fn start_anvil() -> Anvil {
    let port = free_port();
    let child = Command::new("anvil")
        .args([
            "--port",
            &port.to_string(),
            "--silent",
            "--chain-id",
            "31337",
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("anvil not found: put Foundry on PATH (see this file's header)");
    // Owned by `Anvil` at once, so it's killed and reaped on every path (including the panic below).
    let anvil = Anvil {
        child,
        url: format!("http://127.0.0.1:{port}"),
    };
    let start = Instant::now();
    while start.elapsed() < Duration::from_secs(20) {
        if cast(&["block-number", "--rpc-url", &anvil.url]).is_ok() {
            return anvil;
        }
        std::thread::sleep(Duration::from_millis(200));
    }
    panic!("anvil didn't start");
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

/// Deploys a compiled contract's creation bytecode (no constructor arguments) and returns its address.
fn deploy_artifact(url: &str, file: &str, contract: &str) -> Address {
    let p = contracts_dir()
        .join("out")
        .join(format!("{file}.sol"))
        .join(format!("{contract}.json"));
    let raw = std::fs::read_to_string(&p)
        .unwrap_or_else(|_| panic!("{} missing: run forge build", p.display()));
    let v: serde_json::Value = serde_json::from_str(&raw).unwrap();
    let code = v["bytecode"]["object"].as_str().unwrap().to_string();
    let out = cast(&[
        "send",
        "--rpc-url",
        url,
        "--private-key",
        KEYS[0],
        "--json",
        "--create",
        &code,
    ])
    .unwrap();
    let r: serde_json::Value = serde_json::from_str(&out).unwrap();
    r["contractAddress"].as_str().unwrap().parse().unwrap()
}

fn config(url: &str, deployments: &Path, data: &Path) -> ChainConfig {
    let mut env: HashMap<&str, String> = HashMap::new();
    env.insert("CHAIN_RPC_URL", url.into());
    env.insert("CHAIN_DEPLOYMENTS", deployments.display().to_string());
    env.insert("CHAIN_DATA_DIR", data.display().to_string());
    env.insert(
        "CHAIN_ABI_DIR",
        contracts_dir().join("out").display().to_string(),
    );
    env.insert("CHAIN_POLL_MS", "200".into());
    env.insert("CHAIN_BALANCE_MS", "300".into());
    env.insert("GAS_STATION_KEY", KEYS[0].into());
    env.insert("TICKET_SIGNER_KEY", KEYS[1].into());
    env.insert("VOUCHER_SIGNER_KEY", KEYS[2].into());
    env.insert("KEEPER_KEY", KEYS[3].into());
    env.insert("NAMES_KEY", KEYS[4].into());
    env.insert("WALLET_SEED", PLAYER_SEED.into());
    let get = move |k: &str| env.get(k).cloned();
    ChainConfig::from_env(Network::Anvil, &get).unwrap()
}

thread_local! {
    /// Observations that arrived while waiting for something else, in order.
    static BACKLOG: std::cell::RefCell<Vec<Observed>> = const { std::cell::RefCell::new(Vec::new()) };
}

/// Returns the first observation (earlier unclaimed ones first) matching `want`, polling up to `secs`.
fn wait_for(
    ledger: &mut ChainLedger,
    what: &str,
    secs: u64,
    want: impl Fn(&Observation) -> bool,
) -> Observed {
    let start = Instant::now();
    loop {
        let fresh = ledger.poll();
        let found = BACKLOG.with(|b| {
            let mut b = b.borrow_mut();
            b.extend(fresh);
            b.iter()
                .position(|o| want(&o.observed))
                .map(|i| b.remove(i))
        });
        if let Some(o) = found {
            return o;
        }
        if start.elapsed() > Duration::from_secs(secs) {
            let seen = BACKLOG.with(|b| format!("{:#?}", b.borrow()));
            panic!(
                "timed out waiting for {what}; unclaimed: {seen}; status {:?}",
                ledger.status()
            );
        }
        std::thread::sleep(Duration::from_millis(100));
    }
}

#[test]
fn executor_wallets_balances_and_failures() {
    BACKLOG.with(|b| b.borrow_mut().clear());
    let anvil = start_anvil();
    let usdc = deploy_artifact(&anvil.url, "MockUSDC", "MockUSDC");
    let dir = tempfile::tempdir().unwrap();
    let dep = dir.path().join("anvil.json");
    std::fs::write(
        &dep,
        serde_json::json!({"chainId": 31337, "contracts": {}, "uniswap": {}, "usdc": usdc.to_string(), "ens": {}, "startBlock": 0})
            .to_string(),
    )
    .unwrap();
    let data = dir.path().join("data");

    // Wallets: assigned once, reported, persisted.
    let mut ledger = ChainLedger::start(config(&anvil.url, &dep, &data)).unwrap();
    ledger.submit(Intent::EnsureWallet {
        player: "asha".into(),
    });
    let o = wait_for(&mut ledger, "WalletReady", 10, |o| {
        matches!(o, Observation::WalletReady { .. })
    });
    let Observation::WalletReady { player, address } = o.observed else {
        unreachable!()
    };
    assert_eq!(player, "asha");
    // m/44'/60'/0'/0/0 of the "abandon … about" phrase.
    assert_eq!(
        address.to_lowercase(),
        "0x9858effd232b4033e47d90003d41ec34ecaeda94"
    );
    assert_eq!(
        ledger.wallet_address("asha").as_deref(),
        Some(address.as_str())
    );

    // Balances: minting USDC to the wallet shows up as an observation, once.
    cast(&[
        "send",
        "--rpc-url",
        &anvil.url,
        "--private-key",
        KEYS[0],
        &usdc.to_string(),
        "mint(address,uint256)",
        &address,
        "5000000",
    ])
    .unwrap();
    let o = wait_for(&mut ledger, "Balances", 10, |o| {
        matches!(
            o,
            Observation::Balances {
                usdc: 5_000_000,
                ..
            }
        )
    });
    assert_eq!(o.log_index, chain::NOT_A_LOG);

    // A failing intent becomes IntentFailed with its ref, and the same ref may be retried.
    let meal = Intent::BuyMeal {
        player: "asha".into(),
        item: "chai".into(),
        food: 1_000_000,
        max_usdc: 5_000,
        reference: "meal:asha:1".into(),
    };
    ledger.submit(meal.clone());
    let o = wait_for(&mut ledger, "IntentFailed", 10, |o| {
        matches!(o, Observation::IntentFailed { .. })
    });
    let Observation::IntentFailed { reference, reason } = o.observed else {
        unreachable!()
    };
    assert_eq!(reference, "meal:asha:1");
    assert!(reason.contains("MealCounter"), "{reason}");
    ledger.submit(meal);
    wait_for(&mut ledger, "IntentFailed again", 10, |o| {
        matches!(o, Observation::IntentFailed { .. })
    });

    // Restart: the same player keeps the same wallet. This time "MealCounter" points at the USDC contract, so a
    // BuyMeal runs its player-sent steps for real: a gas top-up from the gas station (the wallet has no ETH), the
    // one-time approve, then buyMeal, which the USDC contract can't do: refused at estimation, reported with its ref.
    ledger.shutdown();
    std::fs::write(
        &dep,
        serde_json::json!({"chainId": 31337, "contracts": {"MealCounter": usdc.to_string()}, "usdc": usdc.to_string(), "startBlock": 0})
            .to_string(),
    )
    .unwrap();
    let mut ledger = ChainLedger::start(config(&anvil.url, &dep, &data)).unwrap();
    assert_eq!(
        cast(&["balance", "--rpc-url", &anvil.url, &address]).unwrap(),
        "0"
    );
    ledger.submit(Intent::BuyMeal {
        player: "asha".into(),
        item: "chai".into(),
        food: 1_000_000,
        max_usdc: 5_000,
        reference: "meal:asha:2".into(),
    });
    let o = wait_for(
        &mut ledger,
        "IntentFailed for buyMeal",
        20,
        |o| matches!(o, Observation::IntentFailed { reference, .. } if reference == "meal:asha:2"),
    );
    let Observation::IntentFailed { reason, .. } = o.observed else {
        unreachable!()
    };
    assert!(reason.starts_with("buyMeal:"), "{reason}");
    let eth: u128 = cast(&["balance", "--rpc-url", &anvil.url, &address])
        .unwrap()
        .parse()
        .unwrap();
    assert!(eth > 0, "the gas station topped the wallet up");
    let allowance = cast(&[
        "call",
        "--rpc-url",
        &anvil.url,
        &usdc.to_string(),
        "allowance(address,address)(uint256)",
        &address,
        &usdc.to_string(),
    ])
    .unwrap();
    assert!(
        allowance.starts_with(
            "1157920892373161954235709850086879078532699846656405640394575840079131296399"
        ),
        "{allowance}"
    );
    ledger.submit(Intent::EnsureWallet {
        player: "asha".into(),
    });
    let o = wait_for(&mut ledger, "WalletReady after restart", 10, |o| {
        matches!(o, Observation::WalletReady { .. })
    });
    assert!(matches!(o.observed, Observation::WalletReady { address: ref a, .. } if *a == address));
    ledger.shutdown();

    // The per-key queue: many transactions at once get consecutive nonces and all land; a would-revert transfer is
    // refused before sending, with OpenZeppelin's custom error named from contracts/out.
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    rt.block_on(async {
        let provider = chain::rpc::connect(&anvil.url).unwrap();
        let keeper: alloy::signers::local::PrivateKeySigner = KEYS[3].parse().unwrap();
        cast(&[
            "send",
            "--rpc-url",
            &anvil.url,
            "--private-key",
            KEYS[0],
            &usdc.to_string(),
            "mint(address,uint256)",
            &keeper.address().to_string(),
            "100",
        ])
        .unwrap();
        let cfg = Arc::new(SendConfig {
            chain_id: 31337,
            poll: Duration::from_millis(100),
            receipt_timeout: Duration::from_secs(10),
            max_resends: 2,
            max_in_flight: 4,
            fee_bump_percent: 25,
        });
        let errors = Arc::new(ErrorBook::from_forge_out(&contracts_dir().join("out")));
        let sender = SenderHandle::spawn(provider, keeper, cfg, errors);
        let to = Address::repeat_byte(0x42);
        let data = Bytes::from(
            IERC20::transferCall {
                to,
                amount: U256::from(10u64),
            }
            .abi_encode(),
        );
        let sends = (0..6).map(|_| sender.send(usdc, data.clone(), U256::ZERO, |_| {}));
        let results = futures_join(sends.collect()).await;
        let mut hashes: Vec<_> = results
            .into_iter()
            .map(|r| r.expect("transfer").hash)
            .collect();
        hashes.sort();
        hashes.dedup();
        assert_eq!(hashes.len(), 6);
        let too_much = Bytes::from(
            IERC20::transferCall {
                to,
                amount: U256::from(1_000u64),
            }
            .abi_encode(),
        );
        match sender.send(usdc, too_much, U256::ZERO, |_| {}).await {
            Err(TxError::WouldRevert(reason)) => {
                assert!(reason.contains("ERC20InsufficientBalance"), "{reason}")
            }
            other => panic!("expected a refusal, got {other:?}"),
        }
    });
    let bal = cast(&[
        "call",
        "--rpc-url",
        &anvil.url,
        &usdc.to_string(),
        "balanceOf(address)(uint256)",
        "0x4242424242424242424242424242424242424242",
    ])
    .unwrap();
    assert_eq!(bal.split_whitespace().next(), Some("60"));
}

/// Joins futures without pulling in the `futures` crate.
async fn futures_join<F: std::future::Future>(fs: Vec<F>) -> Vec<F::Output>
where
    F::Output: Send,
{
    let mut out = Vec::with_capacity(fs.len());
    let mut pinned: Vec<_> = fs.into_iter().map(Box::pin).collect();
    let mut done: Vec<Option<F::Output>> = pinned.iter().map(|_| None).collect();
    std::future::poll_fn(|cx| {
        let mut all = true;
        for (i, f) in pinned.iter_mut().enumerate() {
            if done[i].is_none() {
                match f.as_mut().poll(cx) {
                    std::task::Poll::Ready(v) => done[i] = Some(v),
                    std::task::Poll::Pending => all = false,
                }
            }
        }
        if all {
            std::task::Poll::Ready(())
        } else {
            std::task::Poll::Pending
        }
    })
    .await;
    for d in done {
        out.push(d.expect("all done"));
    }
    out
}

/// Removes files when dropped.
struct Cleanup(Vec<PathBuf>);

impl Drop for Cleanup {
    fn drop(&mut self) {
        for p in &self.0 {
            let _ = std::fs::remove_file(p);
        }
    }
}

/// One raw JSON-RPC call (for anvil's own methods).
fn rpc(url: &str, method: &'static str, params: serde_json::Value) -> serde_json::Value {
    use alloy::providers::Provider;
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    rt.block_on(async {
        let p = chain::rpc::connect(url).unwrap();
        p.raw_request::<_, serde_json::Value>(method.into(), params)
            .await
            .unwrap_or_else(|e| panic!("{method}: {e}"))
    })
}

/// What `contracts/script/dev_chain.sh` does on a fresh chain: Uniswap v4's Sepolia bytecode at its Sepolia
/// addresses, and PositionManager's constructor-set storage.
fn place_uniswap(url: &str) {
    let dir = contracts_dir().join("script/anvil/uniswap");
    for (addr, name) in [
        ("0xE03A1074c86CFeDd5C142C4F04F1a1536e203543", "PoolManager"),
        (
            "0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4",
            "PositionManager",
        ),
        (
            "0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b",
            "UniversalRouter",
        ),
        ("0x000000000022D473030F116dDEE9F6B43aC78BA3", "Permit2"),
        ("0xe1dd9c3fa50edb962e442f60dfbc432e24537e4c", "StateView"),
        ("0x68aFa8b853cAa7a2D40B0F6AEE5C4DbC147C8244", "V4Quoter"),
    ] {
        let code: String = std::fs::read_to_string(dir.join(format!("{name}.hex")))
            .unwrap_or_else(|_| panic!("script/anvil/uniswap/{name}.hex missing"))
            .split_whitespace()
            .collect();
        // Too long for a command line on Windows, so straight over JSON-RPC.
        rpc(url, "anvil_setCode", serde_json::json!([addr, code]));
    }
    let posm = "0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4";
    for (slot, value) in [
        (
            "0x0",
            "0x556e697377617020763420506f736974696f6e73204e46540000000000000030",
        ),
        (
            "0x1",
            "0x554e492d56342d504f534d000000000000000000000000000000000000000016",
        ),
        (
            "0x8",
            "0x0000000000000000000000000000000000000000000000000000000000000001",
        ),
    ] {
        cast(&[
            "rpc",
            "anvil_setStorageAt",
            posm,
            slot,
            value,
            "--rpc-url",
            url,
        ])
        .unwrap();
    }
}

#[test]
fn full_flow_through_deploy_script() {
    BACKLOG.with(|b| b.borrow_mut().clear());
    let script = contracts_dir().join("script/Deploy.s.sol");
    if !script.exists() {
        eprintln!("skip: {} doesn't exist yet", script.display());
        return;
    }
    let anvil = start_anvil();
    let dir = tempfile::tempdir().unwrap();
    // Deploy under a network name of its own, so a dev chain's deployments/anvil.json is never touched: the deploy
    // script reads deployments/<NETWORK>.config.json (a copy of anvil's) and writes deployments/<NETWORK>.json.
    let network = format!("chain-test-{}", std::process::id());
    let deployments_dir = contracts_dir().join("deployments");
    let config_copy = deployments_dir.join(format!("{network}.config.json"));
    let dep = deployments_dir.join(format!("{network}.json"));
    let _cleanup = Cleanup(vec![config_copy.clone(), dep.clone()]);
    std::fs::copy(deployments_dir.join("anvil.config.json"), &config_copy).unwrap();
    place_uniswap(&anvil.url);
    let keeper = cast(&["wallet", "address", "--private-key", KEYS[3]]).unwrap();
    let ticket = cast(&["wallet", "address", "--private-key", KEYS[1]]).unwrap();
    let voucher = cast(&["wallet", "address", "--private-key", KEYS[2]]).unwrap();
    let other = cast(&["wallet", "address", "--private-key", KEYS[5]]).unwrap();
    let out = Command::new("forge")
        .current_dir(contracts_dir())
        .args([
            "script",
            "script/Deploy.s.sol",
            "--rpc-url",
            &anvil.url,
            "--broadcast",
            "--slow",
            "-q",
        ])
        .env("DEPLOYER_KEY", KEYS[0])
        .env("KEEPER_ADDRESS", &keeper)
        .env("TICKET_SIGNER_ADDRESS", &ticket)
        .env("VOUCHER_SIGNER_ADDRESS", &voucher)
        .env("OPS_ADDRESS", &other)
        .env("TEAM_ADDRESS", &other)
        .env("NETWORK", &network)
        .output()
        .expect("forge not found");
    assert!(
        out.status.success(),
        "deploy failed:
{}
{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    // Blocks keep coming after the deploy (as on dev_chain.sh), so LuckyLedger's reveal delay can pass.
    cast(&["rpc", "evm_setIntervalMining", "1", "--rpc-url", &anvil.url]).unwrap();
    let mut ledger =
        ChainLedger::start(config(&anvil.url, &dep, &dir.path().join("data"))).unwrap();
    let deployments: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(&dep).unwrap()).unwrap();
    let usdc = deployments["usdc"].as_str().unwrap().to_string();

    // A player gets a wallet and some USDC (MockUSDC mints to anyone).
    ledger.submit(Intent::EnsureWallet {
        player: "asha".into(),
    });
    let Observation::WalletReady { address, .. } = wait_for(&mut ledger, "WalletReady", 10, |o| {
        matches!(o, Observation::WalletReady { .. })
    })
    .observed
    else {
        unreachable!()
    };
    cast(&[
        "send",
        "--rpc-url",
        &anvil.url,
        "--private-key",
        KEYS[0],
        &usdc,
        "mint(address,uint256)",
        &address,
        "20000000",
    ])
    .unwrap();
    wait_for(&mut ledger, "Balances", 10, |o| {
        matches!(
            o,
            Observation::Balances {
                usdc: 20_000_000,
                ..
            }
        )
    });

    // Buying a meal: gas top-up, approve once, MealCounter.buyMeal with a server-signed ticket → MealEaten.
    ledger.submit(Intent::BuyMeal {
        player: "asha".into(),
        item: "chai".into(),
        food: 1_000_000,
        max_usdc: 9_000,
        reference: "meal:asha:1".into(),
    });
    let o = wait_for(&mut ledger, "MealEaten", 30, |o| {
        matches!(
            o,
            Observation::MealEaten { .. } | Observation::IntentFailed { .. }
        )
    });
    match &o.observed {
        Observation::MealEaten {
            player,
            item,
            reference,
            food,
            ..
        } => {
            assert_eq!(
                (player.as_str(), item.as_str(), reference.as_str(), *food),
                ("asha", "chai", "meal:asha:1", 1_000_000)
            );
            assert_ne!(o.log_index, chain::NOT_A_LOG);
            assert!(o.time > 0);
        }
        other => panic!("BuyMeal failed: {other:?}"),
    }
    // The same ref again does nothing (already done).
    ledger.submit(Intent::BuyMeal {
        player: "asha".into(),
        item: "chai".into(),
        food: 1_000_000,
        max_usdc: 9_000,
        reference: "meal:asha:1".into(),
    });

    // The farm's keeper sells harvest (proceeds go to the Treasury), then the Treasury splits them.
    ledger.submit(Intent::SellHarvest {
        food: 50_000_000,
        reference: "harvest:1".into(),
    });
    let o = wait_for(&mut ledger, "HarvestSold", 30, |o| {
        matches!(
            o,
            Observation::HarvestSold { .. } | Observation::IntentFailed { .. }
        )
    });
    assert!(
        matches!(&o.observed, Observation::HarvestSold { reference, sold, .. } if reference == "harvest:1" && *sold > 0),
        "{o:?}"
    );
    ledger.submit(Intent::Split);
    let o = wait_for(&mut ledger, "Split", 30, |o| {
        matches!(
            o,
            Observation::Split { .. } | Observation::IntentFailed { .. }
        )
    });
    assert!(matches!(o.observed, Observation::Split { .. }), "{o:?}");

    // The demo campaign (created by the deploy script) and its Spice Run: swap on Uniswap, deliver, claim.
    let created = wait_for(&mut ledger, "CampaignCreated", 30, |o| {
        matches!(o, Observation::CampaignCreated { .. })
    });
    let Observation::CampaignCreated {
        id: campaign,
        payout_per_claim,
        ..
    } = created.observed
    else {
        unreachable!()
    };
    ledger.submit(Intent::SwapForQuest {
        player: "asha".into(),
        campaign,
        usdc_in: 2_000_000,
        min_out: 0,
        reference: "swap:asha:1".into(),
    });
    let o = wait_for(&mut ledger, "QuestSwap", 30, |o| {
        matches!(
            o,
            Observation::QuestSwap { .. } | Observation::IntentFailed { .. }
        )
    });
    assert!(
        matches!(&o.observed, Observation::QuestSwap { player, amount_in: 2_000_000, .. } if player == "asha"),
        "{o:?}"
    );
    ledger.submit(Intent::Deliver {
        player: "asha".into(),
        campaign,
        reference: "deliver:asha:1".into(),
    });
    let o = wait_for(&mut ledger, "Delivered", 30, |o| {
        matches!(
            o,
            Observation::Delivered { .. } | Observation::IntentFailed { .. }
        )
    });
    assert!(
        matches!(&o.observed, Observation::Delivered { reference, .. } if reference == "deliver:asha:1"),
        "{o:?}"
    );
    let human = chain::HumanId(format!("0x{}", "ab".repeat(32)));
    // A cargo advance first; the claim then repays it.
    ledger.submit(Intent::Advance {
        campaign,
        player: "asha".into(),
        human_id: human.clone(),
        amount: 500_000,
        reference: "advance:asha:1".into(),
    });
    let o = wait_for(&mut ledger, "Advanced", 30, |o| {
        matches!(
            o,
            Observation::Advanced { .. } | Observation::IntentFailed { .. }
        )
    });
    assert!(
        matches!(
            &o.observed,
            Observation::Advanced {
                amount: 500_000,
                ..
            }
        ),
        "{o:?}"
    );
    ledger.submit(Intent::ClaimCampaign {
        campaign,
        player: "asha".into(),
        human_id: human.clone(),
        amount: payout_per_claim,
        reference: "claim:asha:1".into(),
    });
    let o = wait_for(&mut ledger, "Claimed", 30, |o| {
        matches!(
            o,
            Observation::Claimed { .. } | Observation::IntentFailed { .. }
        )
    });
    assert!(
        matches!(&o.observed, Observation::Claimed { amount, advance_repaid: 500_000, .. } if *amount == payout_per_claim - 500_000),
        "{o:?}"
    );

    // House payouts: a voucher from the FIXED bucket, and a rescue meal from SAFETY (answered by MealEaten).
    ledger.submit(Intent::PayHouse {
        player: "asha".into(),
        human_id: human.clone(),
        bucket: chain::Bucket::Fixed,
        amount: 1_000_000,
        reference: "rush:asha:1".into(),
    });
    let o = wait_for(&mut ledger, "Paid", 30, |o| {
        matches!(
            o,
            Observation::Paid { .. } | Observation::IntentFailed { .. }
        )
    });
    assert!(
        matches!(&o.observed, Observation::Paid { amount: 1_000_000, reference, player, .. } if reference == "rush:asha:1" && player == "asha"),
        "{o:?}"
    );
    ledger.submit(Intent::PayRescueMeal {
        player: "asha".into(),
        human_id: human.clone(),
        item: "thali".into(),
        food: 6_000_000,
        max_usdc: 60_000,
        reference: "rescue:asha:1".into(),
    });
    let o = wait_for(&mut ledger, "rescue MealEaten", 30, |o| {
        matches!(o, Observation::MealEaten { reference, .. } if reference == "rescue:asha:1")
            || matches!(o, Observation::IntentFailed { .. })
    });
    assert!(
        matches!(&o.observed, Observation::MealEaten { item, .. } if item == "thali"),
        "{o:?}"
    );

    // The weekly draw: commit (root built here from the tickets), reveal after the delay, the winner claims.
    let seed = alloy::primitives::B256::repeat_byte(0x5e);
    let seed_hash = alloy::primitives::keccak256(seed.as_slice());
    ledger.submit(Intent::CommitDraw {
        week: 1,
        seed_hash: seed_hash.to_string(),
        root: String::new(),
        count: 10,
        prize: 1_000_000,
        tickets: vec![chain::TicketRange {
            player: "asha".into(),
            from: 0,
            to: 9,
        }],
    });
    let o = wait_for(&mut ledger, "DrawCommitted", 30, |o| {
        matches!(
            o,
            Observation::DrawCommitted { .. } | Observation::IntentFailed { .. }
        )
    });
    assert!(
        matches!(
            &o.observed,
            Observation::DrawCommitted {
                week: 1,
                count: 10,
                ..
            }
        ),
        "{o:?}"
    );
    std::thread::sleep(Duration::from_secs(4));
    ledger.submit(Intent::RevealDraw {
        week: 1,
        seed: seed.to_string(),
    });
    let o = wait_for(&mut ledger, "DrawRevealed", 30, |o| {
        matches!(
            o,
            Observation::DrawRevealed { .. } | Observation::IntentFailed { .. }
        )
    });
    assert!(
        matches!(&o.observed, Observation::DrawRevealed { week: 1, winner_index, .. } if *winner_index < 10),
        "{o:?}"
    );
    ledger.submit(Intent::ClaimDraw {
        week: 1,
        player: "asha".into(),
        from: 0,
        to: 9,
        reference: "draw:1".into(),
    });
    let o = wait_for(&mut ledger, "DrawClaimed", 30, |o| {
        matches!(
            o,
            Observation::DrawClaimed { .. } | Observation::IntentFailed { .. }
        )
    });
    assert!(
        matches!(&o.observed, Observation::DrawClaimed { week: 1, prize: 1_000_000, player, .. } if player == "asha"),
        "{o:?}"
    );

    // Reads: Hold the Line's balance check, and the periodic pool/float state.
    // A kiosk quote: V4Quoter on the campaign's quest pool, a read answered by SwapQuoted.
    ledger.submit(Intent::QuoteSwap {
        player: "asha".into(),
        campaign,
        usdc_in: 500_000,
        reference: "quote:asha:1".into(),
    });
    let o = wait_for(&mut ledger, "SwapQuoted", 30, |o| {
        matches!(
            o,
            Observation::SwapQuoted { .. } | Observation::IntentFailed { .. }
        )
    });
    match &o.observed {
        Observation::SwapQuoted {
            amount_out,
            fee_bps,
            symbol,
            decimals,
            reference,
            ..
        } => {
            assert!(*amount_out > 0);
            assert_eq!(
                (*fee_bps, symbol.as_str(), *decimals, reference.as_str()),
                (3_000, "MANGO", 18, "quote:asha:1")
            );
            assert_eq!(o.log_index, chain::NOT_A_LOG);
        }
        other => panic!("{other:?}"),
    }
    ledger.submit(Intent::CheckHolding {
        player: "asha".into(),
        campaign,
        reference: "hold:asha:1".into(),
    });
    let o = wait_for(&mut ledger, "Holding", 30, |o| {
        matches!(
            o,
            Observation::Holding { .. } | Observation::IntentFailed { .. }
        )
    });
    assert!(
        matches!(&o.observed, Observation::Holding { reference, .. } if reference == "hold:asha:1"),
        "{o:?}"
    );
    wait_for(&mut ledger, "PoolBalances", 30, |o| {
        matches!(o, Observation::PoolBalances { .. })
    });
    wait_for(&mut ledger, "FloatState", 30, |o| {
        matches!(o, Observation::FloatState { .. })
    });

    // Keeper float housekeeping: rebalance (no event of its own; it must not fail).
    ledger.submit(Intent::Rebalance);
    std::thread::sleep(Duration::from_secs(3));
    let fresh = ledger.poll();
    let failed = BACKLOG.with(|b| {
        b.borrow_mut().extend(fresh);
        b.borrow().iter().find(|o| matches!(&o.observed, Observation::IntentFailed { reference, .. } if reference == "rebalance")).cloned()
    });
    assert!(failed.is_none(), "{failed:?}");

    // No ENS on anvil: a name registration fails cleanly with its public ref.
    ledger.submit(Intent::RegisterName {
        player: "asha".into(),
        label: "asha".into(),
    });
    let o = wait_for(
        &mut ledger,
        "name failure",
        30,
        |o| matches!(o, Observation::IntentFailed { reference, .. } if reference == "name:asha"),
    );
    println!("name: {o:?}");
    println!("status: {:?}", ledger.status());
    ledger.shutdown();
}
