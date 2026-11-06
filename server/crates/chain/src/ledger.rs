//! The synchronous facade the server's city thread uses (spec §3.2 `Ledger`): `submit` only enqueues, `poll` only
//! drains a channel. All network work happens on this crate's own thread and tokio runtime.

use crate::balances::{self, Watched};
use crate::config::{ChainConfig, ConfigError, Network};
use crate::deployments::{Deployments, DeploymentsError};
use crate::draw;
use crate::exec::{self, Shared, Status};
use crate::gas::GasLedger;
use crate::indexer;
use crate::intents::IntentTable;
use crate::revert::ErrorBook;
use crate::rpc;
use crate::store::StoreError;
use crate::types::{Intent, IntentExt, Observation, Observed, PlayerId, NOT_A_LOG};
use crate::wallets::{HdRoot, WalletBook, WalletError};
use alloy::providers::Provider;
use std::collections::HashSet;
use std::sync::atomic::Ordering;
use std::sync::{mpsc as std_mpsc, Arc, Mutex};
use std::time::Duration;
use tokio::sync::{mpsc, oneshot};

#[derive(Debug, thiserror::Error)]
pub enum ChainError {
    #[error(transparent)]
    Config(#[from] ConfigError),
    #[error(transparent)]
    Deployments(#[from] DeploymentsError),
    #[error(transparent)]
    Store(#[from] StoreError),
    #[error(transparent)]
    Wallet(#[from] WalletError),
    #[error("chain node: {0}")]
    Rpc(String),
    #[error("{0}")]
    Other(String),
}

/// A snapshot of the chain link's health, for `/health` and the console.
#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize)]
pub struct ChainStatus {
    pub network: &'static str,
    pub chain_id: u64,
    pub head: u64,
    pub confirmed: u64,
    pub indexed: u64,
    pub in_flight: u64,
    pub last_error: Option<String>,
}

enum Command {
    Submit(Intent),
}

/// Tallyport's chain link. Create one with [`ChainLedger::start`]; drop it (or call [`ChainLedger::shutdown`]) to stop.
pub struct ChainLedger {
    commands: mpsc::UnboundedSender<Command>,
    observations: std_mpsc::Receiver<Observed>,
    /// Failures noticed on this side (e.g. the runtime stopped), delivered by the next `poll`.
    local: Vec<Observed>,
    watched: Watched,
    wallets: Arc<Mutex<WalletBook>>,
    status: Arc<Status>,
    network: Network,
    chain_id: u64,
    stop: Option<oneshot::Sender<()>>,
    thread: Option<std::thread::JoinHandle<()>>,
}

impl std::fmt::Debug for ChainLedger {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ChainLedger")
            .field("status", &self.status())
            .finish_non_exhaustive()
    }
}

impl ChainLedger {
    /// Loads deployments and local state, checks the node is on the configured chain, then starts the executor,
    /// the indexer and the balance reader on a dedicated thread. Returns once the link is up (or failed to come up).
    pub fn start(cfg: ChainConfig) -> Result<ChainLedger, ChainError> {
        std::fs::create_dir_all(&cfg.data_dir).map_err(|e| StoreError::Io {
            path: cfg.data_dir.clone(),
            source: e,
        })?;
        let dep = Deployments::load(&cfg.deployments_path, cfg.chain_id)?;
        let errors = Arc::new(match &cfg.abi_dir {
            Some(dir) => ErrorBook::from_forge_out(dir),
            None => ErrorBook::default(),
        });
        let root = HdRoot::from_phrase(cfg.secrets.wallet_seed.expose())
            .map_err(|e| ChainError::Config(ConfigError::Invalid("WALLET_SEED", e)))?;
        let mut book = WalletBook::open(&cfg.data_dir, root)?;
        recover_data_dir(&cfg, &mut book)?;
        let wallets = Arc::new(Mutex::new(book));
        let intents = IntentTable::open(&cfg.data_dir)?;
        let gas = GasLedger::open(&cfg.data_dir)?;
        let checkpoint = indexer::initial_checkpoint(
            &cfg.data_dir,
            cfg.chain_id,
            cfg.resume_after_block,
            dep.start_block,
        )
        .map_err(ChainError::Other)?;
        let provider = rpc::connect(&cfg.rpc_url).map_err(ChainError::Rpc)?;

        tracing::info!(
            network = cfg.network.name(),
            chain_id = cfg.chain_id,
            keeper = %cfg.secrets.keeper.address(),
            ticket_signer = %cfg.secrets.ticket_signer.address(),
            voucher_signer = %cfg.secrets.voucher_signer.address(),
            errors_known = errors.len(),
            from_block = checkpoint + 1,
            "chain link starting"
        );

        let (out_tx, out_rx) = std_mpsc::channel();
        let (cmd_tx, mut cmd_rx) = mpsc::unbounded_channel::<Command>();
        let (stop_tx, stop_rx) = oneshot::channel::<()>();
        let (ready_tx, ready_rx) = std_mpsc::channel::<Result<(), ChainError>>();
        let status = Arc::new(Status::default());
        let watched: Watched = Arc::new(Mutex::new(None));
        let (network, chain_id) = (cfg.network, cfg.chain_id);

        let shared = Arc::new(Shared::new(
            cfg,
            dep,
            provider,
            errors,
            wallets.clone(),
            intents,
            gas,
            out_tx,
            status.clone(),
        ));
        let watched_bg = watched.clone();
        let thread = std::thread::Builder::new()
            .name("tallyport-chain".into())
            .spawn(move || {
                let rt = match tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build()
                {
                    Ok(rt) => rt,
                    Err(e) => {
                        let _ =
                            ready_tx.send(Err(ChainError::Other(format!("tokio runtime: {e}"))));
                        return;
                    }
                };
                rt.block_on(async move {
                    // The node must be the chain the config and deployments are for.
                    let id = tokio::time::timeout(
                        Duration::from_secs(15),
                        shared.provider.get_chain_id(),
                    )
                    .await;
                    let check = match id {
                        Ok(Ok(id)) if id == shared.cfg.chain_id => Ok(()),
                        Ok(Ok(id)) => Err(ChainError::Rpc(format!(
                            "node is on chain {id}, config says {}",
                            shared.cfg.chain_id
                        ))),
                        Ok(Err(e)) => Err(ChainError::Rpc(e.to_string())),
                        Err(_) => Err(ChainError::Rpc("no answer from the node in 15 s".into())),
                    };
                    let ok = check.is_ok();
                    let _ = ready_tx.send(check);
                    if !ok {
                        return;
                    }
                    let tasks = vec![
                        tokio::spawn(indexer::run(shared.clone(), checkpoint)),
                        tokio::spawn(balances::run(shared.clone(), watched_bg)),
                    ];
                    let unfinished = shared.intents.lock().expect("intents lock").unfinished();
                    for (intent, _) in unfinished {
                        tokio::spawn(exec::resume(shared.clone(), intent));
                    }
                    let mut stop_rx = stop_rx;
                    loop {
                        tokio::select! {
                            cmd = cmd_rx.recv() => match cmd {
                                Some(Command::Submit(intent)) => {
                                    tokio::spawn(exec::submit(shared.clone(), intent));
                                }
                                None => break,
                            },
                            _ = &mut stop_rx => break,
                        }
                    }
                    for t in tasks {
                        t.abort();
                    }
                    tracing::info!("chain link stopped");
                });
            })
            .map_err(|e| ChainError::Other(format!("can't start the chain thread: {e}")))?;

        match ready_rx.recv_timeout(Duration::from_secs(20)) {
            Ok(Ok(())) => {}
            Ok(Err(e)) => {
                let _ = thread.join();
                return Err(e);
            }
            Err(_) => {
                return Err(ChainError::Rpc(
                    "the chain link didn't come up in 20 s".into(),
                ))
            }
        }
        Ok(ChainLedger {
            commands: cmd_tx,
            observations: out_rx,
            local: vec![],
            watched,
            wallets,
            status,
            network,
            chain_id,
            stop: Some(stop_tx),
            thread: Some(thread),
        })
    }

    /// Asks for something to happen on chain. Never blocks; the outcome comes back from [`poll`](Self::poll).
    pub fn submit(&mut self, intent: Intent) {
        let key = intent.key();
        if self.commands.send(Command::Submit(intent)).is_err() {
            self.local.push(Observed {
                block: self.status.confirmed.load(Ordering::Relaxed),
                log_index: NOT_A_LOG,
                time: 0,
                observed: Observation::IntentFailed {
                    reference: key,
                    reason: "the chain link has stopped".into(),
                },
            });
        }
    }

    /// What the chain did since the last call. Log-derived observations are confirmed and in (block, log index)
    /// order; see [`Observed`] for synthetic ones.
    pub fn poll(&mut self) -> Vec<Observed> {
        let mut v = std::mem::take(&mut self.local);
        v.extend(self.observations.try_iter());
        v
    }

    /// Limits balance reads to these players (e.g. the connected ones). Until called, every player is read.
    pub fn watch_players(&mut self, players: impl IntoIterator<Item = PlayerId>) {
        *self.watched.lock().expect("watched lock") =
            Some(players.into_iter().collect::<HashSet<_>>());
    }

    /// The player's wallet address, if they have one (assigned by `Intent::EnsureWallet`).
    pub fn wallet_address(&self, player: &str) -> Option<String> {
        self.wallets
            .lock()
            .expect("wallets lock")
            .get(player)
            .map(|w| w.address.to_string())
    }

    pub fn status(&self) -> ChainStatus {
        ChainStatus {
            network: self.network.name(),
            chain_id: self.chain_id,
            head: self.status.head.load(Ordering::Relaxed),
            confirmed: self.status.confirmed.load(Ordering::Relaxed),
            indexed: self.status.checkpoint.load(Ordering::Relaxed),
            in_flight: self.status.in_flight.load(Ordering::Relaxed),
            last_error: self.status.last_error.lock().expect("status lock").clone(),
        }
    }

    /// Stops the chain thread and waits for it. Transactions already sent stay sent; unfinished intents resume at
    /// the next start.
    pub fn shutdown(mut self) {
        self.stop_thread();
    }

    fn stop_thread(&mut self) {
        if let Some(stop) = self.stop.take() {
            let _ = stop.send(());
        }
        if let Some(t) = self.thread.take() {
            let _ = t.join();
        }
    }
}

impl Drop for ChainLedger {
    fn drop(&mut self) {
        self.stop_thread();
    }
}

/// Rebuilds what a lost data dir held from what the save knows (`cfg.recovery`): player wallets first, then the
/// tickets of committed, unclaimed draws (the winner's proof is built from them). Records that are already there are
/// checked, not rewritten; any disagreement stops the start.
fn recover_data_dir(cfg: &ChainConfig, book: &mut WalletBook) -> Result<(), ChainError> {
    let recovered = book.recover(&cfg.recovery.wallets)?;
    if recovered > 0 {
        tracing::warn!(
            recovered,
            "wallets.jsonl was missing wallets the save has; rebuilt them from the save"
        );
    }
    for (week, tickets) in &cfg.recovery.draws {
        if tickets.is_empty() || draw::load(&cfg.data_dir, *week)?.is_some() {
            continue;
        }
        let mut entries = Vec::with_capacity(tickets.len());
        for (player, from, to) in tickets {
            let address = match book.get(player) {
                Some(w) => w.address,
                None => {
                    tracing::warn!(
                        week,
                        player = %player,
                        "a draw ticket's player has no wallet in the save; giving them the next one"
                    );
                    book.ensure(player)?.address
                }
            };
            entries.push(draw::Entry {
                player: player.clone(),
                address,
                from: *from,
                to: *to,
            });
        }
        let root = draw::tree(&entries)
            .ok_or_else(|| ChainError::Other(format!("week {week}'s tickets make no tree")))?
            .root();
        draw::save(
            &cfg.data_dir,
            &draw::Committed {
                week: *week,
                root,
                entries,
            },
        )?;
        tracing::warn!(week, root = %root, "draw tickets were missing; rebuilt them from the save");
    }
    Ok(())
}
