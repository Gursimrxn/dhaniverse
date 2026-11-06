//! The executor: takes intents, plans them, sends their transactions through the per-key queues, and reports what
//! only it can see (wallets, names, failures). Contract events are reported by the indexer, not here.

use crate::bindings::IERC20;
use crate::config::ChainConfig;
use crate::deployments::{Deployments, QuestPool};
use crate::draw;
use crate::eip712::VoucherSigner;
use crate::gas::{utc_day, GasLedger, TopUp};
use crate::intents::{Admission, IntentTable};
use crate::plan::{self, After, DrawPrep, PlanCtx, PlayerInfo, Reads, Sender};
use crate::revert::ErrorBook;
use crate::rpc::{view, ChainReads};
use crate::sender::{SendConfig, SenderHandle, TxOutcome};
use crate::types::{Intent, IntentExt, Observation, Observed, NOT_A_LOG};
use crate::wallets::WalletBook;
use alloy::primitives::{Address, Bytes, B256};
use alloy::providers::{DynProvider, Provider};
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

/// Live counters, readable from the server thread.
#[derive(Debug, Default)]
pub struct Status {
    /// Latest block the node reported.
    pub head: AtomicU64,
    /// Latest block with enough confirmations.
    pub confirmed: AtomicU64,
    /// Last block the indexer fully processed.
    pub checkpoint: AtomicU64,
    /// Intents being worked on.
    pub in_flight: AtomicU64,
    pub last_error: Mutex<Option<String>>,
}

impl Status {
    pub(crate) fn error(&self, e: impl Into<String>) {
        let e = e.into();
        tracing::warn!(error = %e, "chain");
        *self.last_error.lock().expect("status lock") = Some(e);
    }
}

/// Everything the runtime's tasks share.
pub(crate) struct Shared {
    pub cfg: ChainConfig,
    pub dep: Deployments,
    pub provider: DynProvider,
    pub errors: Arc<ErrorBook>,
    pub wallets: Arc<Mutex<WalletBook>>,
    pub intents: Mutex<IntentTable>,
    pub gas: Mutex<GasLedger>,
    pub out: std::sync::mpsc::Sender<Observed>,
    pub status: Arc<Status>,
    pub tickets: VoucherSigner,
    pub vouchers: VoucherSigner,
    pub send_cfg: Arc<SendConfig>,
    /// Quest pools the indexer follows, by pool id (the demo pool, plus every live campaign's).
    pub quest_pools: Mutex<HashMap<B256, QuestPool>>,
    /// Set when a new campaign appears, so the indexer re-reads the quest pools.
    pub pools_stale: AtomicBool,
    /// ERC-20 symbol and decimals, by token.
    token_meta: Mutex<HashMap<Address, (String, u8)>>,
    senders: Mutex<HashMap<Sender, SenderHandle>>,
    player_locks: Mutex<HashMap<String, Arc<tokio::sync::Mutex<()>>>>,
    repeating: Mutex<HashSet<String>>,
}

fn now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

impl Shared {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        cfg: ChainConfig,
        dep: Deployments,
        provider: DynProvider,
        errors: Arc<ErrorBook>,
        wallets: Arc<Mutex<WalletBook>>,
        intents: IntentTable,
        gas: GasLedger,
        out: std::sync::mpsc::Sender<Observed>,
        status: Arc<Status>,
    ) -> Shared {
        let tickets = VoucherSigner::new(cfg.secrets.ticket_signer.0.clone(), cfg.chain_id);
        let vouchers = VoucherSigner::new(cfg.secrets.voucher_signer.0.clone(), cfg.chain_id);
        let send_cfg = Arc::new(SendConfig {
            chain_id: cfg.chain_id,
            poll: cfg.poll_interval,
            receipt_timeout: cfg.receipt_timeout,
            max_resends: cfg.max_resends,
            max_in_flight: cfg.max_in_flight,
            fee_bump_percent: cfg.fee_bump_percent,
        });
        let pools = dep.quest_pool.iter().map(|q| (q.id, q.clone())).collect();
        Shared {
            cfg,
            dep,
            provider,
            errors,
            wallets,
            intents: Mutex::new(intents),
            gas: Mutex::new(gas),
            out,
            status,
            tickets,
            vouchers,
            send_cfg,
            quest_pools: Mutex::new(pools),
            pools_stale: AtomicBool::new(false),
            token_meta: Mutex::new(HashMap::new()),
            senders: Mutex::new(HashMap::new()),
            player_locks: Mutex::new(HashMap::new()),
            repeating: Mutex::new(HashSet::new()),
        }
    }

    /// Sends an observation to the server thread.
    pub fn emit(&self, block: u64, log_index: u64, time: u64, observed: Observation) {
        let _ = self.out.send(Observed {
            block,
            log_index,
            time,
            observed,
        });
    }

    /// An observation that doesn't come from a log, stamped with the latest confirmed block (time unknown: 0).
    pub fn emit_synthetic(&self, observed: Observation) {
        self.emit(
            self.status.confirmed.load(Ordering::Relaxed),
            NOT_A_LOG,
            0,
            observed,
        );
    }

    /// A block's timestamp, 0 if the node won't say.
    pub async fn block_time(&self, block: u64) -> u64 {
        match self.provider.get_block_by_number(block.into()).await {
            Ok(Some(b)) => b.header.timestamp,
            _ => 0,
        }
    }

    fn sender(&self, who: &Sender) -> Result<SenderHandle, String> {
        if let Some(h) = self.senders.lock().expect("senders lock").get(who) {
            return Ok(h.clone());
        }
        let s = &self.cfg.secrets;
        let signer = match who {
            Sender::Keeper => s.keeper.0.clone(),
            Sender::Names => s.names.as_ref().ok_or("NAMES_KEY is not set")?.0.clone(),
            Sender::GasStation => s
                .gas_station
                .as_ref()
                .ok_or("GAS_STATION_KEY is not set")?
                .0
                .clone(),
            Sender::Player(id) => self
                .wallets
                .lock()
                .expect("wallets lock")
                .signer(id)
                .ok_or_else(|| format!("player {id} has no wallet"))?,
        };
        let h = SenderHandle::spawn(
            self.provider.clone(),
            signer,
            self.send_cfg.clone(),
            self.errors.clone(),
        );
        self.senders
            .lock()
            .expect("senders lock")
            .insert(who.clone(), h.clone());
        Ok(h)
    }

    fn player_lock(&self, player: &str) -> Arc<tokio::sync::Mutex<()>> {
        self.player_locks
            .lock()
            .expect("locks")
            .entry(player.to_string())
            .or_default()
            .clone()
    }

    /// Waits until `block` has the configured confirmations (the indexer moves `confirmed`).
    async fn confirmed(&self, block: u64) {
        while self.status.confirmed.load(Ordering::Relaxed) < block {
            tokio::time::sleep(self.cfg.poll_interval).await;
        }
    }
}

/// Entry point for a newly submitted intent.
pub(crate) async fn submit(shared: Arc<Shared>, intent: Intent) {
    let key = intent.key();
    if let Intent::EnsureWallet { player } = &intent {
        let r = shared.wallets.lock().expect("wallets lock").ensure(player);
        match r {
            Ok(w) => shared.emit_synthetic(Observation::WalletReady {
                player: player.clone(),
                address: w.address.to_string(),
            }),
            Err(e) => fail(&shared, &intent, &e.to_string()),
        }
        return;
    }
    if intent.is_repeatable() {
        if !shared
            .repeating
            .lock()
            .expect("repeating lock")
            .insert(key.clone())
        {
            tracing::debug!(%key, "already running");
            return;
        }
    } else {
        let admitted = shared.intents.lock().expect("intents lock").admit(&intent);
        match admitted {
            Ok(Admission::Run) => {}
            Ok(Admission::AlreadyDone) => {
                tracing::info!(%key, "already done; ignored");
                return;
            }
            Ok(Admission::InFlight) => {
                tracing::debug!(%key, "already in flight; ignored");
                return;
            }
            Err(e) => {
                shared.status.error(format!("intents table: {e}"));
                shared.emit_synthetic(Observation::IntentFailed {
                    reference: intent.public_ref(),
                    reason: format!("storage: {e}"),
                });
                return;
            }
        }
    }
    run(&shared, &intent).await;
    if intent.is_repeatable() {
        shared
            .repeating
            .lock()
            .expect("repeating lock")
            .remove(&key);
    }
}

/// Re-runs an intent a previous process left pending (the contracts' ref checks stop a second payment).
pub(crate) async fn resume(shared: Arc<Shared>, intent: Intent) {
    tracing::info!(key = %intent.key(), "resuming an unfinished intent");
    run(&shared, &intent).await;
}

fn fail(shared: &Shared, intent: &Intent, reason: &str) {
    let key = intent.key();
    tracing::warn!(%key, kind = intent.kind(), %reason, "intent failed");
    if !intent.is_repeatable() {
        if let Err(e) = shared
            .intents
            .lock()
            .expect("intents lock")
            .failed(&key, reason)
        {
            shared.status.error(format!("intents table: {e}"));
        }
    }
    shared.emit_synthetic(Observation::IntentFailed {
        reference: intent.public_ref(),
        reason: reason.to_string(),
    });
}

async fn run(shared: &Arc<Shared>, intent: &Intent) {
    shared.status.in_flight.fetch_add(1, Ordering::Relaxed);
    let result = execute(shared, intent).await;
    shared.status.in_flight.fetch_sub(1, Ordering::Relaxed);
    if let Err(reason) = result {
        fail(shared, intent, &reason);
    }
}

async fn execute(shared: &Arc<Shared>, intent: &Intent) -> Result<(), String> {
    let key = intent.key();
    // One intent at a time per player: approvals and balances read in planning stay true while it runs.
    let lock = intent.player().map(|p| shared.player_lock(p));
    let _guard = match &lock {
        Some(l) => Some(l.lock().await),
        None => None,
    };
    let player = match intent.player() {
        Some(p) => {
            let w = shared
                .wallets
                .lock()
                .expect("wallets lock")
                .ensure(p)
                .map_err(|e| e.to_string())?;
            Some(PlayerInfo {
                address: w.address,
                label: w.label,
            })
        }
        None => None,
    };
    let reads = ChainReads {
        provider: shared.provider.clone(),
        errors: shared.errors.clone(),
    };
    if let Intent::CheckHolding {
        player: id,
        campaign,
        reference,
    } = intent
    {
        let p = player.as_ref().ok_or("no wallet")?;
        let escrow = shared
            .dep
            .contract("CampaignEscrow")
            .map_err(|e| e.to_string())?;
        let token = reads.campaign_quest_token(escrow, *campaign).await?;
        if token == Address::ZERO {
            return Err(format!("campaign {campaign} has no quest token"));
        }
        let amount = reads.erc20_balance(token, p.address).await?;
        shared.emit_synthetic(Observation::Holding {
            player: id.clone(),
            campaign: *campaign,
            amount: u128::try_from(amount).unwrap_or(u128::MAX),
            reference: reference.clone(),
        });
        return Ok(());
    }
    if let Intent::QuoteSwap {
        player: id,
        campaign,
        usdc_in,
        reference,
    } = intent
    {
        let quoted = quote_swap(shared, &reads, *campaign, *usdc_in).await?;
        shared.emit_synthetic(Observation::SwapQuoted {
            player: id.clone(),
            campaign: *campaign,
            usdc_in: *usdc_in,
            amount_out: quoted.amount_out,
            fee_bps: quoted.fee_bps,
            token: quoted.token.to_string(),
            symbol: quoted.symbol,
            decimals: quoted.decimals,
            reference: reference.clone(),
        });
        return Ok(());
    }
    let draw = draw_prep(shared, intent)?;
    let ctx = PlanCtx {
        cfg: &shared.cfg,
        dep: &shared.dep,
        tickets: &shared.tickets,
        vouchers: &shared.vouchers,
        now: now(),
        draw,
    };
    let plan = plan::plan(intent, &ctx, player.as_ref(), &reads).await?;
    tracing::info!(%key, kind = intent.kind(), txs = plan.txs.len(), "executing");

    let mut last: Option<TxOutcome> = None;
    for tx in &plan.txs {
        if let Sender::Player(id) = &tx.sender {
            top_up(shared, id).await?;
        }
        let handle = shared.sender(&tx.sender)?;
        let record = {
            let shared = shared.clone();
            let key = key.clone();
            let repeatable = intent.is_repeatable();
            move |hash: B256| {
                if !repeatable {
                    if let Err(e) = shared
                        .intents
                        .lock()
                        .expect("intents lock")
                        .sent(&key, hash)
                    {
                        shared.status.error(format!("intents table: {e}"));
                    }
                }
            }
        };
        let outcome = handle
            .send(tx.to, tx.data.clone(), tx.value, record)
            .await
            .map_err(|e| format!("{}: {e}", tx.what))?;
        tracing::info!(%key, what = tx.what, hash = %outcome.hash, block = outcome.block, "mined");
        last = Some(outcome);
    }
    let Some(last) = last else {
        // Already true on chain (e.g. a name this player owns): record it and report it without a transaction.
        if let After::NameRegistered {
            player,
            label,
            name,
        } = plan.after
        {
            if let Err(e) = shared
                .wallets
                .lock()
                .expect("wallets lock")
                .set_label(&player, &label)
            {
                shared.status.error(format!("wallets: {e}"));
            }
            let _ = shared
                .intents
                .lock()
                .expect("intents lock")
                .done(&key, B256::ZERO, 0);
            shared.emit_synthetic(Observation::NameRegistered {
                player,
                label,
                name,
                tx: String::new(),
            });
            return Ok(());
        }
        return Err("nothing to send".into());
    };
    if !intent.is_repeatable() {
        if let Err(e) = shared
            .intents
            .lock()
            .expect("intents lock")
            .done(&key, last.hash, last.block)
        {
            shared.status.error(format!("intents table: {e}"));
        }
    }
    match plan.after {
        After::Indexed => {}
        After::NameRegistered {
            player,
            label,
            name,
        } => {
            if let Err(e) = shared
                .wallets
                .lock()
                .expect("wallets lock")
                .set_label(&player, &label)
            {
                shared.status.error(format!("wallets: {e}"));
            }
            shared.confirmed(last.block).await;
            let time = shared.block_time(last.block).await;
            shared.emit(
                last.block,
                NOT_A_LOG,
                time,
                Observation::NameRegistered {
                    player,
                    label,
                    name,
                    tx: last.hash.to_string(),
                },
            );
        }
        After::RecordsSet { player, records } => {
            shared.confirmed(last.block).await;
            let time = shared.block_time(last.block).await;
            shared.emit(
                last.block,
                NOT_A_LOG,
                time,
                Observation::RecordsSet {
                    player,
                    records,
                    tx: last.hash.to_string(),
                },
            );
        }
    }
    Ok(())
}

struct Quoted {
    amount_out: u128,
    fee_bps: u32,
    token: Address,
    symbol: String,
    decimals: u8,
}

/// V4Quoter's price for `usdc_in` of USDC into the campaign's quest pool (a read, no transaction).
async fn quote_swap(
    shared: &Shared,
    reads: &ChainReads,
    campaign: u64,
    usdc_in: u64,
) -> Result<Quoted, String> {
    if usdc_in == 0 {
        return Err("nothing to quote".into());
    }
    let quoter = shared
        .dep
        .quoter
        .ok_or("deployments have no uniswap.quoter")?;
    let escrow = shared
        .dep
        .contract("CampaignEscrow")
        .map_err(|e| e.to_string())?;
    let token = reads.campaign_quest_token(escrow, campaign).await?;
    if token == Address::ZERO {
        return Err(format!("campaign {campaign} has no quest token"));
    }
    let pool = shared.dep.quest_pool_for(token);
    let zero_for_one = pool.key.currency0 == shared.dep.usdc;
    let out = reads
        .quote_exact_in(quoter, pool.key.clone(), zero_for_one, usdc_in)
        .await?;
    let amount_out = u128::try_from(out).map_err(|_| "quote out of range".to_string())?;
    let (symbol, decimals) = token_meta(shared, token).await?;
    Ok(Quoted {
        amount_out,
        fee_bps: pool.key.fee.to::<u32>(),
        token,
        symbol,
        decimals,
    })
}

/// A token's ERC-20 symbol and decimals, read once and cached.
async fn token_meta(shared: &Shared, token: Address) -> Result<(String, u8), String> {
    if let Some(m) = shared.token_meta.lock().expect("meta lock").get(&token) {
        return Ok(m.clone());
    }
    let symbol = view(
        &shared.provider,
        &shared.errors,
        token,
        IERC20::symbolCall {},
    )
    .await?;
    let decimals = view(
        &shared.provider,
        &shared.errors,
        token,
        IERC20::decimalsCall {},
    )
    .await?;
    shared
        .token_meta
        .lock()
        .expect("meta lock")
        .insert(token, (symbol.clone(), decimals));
    Ok((symbol, decimals))
}

/// The ticket tree for a draw intent: built from the tickets (and saved) for `CommitDraw`, loaded for `ClaimDraw`.
fn draw_prep(shared: &Shared, intent: &Intent) -> Result<Option<DrawPrep>, String> {
    let dir = &shared.cfg.data_dir;
    match intent {
        Intent::CommitDraw { week, tickets, .. } if !tickets.is_empty() => {
            let mut entries = Vec::with_capacity(tickets.len());
            {
                let mut wallets = shared.wallets.lock().expect("wallets lock");
                for t in tickets {
                    if t.to < t.from {
                        return Err(format!(
                            "ticket range {}..={} for {} is empty",
                            t.from, t.to, t.player
                        ));
                    }
                    let w = wallets.ensure(&t.player).map_err(|e| e.to_string())?;
                    entries.push(draw::Entry {
                        player: t.player.clone(),
                        address: w.address,
                        from: t.from,
                        to: t.to,
                    });
                }
            }
            let root = draw::tree(&entries).ok_or("no tickets")?.root();
            draw::save(
                dir,
                &draw::Committed {
                    week: *week,
                    root,
                    entries,
                },
            )
            .map_err(|e| e.to_string())?;
            Ok(Some(DrawPrep {
                root,
                proof: vec![],
            }))
        }
        Intent::ClaimDraw {
            week,
            player,
            from,
            to,
            ..
        } => {
            let c = draw::load(dir, *week)
                .map_err(|e| e.to_string())?
                .ok_or_else(|| format!("no tickets saved for week {week}"))?;
            let e = c
                .entries
                .iter()
                .find(|e| &e.player == player && e.from == *from && e.to == *to)
                .ok_or_else(|| {
                    format!("{player} has no ticket range {from}..={to} in week {week}")
                })?;
            let tree = draw::tree(&c.entries).ok_or("no tickets")?;
            if tree.root() != c.root {
                return Err(format!(
                    "saved tickets for week {week} don't match their root"
                ));
            }
            let proof = tree.proof(e.leaf()).ok_or("ticket range not in the tree")?;
            Ok(Some(DrawPrep {
                root: c.root,
                proof,
            }))
        }
        _ => Ok(None),
    }
}

/// Tops a player's wallet up to the gas target before a player-sent transaction (spec §3.3), within today's cap.
async fn top_up(shared: &Arc<Shared>, player: &str) -> Result<(), String> {
    if shared.cfg.secrets.gas_station.is_none() {
        return Ok(());
    }
    let address = shared
        .wallets
        .lock()
        .expect("wallets lock")
        .get(player)
        .map(|w| w.address)
        .ok_or_else(|| format!("player {player} has no wallet"))?;
    let balance = shared
        .provider
        .get_balance(address)
        .await
        .map_err(|e| shared.errors.explain(&e))?;
    let day = utc_day(now());
    let decision = shared
        .gas
        .lock()
        .expect("gas lock")
        .plan(&shared.cfg.gas, player, balance, day);
    match decision {
        TopUp::NotNeeded => Ok(()),
        TopUp::CapReached { spent, cap } => Err(format!(
            "gas top-ups for {player} are used up today ({spent} of {cap} wei)"
        )),
        TopUp::Send(wei) => {
            let station = shared.sender(&Sender::GasStation)?;
            let out = station
                .send(address, Bytes::new(), wei, |_| {})
                .await
                .map_err(|e| format!("gas top-up: {e}"))?;
            tracing::info!(%player, %wei, hash = %out.hash, "gas top-up");
            shared
                .gas
                .lock()
                .expect("gas lock")
                .record(player, day, wei)
                .map_err(|e| e.to_string())?;
            Ok(())
        }
    }
}
