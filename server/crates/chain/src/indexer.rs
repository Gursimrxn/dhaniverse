//! The indexer (spec §3.3): `eth_getLogs` over our deployments and the quest pool's `Swap` logs, only up to
//! `head - confirmations`, decoded into Observations in (block, log index) order, checkpoint persisted after each range.

use crate::bindings::*;
use crate::deployments::{Deployments, QuestPool};
use crate::exec::Shared;
use crate::rpc::view;
use crate::store::{read_json, write_json};
use crate::types::{HumanId, Observation};
use alloy::network::TransactionResponse;
use alloy::primitives::{Address, B256, I256, U256};
use alloy::providers::Provider;
use alloy::rpc::types::{Filter, Log};
use alloy::sol_types::SolEvent;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::Ordering;
use std::sync::Arc;

/// Turns addresses and hashes from logs back into the server's words.
pub(crate) trait Naming {
    /// The player id for one of our wallets.
    fn player(&self, address: &Address) -> Option<String>;
    /// The server's ref string for a ref hash this server sent.
    fn server_ref(&self, hash: &B256) -> Option<String>;
    /// The menu item for an item hash.
    fn item(&self, hash: &B256) -> Option<String>;
}

fn who(n: &dyn Naming, a: &Address) -> String {
    n.player(a).unwrap_or_else(|| a.to_string())
}

fn refstr(n: &dyn Naming, h: &B256) -> String {
    n.server_ref(h).unwrap_or_else(|| h.to_string())
}

/// Quest template names (`CampaignParams.template` = keccak256 of the name).
pub const TEMPLATES: [&str; 4] = ["spice_run", "paint_sign", "town_pass", "hold_line"];

/// A template's name from its hash, or the hash as hex if it isn't one we know.
pub(crate) fn template_name(hash: &B256) -> String {
    TEMPLATES
        .iter()
        .find(|t| alloy::primitives::keccak256(t.as_bytes()) == *hash)
        .map(|t| t.to_string())
        .unwrap_or_else(|| hash.to_string())
}

/// U256 → u64, saturating (USDC and FOOD amounts fit easily; a contract bug must not panic the indexer).
pub(crate) fn u64_of(v: U256) -> u64 {
    u64::try_from(v).unwrap_or(u64::MAX)
}

fn u128_of(v: U256) -> u128 {
    u128::try_from(v).unwrap_or(u128::MAX)
}

/// Decodes one confirmed log. `pools` are the quest pools by id; `tx_from` is the transaction's sender (needed for
/// quest-pool swaps).
pub(crate) fn decode(
    log: &Log,
    dep: &Deployments,
    pools: &HashMap<B256, QuestPool>,
    names: &dyn Naming,
    tx_from: Option<Address>,
) -> Option<Observation> {
    let addr = log.address();
    let topic0 = *log.topic0()?;
    let tx = log.transaction_hash.unwrap_or_default().to_string();
    let from = |name: &str| dep.contracts.get(name) == Some(&addr);
    let data = &log.inner.data;
    macro_rules! ev {
        ($t:ty) => {
            match <$t>::decode_log_data(data) {
                Ok(e) => e,
                Err(err) => {
                    tracing::warn!(event = <$t>::SIGNATURE, error = %err, "undecodable log skipped");
                    return None;
                }
            }
        };
    }
    let o = if topic0 == IMealCounter::MealEaten::SIGNATURE_HASH && from("MealCounter") {
        let e = ev!(IMealCounter::MealEaten);
        Observation::MealEaten {
            player: who(names, &e.player),
            item: names.item(&e.item).unwrap_or_else(|| e.item.to_string()),
            usdc: u64_of(e.usdcPaid),
            food: u64_of(e.foodBurned),
            from_ration: u64_of(e.fromRation),
            reference: refstr(names, &e.r#ref),
            tx,
        }
    } else if topic0 == IFarm::HarvestSold::SIGNATURE_HASH && from("Farm") {
        let e = ev!(IFarm::HarvestSold);
        Observation::HarvestSold {
            offered: u64_of(e.offered),
            sold: u64_of(e.sold),
            usdc: u64_of(e.usdc),
            reference: refstr(names, &e.r#ref),
            tx,
        }
    } else if topic0 == IFoodHook::TradeCounted::SIGNATURE_HASH && from("FoodHook") {
        let e = ev!(IFoodHook::TradeCounted);
        Observation::FoodTrade {
            day: u64_of(e.day),
            usdc: u64_of(e.usdc),
            food: u64_of(e.food),
            price_after: u64_of(e.priceAfter),
            tx,
        }
    } else if topic0 == IFoodHook::DayOpened::SIGNATURE_HASH && from("FoodHook") {
        let e = ev!(IFoodHook::DayOpened);
        Observation::FoodDayOpened {
            day: u64_of(e.day),
            open_price: u64_of(e.openPrice),
        }
    } else if topic0 == ITreasury::Split::SIGNATURE_HASH && from("Treasury") {
        let e = ev!(ITreasury::Split);
        Observation::Split {
            total: u64_of(e.total),
            fixed: u64_of(e.fixedShare),
            safety: u64_of(e.safety),
            ops: u64_of(e.ops),
            team: u64_of(e.team),
            tx,
        }
    } else if topic0 == IHousePool::Paid::SIGNATURE_HASH && from("HousePool") {
        let e = ev!(IHousePool::Paid);
        let Some(bucket) = crate::types::bucket_from_source(e.source) else {
            tracing::warn!(source = e.source, "Paid from an unknown bucket skipped");
            return None;
        };
        Observation::Paid {
            bucket,
            player: who(names, &e.player),
            human_id: HumanId(e.humanId.to_string()),
            amount: u64_of(e.amount),
            reference: refstr(names, &e.r#ref),
            tx,
        }
    } else if topic0 == ICampaignEscrow::CampaignCreated::SIGNATURE_HASH && from("CampaignEscrow") {
        let e = ev!(ICampaignEscrow::CampaignCreated);
        let p = e.params;
        Observation::CampaignCreated {
            id: u64_of(e.campaignId),
            sponsor: e.sponsor.to_string(),
            template: template_name(&p.template),
            meta_hash: p.metaHash.to_string(),
            budget: u64_of(e.net),
            payout_per_claim: u64_of(p.payoutPerClaim),
            energy_cost: p.energyCost,
            max_claims: p.maxClaims,
            per_human_cap: p.perHumanCap,
            start: p.start,
            end: p.end,
            kind: p.kind,
            deliver_to: p.deliverTo.to_string(),
        }
    } else if topic0 == ICampaignEscrow::Claimed::SIGNATURE_HASH && from("CampaignEscrow") {
        let e = ev!(ICampaignEscrow::Claimed);
        Observation::Claimed {
            campaign: u64_of(e.campaignId),
            player: who(names, &e.player),
            human_id: HumanId(e.humanId.to_string()),
            // The contract's `amount` is the whole voucher, the repaid advance included; the server (like its
            // offline ledger) counts `amount` as what reached the wallet, so report the fresh part.
            amount: u64_of(e.amount.saturating_sub(e.advanceRepaid)),
            advance_repaid: u64_of(e.advanceRepaid),
            reference: refstr(names, &e.r#ref),
            tx,
        }
    } else if topic0 == ICampaignEscrow::Advanced::SIGNATURE_HASH && from("CampaignEscrow") {
        let e = ev!(ICampaignEscrow::Advanced);
        Observation::Advanced {
            campaign: u64_of(e.campaignId),
            player: who(names, &e.player),
            human_id: HumanId(e.humanId.to_string()),
            amount: u64_of(e.amount),
            reference: refstr(names, &e.r#ref),
            tx,
        }
    } else if topic0 == ICampaignEscrow::Refunded::SIGNATURE_HASH && from("CampaignEscrow") {
        let e = ev!(ICampaignEscrow::Refunded);
        Observation::Refunded {
            campaign: u64_of(e.campaignId),
            amount: u64_of(e.amount),
            tx,
        }
    } else if topic0 == ICampaignEscrow::Cancelled::SIGNATURE_HASH && from("CampaignEscrow") {
        let e = ev!(ICampaignEscrow::Cancelled);
        Observation::CampaignClosed {
            campaign: u64_of(e.campaignId),
            tx,
        }
    } else if topic0 == ICampaignEscrow::PausedSet::SIGNATURE_HASH && from("CampaignEscrow") {
        let e = ev!(ICampaignEscrow::PausedSet);
        if !e.paused {
            return None;
        }
        Observation::CampaignClosed {
            campaign: u64_of(e.campaignId),
            tx,
        }
    } else if topic0 == ISpiceMerchant::Delivered::SIGNATURE_HASH && from("SpiceMerchant") {
        let e = ev!(ISpiceMerchant::Delivered);
        Observation::Delivered {
            campaign: u64_of(e.campaignId),
            player: who(names, &e.player),
            token: e.token.to_string(),
            amount: u128_of(e.amount),
            reference: refstr(names, &e.questRef),
            tx,
        }
    } else if topic0 == ILuckyLedger::Committed::SIGNATURE_HASH && from("LuckyLedger") {
        let e = ev!(ILuckyLedger::Committed);
        Observation::DrawCommitted {
            week: u64_of(e.week),
            seed_hash: e.seedHash.to_string(),
            root: e.ticketsRoot.to_string(),
            count: u64_of(e.ticketCount),
            prize: u64_of(e.prize),
            tx,
        }
    } else if topic0 == ILuckyLedger::Revealed::SIGNATURE_HASH && from("LuckyLedger") {
        let e = ev!(ILuckyLedger::Revealed);
        Observation::DrawRevealed {
            week: u64_of(e.week),
            seed: e.seed.to_string(),
            winner_index: u64_of(e.winnerIndex),
            tx,
        }
    } else if topic0 == ILuckyLedger::DrawClaimed::SIGNATURE_HASH && from("LuckyLedger") {
        let e = ev!(ILuckyLedger::DrawClaimed);
        Observation::DrawClaimed {
            week: u64_of(e.week),
            player: who(names, &e.player),
            prize: u64_of(e.prize),
            tx,
        }
    } else if topic0 == IPoolManager::Swap::SIGNATURE_HASH && Some(addr) == dep.pool_manager {
        let e = ev!(IPoolManager::Swap);
        let qp = pools.get(&e.id)?;
        // Only swaps sent by one of our players' wallets count for quests.
        let player = names.player(&tx_from?)?;
        // v4 reports the swapper's balance change: negative is what they paid in, positive what they took out.
        let (a0, a1) = (
            I256::try_from(e.amount0).ok()?,
            I256::try_from(e.amount1).ok()?,
        );
        let (c0, c1) = (qp.key.currency0, qp.key.currency1);
        let ((token_in, amount_in), (token_out, amount_out)) = if a0.is_negative() {
            ((c0, a0), (c1, a1))
        } else {
            ((c1, a1), (c0, a0))
        };
        Observation::QuestSwap {
            player,
            token_in: token_in.to_string(),
            token_out: token_out.to_string(),
            amount_in: u128_of(amount_in.unsigned_abs()),
            amount_out: u128_of(amount_out.unsigned_abs()),
            tx,
        }
    } else {
        return None;
    };
    Some(o)
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct Checkpoint {
    chain_id: u64,
    /// Last fully processed block.
    block: u64,
}

pub(crate) fn checkpoint_path(dir: &Path) -> PathBuf {
    dir.join("indexer.json")
}

/// Where to start: the server's own word (`resume_after_block`), else the saved checkpoint, else the deploy block.
pub(crate) fn initial_checkpoint(
    dir: &Path,
    chain_id: u64,
    resume: Option<u64>,
    start_block: u64,
) -> Result<u64, String> {
    if let Some(b) = resume {
        return Ok(b);
    }
    match read_json::<Checkpoint>(&checkpoint_path(dir)).map_err(|e| e.to_string())? {
        Some(c) if c.chain_id == chain_id => Ok(c.block),
        Some(c) => Err(format!(
            "indexer.json is for chain {}, not {chain_id}",
            c.chain_id
        )),
        None => Ok(start_block.saturating_sub(1)),
    }
}

/// A snapshot of the naming tables for one batch of logs.
struct Snapshot<'a> {
    wallets: &'a crate::wallets::WalletBook,
    intents: &'a crate::intents::IntentTable,
}

impl Naming for Snapshot<'_> {
    fn player(&self, a: &Address) -> Option<String> {
        self.wallets.player_of(a).cloned()
    }
    fn server_ref(&self, h: &B256) -> Option<String> {
        self.intents.ref_of(h).map(str::to_string)
    }
    fn item(&self, h: &B256) -> Option<String> {
        self.intents.item_of(h).map(str::to_string)
    }
}

fn range_error(msg: &str) -> bool {
    let m = msg.to_ascii_lowercase();
    [
        "range",
        "too many",
        "limit",
        "exceed",
        "block range",
        "10000",
        "query returned more",
    ]
    .iter()
    .any(|k| m.contains(k))
}

/// How often the quest pools (one per live campaign's quest token) are re-read.
const POOL_REFRESH: std::time::Duration = std::time::Duration::from_secs(60);

/// Learns every live campaign's quest pool from `CampaignEscrow` (`openCampaigns`, `questToken`), so the indexer
/// follows their swaps. Stateless: a restart re-reads them.
pub(crate) async fn refresh_quest_pools(shared: &Arc<Shared>) {
    let Some(escrow) = shared.dep.contracts.get("CampaignEscrow").copied() else {
        return;
    };
    let ids = match view(
        &shared.provider,
        &shared.errors,
        escrow,
        ICampaignEscrow::openCampaignsCall {},
    )
    .await
    {
        Ok(ids) => ids,
        Err(e) => {
            tracing::warn!(error = %e, "can't list open campaigns");
            return;
        }
    };
    for id in ids {
        match view(
            &shared.provider,
            &shared.errors,
            escrow,
            ICampaignEscrow::questTokenCall { campaignId: id },
        )
        .await
        {
            Ok(token) if token != Address::ZERO => {
                let qp = shared.dep.quest_pool_for(token);
                shared
                    .quest_pools
                    .lock()
                    .expect("pools lock")
                    .insert(qp.id, qp);
            }
            Ok(_) => {}
            Err(e) => {
                tracing::warn!(campaign = %id, error = %e, "can't read a campaign's quest token")
            }
        }
    }
}

/// Runs forever: follows the chain and emits confirmed observations.
pub(crate) async fn run(shared: Arc<Shared>, mut checkpoint: u64) {
    let mut range = shared.cfg.log_range;
    shared
        .status
        .checkpoint
        .store(checkpoint, Ordering::Relaxed);
    let mut pools_read = tokio::time::Instant::now() - POOL_REFRESH;
    loop {
        if pools_read.elapsed() >= POOL_REFRESH || shared.pools_stale.swap(false, Ordering::Relaxed)
        {
            refresh_quest_pools(&shared).await;
            pools_read = tokio::time::Instant::now();
        }
        match step(&shared, &mut checkpoint, &mut range).await {
            Ok(true) => tokio::time::sleep(shared.cfg.poll_interval).await,
            Ok(false) => {}
            Err(e) => {
                shared.status.error(format!("indexer: {e}"));
                tokio::time::sleep(shared.cfg.poll_interval * 2).await;
            }
        }
    }
}

/// Processes one range. Returns true when caught up with the confirmed head.
async fn step(shared: &Arc<Shared>, checkpoint: &mut u64, range: &mut u64) -> Result<bool, String> {
    let p = &shared.provider;
    let head = p.get_block_number().await.map_err(|e| e.to_string())?;
    let safe = head.saturating_sub(shared.cfg.confirmations);
    shared.status.head.store(head, Ordering::Relaxed);
    shared.status.confirmed.store(safe, Ordering::Relaxed);
    if *checkpoint >= safe {
        return Ok(true);
    }
    let from = *checkpoint + 1;
    let to = safe.min(from + *range - 1);

    let pools = shared.quest_pools.lock().expect("pools lock").clone();
    let pool_ids: Vec<B256> = pools.keys().copied().collect();
    let mut logs = Vec::new();
    let watched = shared.dep.watched();
    let fetch =
        |filter: Filter| async move { p.get_logs(&filter).await.map_err(|e| e.to_string()) };
    let result = async {
        if !watched.is_empty() {
            logs.extend(fetch(Filter::new().address(watched).from_block(from).to_block(to)).await?);
        }
        if let (Some(pm), false) = (shared.dep.pool_manager, pool_ids.is_empty()) {
            let f = Filter::new()
                .address(pm)
                .event_signature(IPoolManager::Swap::SIGNATURE_HASH)
                .topic1(pool_ids.clone())
                .from_block(from)
                .to_block(to);
            logs.extend(fetch(f).await?);
        }
        Ok::<_, String>(())
    }
    .await;
    if let Err(e) = result {
        if *range > 1 && range_error(&e) {
            *range = (*range / 2).max(1);
            tracing::warn!(
                range = *range,
                "log range too wide for this node; narrowing"
            );
        }
        return Err(e);
    }
    logs.retain(|l| !l.removed);
    logs.sort_by_key(|l| {
        (
            l.block_number.unwrap_or_default(),
            l.log_index.unwrap_or_default(),
        )
    });

    // Quest swaps are attributed by the transaction's sender.
    let mut senders: HashMap<B256, Address> = HashMap::new();
    for l in &logs {
        if l.topic0() == Some(&IPoolManager::Swap::SIGNATURE_HASH) {
            if let Some(h) = l.transaction_hash {
                if let std::collections::hash_map::Entry::Vacant(v) = senders.entry(h) {
                    if let Some(tx) = p
                        .get_transaction_by_hash(h)
                        .await
                        .map_err(|e| e.to_string())?
                    {
                        v.insert(tx.from());
                    }
                }
            }
        }
    }

    let decoded: Vec<(u64, u64, Observation)> = {
        let wallets = shared.wallets.lock().expect("wallets lock");
        let intents = shared.intents.lock().expect("intents lock");
        let names = Snapshot {
            wallets: &wallets,
            intents: &intents,
        };
        logs.iter()
            .filter_map(|l| {
                let from = l.transaction_hash.and_then(|h| senders.get(&h).copied());
                decode(l, &shared.dep, &pools, &names, from).map(|o| {
                    (
                        l.block_number.unwrap_or_default(),
                        l.log_index.unwrap_or_default(),
                        o,
                    )
                })
            })
            .collect()
    };
    // Block timestamps: from the log when the node includes them, otherwise one header read per block.
    let mut times: HashMap<u64, u64> = HashMap::new();
    for l in &logs {
        if let (Some(b), Some(t)) = (l.block_number, l.block_timestamp) {
            times.insert(b, t);
        }
    }
    if decoded
        .iter()
        .any(|(_, _, o)| matches!(o, Observation::CampaignCreated { .. }))
    {
        shared.pools_stale.store(true, Ordering::Relaxed);
    }
    let n = decoded.len();
    for (block, index, o) in decoded {
        let time = match times.get(&block) {
            Some(t) => *t,
            None => {
                let t = shared.block_time(block).await;
                times.insert(block, t);
                t
            }
        };
        shared.emit(block, index, time, o);
    }
    *checkpoint = to;
    write_json(
        &checkpoint_path(&shared.cfg.data_dir),
        &Checkpoint {
            chain_id: shared.cfg.chain_id,
            block: to,
        },
    )
    .map_err(|e| e.to_string())?;
    shared.status.checkpoint.store(to, Ordering::Relaxed);
    if n > 0 {
        tracing::debug!(from, to, observations = n, "indexed");
    }
    // Widen again slowly after a narrowing.
    *range = (*range * 2).min(shared.cfg.log_range);
    Ok(to >= safe)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::deployments::{Deployments, QuestPool};
    use crate::eip712::{item_hash, ref_hash};
    use crate::types::Bucket;
    use alloy::primitives::{LogData, Uint};

    const DEP: &str = r#"{
      "chainId": 31337,
      "contracts": {
        "MealCounter": "0x00000000000000000000000000000000000000a1",
        "HousePool": "0x00000000000000000000000000000000000000a4",
        "CampaignEscrow": "0x00000000000000000000000000000000000000a5",
        "SpiceMerchant": "0x00000000000000000000000000000000000000a7",
        "FoodHook": "0x00000000000000000000000000000000000000a9",
        "QuestToken": "0x00000000000000000000000000000000000000f0"
      },
      "uniswap": { "poolManager": "0x00000000000000000000000000000000000000b1" },
      "usdc": "0x00000000000000000000000000000000000000c1"
    }"#;

    struct Names;
    impl Naming for Names {
        fn player(&self, a: &Address) -> Option<String> {
            (*a == Address::repeat_byte(0xaa)).then(|| "asha".to_string())
        }
        fn server_ref(&self, h: &B256) -> Option<String> {
            (*h == ref_hash("m1")).then(|| "m1".to_string())
        }
        fn item(&self, h: &B256) -> Option<String> {
            (*h == item_hash("chai")).then(|| "chai".to_string())
        }
    }

    fn log(address: Address, data: LogData) -> Log {
        Log {
            inner: alloy::primitives::Log { address, data },
            block_number: Some(5),
            log_index: Some(2),
            transaction_hash: Some(B256::repeat_byte(9)),
            ..Default::default()
        }
    }

    fn pools(d: &Deployments) -> HashMap<B256, QuestPool> {
        d.quest_pool.iter().map(|q| (q.id, q.clone())).collect()
    }

    fn decode_t(
        l: &Log,
        d: &Deployments,
        names: &dyn Naming,
        from: Option<Address>,
    ) -> Option<Observation> {
        decode(l, d, &pools(d), names, from)
    }

    fn dep() -> Deployments {
        Deployments::parse(DEP, 31_337).unwrap()
    }

    #[test]
    fn meal_eaten_maps_back_to_server_words() {
        let d = dep();
        let e = IMealCounter::MealEaten {
            player: Address::repeat_byte(0xaa),
            r#ref: ref_hash("m1"),
            item: item_hash("chai"),
            usdcPaid: U256::from(4_000u64),
            foodBurned: U256::from(1_000_000u64),
            fromRation: U256::ZERO,
        };
        let l = log(d.contract("MealCounter").unwrap(), e.encode_log_data());
        let o = decode(&l, &d, &pools(&d), &Names, None).unwrap();
        assert_eq!(
            o,
            Observation::MealEaten {
                player: "asha".into(),
                item: "chai".into(),
                usdc: 4_000,
                food: 1_000_000,
                from_ration: 0,
                reference: "m1".into(),
                tx: B256::repeat_byte(9).to_string(),
            }
        );
        // The same event from any other address is ignored.
        let spoof = log(Address::repeat_byte(0x66), e.encode_log_data());
        assert_eq!(decode(&spoof, &d, &pools(&d), &Names, None), None);
    }

    #[test]
    fn unknown_players_and_refs_stay_as_hex() {
        let d = dep();
        let e = IHousePool::Paid {
            source: 1,
            player: Address::repeat_byte(0xbb),
            humanId: B256::repeat_byte(3),
            amount: U256::from(250_000u64),
            r#ref: ref_hash("other"),
        };
        let o = decode_t(
            &log(d.contract("HousePool").unwrap(), e.encode_log_data()),
            &d,
            &Names,
            None,
        )
        .unwrap();
        match o {
            Observation::Paid {
                bucket,
                player,
                reference,
                amount,
                ..
            } => {
                assert_eq!(bucket, Bucket::Surprise);
                assert_eq!(player, Address::repeat_byte(0xbb).to_string());
                assert_eq!(reference, ref_hash("other").to_string());
                assert_eq!(amount, 250_000);
            }
            other => panic!("{other:?}"),
        }
        let bad = IHousePool::Paid { source: 3, ..e };
        assert_eq!(
            decode_t(
                &log(d.contract("HousePool").unwrap(), bad.encode_log_data()),
                &d,
                &Names,
                None
            ),
            None
        );
    }

    #[test]
    fn campaign_events() {
        let d = dep();
        let esc = d.contract("CampaignEscrow").unwrap();
        let p = CampaignParams {
            template: B256::repeat_byte(1),
            metaHash: B256::repeat_byte(2),
            budget: U256::from(100_000_000u64),
            payoutPerClaim: U256::from(400_000u64),
            energyCost: 20,
            maxClaims: 200,
            perHumanCap: 1,
            start: 10,
            end: 20,
            kind: 0,
            deliverTo: Address::repeat_byte(4),
            questToken: Address::repeat_byte(0xf0),
        };
        let e = ICampaignEscrow::CampaignCreated {
            campaignId: U256::from(1u64),
            sponsor: Address::repeat_byte(5),
            params: p,
            net: U256::from(90_000_000u64),
            fee: U256::from(10_000_000u64),
        };
        match decode_t(&log(esc, e.encode_log_data()), &d, &Names, None).unwrap() {
            Observation::CampaignCreated {
                id,
                payout_per_claim,
                max_claims,
                budget,
                template,
                ..
            } => {
                assert_eq!(
                    (id, payout_per_claim, max_claims, budget),
                    (1, 400_000, 200, 90_000_000)
                );
                assert_eq!(template, B256::repeat_byte(1).to_string());
            }
            other => panic!("{other:?}"),
        }
        let e = ICampaignEscrow::Claimed {
            campaignId: U256::from(1u64),
            player: Address::repeat_byte(0xaa),
            humanId: B256::repeat_byte(3),
            amount: U256::from(400_000u64),
            advanceRepaid: U256::from(100_000u64),
            r#ref: ref_hash("m1"),
        };
        assert!(matches!(
            decode_t(&log(esc, e.encode_log_data()), &d, &Names, None),
            Some(Observation::Claimed {
                amount: 300_000, // 400,000 voucher less the 100,000 advance it repaid
                advance_repaid: 100_000,
                ..
            })
        ));
        let e = ISpiceMerchant::Delivered {
            campaignId: U256::from(1u64),
            player: Address::repeat_byte(0xaa),
            token: Address::repeat_byte(0xf0),
            amount: U256::from(10u64).pow(U256::from(18u64)),
            questRef: ref_hash("m1"),
        };
        assert!(matches!(
            decode_t(
                &log(d.contract("SpiceMerchant").unwrap(), e.encode_log_data()),
                &d,
                &Names,
                None
            ),
            Some(Observation::Delivered {
                amount: 1_000_000_000_000_000_000,
                ..
            })
        ));
    }

    #[test]
    fn quest_swaps_need_the_pool_and_a_player_sender() {
        let d = dep();
        let qp = d.quest_pool.clone().unwrap();
        let pm = d.pool_manager.unwrap();
        // USDC (0x…c1) is currency0: the player pays 2 USDC (negative) and takes 5 MANGO.
        let e = IPoolManager::Swap {
            id: qp.id,
            sender: Address::repeat_byte(0x77),
            amount0: -2_000_000i128,
            amount1: 5_000_000_000_000_000_000i128,
            sqrtPriceX96: Uint::<160, 3>::from(1u64),
            liquidity: 1,
            tick: alloy::primitives::Signed::<24, 1>::ZERO,
            fee: Uint::<24, 1>::from(3_000u32),
        };
        let l = log(pm, e.encode_log_data());
        let o = decode(&l, &d, &pools(&d), &Names, Some(Address::repeat_byte(0xaa))).unwrap();
        assert_eq!(
            o,
            Observation::QuestSwap {
                player: "asha".into(),
                token_in: d.usdc.to_string(),
                token_out: qp.token.to_string(),
                amount_in: 2_000_000,
                amount_out: 5_000_000_000_000_000_000,
                tx: B256::repeat_byte(9).to_string(),
            }
        );
        // A stranger's swap, or another pool, is not a quest swap.
        assert_eq!(
            decode(&l, &d, &pools(&d), &Names, Some(Address::repeat_byte(0x01))),
            None
        );
        let other = IPoolManager::Swap {
            id: B256::repeat_byte(1),
            ..e
        };
        assert_eq!(
            decode_t(
                &log(pm, other.encode_log_data()),
                &d,
                &Names,
                Some(Address::repeat_byte(0xaa))
            ),
            None
        );
    }

    #[test]
    fn food_market_events() {
        let d = dep();
        let e = IFoodHook::TradeCounted {
            day: U256::from(3u64),
            usdc: U256::from(4_000u64),
            food: U256::from(1_000_000u64),
            priceAfter: U256::from(4_100u64),
        };
        assert!(matches!(
            decode_t(
                &log(d.contract("FoodHook").unwrap(), e.encode_log_data()),
                &d,
                &Names,
                None
            ),
            Some(Observation::FoodTrade {
                day: 3,
                price_after: 4_100,
                ..
            })
        ));
    }

    #[test]
    fn checkpoint_start_and_resume() {
        let dir = tempfile::tempdir().unwrap();
        assert_eq!(initial_checkpoint(dir.path(), 1, None, 100).unwrap(), 99);
        assert_eq!(initial_checkpoint(dir.path(), 1, None, 0).unwrap(), 0);
        write_json(
            &checkpoint_path(dir.path()),
            &Checkpoint {
                chain_id: 1,
                block: 150,
            },
        )
        .unwrap();
        assert_eq!(initial_checkpoint(dir.path(), 1, None, 100).unwrap(), 150);
        assert_eq!(
            initial_checkpoint(dir.path(), 1, Some(120), 100).unwrap(),
            120
        );
        assert!(initial_checkpoint(dir.path(), 2, None, 100).is_err());
    }

    #[test]
    fn amounts_saturate() {
        assert_eq!(u64_of(U256::MAX), u64::MAX);
        assert_eq!(u64_of(U256::from(7u64)), 7);
        assert!(range_error("query exceeds max block range 500"));
        assert!(!range_error("connection refused"));
    }
}
