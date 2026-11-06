//! `contracts/deployments/<network>.json`, written by `script/Deploy.s.sol` (spec §1):
//! `{"chainId":…, "contracts":{"FoodToken":"0x…", …}, "uniswap":{…}, "usdc":"0x…", "ens":{…}, "startBlock":…}`.
//!
//! Only the shape is fixed here; every address comes from the file.

use alloy::primitives::{keccak256, Address, B256};
use alloy::sol_types::SolValue;
use serde::Deserialize;
use serde_json::Value;
use std::collections::BTreeMap;
use std::path::Path;

use crate::bindings::PoolKey;

#[derive(Debug, thiserror::Error)]
pub enum DeploymentsError {
    #[error("can't read {0}: {1}")]
    Read(String, std::io::Error),
    #[error("{0} is not valid deployments JSON: {1}")]
    Parse(String, serde_json::Error),
    #[error("deployments are for chain {found}, but the config says {expected}")]
    WrongChain { expected: u64, found: u64 },
    #[error("deployments have no {0}")]
    Missing(String),
    #[error("deployments field {0} is not an address: {1}")]
    BadAddress(String, String),
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Raw {
    chain_id: u64,
    #[serde(default)]
    contracts: BTreeMap<String, Value>,
    #[serde(default)]
    uniswap: BTreeMap<String, Value>,
    usdc: Option<String>,
    #[serde(default)]
    ens: BTreeMap<String, Value>,
    #[serde(default)]
    start_block: Option<u64>,
    #[serde(default)]
    keys: BTreeMap<String, Value>,
}

/// How a player's quest swap is routed.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SwapRoute {
    /// Uniswap's UniversalRouter (`V4_SWAP`), paying through Permit2: Sepolia, and anvil if the real router is deployed.
    UniversalRouter { router: Address, permit2: Address },
    /// v4-core's `PoolSwapTest` (a local chain without the UniversalRouter). No on-chain `min_out`; checked afterwards.
    PoolSwapTest { router: Address },
}

/// How quest pools are shaped: a plain v4 pool of the quest token against USDC (spec §2.9).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct QuestShape {
    pub fee: u32,
    pub tick_spacing: i32,
    pub hooks: Address,
}

impl QuestShape {
    /// The pool of `token` against `usdc`.
    pub fn pool(&self, usdc: Address, token: Address) -> QuestPool {
        let (currency0, currency1) = if usdc < token {
            (usdc, token)
        } else {
            (token, usdc)
        };
        let key = PoolKey {
            currency0,
            currency1,
            fee: alloy::primitives::Uint::<24, 1>::from(self.fee & 0xff_ffff),
            tickSpacing: alloy::primitives::Signed::<24, 1>::try_from(self.tick_spacing as i64)
                .unwrap_or(alloy::primitives::Signed::<24, 1>::ZERO),
            hooks: self.hooks,
        };
        QuestPool {
            id: pool_id(&key),
            key,
            token,
        }
    }
}

/// A quest pool: a quest token (e.g. MANGO) against USDC.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct QuestPool {
    pub key: PoolKey,
    pub id: B256,
    pub token: Address,
}

#[derive(Clone, Debug)]
pub struct Deployments {
    pub chain_id: u64,
    pub start_block: u64,
    pub usdc: Address,
    /// Every Tallyport contract by name.
    pub contracts: BTreeMap<String, Address>,
    pub pool_manager: Option<Address>,
    pub swap_route: Option<SwapRoute>,
    /// The demo quest token's pool (`contracts.QuestToken` / USDC).
    pub quest_pool: Option<QuestPool>,
    /// Fee, tick spacing and hooks of quest pools (each campaign's token is paired with USDC this way).
    pub quest_shape: QuestShape,
    /// Uniswap's V4Quoter, used to price a swap when the server leaves `min_out` at 0.
    pub quoter: Option<Address>,
    /// `ens.parent` (e.g. `tallyport.eth`), overriding the config's default.
    pub ens_parent: Option<String>,
    /// `ens.coinType` (60), overriding the config's default.
    pub ens_coin_type: Option<u64>,
    /// The city's ENS registry (registers `label.<parent>`).
    pub ens_registry: Option<Address>,
    /// `ens.parentLabel` (e.g. `tallyport`), part of each player resolver's salt.
    pub ens_parent_label: Option<String>,
    /// ENS's VerifiableFactory and the PermissionedResolver implementation: each player's own resolver.
    pub ens_factory: Option<Address>,
    pub ens_resolver_impl: Option<Address>,
    /// `keys.admin`: holds the upgrade role on player resolvers (overridable with `ENS_ADMIN_ADDRESS`).
    pub ens_admin: Option<Address>,
}

fn addr(field: &str, v: &Value) -> Result<Option<Address>, DeploymentsError> {
    match v {
        Value::String(s) if s.starts_with("0x") && s.len() == 42 => s
            .parse()
            .map(Some)
            .map_err(|_| DeploymentsError::BadAddress(field.into(), s.clone())),
        // Comments, nested objects, numbers: not an address, skipped.
        _ => Ok(None),
    }
}

fn first_addr(
    map: &BTreeMap<String, Value>,
    names: &[&str],
    prefix: &str,
) -> Result<Option<Address>, DeploymentsError> {
    for n in names {
        if let Some(v) = map.get(*n) {
            if let Some(a) = addr(&format!("{prefix}.{n}"), v)? {
                return Ok(Some(a));
            }
        }
    }
    Ok(None)
}

/// v4's `PoolId`: `keccak256(abi.encode(poolKey))`.
pub fn pool_id(key: &PoolKey) -> B256 {
    keccak256(key.abi_encode())
}

impl Deployments {
    /// The quest pool for a campaign's quest token.
    pub fn quest_pool_for(&self, token: Address) -> QuestPool {
        self.quest_shape.pool(self.usdc, token)
    }

    pub fn load(path: &Path, expected_chain_id: u64) -> Result<Deployments, DeploymentsError> {
        let raw = std::fs::read_to_string(path)
            .map_err(|e| DeploymentsError::Read(path.display().to_string(), e))?;
        Deployments::parse(&raw, expected_chain_id).map_err(|e| match e {
            DeploymentsError::Parse(_, err) => {
                DeploymentsError::Parse(path.display().to_string(), err)
            }
            other => other,
        })
    }

    pub fn parse(json: &str, expected_chain_id: u64) -> Result<Deployments, DeploymentsError> {
        let raw: Raw = serde_json::from_str(json)
            .map_err(|e| DeploymentsError::Parse("deployments".into(), e))?;
        if raw.chain_id != expected_chain_id {
            return Err(DeploymentsError::WrongChain {
                expected: expected_chain_id,
                found: raw.chain_id,
            });
        }
        let mut contracts = BTreeMap::new();
        for (name, v) in &raw.contracts {
            if let Some(a) = addr(&format!("contracts.{name}"), v)? {
                contracts.insert(name.clone(), a);
            }
        }
        let usdc = match &raw.usdc {
            Some(s) => s
                .parse()
                .map_err(|_| DeploymentsError::BadAddress("usdc".into(), s.clone()))?,
            None => *contracts
                .get("MockUSDC")
                .or_else(|| contracts.get("USDC"))
                .ok_or_else(|| DeploymentsError::Missing("usdc".into()))?,
        };
        let u = &raw.uniswap;
        let pool_manager = first_addr(u, &["poolManager", "PoolManager"], "uniswap")?;
        let router = first_addr(u, &["universalRouter", "UniversalRouter"], "uniswap")?;
        let permit2 = first_addr(u, &["permit2", "Permit2"], "uniswap")?;
        let swap_test = first_addr(
            u,
            &["poolSwapTest", "PoolSwapTest", "swapRouter"],
            "uniswap",
        )?;
        let swap_route = match (router, permit2, swap_test) {
            (Some(router), Some(permit2), _) => {
                Some(SwapRoute::UniversalRouter { router, permit2 })
            }
            (_, _, Some(router)) => Some(SwapRoute::PoolSwapTest { router }),
            _ => None,
        };

        let quest_token = first_addr(
            &raw.contracts,
            &["QuestToken", "MANGO", "Mango"],
            "contracts",
        )?;
        // `uniswap.questPool` may spell out the pool shape; otherwise it's the spec's plain pool (fee 3000, spacing 60).
        let spec = u.get("questPool").and_then(Value::as_object);
        let num = |k: &str, d: i64| {
            spec.and_then(|o| o.get(k))
                .and_then(Value::as_i64)
                .unwrap_or(d)
        };
        let quest_shape = QuestShape {
            fee: u32::try_from(num("fee", 3_000))
                .map_err(|_| DeploymentsError::Missing("a valid uniswap.questPool.fee".into()))?,
            tick_spacing: i32::try_from(num("tickSpacing", 60)).map_err(|_| {
                DeploymentsError::Missing("a valid uniswap.questPool.tickSpacing".into())
            })?,
            hooks: spec
                .and_then(|o| o.get("hooks"))
                .map(|v| addr("uniswap.questPool.hooks", v))
                .transpose()?
                .flatten()
                .unwrap_or(Address::ZERO),
        };
        let quest_pool = quest_token.map(|t| quest_shape.pool(usdc, t));
        if let (Some(qp), Some(given)) = (
            &quest_pool,
            spec.and_then(|o| o.get("poolId").or(o.get("id")))
                .and_then(Value::as_str),
        ) {
            let given: B256 = given.parse().map_err(|_| {
                DeploymentsError::BadAddress("uniswap.questPool.id".into(), given.into())
            })?;
            if given != qp.id {
                return Err(DeploymentsError::Missing(format!(
                    "a quest pool key matching uniswap.questPool.id {given} (computed {})",
                    qp.id
                )));
            }
        }
        let quoter = first_addr(u, &["v4Quoter", "V4Quoter", "quoter"], "uniswap")?;

        let e = &raw.ens;
        Ok(Deployments {
            chain_id: raw.chain_id,
            start_block: raw.start_block.unwrap_or(0),
            usdc,
            contracts,
            pool_manager,
            swap_route,
            quest_pool,
            quest_shape,
            quoter,
            ens_parent: e.get("parent").and_then(Value::as_str).map(str::to_string),
            ens_coin_type: e.get("coinType").and_then(Value::as_u64),
            ens_registry: first_addr(e, &["registry", "cityRegistry"], "ens")?,
            ens_parent_label: e
                .get("parentLabel")
                .and_then(Value::as_str)
                .map(str::to_string),
            ens_factory: first_addr(e, &["factory"], "ens")?,
            ens_resolver_impl: first_addr(e, &["resolverImpl"], "ens")?,
            ens_admin: first_addr(&raw.keys, &["admin"], "keys")?,
        })
    }

    /// A Tallyport contract's address by name, or a clear error.
    pub fn contract(&self, name: &str) -> Result<Address, DeploymentsError> {
        self.contracts
            .get(name)
            .copied()
            .ok_or_else(|| DeploymentsError::Missing(format!("contracts.{name}")))
    }

    /// Every address the indexer watches for our own events (not the PoolManager: it's filtered by pool id).
    pub fn watched(&self) -> Vec<Address> {
        const WATCH: [&str; 9] = [
            "MealCounter",
            "Farm",
            "Treasury",
            "HousePool",
            "CampaignEscrow",
            "FloatManager",
            "SpiceMerchant",
            "LuckyLedger",
            "FoodHook",
        ];
        WATCH
            .iter()
            .filter_map(|n| self.contracts.get(*n).copied())
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = r#"{
      "chainId": 31337,
      "_comment": "anvil",
      "contracts": {
        "FoodToken": "0x5FbDB2315678afecb367f032d93F642f64180aa3",
        "MealCounter": "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512",
        "HousePool": "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0",
        "QuestToken": "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9",
        "note": "not an address"
      },
      "uniswap": {
        "_source": "local",
        "poolManager": "0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9",
        "poolSwapTest": "0x5FC8d32690cc91D4c39d9d3abcBD16989F875707"
      },
      "usdc": "0x0165878A594ca255338adfa4d48449f69242Eb8F",
      "ens": {},
      "startBlock": 7
    }"#;

    #[test]
    fn parses_the_spec_shape() {
        let d = Deployments::parse(SAMPLE, 31_337).unwrap();
        assert_eq!(d.start_block, 7);
        assert_eq!(d.contracts.len(), 4);
        assert!(d.contract("Farm").is_err());
        assert!(matches!(d.swap_route, Some(SwapRoute::PoolSwapTest { .. })));
        let qp = d.quest_pool.clone().unwrap();
        assert!(qp.key.currency0 < qp.key.currency1);
        assert_eq!(qp.id, pool_id(&qp.key));
        assert_eq!(d.watched().len(), 2);
    }

    #[test]
    fn wrong_chain_is_refused() {
        assert!(matches!(
            Deployments::parse(SAMPLE, 11_155_111),
            Err(DeploymentsError::WrongChain { .. })
        ));
    }

    #[test]
    fn universal_router_preferred_when_present() {
        let j = SAMPLE.replace(
            "\"poolSwapTest\"",
            "\"universalRouter\": \"0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b\", \"permit2\": \"0x000000000022D473030F116dDEE9F6B43aC78BA3\", \"x\"",
        );
        let d = Deployments::parse(&j, 31_337).unwrap();
        assert!(matches!(
            d.swap_route,
            Some(SwapRoute::UniversalRouter { .. })
        ));
    }

    #[test]
    fn pool_id_matches_v4() {
        // keccak256(abi.encode(PoolKey)) is five 32-byte words.
        let key = PoolKey {
            currency0: Address::repeat_byte(1),
            currency1: Address::repeat_byte(2),
            fee: alloy::primitives::Uint::<24, 1>::from(3_000u32),
            tickSpacing: alloy::primitives::Signed::<24, 1>::try_from(60i64).unwrap(),
            hooks: Address::ZERO,
        };
        assert_eq!(key.abi_encode().len(), 160);
        let mut manual = Vec::new();
        manual.extend_from_slice(
            B256::left_padding_from(Address::repeat_byte(1).as_slice()).as_slice(),
        );
        manual.extend_from_slice(
            B256::left_padding_from(Address::repeat_byte(2).as_slice()).as_slice(),
        );
        manual.extend_from_slice(&alloy::primitives::U256::from(3_000u64).to_be_bytes::<32>());
        manual.extend_from_slice(&alloy::primitives::U256::from(60u64).to_be_bytes::<32>());
        manual.extend_from_slice(&[0u8; 32]);
        assert_eq!(pool_id(&key), keccak256(&manual));
    }
}
