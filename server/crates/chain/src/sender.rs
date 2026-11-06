//! One queue per sending key (spec §3.3): local nonces, EIP-1559 fees, receipts awaited, dropped transactions
//! rebroadcast and stuck ones replaced with bumped fees.
//!
//! Nonces are allocated only when a transaction is accepted by the node, so a transaction that would revert (caught by
//! `eth_estimateGas`) or that the node refuses never leaves a gap. Up to `max_in_flight` transactions per key wait for
//! receipts at once.

use crate::revert::ErrorBook;
use alloy::eips::eip2718::Encodable2718;
use alloy::eips::BlockId;
use alloy::network::{
    EthereumWallet, NetworkTransactionBuilder, ReceiptResponse, TransactionBuilder,
};
use alloy::primitives::{Address, Bytes, B256, U256};
use alloy::providers::{DynProvider, Provider};
use alloy::rpc::types::TransactionRequest;
use alloy::signers::local::PrivateKeySigner;
use alloy::transports::{RpcError, TransportErrorKind};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{mpsc, oneshot, OwnedSemaphorePermit, Semaphore};

#[derive(Clone, Debug)]
pub struct SendConfig {
    pub chain_id: u64,
    pub poll: Duration,
    pub receipt_timeout: Duration,
    pub max_resends: u32,
    pub max_in_flight: usize,
    pub fee_bump_percent: u64,
}

/// A mined, successful transaction.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct TxOutcome {
    pub hash: B256,
    pub block: u64,
}

#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
pub enum TxError {
    /// `eth_estimateGas` failed: the transaction would revert (nothing was sent).
    #[error("{0}")]
    WouldRevert(String),
    #[error("transaction {hash} reverted: {reason}")]
    Reverted { hash: B256, reason: String },
    #[error("{0}")]
    Rpc(String),
    #[error("transaction with nonce {nonce} was dropped and could not be replaced")]
    Dropped { nonce: u64 },
    #[error("the sender for {0} stopped")]
    Stopped(Address),
}

type OnSent = Box<dyn FnOnce(B256) + Send>;

struct Job {
    to: Address,
    data: Bytes,
    value: U256,
    on_sent: OnSent,
    reply: oneshot::Sender<Result<TxOutcome, TxError>>,
}

/// A handle to one key's queue.
#[derive(Clone, Debug)]
pub struct SenderHandle {
    address: Address,
    jobs: mpsc::UnboundedSender<Job>,
}

impl std::fmt::Debug for Job {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Job(to {})", self.to)
    }
}

impl SenderHandle {
    /// Starts the queue for `signer` on the current tokio runtime.
    pub fn spawn(
        provider: DynProvider,
        signer: PrivateKeySigner,
        cfg: Arc<SendConfig>,
        errors: Arc<ErrorBook>,
    ) -> SenderHandle {
        let (jobs, rx) = mpsc::unbounded_channel();
        let address = signer.address();
        tokio::spawn(run(provider, signer, cfg, errors, rx));
        SenderHandle { address, jobs }
    }

    pub fn address(&self) -> Address {
        self.address
    }

    /// Sends a transaction and waits for it to be mined. `on_sent` gets the hash as soon as the node accepts it.
    pub async fn send(
        &self,
        to: Address,
        data: Bytes,
        value: U256,
        on_sent: impl FnOnce(B256) + Send + 'static,
    ) -> Result<TxOutcome, TxError> {
        let (reply, rx) = oneshot::channel();
        self.jobs
            .send(Job {
                to,
                data,
                value,
                on_sent: Box::new(on_sent),
                reply,
            })
            .map_err(|_| TxError::Stopped(self.address))?;
        rx.await.map_err(|_| TxError::Stopped(self.address))?
    }
}

/// Errors that mean our idea of the next nonce is wrong.
fn nonce_problem(msg: &str) -> bool {
    let m = msg.to_ascii_lowercase();
    m.contains("nonce too low")
        || m.contains("nonce too high")
        || m.contains("replacement transaction underpriced")
        || m.contains("replacement fee too low")
        || m.contains("invalid nonce")
}

/// The node already has this exact transaction: as good as accepted.
fn already_known(msg: &str) -> bool {
    let m = msg.to_ascii_lowercase();
    m.contains("already known") || m.contains("already imported") || m.contains("known transaction")
}

fn rpc_msg(e: &RpcError<TransportErrorKind>) -> String {
    match e {
        RpcError::ErrorResp(p) => p.message.to_string(),
        other => other.to_string(),
    }
}

struct Sent {
    hash: B256,
    nonce: u64,
    raw: Vec<u8>,
    tx: TransactionRequest,
    max_fee: u128,
    priority_fee: u128,
}

async fn run(
    provider: DynProvider,
    signer: PrivateKeySigner,
    cfg: Arc<SendConfig>,
    errors: Arc<ErrorBook>,
    mut rx: mpsc::UnboundedReceiver<Job>,
) {
    let wallet = EthereumWallet::from(signer.clone());
    let from = signer.address();
    let slots = Arc::new(Semaphore::new(cfg.max_in_flight));
    let mut next_nonce: Option<u64> = None;
    while let Some(job) = rx.recv().await {
        let Ok(permit) = slots.clone().acquire_owned().await else {
            break;
        };
        match broadcast(
            &provider,
            &wallet,
            from,
            &cfg,
            &errors,
            &mut next_nonce,
            (job.to, &job.data, job.value),
        )
        .await
        {
            Ok(sent) => {
                tracing::debug!(%from, hash = %sent.hash, nonce = sent.nonce, "sent");
                (job.on_sent)(sent.hash);
                tokio::spawn(watch(
                    provider.clone(),
                    wallet.clone(),
                    cfg.clone(),
                    errors.clone(),
                    sent,
                    job.reply,
                    permit,
                ));
            }
            Err(e) => {
                let _ = job.reply.send(Err(e));
            }
        }
    }
}

async fn broadcast(
    p: &DynProvider,
    wallet: &EthereumWallet,
    from: Address,
    cfg: &SendConfig,
    errors: &ErrorBook,
    next_nonce: &mut Option<u64>,
    (to, data, value): (Address, &Bytes, U256),
) -> Result<Sent, TxError> {
    let base = TransactionRequest::default()
        .with_from(from)
        .with_to(to)
        .with_input(data.clone())
        .with_value(value);
    let gas = p
        .estimate_gas(base.clone())
        .await
        .map_err(|e| TxError::WouldRevert(errors.explain(&e)))?;
    let fees = p
        .estimate_eip1559_fees()
        .await
        .map_err(|e| TxError::Rpc(rpc_msg(&e)))?;
    let gas_limit = gas.saturating_mul(12) / 10 + 10_000;
    for _ in 0..3 {
        let nonce = match *next_nonce {
            Some(n) => n,
            None => p
                .get_transaction_count(from)
                .pending()
                .await
                .map_err(|e| TxError::Rpc(rpc_msg(&e)))?,
        };
        let tx = base
            .clone()
            .with_nonce(nonce)
            .with_chain_id(cfg.chain_id)
            .with_gas_limit(gas_limit)
            .with_max_fee_per_gas(fees.max_fee_per_gas)
            .with_max_priority_fee_per_gas(fees.max_priority_fee_per_gas);
        let envelope = tx
            .clone()
            .build(wallet)
            .await
            .map_err(|e| TxError::Rpc(format!("signing failed: {e}")))?;
        let hash = *envelope.tx_hash();
        let raw = envelope.encoded_2718();
        match p.send_raw_transaction(&raw).await {
            Ok(_) => {}
            Err(e) if already_known(&rpc_msg(&e)) => {}
            Err(e) if nonce_problem(&rpc_msg(&e)) => {
                tracing::warn!(%from, nonce, error = %rpc_msg(&e), "nonce out of step; asking the node");
                *next_nonce = None;
                continue;
            }
            Err(e) => return Err(TxError::Rpc(errors.explain(&e))),
        }
        *next_nonce = Some(nonce + 1);
        return Ok(Sent {
            hash,
            nonce,
            raw,
            tx,
            max_fee: fees.max_fee_per_gas,
            priority_fee: fees.max_priority_fee_per_gas,
        });
    }
    Err(TxError::Rpc("could not find a usable nonce".into()))
}

/// Waits for any of the transaction's versions to be mined; rebroadcasts or replaces it when it seems stuck.
async fn watch(
    p: DynProvider,
    wallet: EthereumWallet,
    cfg: Arc<SendConfig>,
    errors: Arc<ErrorBook>,
    mut sent: Sent,
    reply: oneshot::Sender<Result<TxOutcome, TxError>>,
    _slot: OwnedSemaphorePermit,
) {
    let mut hashes = vec![sent.hash];
    let mut resends = 0;
    let mut deadline = tokio::time::Instant::now() + cfg.receipt_timeout;
    let result = loop {
        let mut mined = None;
        for h in &hashes {
            if let Ok(Some(r)) = p.get_transaction_receipt(*h).await {
                mined = Some(r);
                break;
            }
        }
        if let Some(r) = mined {
            let hash = r.transaction_hash();
            let block = r.block_number().unwrap_or_default();
            if r.status() {
                break Ok(TxOutcome { hash, block });
            }
            let reason = replay_reason(&p, &errors, &sent.tx, block).await;
            break Err(TxError::Reverted { hash, reason });
        }
        if tokio::time::Instant::now() < deadline {
            tokio::time::sleep(cfg.poll).await;
            continue;
        }
        // Not mined in time. If the nonce is already used and none of our versions has a receipt, it's gone.
        let mined_nonce = p
            .get_transaction_count(sent.tx.from.unwrap_or_default())
            .await
            .unwrap_or(0);
        if mined_nonce > sent.nonce {
            // One more look: a receipt can lag the nonce by a moment.
            tokio::time::sleep(cfg.poll).await;
            let mut found = false;
            for h in &hashes {
                if let Ok(Some(_)) = p.get_transaction_receipt(*h).await {
                    found = true;
                }
            }
            if !found {
                break Err(TxError::Dropped { nonce: sent.nonce });
            }
            continue;
        }
        if resends >= cfg.max_resends {
            break Err(TxError::Dropped { nonce: sent.nonce });
        }
        resends += 1;
        let in_pool = matches!(p.get_transaction_by_hash(sent.hash).await, Ok(Some(_)));
        if !in_pool {
            tracing::warn!(hash = %sent.hash, "transaction dropped from the pool; rebroadcasting");
            if let Err(e) = p.send_raw_transaction(&sent.raw).await {
                tracing::warn!(error = %rpc_msg(&e), "rebroadcast refused");
            }
        } else {
            // Stuck in the pool: replace it (same nonce) with higher fees.
            let bump = |v: u128| v.saturating_mul(100 + cfg.fee_bump_percent as u128) / 100 + 1;
            let max_fee = bump(sent.max_fee);
            let priority_fee = bump(sent.priority_fee);
            let tx = sent
                .tx
                .clone()
                .with_max_fee_per_gas(max_fee)
                .with_max_priority_fee_per_gas(priority_fee);
            match tx.clone().build(&wallet).await {
                Ok(env) => {
                    let raw = env.encoded_2718();
                    match p.send_raw_transaction(&raw).await {
                        Ok(_) => {
                            tracing::warn!(old = %sent.hash, new = %env.tx_hash(), "replaced a stuck transaction");
                            hashes.push(*env.tx_hash());
                            sent = Sent {
                                hash: *env.tx_hash(),
                                raw,
                                tx,
                                max_fee,
                                priority_fee,
                                ..sent
                            };
                        }
                        Err(e) => tracing::warn!(error = %rpc_msg(&e), "replacement refused"),
                    }
                }
                Err(e) => tracing::warn!(error = %e, "could not sign a replacement"),
            }
        }
        deadline = tokio::time::Instant::now() + cfg.receipt_timeout;
    };
    let _ = reply.send(result);
}

/// Why a mined transaction reverted: replays it as a call on the state before its block.
async fn replay_reason(
    p: &DynProvider,
    errors: &ErrorBook,
    tx: &TransactionRequest,
    block: u64,
) -> String {
    let call = TransactionRequest::default()
        .with_from(tx.from.unwrap_or_default())
        .with_to(tx.to.and_then(|t| t.to().copied()).unwrap_or_default())
        .with_input(tx.input.input().cloned().unwrap_or_default())
        .with_value(tx.value.unwrap_or_default());
    match p
        .call(call)
        .block(BlockId::number(block.saturating_sub(1)))
        .await
    {
        Ok(_) => "reverted (no reason available)".into(),
        Err(e) => errors.explain(&e),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classifies_node_errors() {
        assert!(nonce_problem("nonce too low: next nonce 5, tx nonce 4"));
        assert!(nonce_problem("replacement transaction underpriced"));
        assert!(!nonce_problem("insufficient funds for gas * price + value"));
        assert!(already_known("already known"));
        assert!(!already_known("execution reverted"));
    }
}
