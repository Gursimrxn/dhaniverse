//! The Tallyport town server with its chain: the `chain` crate's `ChainLedger` and `WorldIdVerifier` plugged into the
//! game server's `Ledger` and `HumanVerifier` seams, and the start-up that picks offline, anvil or Sepolia.

use chain::config::{ChainConfig, Network};
use chain::deployments::Deployments;
use chain::{ChainLedger, WorldIdVerifier};
use rules::chain::{ChainMode, HumanId, Intent, Observed};
use serde_json::{json, Value};
use server::app::ServerConfig;
use server::http::VerifyDesk;
use server::hub::Links;
use server::ledger::{HumanVerifier, Ledger, OfflineVerifier};
use server::world::World;
use std::path::{Path, PathBuf};
use std::sync::Arc;

/// `ChainLedger` as the hub's `Ledger`: `submit` enqueues, `poll` drains, neither blocks.
pub struct ChainLink(pub ChainLedger);

impl Ledger for ChainLink {
    fn submit(&mut self, intent: Intent) {
        self.0.submit(intent);
    }

    fn poll(&mut self) -> Vec<Observed> {
        self.0.poll()
    }
}

/// World ID 4 as the hub's `HumanVerifier`.
pub struct WorldId(pub WorldIdVerifier, pub Option<String>);

impl HumanVerifier for WorldId {
    fn verify(&self, player_wallet: &str, proof: &Value) -> Result<HumanId, String> {
        self.0.verify(player_wallet, proof)
    }

    fn session_context(&self, player: &str, player_wallet: &str) -> Result<Value, String> {
        let c = self.0.session_context(player, player_wallet)?;
        Ok(json!({
            "app_id": c.app_id,
            "action": c.action,
            "environment": c.environment,
            "allow_legacy_proofs": c.allow_legacy_proofs,
            "rp_context": {
                "rp_id": c.rp_id,
                "nonce": c.nonce,
                "created_at": c.created_at,
                "expires_at": c.expires_at,
                "signature": c.signature,
            },
            "rehearsal": false,
        }))
    }

    fn app_id(&self) -> Option<String> {
        self.1.clone()
    }

    fn can_verify(&self) -> bool {
        true
    }
}

pub fn network(mode: ChainMode) -> Option<Network> {
    match mode {
        ChainMode::Offline => None,
        ChainMode::Anvil => Some(Network::Anvil),
        ChainMode::Sepolia => Some(Network::Sepolia),
    }
}

/// Where the chain crate keeps wallets, sent intents and its checkpoint when `CHAIN_DATA_DIR` isn't set: beside the
/// save, so the two always travel together (`town.jsonl` → `town.chain-anvil/`).
pub fn default_data_dir(save: &Path, network: Network) -> PathBuf {
    let stem = save.file_stem().and_then(|s| s.to_str()).unwrap_or("save");
    let dir = save
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    dir.join(format!("{stem}.chain-{}", network.name()))
}

/// The chain config for a server config: keys and RPC from the environment, the deployments file from
/// `--deployments` when given, the data dir beside the save unless `CHAIN_DATA_DIR` says otherwise.
pub fn chain_config(server: &ServerConfig, network: Network) -> Result<ChainConfig, String> {
    let mut cfg = ChainConfig::from_process_env(network).map_err(|e| e.to_string())?;
    if std::env::var_os("CHAIN_DATA_DIR").is_none() {
        cfg.data_dir = default_data_dir(&server.save, network);
    }
    if let Some(d) = &server.http.deployments {
        if std::env::var_os("CHAIN_DEPLOYMENTS").is_none()
            && std::env::var_os("DEPLOYMENTS").is_none()
        {
            cfg.deployments_path = d.clone();
        }
    }
    if cfg.abi_dir.is_none() {
        let out = cfg
            .deployments_path
            .parent()
            .and_then(Path::parent)
            .map(|c| c.join("out"));
        cfg.abi_dir = out.filter(|o| o.is_dir());
    }
    Ok(cfg)
}

/// The links for a town on a chain. The indexer starts just before the last chain log the save holds (the world
/// drops what it has already seen), or at the deploy block for a save that has seen none, so a save and the chain
/// can never drift apart, whatever happened to the chain data dir.
pub fn chain_links(
    world: &World,
    server: &ServerConfig,
    public_url: &str,
    mut cfg: ChainConfig,
) -> Result<Links, String> {
    let start = match world.state.chain.cursor {
        Some((block, _)) => block.saturating_sub(1),
        None => Deployments::load(&cfg.deployments_path, cfg.chain_id)
            .map_err(|e| e.to_string())?
            .start_block
            .saturating_sub(1),
    };
    if cfg.resume_after_block.is_none() {
        cfg.resume_after_block = Some(start);
    }
    cfg.recovery = recovery(world)?;
    // Flags (--world-rp-id, --world-app-id) win over the environment.
    let mut world_id = cfg.world_id.clone();
    if let Some(w) = world_id.as_mut() {
        if let Some(rp) = &server.world_rp_id {
            w.rp_id.clone_from(rp);
        }
        if let Some(app) = &server.http.world_app_id {
            w.app_id = Some(app.clone());
        }
    }
    let ledger = ChainLedger::start(cfg).map_err(|e| format!("chain: {e}"))?;
    let verifier: Arc<dyn HumanVerifier> = match world_id {
        Some(w) => {
            let app_id = w.app_id.clone();
            Arc::new(WorldId(WorldIdVerifier::new(w), app_id))
        }
        None => {
            eprintln!(
                "World ID isn't configured (RP_SIGNING_KEY, WORLD_RP_ID): the Town Pass {}",
                if server.debug {
                    "takes rehearsal proofs only (--debug)"
                } else {
                    "is closed; set them, or rehearse with --debug"
                }
            );
            Arc::new(OfflineVerifier::new(server.debug))
        }
    };
    Ok(Links {
        ledger: Box::new(ChainLink(ledger)),
        offline: None,
        verifier,
        verify: Arc::new(VerifyDesk::new(public_url)),
        world_app_id: None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn data_dir_sits_beside_the_save() {
        assert_eq!(
            default_data_dir(Path::new("saves/town.jsonl"), Network::Anvil),
            PathBuf::from("saves/town.chain-anvil")
        );
        assert_eq!(
            default_data_dir(Path::new("save.jsonl"), Network::Sepolia),
            PathBuf::from("./save.chain-sepolia")
        );
    }

    #[test]
    fn modes_map_to_networks() {
        assert_eq!(network(ChainMode::Offline), None);
        assert_eq!(network(ChainMode::Anvil), Some(Network::Anvil));
        assert_eq!(network(ChainMode::Sepolia), Some(Network::Sepolia));
    }
}

/// What the save knows that the chain's data dir also keeps (every player's wallet, each committed and unclaimed
/// draw's tickets), so a town restored from Arkiv on a machine without that dir gets it rebuilt, not started empty.
pub fn recovery(world: &World) -> Result<chain::config::Recovery, String> {
    let mut wallets = Vec::new();
    for (account, player) in world.state.life.players() {
        if let Some(address) = &player.wallet {
            let address = address
                .parse()
                .map_err(|_| format!("the save's wallet for {account} isn't an address: {address}"))?;
            wallets.push((account.clone(), address));
        }
    }
    let draws = world
        .state
        .games
        .draws
        .values()
        .filter(|d| d.committed && !d.claimed)
        .map(|d| {
            let tickets = d
                .tickets
                .iter()
                .map(|t| (t.player.clone(), t.from, t.to))
                .collect();
            (d.week, tickets)
        })
        .collect();
    Ok(chain::config::Recovery { wallets, draws })
}
