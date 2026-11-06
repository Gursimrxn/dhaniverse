//! Periodic balance reads (spec §3.3): USDC per player, HousePool buckets and budgets, FloatManager state, sent as one
//! JSON-RPC batch of `eth_call`s. An observation is emitted only when a value changes, so the world log isn't flooded.

use crate::bindings::*;
use crate::exec::Shared;
use crate::indexer::u64_of;
use crate::types::{Bucket, Observation};
use alloy::eips::BlockId;
use alloy::network::TransactionBuilder;
use alloy::primitives::{Address, Bytes, U256};
use alloy::providers::{DynProvider, Provider};
use alloy::rpc::types::TransactionRequest;
use alloy::sol_types::SolCall;
use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};

/// Which players to read. `None` means every player with a wallet.
pub(crate) type Watched = Arc<Mutex<Option<HashSet<String>>>>;

/// Runs `eth_call`s as one batch; falls back to one call at a time if the node refuses batches.
pub(crate) async fn batch_call(p: &DynProvider, calls: &[(Address, Bytes)]) -> Vec<Option<Bytes>> {
    if calls.is_empty() {
        return vec![];
    }
    let client = p.client();
    let mut batch = alloy::rpc::client::BatchRequest::new(client);
    let mut waiters = Vec::with_capacity(calls.len());
    let mut ok = true;
    for (to, data) in calls {
        let req = TransactionRequest::default()
            .with_to(*to)
            .with_input(data.clone());
        match batch.add_call::<_, Bytes>("eth_call", &(req, BlockId::latest())) {
            Ok(w) => waiters.push(w),
            Err(_) => {
                ok = false;
                break;
            }
        }
    }
    if ok && batch.send().await.is_ok() {
        let mut out = Vec::with_capacity(waiters.len());
        for w in waiters {
            out.push(w.await.ok());
        }
        return out;
    }
    let mut out = Vec::with_capacity(calls.len());
    for (to, data) in calls {
        let req = TransactionRequest::default()
            .with_to(*to)
            .with_input(data.clone());
        out.push(p.call(req).await.ok());
    }
    out
}

fn dec<C: SolCall>(raw: &Option<Bytes>) -> Option<C::Return> {
    raw.as_ref().and_then(|r| C::abi_decode_returns(r).ok())
}

/// The last values sent, to emit only changes.
#[derive(Default)]
pub(crate) struct Last {
    usdc: HashMap<String, u64>,
    pools: Option<Observation>,
    float: Option<Observation>,
    warned: HashSet<&'static str>,
}

impl Last {
    fn warn_once(&mut self, what: &'static str) {
        if self.warned.insert(what) {
            tracing::warn!(
                what,
                "balance read failed (contract missing or a different ABI); skipping it"
            );
        }
    }
}

/// One round of reads.
pub(crate) async fn read_once(shared: &Arc<Shared>, watched: &Watched, last: &mut Last) {
    let players: Vec<(String, Address)> = {
        let filter = watched.lock().expect("watched lock").clone();
        let wallets = shared.wallets.lock().expect("wallets lock");
        wallets
            .all()
            .filter(|w| filter.as_ref().is_none_or(|f| f.contains(&w.player)))
            .map(|w| (w.player.clone(), w.address))
            .collect()
    };
    let mut calls: Vec<(Address, Bytes)> = players
        .iter()
        .map(|(_, a)| {
            (
                shared.dep.usdc,
                IERC20::balanceOfCall { account: *a }.abi_encode().into(),
            )
        })
        .collect();
    let pool = shared.dep.contracts.get("HousePool").copied();
    let pool_at = calls.len();
    if let Some(pool) = pool {
        for b in Bucket::ALL {
            calls.push((
                pool,
                IHousePool::bucketBalanceCall { bucket: b.source() }
                    .abi_encode()
                    .into(),
            ));
        }
        for b in Bucket::ALL {
            calls.push((
                pool,
                IHousePool::todayBudgetCall { bucket: b.source() }
                    .abi_encode()
                    .into(),
            ));
        }
    }
    let float = shared.dep.contracts.get("FloatManager").copied();
    let escrow = shared.dep.contracts.get("CampaignEscrow").copied();
    let float_at = calls.len();
    if let (Some(f), Some(e)) = (float, escrow) {
        calls.push((f, IFloatManager::totalAssetsCall {}.abi_encode().into()));
        calls.push((f, IFloatManager::liquidCall {}.abi_encode().into()));
        calls.push((f, IFloatManager::investedCall {}.abi_encode().into()));
        calls.push((f, IFloatManager::lossReserveCall {}.abi_encode().into()));
        calls.push((f, IFloatManager::bufferCall {}.abi_encode().into()));
        calls.push((f, IFloatManager::yieldEarnedCall {}.abi_encode().into()));
        calls.push((
            e,
            ICampaignEscrow::totalLiabilitiesCall {}.abi_encode().into(),
        ));
    }
    let results = batch_call(&shared.provider, &calls).await;
    if results.len() != calls.len() {
        return;
    }

    for (i, (player, _)) in players.iter().enumerate() {
        let Some(v) = dec::<IERC20::balanceOfCall>(&results[i]) else {
            last.warn_once("usdc balance");
            continue;
        };
        let usdc = u64_of(v);
        if last.usdc.get(player) != Some(&usdc) {
            last.usdc.insert(player.clone(), usdc);
            shared.emit_synthetic(Observation::Balances {
                player: player.clone(),
                usdc,
            });
        }
    }

    if pool.is_some() {
        let r = &results[pool_at..pool_at + 6];
        let bal = |i: usize| dec::<IHousePool::bucketBalanceCall>(&r[i]);
        let bud = |i: usize| dec::<IHousePool::todayBudgetCall>(&r[3 + i]);
        match (bal(0), bal(1), bal(2), bud(0), bud(1), bud(2)) {
            (Some(f), Some(s), Some(sa), Some(bf), Some(bs), Some(bsa)) => {
                let o = Observation::PoolBalances {
                    fixed: u64_of(f),
                    surprise: u64_of(s),
                    safety: u64_of(sa),
                    budget_fixed: u64_of(bf.left),
                    budget_surprise: u64_of(bs.left),
                    budget_safety: u64_of(bsa.left),
                };
                if last.pools.as_ref() != Some(&o) {
                    last.pools = Some(o.clone());
                    shared.emit_synthetic(o);
                }
            }
            _ => last.warn_once("house pool"),
        }
    }

    if float.is_some() && escrow.is_some() {
        let r = &results[float_at..float_at + 7];
        let get = |i: usize| -> Option<U256> { r[i].as_ref().and_then(|b| word(b)) };
        match (get(0), get(1), get(2), get(3), get(4), get(5), get(6)) {
            (
                Some(total),
                Some(liquid),
                Some(invested),
                Some(reserve),
                Some(buffer),
                Some(earned),
                Some(liabilities),
            ) => {
                let o = Observation::FloatState {
                    total_assets: u64_of(total),
                    liquid: u64_of(liquid),
                    invested: u64_of(invested),
                    buffer: u64_of(buffer),
                    liabilities: u64_of(liabilities),
                    loss_reserve: u64_of(reserve),
                    yield_earned: u64_of(earned),
                };
                if last.float.as_ref() != Some(&o) {
                    last.float = Some(o.clone());
                    shared.emit_synthetic(o);
                }
            }
            _ => last.warn_once("float manager"),
        }
    }
}

/// A single `uint256` return word.
fn word(b: &[u8]) -> Option<U256> {
    (b.len() == 32).then(|| U256::from_be_slice(b))
}

pub(crate) async fn run(shared: Arc<Shared>, watched: Watched) {
    let mut last = Last::default();
    loop {
        read_once(&shared, &watched, &mut last).await;
        tokio::time::sleep(shared.cfg.balance_interval).await;
    }
}
