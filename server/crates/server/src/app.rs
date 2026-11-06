//! Starting a town: the flags and `server.toml`, the save, the links to the chain, and the threads. This binary settles
//! offline. A binary with a chain (the `chain` crate's) calls `run` with its own `Links`, so the wiring is the same.

use crate::http::{HttpConfig, HttpDesk};
use crate::hub::{Hub, Links, Options};
use crate::log::Log;
use crate::net;
use crate::public::PublicView;
use crate::world::{Setup, World, DEFAULT_QUESTS};
use rules::chain::ChainMode;
use serde::Deserialize;
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::sync::mpsc::channel;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const DEFAULT_ADDR: &str = "127.0.0.1:7878";
const DEFAULT_HEARTBEAT_MS: u64 = 5000;
const DEFAULT_PUBLISHER: &str = "http://127.0.0.1:8787";
const VALUE_FLAGS: [&str; 17] = [
    "--config",
    "--addr",
    "--save",
    "--rules",
    "--quests",
    "--seed",
    "--speed",
    "--heartbeat-ms",
    "--chain",
    "--deployments",
    "--publisher-url",
    "--web",
    "--public-url",
    "--public-rpc-url",
    "--world-app-id",
    "--arkiv",
    "--town",
];
const SWITCHES: [&str; 3] = ["--debug", "--new-if-incompatible", "--behind-proxy"];
pub const USAGE: &str = "server [flags]

  --config <file>          read these settings from a TOML file (keys as below, without the dashes,
                           with _ for -); flags win. Never put secrets in it
  --addr <ip:port>         where to listen (default 127.0.0.1:7878, this machine only;
                           0.0.0.0:7878 lets other machines join; port 0 picks a free one)
  --save <file>            the save, created if missing (default save.jsonl)
  --rules <file>           used only when starting a new save (default rules.toml)
  --quests <file>          the quest book, used only when starting a new save (default quests.toml,
                           or the built-in one if that's missing)
  --seed <n>               the city's seed, for a new save (default 1)
  --chain <mode>           offline, anvil or sepolia (default offline, or CHAIN_MODE). This binary
                           settles offline; anvil and sepolia run from the tallyport binary
  --deployments <file>     contracts/deployments/<network>.json, served as /deployments.json
  --publisher-url <url>    the Arkiv/Swarm publisher (default PUBLISHER_URL or http://127.0.0.1:8787)
  --web <dir>              the web pages to serve (default ../web, if it's there)
  --public-url <url>       how browsers reach this server, for Town Pass links
                           (default PUBLIC_URL or http://<addr>)
  --public-rpc-url <url>   a keyless read RPC the pages may use (default PUBLIC_RPC_URL)
  --world-app-id <id>      the World ID app id the pages show (default WORLD_APP_ID)
  --arkiv <url>            before starting, bring the save up to date from Arkiv through the publisher's
                           GET /log at this http:// URL on this machine (needs DHANIVERSE_RESTORE_TOKEN).
                           A missing save is rebuilt whole; a broken chain stops the server
  --town <id>              the town to rebuild with --arkiv when the save is missing
  --debug                  allow the rehearsal commands in PROTOCOL.md
  --speed <n>              run the clock faster; needs --debug (default 1)
  --heartbeat-ms <n>       how often the clock moves; 0 stops it (default 5000)
  --behind-proxy           rate-limit by X-Forwarded-For; only behind a TLS proxy
  --new-if-incompatible    if the save won't replay, move it to <save>.old-<timestamp>
                           and start a new city, instead of stopping
  --help                   print this and exit";

/// `server.toml`: the same settings as the flags.
#[derive(Debug, Default, Deserialize)]
#[serde(deny_unknown_fields)]
struct FileConfig {
    addr: Option<String>,
    save: Option<String>,
    rules: Option<String>,
    quests: Option<String>,
    seed: Option<u64>,
    chain: Option<String>,
    deployments: Option<String>,
    publisher_url: Option<String>,
    web: Option<String>,
    public_url: Option<String>,
    public_rpc_url: Option<String>,
    world_app_id: Option<String>,
    arkiv: Option<String>,
    town: Option<String>,
    heartbeat_ms: Option<u64>,
    debug: Option<bool>,
    behind_proxy: Option<bool>,
}

/// Everything a town starts with. No secrets: those come from the environment, read by the chain crate.
#[derive(Clone, Debug)]
pub struct ServerConfig {
    pub addr: String,
    pub save: PathBuf,
    pub rules: PathBuf,
    pub quests: PathBuf,
    pub seed: u64,
    pub chain: ChainMode,
    pub debug: bool,
    pub speed: u64,
    pub heartbeat_ms: u64,
    pub behind_proxy: bool,
    pub new_if_incompatible: bool,
    pub public_url: Option<String>,
    pub http: HttpConfig,
    /// `--arkiv`: the publisher to restore the save from before opening it.
    pub arkiv: Option<String>,
    /// `--town`: which town `--arkiv` rebuilds when there is no save.
    pub town: Option<String>,
}

impl ServerConfig {
    /// How browsers reach this server, given where it's listening.
    pub fn public_url(&self, listening: &str) -> String {
        self.public_url
            .clone()
            .unwrap_or_else(|| format!("http://{listening}"))
    }
}

/// Stops at anything it doesn't know, before a mistyped flag can start a server and write a save.
fn check_args(args: &[String]) -> Result<(), String> {
    let mut rest = args.iter();
    while let Some(arg) = rest.next() {
        if VALUE_FLAGS.contains(&arg.as_str()) {
            if rest.next().is_none() {
                return Err(format!("{arg} needs a value\n\n{USAGE}"));
            }
        } else if !SWITCHES.contains(&arg.as_str()) {
            return Err(format!("unknown flag {arg}\n\n{USAGE}"));
        }
    }
    Ok(())
}

fn env(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.trim().is_empty())
}

/// Reads the flags, the config file and the environment. None means `--help` was asked for.
pub fn parse_args(args: &[String]) -> Result<Option<ServerConfig>, String> {
    if args.iter().any(|a| a == "--help" || a == "-h") {
        return Ok(None);
    }
    check_args(args)?;
    let value = |name: &str| {
        let found = args.iter().position(|a| a == name);
        found.and_then(|i| args.get(i + 1)).cloned()
    };
    let switch = |name: &str| args.iter().any(|a| a == name);
    let file: FileConfig = match value("--config") {
        Some(path) => {
            let text = std::fs::read_to_string(&path).map_err(|e| format!("{path}: {e}"))?;
            toml::from_str(&text).map_err(|e| format!("{path}: {e}"))?
        }
        None => FileConfig::default(),
    };
    let number = |name: &str, from_file: Option<u64>, default: u64| match value(name) {
        Some(text) => text.parse().map_err(|_| format!("{name} needs a number")),
        None => Ok(from_file.unwrap_or(default)),
    };
    let debug = switch("--debug") || file.debug.unwrap_or(false);
    let speed = number("--speed", None, 1)?;
    if speed != 1 && !debug {
        return Err("--speed is for rehearsal, so it needs --debug".to_string());
    }
    let chain_text = value("--chain")
        .or(file.chain)
        .or_else(|| env("CHAIN_MODE"))
        .unwrap_or_else(|| "offline".to_string());
    let chain = ChainMode::parse(&chain_text)
        .ok_or_else(|| format!("--chain is offline, anvil or sepolia, not {chain_text}"))?;
    let web = value("--web").or(file.web).map(PathBuf::from).or_else(|| {
        let beside = PathBuf::from("../web");
        beside.join("verify.html").is_file().then_some(beside)
    });
    let http = HttpConfig {
        web_dir: web,
        deployments: value("--deployments")
            .or(file.deployments)
            .map(PathBuf::from),
        rpc_url: value("--public-rpc-url")
            .or(file.public_rpc_url)
            .or_else(|| env("PUBLIC_RPC_URL")),
        publisher_url: Some(
            value("--publisher-url")
                .or(file.publisher_url)
                .or_else(|| env("PUBLISHER_URL"))
                .unwrap_or_else(|| DEFAULT_PUBLISHER.to_string()),
        ),
        world_app_id: value("--world-app-id")
            .or(file.world_app_id)
            .or_else(|| env("WORLD_APP_ID")),
    };
    Ok(Some(ServerConfig {
        addr: value("--addr")
            .or(file.addr)
            .unwrap_or_else(|| DEFAULT_ADDR.to_string()),
        save: PathBuf::from(
            value("--save")
                .or(file.save)
                .unwrap_or_else(|| "save.jsonl".to_string()),
        ),
        rules: PathBuf::from(
            value("--rules")
                .or(file.rules)
                .unwrap_or_else(|| "rules.toml".to_string()),
        ),
        quests: PathBuf::from(
            value("--quests")
                .or(file.quests)
                .unwrap_or_else(|| "quests.toml".to_string()),
        ),
        seed: number("--seed", file.seed, 1)?,
        chain,
        debug,
        speed,
        heartbeat_ms: number("--heartbeat-ms", file.heartbeat_ms, DEFAULT_HEARTBEAT_MS)?,
        behind_proxy: switch("--behind-proxy") || file.behind_proxy.unwrap_or(false),
        new_if_incompatible: switch("--new-if-incompatible"),
        public_url: value("--public-url")
            .or(file.public_url)
            .or_else(|| env("PUBLIC_URL")),
        http,
        arkiv: value("--arkiv").or(file.arkiv),
        town: value("--town").or(file.town),
    }))
}

/// Opens the save, or starts a new city from the config's files.
pub fn open_save(config: &ServerConfig) -> Result<(Log, World), String> {
    if let Some(publisher) = &config.arkiv {
        let done = crate::arkiv::restore_from_env(&config.save, publisher, config.town.as_deref())?;
        println!(
            "restored from Arkiv: town {}, {} new line(s), Arkiv holds lines up to {}, the save had {}",
            done.town, done.lines, done.tip, done.had
        );
    }
    let rules = std::fs::read_to_string(&config.rules)
        .map_err(|e| format!("{}: {e}", config.rules.display()))?;
    let quests = match std::fs::read_to_string(&config.quests) {
        Ok(text) => text,
        Err(_) if config.quests == Path::new("quests.toml") => DEFAULT_QUESTS.to_string(),
        Err(e) => return Err(format!("{}: {e}", config.quests.display())),
    };
    let setup = Setup {
        seed: config.seed,
        rules,
        quests,
        chain: config.chain,
        // A new save picks its own at random.
        town_id: String::new(),
    };
    if !config.new_if_incompatible {
        return Log::open_city(&config.save, &setup);
    }
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs());
    let (log, world, moved) = Log::open_city_or_start_new(&config.save, &setup, now)?;
    if let Some(old) = moved {
        eprintln!(
            "NEW CITY: this save doesn't replay under the current rules, so a new city started. \
             The old save is kept, unchanged, at {}",
            old.display()
        );
    }
    Ok((log, world))
}

/// Runs a town until the process ends. `links` makes the chain and World ID links for the world once it's loaded;
/// it's given the config and the public URL Town Pass links should use.
pub fn run(
    config: ServerConfig,
    links: impl FnOnce(&World, &ServerConfig, &str) -> Result<Links, String>,
) -> Result<(), String> {
    let (log, world) = open_save(&config)?;
    let options = Options {
        heartbeat: (config.heartbeat_ms > 0).then(|| Duration::from_millis(config.heartbeat_ms)),
        speed: config.speed,
        debug: config.debug,
    };
    // Bound first, so a picked port (0) is known for the Town Pass links.
    let listener = TcpListener::bind(&config.addr).map_err(|e| format!("{}: {e}", config.addr))?;
    let local = listener.local_addr().map_err(|e| e.to_string())?;
    let public_url = config.public_url(&local.to_string());
    let mut links = links(&world, &config, &public_url)?;
    let (to_city, from_net) = channel();
    let public = Arc::new(PublicView::default());
    let mut http = config.http.clone();
    if http.world_app_id.is_none() {
        http.world_app_id = links.verifier.app_id();
    }
    links.world_app_id = http.world_app_id.clone();
    let desk = Arc::new(HttpDesk::new(
        Arc::clone(&public),
        http,
        Arc::clone(&links.verify),
        Arc::clone(&links.verifier),
        to_city.clone(),
    ));
    let mut hub = Hub::new(world, log, options, links)?;
    hub.publish_to(Arc::clone(&public));
    let addr = net::listen_on(listener, config.behind_proxy, desk, to_city)?;
    println!("listening on {addr}");
    hub.run(from_net)
}
