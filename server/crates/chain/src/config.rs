//! Configuration: one struct, filled from environment variables (keys only ever come from the environment).
//!
//! | Variable | Meaning | Default |
//! |---|---|---|
//! | `CHAIN_RPC_URL` (or `RPC_URL`) | JSON-RPC endpoint (falls back to `SEPOLIA_RPC_URL` on sepolia) | anvil: `http://127.0.0.1:8545` |
//! | `CHAIN_ID` | expected chain id (checked against the node and the deployments file) | 31337 / 11155111 |
//! | `CHAIN_DEPLOYMENTS` (or `DEPLOYMENTS`) | path of `deployments/<network>.json` | `../contracts/deployments/<network>.json` |
//! | `CHAIN_DATA_DIR` | where wallets, sent intents and the indexer checkpoint are kept | `chain-data/<network>` |
//! | `CHAIN_CONFIRMATIONS` | blocks before a log counts | anvil 0, sepolia 2 |
//! | `TICKET_SIGNER_KEY` | signs MealTickets | required |
//! | `VOUCHER_SIGNER_KEY` | signs PayoutVouchers, CampaignClaims, AdvanceVouchers | required |
//! | `KEEPER_KEY` | sends keeper transactions (Farm, Treasury, FloatManager, LuckyLedger, vouchers) | required |
//! | `NAMES_KEY` | registers ENS subnames and writes server-owned records | optional (names off) |
//! | `GAS_STATION_KEY` | tops up player wallets with ETH for gas | optional (no top-ups) |
//! | `WALLET_SEED` | BIP-39 phrase for the server-held player wallets | required |
//! | `RP_SIGNING_KEY` | World ID 4: signs RP contexts (EIP-191) | optional (World ID off) |
//! | `WORLD_RP_ID` | World ID relying-party id (`rp_…`) | `WORLD_APP_ID` if set, else the founder's `rp_f24fbbc28154fb5c` |
//! | `WORLD_APP_ID` | World ID app id (`app_…`), for IDKit on the verify page | `app_eca8340a4f71973c608bbaa31a7af47e` |
//! | `WORLD_ACTION` | the Developer Portal action every Town Pass proves | `tallyport-town-pass` |
//! | `WORLD_ENVIRONMENT` | `production`, `staging` or `sandbox` | `production` |
//! | `WORLD_ALLOW_LEGACY_PROOFS` | also take World ID 3.0 proofs (`true`/`false`); see [`WorldIdConfig`] | `false` |
//!
//! Tuning knobs (`CHAIN_GAS_FLOOR_WEI`, `CHAIN_GAS_TOPUP_WEI`, `CHAIN_GAS_DAILY_CAP_WEI`, `CHAIN_VOUCHER_TTL_SECS`,
//! `CHAIN_LOG_RANGE`, `CHAIN_ENS_PARENT`, `CHAIN_ABI_DIR`) are read too; see [`ChainConfig::from_env`].

use alloy::primitives::U256;
use alloy::signers::local::PrivateKeySigner;
use std::fmt;
use std::path::PathBuf;
use std::time::Duration;

/// Which chain we're on.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Network {
    Anvil,
    Sepolia,
}

impl Network {
    pub fn name(self) -> &'static str {
        match self {
            Network::Anvil => "anvil",
            Network::Sepolia => "sepolia",
        }
    }

    pub fn default_chain_id(self) -> u64 {
        match self {
            Network::Anvil => 31_337,
            Network::Sepolia => 11_155_111,
        }
    }

    /// Spec §3.3: sepolia 2, anvil 0.
    pub fn default_confirmations(self) -> u64 {
        match self {
            Network::Anvil => 0,
            Network::Sepolia => 2,
        }
    }

    pub fn parse(s: &str) -> Result<Network, ConfigError> {
        match s {
            "anvil" => Ok(Network::Anvil),
            "sepolia" => Ok(Network::Sepolia),
            other => Err(ConfigError::Invalid(
                "network",
                format!("{other:?} (expected anvil or sepolia)"),
            )),
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("{0} is not set")]
    Missing(&'static str),
    #[error("{0} is invalid: {1}")]
    Invalid(&'static str, String),
}

/// A string that never shows up in `Debug` or `Display`.
#[derive(Clone, PartialEq, Eq)]
pub struct Secret(String);

impl Secret {
    pub fn new(s: impl Into<String>) -> Secret {
        Secret(s.into())
    }
    /// The value, for the one place that needs it.
    pub fn expose(&self) -> &str {
        &self.0
    }
}

impl fmt::Debug for Secret {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("Secret(<redacted>)")
    }
}

/// A private key, shown only by its address.
#[derive(Clone)]
pub struct Key(pub PrivateKeySigner);

impl Key {
    pub fn parse(var: &'static str, hex: &str) -> Result<Key, ConfigError> {
        hex.trim()
            .parse::<PrivateKeySigner>()
            .map(Key)
            .map_err(|_| ConfigError::Invalid(var, "not a 32-byte hex private key".into()))
    }
    pub fn address(&self) -> alloy::primitives::Address {
        self.0.address()
    }
}

impl fmt::Debug for Key {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Key({})", self.0.address())
    }
}

/// Every secret the crate uses. `DEPLOYER_KEY` is deliberately absent: the server never deploys.
#[derive(Clone, Debug)]
pub struct Secrets {
    pub ticket_signer: Key,
    pub voucher_signer: Key,
    pub keeper: Key,
    pub names: Option<Key>,
    pub gas_station: Option<Key>,
    pub wallet_seed: Secret,
}

/// The founder's World ID app (Developer Portal), the defaults when `WORLD_APP_ID` / `WORLD_RP_ID` aren't set.
pub const DEFAULT_WORLD_APP_ID: &str = "app_eca8340a4f71973c608bbaa31a7af47e";
pub const DEFAULT_WORLD_RP_ID: &str = "rp_f24fbbc28154fb5c";
/// The Developer Portal action every Town Pass proves, unless `WORLD_ACTION` says otherwise.
pub const DEFAULT_WORLD_ACTION: &str = "tallyport-town-pass";

/// World ID 4 settings (IDKit 4: the server signs an RP context per verify session, then forwards IDKit's result to
/// `POST https://developer.world.org/api/v4/verify/{rp_id}`).
#[derive(Clone, Debug)]
pub struct WorldIdConfig {
    /// `WORLD_RP_ID` (`rp_…`); falls back to `WORLD_APP_ID`, which the API also accepts.
    pub rp_id: String,
    /// `WORLD_APP_ID` (`app_…`), handed to the verify page for IDKit.
    pub app_id: Option<String>,
    /// `RP_SIGNING_KEY`: signs RP contexts (EIP-191).
    pub signing_key: Key,
    /// `WORLD_ENVIRONMENT`: `production` (default), `staging` or `sandbox`. The API's answer must match.
    pub environment: String,
    /// `WORLD_ACTION`: the action id, as created in the Developer Portal.
    pub action: String,
    /// `WORLD_ALLOW_LEGACY_PROOFS`: also take World ID 3.0 (Orb legacy) proofs. Off by default: a person could then
    /// prove once with a 3.0 credential and again after upgrading to 4.0, and the two nullifiers can't be linked, so
    /// one person could hold two players (World's docs: "track both v3 and v4 nullifiers"). New apps start 4.0-only.
    pub allow_legacy_proofs: bool,
    /// `https://developer.world.org/api/v4/verify` (the rp id is appended).
    pub verify_base_url: String,
    /// How long a signed RP context is valid (IDKit's default is 300 s).
    pub context_ttl: Duration,
    pub timeout: Duration,
}

impl WorldIdConfig {
    pub fn new(rp_id: impl Into<String>, signing_key: Key) -> WorldIdConfig {
        WorldIdConfig {
            rp_id: rp_id.into(),
            app_id: None,
            signing_key,
            environment: "production".into(),
            action: DEFAULT_WORLD_ACTION.into(),
            allow_legacy_proofs: false,
            verify_base_url: "https://developer.world.org/api/v4/verify".into(),
            context_ttl: Duration::from_secs(300),
            timeout: Duration::from_secs(15),
        }
    }

    /// `None` when World ID isn't configured (no `RP_SIGNING_KEY`); an error when it's half configured.
    pub fn from_env(env: &dyn Env) -> Result<Option<WorldIdConfig>, ConfigError> {
        let Some(key) = optional_key(env, "RP_SIGNING_KEY")? else {
            if env.get("WORLD_RP_ID").is_some() {
                return Err(ConfigError::Missing("RP_SIGNING_KEY"));
            }
            return Ok(None);
        };
        // An explicitly chosen app without an rp id verifies under its app id (the API accepts both); otherwise
        // the founder's app and its RP registration.
        let app_id = env.get("WORLD_APP_ID");
        let rp_id = env
            .get("WORLD_RP_ID")
            .or_else(|| app_id.clone())
            .unwrap_or_else(|| DEFAULT_WORLD_RP_ID.into());
        let mut c = WorldIdConfig::new(rp_id, key);
        c.app_id = Some(app_id.unwrap_or_else(|| DEFAULT_WORLD_APP_ID.into()));
        if let Some(a) = env.get("WORLD_ACTION") {
            c.action = a;
        }
        if let Some(v) = env.get("WORLD_ALLOW_LEGACY_PROOFS") {
            c.allow_legacy_proofs = match v.trim() {
                "true" | "1" => true,
                "false" | "0" => false,
                _ => {
                    return Err(ConfigError::Invalid(
                        "WORLD_ALLOW_LEGACY_PROOFS",
                        format!("{v:?} (true or false)"),
                    ))
                }
            };
        }
        if let Some(e) = env.get("WORLD_ENVIRONMENT") {
            if !matches!(e.as_str(), "production" | "staging" | "sandbox") {
                return Err(ConfigError::Invalid(
                    "WORLD_ENVIRONMENT",
                    format!("{e:?} (production, staging or sandbox)"),
                ));
            }
            c.environment = e;
        }
        Ok(Some(c))
    }
}

/// Gas policy for server-held player wallets.
#[derive(Clone, Debug)]
pub struct GasPolicy {
    /// Top up when a player's ETH balance is below this, before a player-sent transaction.
    pub floor_wei: U256,
    /// Top up to this balance.
    pub target_wei: U256,
    /// At most this much ETH per player per UTC day.
    pub daily_cap_wei: U256,
}

#[derive(Clone)]
pub struct ChainConfig {
    pub network: Network,
    pub rpc_url: String,
    pub chain_id: u64,
    pub deployments_path: PathBuf,
    pub data_dir: PathBuf,
    pub confirmations: u64,
    /// How often the indexer asks for new blocks.
    pub poll_interval: Duration,
    /// How often balances (players, pools, float) are read.
    pub balance_interval: Duration,
    /// Most blocks per `eth_getLogs` call (public Sepolia RPCs limit ranges).
    pub log_range: u64,
    /// How long to wait for a receipt before checking whether the transaction was dropped.
    pub receipt_timeout: Duration,
    /// Rebroadcast/replace a dropped transaction at most this many times.
    pub max_resends: u32,
    /// Transactions in flight per sending key.
    pub max_in_flight: usize,
    /// Fee bump (percent) when replacing a stuck transaction.
    pub fee_bump_percent: u64,
    /// Lifetime of signed tickets and vouchers.
    pub voucher_ttl: Duration,
    /// Lifetime of a swap (UniversalRouter deadline).
    pub swap_deadline: Duration,
    /// Slippage allowed below the on-chain quote when the server sends `min_out` 0 (basis points).
    pub swap_slippage_bps: u64,
    pub gas: GasPolicy,
    /// ENS parent name, e.g. `tallyport.eth`.
    pub ens_parent: String,
    /// Coin types the names key writes the player's address under (60 = ETH).
    pub ens_coin_types: Vec<u64>,
    /// Text record keys the player's own wallet may write (the rest go through the names key).
    pub player_record_keys: Vec<String>,
    /// The avatar written when a name is registered (`CHAIN_ENS_DEFAULT_AVATAR`, default empty).
    pub ens_default_avatar: String,
    /// The ENS admin (upgrade role on player resolvers); defaults to the deployments' `keys.admin`.
    pub ens_admin: Option<alloy::primitives::Address>,
    /// Name registrations last this long (renewed by the names key).
    pub name_duration: Duration,
    /// Optional `contracts/out`: revert data is decoded with the custom errors found there.
    pub abi_dir: Option<PathBuf>,
    /// Ignore the persisted checkpoint and start the indexer after this block (the server's own log knows best).
    pub resume_after_block: Option<u64>,
    pub world_id: Option<WorldIdConfig>,
    pub secrets: Secrets,
    /// What the save already knows, used to rebuild a data dir that was lost. Filled by the server, never from env.
    pub recovery: Recovery,
}

/// What the save knows that the data dir also keeps: every player's wallet address, and each committed, unclaimed
/// draw's tickets (player, first, last). A town restored from Arkiv on another machine has the save but not the data
/// dir; the chain link rebuilds `wallets.jsonl` and `draws/` from this instead of starting them empty.
#[derive(Clone, Debug, Default)]
pub struct Recovery {
    pub wallets: Vec<(String, alloy::primitives::Address)>,
    pub draws: Vec<(u64, Vec<(String, u64, u64)>)>,
}

impl fmt::Debug for ChainConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ChainConfig")
            .field("network", &self.network)
            .field("rpc_url", &redact_url(&self.rpc_url))
            .field("chain_id", &self.chain_id)
            .field("deployments_path", &self.deployments_path)
            .field("data_dir", &self.data_dir)
            .field("confirmations", &self.confirmations)
            .field("poll_interval", &self.poll_interval)
            .field("balance_interval", &self.balance_interval)
            .field("log_range", &self.log_range)
            .field("receipt_timeout", &self.receipt_timeout)
            .field("max_resends", &self.max_resends)
            .field("max_in_flight", &self.max_in_flight)
            .field("voucher_ttl", &self.voucher_ttl)
            .field("gas", &self.gas)
            .field("ens_parent", &self.ens_parent)
            .field("abi_dir", &self.abi_dir)
            .field("world_id", &self.world_id)
            .field("secrets", &self.secrets)
            .finish_non_exhaustive()
    }
}

/// Keeps scheme and host; hides paths and queries, where providers put API keys.
pub fn redact_url(url: &str) -> String {
    match url.split_once("://") {
        Some((scheme, rest)) => {
            let host = rest.split(['/', '?']).next().unwrap_or("");
            let host = host.rsplit('@').next().unwrap_or(host);
            if rest.len() > host.len() {
                format!("{scheme}://{host}/<redacted>")
            } else {
                format!("{scheme}://{host}")
            }
        }
        None => "<redacted>".into(),
    }
}

/// Reads environment variables through a function, so tests don't touch the process environment.
pub trait Env {
    fn get(&self, key: &str) -> Option<String>;
}

/// The process environment.
pub struct ProcessEnv;

impl Env for ProcessEnv {
    fn get(&self, key: &str) -> Option<String> {
        std::env::var(key).ok().filter(|v| !v.trim().is_empty())
    }
}

impl<F: Fn(&str) -> Option<String>> Env for F {
    fn get(&self, key: &str) -> Option<String> {
        self(key)
    }
}

fn parse_num<T: std::str::FromStr>(
    env: &dyn Env,
    var: &'static str,
    default: T,
) -> Result<T, ConfigError> {
    match env.get(var) {
        Some(v) => v
            .trim()
            .parse()
            .map_err(|_| ConfigError::Invalid(var, format!("{v:?} is not a number"))),
        None => Ok(default),
    }
}

fn parse_wei(env: &dyn Env, var: &'static str, default: U256) -> Result<U256, ConfigError> {
    match env.get(var) {
        Some(v) => v
            .trim()
            .parse::<U256>()
            .map_err(|_| ConfigError::Invalid(var, format!("{v:?} is not a number"))),
        None => Ok(default),
    }
}

fn key(env: &dyn Env, var: &'static str) -> Result<Key, ConfigError> {
    let v = env.get(var).ok_or(ConfigError::Missing(var))?;
    Key::parse(var, &v)
}

fn optional_key(env: &dyn Env, var: &'static str) -> Result<Option<Key>, ConfigError> {
    env.get(var).map(|v| Key::parse(var, &v)).transpose()
}

const GWEI: u64 = 1_000_000_000;

impl ChainConfig {
    /// Builds the config for `network` from the process environment.
    pub fn from_process_env(network: Network) -> Result<ChainConfig, ConfigError> {
        ChainConfig::from_env(network, &ProcessEnv)
    }

    /// Builds the config for `network` from `env`. Validates every key and the seed phrase up front.
    pub fn from_env(network: Network, env: &dyn Env) -> Result<ChainConfig, ConfigError> {
        let rpc_url = match (
            env.get("CHAIN_RPC_URL").or_else(|| env.get("RPC_URL")),
            network,
        ) {
            (Some(u), _) => u,
            (None, Network::Sepolia) => env
                .get("SEPOLIA_RPC_URL")
                .ok_or(ConfigError::Missing("CHAIN_RPC_URL"))?,
            (None, Network::Anvil) => "http://127.0.0.1:8545".into(),
        };
        if !(rpc_url.starts_with("http://") || rpc_url.starts_with("https://")) {
            return Err(ConfigError::Invalid(
                "CHAIN_RPC_URL",
                "must be an http(s) URL".into(),
            ));
        }
        let seed = env
            .get("WALLET_SEED")
            .ok_or(ConfigError::Missing("WALLET_SEED"))?;
        crate::wallets::validate_seed(&seed).map_err(|e| ConfigError::Invalid("WALLET_SEED", e))?;
        let secrets = Secrets {
            ticket_signer: key(env, "TICKET_SIGNER_KEY")?,
            voucher_signer: key(env, "VOUCHER_SIGNER_KEY")?,
            keeper: key(env, "KEEPER_KEY")?,
            names: optional_key(env, "NAMES_KEY")?,
            gas_station: optional_key(env, "GAS_STATION_KEY")?,
            wallet_seed: Secret::new(seed),
        };
        let fast = network == Network::Anvil;
        let cfg = ChainConfig {
            network,
            rpc_url,
            chain_id: parse_num(env, "CHAIN_ID", network.default_chain_id())?,
            deployments_path: env
                .get("CHAIN_DEPLOYMENTS")
                .or_else(|| env.get("DEPLOYMENTS"))
                .map(PathBuf::from)
                .unwrap_or_else(|| {
                    PathBuf::from(format!("../contracts/deployments/{}.json", network.name()))
                }),
            data_dir: env
                .get("CHAIN_DATA_DIR")
                .map(PathBuf::from)
                .unwrap_or_else(|| PathBuf::from(format!("chain-data/{}", network.name()))),
            confirmations: parse_num(env, "CHAIN_CONFIRMATIONS", network.default_confirmations())?,
            poll_interval: Duration::from_millis(parse_num(
                env,
                "CHAIN_POLL_MS",
                if fast { 500 } else { 4_000 },
            )?),
            balance_interval: Duration::from_millis(parse_num(
                env,
                "CHAIN_BALANCE_MS",
                if fast { 2_000 } else { 6_000 },
            )?),
            log_range: parse_num(env, "CHAIN_LOG_RANGE", if fast { 5_000 } else { 500 })?.max(1),
            receipt_timeout: Duration::from_secs(parse_num(
                env,
                "CHAIN_RECEIPT_TIMEOUT_SECS",
                if fast { 20 } else { 90 },
            )?),
            max_resends: parse_num(env, "CHAIN_MAX_RESENDS", 3)?,
            max_in_flight: parse_num(env, "CHAIN_MAX_IN_FLIGHT", 4usize)?.max(1),
            fee_bump_percent: parse_num(env, "CHAIN_FEE_BUMP_PERCENT", 25)?.max(10),
            voucher_ttl: Duration::from_secs(parse_num(env, "CHAIN_VOUCHER_TTL_SECS", 3_600)?),
            swap_deadline: Duration::from_secs(parse_num(env, "CHAIN_SWAP_DEADLINE_SECS", 600)?),
            swap_slippage_bps: parse_num(env, "CHAIN_SWAP_SLIPPAGE_BPS", 100u64)?.min(5_000),
            gas: GasPolicy {
                floor_wei: parse_wei(
                    env,
                    "CHAIN_GAS_FLOOR_WEI",
                    U256::from(300_000u64 * 5 * GWEI),
                )?,
                target_wei: parse_wei(
                    env,
                    "CHAIN_GAS_TOPUP_WEI",
                    U256::from(1_000_000u64 * 10 * GWEI),
                )?,
                daily_cap_wei: parse_wei(
                    env,
                    "CHAIN_GAS_DAILY_CAP_WEI",
                    U256::from(5_000_000u64 * 10 * GWEI),
                )?,
            },
            ens_parent: env
                .get("CHAIN_ENS_PARENT")
                .unwrap_or_else(|| "tallyport.eth".into()),
            ens_coin_types: vec![60, crate::bindings::ens::DEFAULT_EVM_COIN_TYPE],
            player_record_keys: vec!["avatar".into(), "description".into()],
            ens_default_avatar: env.get("CHAIN_ENS_DEFAULT_AVATAR").unwrap_or_default(),
            ens_admin: env
                .get("ENS_ADMIN_ADDRESS")
                .map(|a| a.trim().parse())
                .transpose()
                .map_err(|_| ConfigError::Invalid("ENS_ADMIN_ADDRESS", "not an address".into()))?,
            name_duration: Duration::from_secs(365 * 24 * 3_600),
            abi_dir: env.get("CHAIN_ABI_DIR").map(PathBuf::from),
            resume_after_block: env
                .get("CHAIN_RESUME_AFTER_BLOCK")
                .map(|v| v.parse())
                .transpose()
                .map_err(|_| {
                    ConfigError::Invalid("CHAIN_RESUME_AFTER_BLOCK", "not a block number".into())
                })?,
            world_id: WorldIdConfig::from_env(env)?,
            secrets,
            recovery: Recovery::default(),
        };
        if cfg.gas.target_wei < cfg.gas.floor_wei {
            return Err(ConfigError::Invalid(
                "CHAIN_GAS_TOPUP_WEI",
                "below CHAIN_GAS_FLOOR_WEI".into(),
            ));
        }
        Ok(cfg)
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use std::collections::HashMap;

    /// anvil's well-known dev keys and mnemonic: public test values, never real funds.
    pub const ANVIL_MNEMONIC: &str = "test test test test test test test test test test test junk";
    pub const ANVIL_KEYS: [&str; 5] = [
        "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
        "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
        "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
        "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6",
        "0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a",
    ];

    pub fn anvil_env() -> HashMap<&'static str, String> {
        let mut m = HashMap::new();
        m.insert("TICKET_SIGNER_KEY", ANVIL_KEYS[1].to_string());
        m.insert("VOUCHER_SIGNER_KEY", ANVIL_KEYS[2].to_string());
        m.insert("KEEPER_KEY", ANVIL_KEYS[3].to_string());
        m.insert("NAMES_KEY", ANVIL_KEYS[4].to_string());
        m.insert("GAS_STATION_KEY", ANVIL_KEYS[0].to_string());
        m.insert("WALLET_SEED", ANVIL_MNEMONIC.to_string());
        m
    }

    pub fn anvil_config(data_dir: &std::path::Path) -> ChainConfig {
        let mut env = anvil_env();
        env.insert("CHAIN_DATA_DIR", data_dir.display().to_string());
        let get = move |k: &str| env.get(k).cloned();
        ChainConfig::from_env(Network::Anvil, &get).unwrap()
    }

    #[test]
    fn defaults_per_network() {
        let env = anvil_env();
        let get = |k: &str| env.get(k).cloned();
        let c = ChainConfig::from_env(Network::Anvil, &get).unwrap();
        assert_eq!(c.chain_id, 31_337);
        assert_eq!(c.confirmations, 0);
        assert_eq!(c.rpc_url, "http://127.0.0.1:8545");
        assert!(c.deployments_path.ends_with("anvil.json"));
        assert!(c.world_id.is_none());

        let mut env = anvil_env();
        env.insert(
            "SEPOLIA_RPC_URL",
            "https://eth-sepolia.example.com/v2/SECRETKEY".into(),
        );
        env.insert("WORLD_APP_ID", "app_123".into());
        env.insert("RP_SIGNING_KEY", ANVIL_KEYS[0].into());
        env.insert("WORLD_ENVIRONMENT", "staging".into());
        let get = |k: &str| env.get(k).cloned();
        let c = ChainConfig::from_env(Network::Sepolia, &get).unwrap();
        assert_eq!(c.chain_id, 11_155_111);
        assert_eq!(c.confirmations, 2);
        let w = c.world_id.as_ref().unwrap();
        assert_eq!(w.action, "tallyport-town-pass");
        assert_eq!(w.rp_id, "app_123");
        assert_eq!(w.environment, "staging");

        env.insert("WORLD_ENVIRONMENT", "prod".into());
        let get = |k: &str| env.get(k).cloned();
        assert!(ChainConfig::from_env(Network::Sepolia, &get).is_err());
        env.remove("RP_SIGNING_KEY");
        env.insert("WORLD_RP_ID", "rp_1".into());
        let get = |k: &str| env.get(k).cloned();
        assert!(matches!(
            ChainConfig::from_env(Network::Sepolia, &get),
            Err(ConfigError::Missing("RP_SIGNING_KEY"))
        ));
    }

    #[test]
    fn world_id_defaults_to_the_founders_app_and_is_4_0_only() {
        let mut env = anvil_env();
        env.insert("RP_SIGNING_KEY", ANVIL_KEYS[0].into());
        let get = |k: &str| env.get(k).cloned();
        let w = ChainConfig::from_env(Network::Anvil, &get).unwrap().world_id.unwrap();
        assert_eq!(w.rp_id, DEFAULT_WORLD_RP_ID);
        assert_eq!(w.app_id.as_deref(), Some(DEFAULT_WORLD_APP_ID));
        assert_eq!(w.action, DEFAULT_WORLD_ACTION);
        assert!(!w.allow_legacy_proofs);

        env.insert("WORLD_RP_ID", "rp_other".into());
        env.insert("WORLD_APP_ID", "app_other".into());
        env.insert("WORLD_ACTION", "other-action".into());
        env.insert("WORLD_ALLOW_LEGACY_PROOFS", "true".into());
        let get = |k: &str| env.get(k).cloned();
        let w = ChainConfig::from_env(Network::Anvil, &get).unwrap().world_id.unwrap();
        assert_eq!((w.rp_id.as_str(), w.app_id.as_deref()), ("rp_other", Some("app_other")));
        assert_eq!(w.action, "other-action");
        assert!(w.allow_legacy_proofs);

        env.insert("WORLD_ALLOW_LEGACY_PROOFS", "yes".into());
        let get = |k: &str| env.get(k).cloned();
        assert!(ChainConfig::from_env(Network::Anvil, &get).is_err());
    }

    #[test]
    fn missing_and_bad_values_are_named() {
        let mut env = anvil_env();
        env.remove("KEEPER_KEY");
        let get = |k: &str| env.get(k).cloned();
        let e = ChainConfig::from_env(Network::Anvil, &get).unwrap_err();
        assert!(e.to_string().contains("KEEPER_KEY"));

        let mut env = anvil_env();
        env.insert("VOUCHER_SIGNER_KEY", "0x1234".into());
        let get = |k: &str| env.get(k).cloned();
        let e = ChainConfig::from_env(Network::Anvil, &get).unwrap_err();
        assert!(e.to_string().contains("VOUCHER_SIGNER_KEY"));
        assert!(!e.to_string().contains("0x1234"));

        let mut env = anvil_env();
        env.insert("WALLET_SEED", "not a real phrase".into());
        let get = |k: &str| env.get(k).cloned();
        assert!(ChainConfig::from_env(Network::Anvil, &get)
            .unwrap_err()
            .to_string()
            .contains("WALLET_SEED"));

        let env = anvil_env();
        let get = |k: &str| env.get(k).cloned();
        assert!(matches!(
            ChainConfig::from_env(Network::Sepolia, &get),
            Err(ConfigError::Missing("CHAIN_RPC_URL"))
        ));
    }

    #[test]
    fn debug_never_shows_secrets() {
        let mut env = anvil_env();
        env.insert(
            "SEPOLIA_RPC_URL",
            "https://eth-sepolia.example.com/v2/SECRETKEY".into(),
        );
        let get = |k: &str| env.get(k).cloned();
        let c = ChainConfig::from_env(Network::Sepolia, &get).unwrap();
        let shown = format!("{c:?}");
        for k in ANVIL_KEYS {
            assert!(!shown.contains(&k[2..]), "key leaked");
        }
        assert!(!shown.contains("junk"), "seed leaked");
        assert!(!shown.contains("SECRETKEY"), "rpc key leaked");
        assert!(shown.contains("eth-sepolia.example.com"));
    }

    #[test]
    fn url_redaction() {
        assert_eq!(redact_url("http://127.0.0.1:8545"), "http://127.0.0.1:8545");
        assert_eq!(redact_url("https://h.io/v2/abc"), "https://h.io/<redacted>");
        assert_eq!(
            redact_url("https://user:pw@h.io/x"),
            "https://h.io/<redacted>"
        );
        assert_eq!(redact_url("h.io/abc"), "<redacted>");
    }
}
