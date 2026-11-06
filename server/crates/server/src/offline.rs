//! The in-process ledger for `chain.mode = "offline"`: the contracts' money rules, played out in memory, so the whole
//! game runs and is tested with no network. It keeps what the contracts would: wallets and USDC balances, HousePool's
//! buckets with their 4% daily budget and per-human cap, the Treasury's split, campaigns with their slots, per-human
//! caps, daily caps and advances, quest tokens from the kiosk, names and records, and the weekly draw.
//!
//! Nothing here is persisted. On a restart it's rebuilt from the world, which saw every observation it ever made, so it
//! picks up where it was. Offline, food is bought and sold in the town's own pool, not here.

use crate::ledger::{keccak_hex, Ledger};
use rules::chain::{Bucket, HumanId, Intent, Observation, Observed, NOT_A_LOG};
use rules::{Config, State, Usdc};
use serde::Deserialize;
use std::collections::{BTreeMap, BTreeSet};
use std::time::{SystemTime, UNIX_EPOCH};

const BPS: u128 = 10_000;
const DAY_S: u64 = 86_400;

#[derive(Clone, Debug, Deserialize)]
pub struct OfflineCampaign {
    pub template: String,
    pub sponsor: String,
    pub budget: Usdc,
    pub payout_per_claim: Usdc,
    pub energy_cost: u32,
    pub max_claims: u32,
    pub per_human_cap: u16,
    pub days: u64,
    pub kind: u8,
}

/// rules.toml's `[offline]`.
#[derive(Clone, Debug, Deserialize)]
pub struct OfflineConfig {
    pub fixed: Usdc,
    pub surprise: Usdc,
    pub safety: Usdc,
    pub start_usdc: Usdc,
    pub quest_pool_usdc: Usdc,
    /// Whole quest tokens.
    pub quest_pool_tokens: u64,
    pub quest_pool_fee_bps: u32,
    pub quest_token_symbol: String,
    pub quest_token_decimals: u8,
    pub min_payout: Usdc,
    pub energy_per_food: u64,
    #[serde(default)]
    pub max_advance: Option<Usdc>,
    #[serde(default)]
    pub campaigns: Vec<OfflineCampaign>,
}

#[derive(Deserialize)]
struct Whole {
    offline: OfflineConfig,
}

#[derive(Clone, Debug)]
struct Campaign {
    template: String,
    payout: Usdc,
    max_claims: u32,
    per_human_cap: u16,
    end: u64,
    remaining: Usdc,
    claims: u32,
    per_human: BTreeMap<HumanId, u32>,
    advances: BTreeMap<HumanId, Usdc>,
    paid_today: (u64, Usdc),
    closed: bool,
}

pub struct OfflineLedger {
    config: OfflineConfig,
    rules: Config,
    queue: Vec<Intent>,
    started: bool,
    block: u64,
    /// The town's real day, which the hub keeps up to date, for HousePool's daily budget.
    day: u64,
    budget_day: Option<u64>,
    wallets: BTreeMap<String, String>,
    usdc: BTreeMap<String, Usdc>,
    tokens: BTreeMap<String, u128>,
    pools: [Usdc; 3],
    budget_left: [Usdc; 3],
    human_paid: BTreeMap<HumanId, Usdc>,
    treasury: Usdc,
    campaigns: BTreeMap<u64, Campaign>,
    draws: BTreeMap<u64, (u64, Usdc)>,
    settled: BTreeSet<String>,
    names: BTreeSet<String>,
    /// The quest pool's USDC and quest tokens, in base units.
    quest_pool: (u128, u128),
}

fn index(bucket: Bucket) -> usize {
    match bucket {
        Bucket::Fixed => 0,
        Bucket::Surprise => 1,
        Bucket::Safety => 2,
    }
}

fn unix_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs())
}

fn share(amount: Usdc, bps: u32) -> Usdc {
    (u128::from(amount) * u128::from(bps) / BPS) as Usdc
}

impl OfflineLedger {
    /// A fresh offline chain from rules.toml: buckets seeded from `[offline]`, its campaigns opened on the first poll.
    pub fn new(rules_toml: &str) -> Result<Self, String> {
        let rules: Config = toml::from_str(rules_toml).map_err(|e| format!("rules.toml: {e}"))?;
        let whole: Whole =
            toml::from_str(rules_toml).map_err(|e| format!("rules.toml [offline]: {e}"))?;
        let config = whole.offline;
        let unit = 10u128.pow(u32::from(config.quest_token_decimals));
        let quest_pool = (
            u128::from(config.quest_pool_usdc),
            u128::from(config.quest_pool_tokens) * unit,
        );
        Ok(OfflineLedger {
            quest_pool,
            pools: [config.fixed, config.surprise, config.safety],
            budget_left: [0; 3],
            config,
            rules,
            queue: Vec::new(),
            started: false,
            block: 0,
            day: 0,
            budget_day: None,
            wallets: BTreeMap::new(),
            usdc: BTreeMap::new(),
            tokens: BTreeMap::new(),
            human_paid: BTreeMap::new(),
            treasury: 0,
            campaigns: BTreeMap::new(),
            draws: BTreeMap::new(),
            settled: BTreeSet::new(),
            names: BTreeSet::new(),
        })
    }

    /// The offline chain as the world last saw it, after a restart. A world that never saw the pools gets a fresh one.
    pub fn resume(rules_toml: &str, state: &State) -> Result<Self, String> {
        let mut ledger = Self::new(rules_toml)?;
        ledger.block = state.chain.block;
        ledger.day = state.real_day();
        // The world keeps its own refs; the chain sees them with the town's id in front.
        ledger.settled = state
            .chain
            .settled
            .iter()
            .map(|r| state.chain_ref(r))
            .collect();
        ledger.quest_pool.0 += u128::from(state.chain.quest_usdc_in);
        ledger.quest_pool.1 = ledger
            .quest_pool
            .1
            .saturating_sub(state.chain.quest_tokens_out);
        for (name, p) in state.life.players() {
            if let Some(wallet) = &p.wallet {
                ledger.wallets.insert(name.clone(), wallet.clone());
                ledger.usdc.insert(name.clone(), p.usdc.unwrap_or(0));
                ledger.tokens.insert(name.clone(), p.quest_tokens);
            }
            if p.ens.is_some() {
                ledger.names.insert(name.clone());
            }
        }
        if !state.house.seen {
            return Ok(ledger);
        }
        ledger.started = true;
        for bucket in Bucket::ALL {
            let book = state.house.book(bucket);
            ledger.pools[index(bucket)] = book.balance;
            ledger.budget_left[index(bucket)] = book.budget_left;
        }
        ledger.budget_day = Some(ledger.day);
        let t = &state.house.treasury;
        ledger.treasury = t.revenue_total.saturating_sub(t.split_total);
        for c in state.campaigns.all() {
            let mut per_human = BTreeMap::new();
            for (_, p) in state.life.players() {
                let done = p.campaigns_done.get(&c.id).copied().unwrap_or(0);
                if let (Some(human), true) = (&p.human, done > 0) {
                    per_human.insert(human.clone(), done);
                }
            }
            let campaign = Campaign {
                template: c.template.clone(),
                payout: c.payout,
                max_claims: c.max_claims,
                per_human_cap: c.per_human_cap,
                end: c.end,
                remaining: c.remaining(),
                claims: c.claims,
                per_human,
                advances: BTreeMap::new(),
                paid_today: (ledger.day, 0),
                closed: c.closed,
            };
            ledger.campaigns.insert(c.id, campaign);
        }
        for draw in state.games.draws.values() {
            ledger
                .draws
                .insert(state.chain_week(draw.week), (draw.count, draw.prize));
        }
        Ok(ledger)
    }

    /// The town's real day, for the pool's daily budget. The hub calls this as the clock moves.
    pub fn set_day(&mut self, day: u64) {
        self.day = day;
    }

    /// Rehearsal: USDC into a player's wallet, as a faucet would.
    pub fn fund(&mut self, player: &str, usdc: Usdc) -> Result<Vec<Observation>, String> {
        if !self.wallets.contains_key(player) {
            return Err(format!("{player} has no wallet yet"));
        }
        let balance = self.usdc.entry(player.to_string()).or_insert(0);
        *balance += usdc;
        let usdc = *balance;
        Ok(vec![Observation::Balances {
            player: player.to_string(),
            usdc,
        }])
    }

    /// Rehearsal: USDC into a HousePool bucket, as `fund(bucket, amount)` would.
    pub fn fund_bucket(&mut self, bucket: Bucket, usdc: Usdc) -> Vec<Observation> {
        self.pools[index(bucket)] += usdc;
        vec![self.pool_balances()]
    }

    /// Rehearsal: a sponsor opens a campaign. Refused as CampaignEscrow would: the 25% rule and the minimum payout.
    pub fn open_campaign(&mut self, c: &OfflineCampaign) -> Result<Vec<Observation>, String> {
        let per_energy = self.rules.food.ceiling / self.config.energy_per_food.max(1);
        if u64::from(c.energy_cost) * per_energy * 4 > c.payout_per_claim {
            return Err("CampaignEscrow__QuestTooCheap: food for the quest's energy at the ceiling price is over 25% of the payout".to_string());
        }
        if c.payout_per_claim < self.config.min_payout {
            return Err(format!(
                "CampaignEscrow__PayoutTooSmall: at least {}",
                self.config.min_payout
            ));
        }
        if !rules::book::TEMPLATES.contains(&c.template.as_str()) {
            return Err(format!("unknown template {}", c.template));
        }
        let id = self.campaigns.keys().next_back().map_or(1, |id| id + 1);
        let start = unix_now();
        let end = start + c.days.max(1) * DAY_S;
        // The platform keeps 10% at deposit; the rest is the campaign's to spend.
        let budget = c.budget - c.budget / 10;
        self.campaigns.insert(
            id,
            Campaign {
                template: c.template.clone(),
                payout: c.payout_per_claim,
                max_claims: c.max_claims,
                per_human_cap: c.per_human_cap,
                end,
                remaining: budget,
                claims: 0,
                per_human: BTreeMap::new(),
                advances: BTreeMap::new(),
                paid_today: (self.day, 0),
                closed: false,
            },
        );
        // Half the fee goes to the SURPRISE bucket.
        self.pools[index(Bucket::Surprise)] += c.budget / 20;
        Ok(vec![
            Observation::CampaignCreated {
                id,
                sponsor: c.sponsor.clone(),
                template: c.template.clone(),
                meta_hash: String::new(),
                budget,
                payout_per_claim: c.payout_per_claim,
                energy_cost: c.energy_cost,
                max_claims: c.max_claims,
                per_human_cap: c.per_human_cap,
                start,
                end,
                kind: c.kind,
                deliver_to: format!("offline sponsor {}", c.sponsor),
            },
            self.pool_balances(),
        ])
    }

    fn pool_balances(&mut self) -> Observation {
        self.roll_day();
        let [fixed, surprise, safety] = self.pools;
        let [budget_fixed, budget_surprise, budget_safety] = self.budget_left;
        Observation::PoolBalances {
            fixed,
            surprise,
            safety,
            budget_fixed,
            budget_surprise,
            budget_safety,
        }
    }

    /// HousePool's day: each bucket's budget is 4% of its balance at the day's start.
    fn roll_day(&mut self) {
        if self.budget_day == Some(self.day) {
            return;
        }
        self.budget_day = Some(self.day);
        self.human_paid.clear();
        let bps = self.rules.house.budget_bps;
        for i in 0..3 {
            self.budget_left[i] = share(self.pools[i], bps);
        }
    }

    fn tx(&self, n: usize) -> String {
        keccak_hex(format!("offline-tx:{}:{n}", self.block).as_bytes())
    }

    fn balance(&self, player: &str) -> Observation {
        Observation::Balances {
            player: player.to_string(),
            usdc: self.usdc.get(player).copied().unwrap_or(0),
        }
    }

    /// What a meal ticket's most pays: the quote, without the ticket's headroom.
    fn charge(&self, max_usdc: Usdc) -> Usdc {
        let slippage = u128::from(self.rules.meals.slippage_bps);
        (u128::from(max_usdc) * BPS / (BPS + slippage)) as Usdc
    }

    fn settle(&mut self, intent: Intent, out: &mut Vec<Observation>) {
        if let Some(reference) = intent.reference() {
            if !self.settled.insert(reference.to_string()) {
                return;
            }
        }
        let failed = |reference: &str, reason: &str| Observation::IntentFailed {
            reference: reference.to_string(),
            reason: reason.to_string(),
        };
        let tx = self.tx(out.len());
        match intent {
            Intent::EnsureWallet { player } => {
                if self.wallets.contains_key(&player) {
                    return;
                }
                let hash = keccak_hex(format!("offline-wallet:{player}").as_bytes());
                let address = format!("0x{}", &hash[26..]);
                self.wallets.insert(player.clone(), address.clone());
                self.usdc.insert(player.clone(), self.config.start_usdc);
                out.push(Observation::WalletReady {
                    player: player.clone(),
                    address,
                });
                out.push(self.balance(&player));
            }
            Intent::BuyMeal {
                player,
                item,
                food,
                max_usdc,
                reference,
            } => {
                let charge = self.charge(max_usdc);
                let balance = self.usdc.entry(player.clone()).or_insert(0);
                if *balance < charge {
                    out.push(failed(&reference, "ERC20InsufficientBalance"));
                    return;
                }
                *balance -= charge;
                self.treasury += charge;
                out.push(Observation::MealEaten {
                    player: player.clone(),
                    item,
                    usdc: charge,
                    food,
                    from_ration: 0,
                    reference,
                    tx,
                });
                out.push(self.balance(&player));
            }
            Intent::SellHarvest { reference, .. } => {
                out.push(failed(
                    &reference,
                    "offline, the harvest sells into the town's own pool",
                ));
            }
            Intent::PayHouse {
                player,
                human_id,
                bucket,
                amount,
                reference,
            } => {
                if let Err(reason) = self.pay_from(bucket, &human_id, amount) {
                    out.push(failed(&reference, reason));
                    return;
                }
                *self.usdc.entry(player.clone()).or_insert(0) += amount;
                out.push(Observation::Paid {
                    bucket,
                    player: player.clone(),
                    human_id,
                    amount,
                    reference,
                    tx,
                });
                out.push(self.balance(&player));
                out.push(self.pool_balances());
            }
            Intent::PayRescueMeal {
                player,
                human_id,
                item,
                food,
                max_usdc,
                reference,
            } => {
                let charge = self.charge(max_usdc);
                if let Err(reason) = self.pay_from(Bucket::Safety, &human_id, charge) {
                    out.push(failed(&reference, reason));
                    return;
                }
                self.treasury += charge;
                out.push(Observation::MealEaten {
                    player,
                    item,
                    usdc: charge,
                    food,
                    from_ration: 0,
                    reference,
                    tx,
                });
                out.push(self.pool_balances());
            }
            Intent::ClaimCampaign {
                campaign,
                player,
                human_id,
                amount,
                reference,
            } => {
                let day = self.day;
                let Some(c) = self.campaigns.get_mut(&campaign) else {
                    out.push(failed(&reference, "CampaignEscrow__UnknownCampaign"));
                    return;
                };
                let held = c.per_human.get(&human_id).copied().unwrap_or(0);
                let now = unix_now();
                let days_left = c.end.saturating_sub(now).div_ceil(DAY_S).max(1);
                let daily_cap = c.remaining / days_left;
                if c.paid_today.0 != day {
                    c.paid_today = (day, 0);
                }
                let reason = if c.closed || now >= c.end {
                    Some("CampaignEscrow__NotLive")
                } else if c.claims >= c.max_claims {
                    Some("CampaignEscrow__NoClaimsLeft")
                } else if held >= u32::from(c.per_human_cap) {
                    Some("CampaignEscrow__PerHumanCap")
                } else if amount > c.payout || amount > c.remaining {
                    Some("CampaignEscrow__OverBudget")
                } else if c.paid_today.1 > 0 && c.paid_today.1 + amount > daily_cap {
                    Some("CampaignEscrow__DailyCapReached")
                } else {
                    None
                };
                if let Some(reason) = reason {
                    out.push(failed(&reference, reason));
                    return;
                }
                let advance_repaid = c.advances.remove(&human_id).unwrap_or(0).min(amount);
                let paid = amount - advance_repaid;
                c.remaining -= paid;
                c.claims += 1;
                c.paid_today.1 += amount;
                c.per_human.insert(human_id.clone(), held + 1);
                *self.usdc.entry(player.clone()).or_insert(0) += paid;
                out.push(Observation::Claimed {
                    campaign,
                    player: player.clone(),
                    human_id,
                    amount: paid,
                    advance_repaid,
                    reference,
                    tx,
                });
                out.push(self.balance(&player));
            }
            Intent::Advance {
                campaign,
                player,
                human_id,
                amount,
                reference,
            } => {
                let most = self.config.max_advance.unwrap_or(1_000_000);
                let Some(c) = self.campaigns.get_mut(&campaign) else {
                    out.push(failed(&reference, "CampaignEscrow__UnknownCampaign"));
                    return;
                };
                if c.advances.contains_key(&human_id) {
                    out.push(failed(&reference, "CampaignEscrow__AdvanceOpen"));
                    return;
                }
                if amount > most || amount > c.remaining || c.closed {
                    out.push(failed(&reference, "CampaignEscrow__AdvanceTooBig"));
                    return;
                }
                c.remaining -= amount;
                c.advances.insert(human_id.clone(), amount);
                *self.usdc.entry(player.clone()).or_insert(0) += amount;
                out.push(Observation::Advanced {
                    campaign,
                    player: player.clone(),
                    human_id,
                    amount,
                    reference,
                    tx,
                });
                out.push(self.balance(&player));
            }
            Intent::SwapForQuest {
                player,
                usdc_in,
                min_out,
                reference,
                ..
            } => {
                let amount_out = self.quest_quote(usdc_in);
                let balance = self.usdc.entry(player.clone()).or_insert(0);
                if *balance < usdc_in {
                    out.push(failed(&reference, "ERC20InsufficientBalance"));
                    return;
                }
                if amount_out < min_out {
                    out.push(failed(&reference, "V4TooLittleReceived"));
                    return;
                }
                *balance -= usdc_in;
                self.quest_pool.0 += u128::from(usdc_in);
                self.quest_pool.1 -= amount_out;
                *self.tokens.entry(player.clone()).or_insert(0) += amount_out;
                out.push(Observation::QuestSwap {
                    player: player.clone(),
                    token_in: "USDC".to_string(),
                    token_out: self.config.quest_token_symbol.clone(),
                    amount_in: u128::from(usdc_in),
                    amount_out,
                    tx,
                });
                out.push(self.balance(&player));
            }
            Intent::QuoteSwap {
                player,
                campaign,
                usdc_in,
                reference,
            } => {
                out.push(Observation::SwapQuoted {
                    player,
                    campaign,
                    usdc_in,
                    amount_out: self.quest_quote(usdc_in),
                    fee_bps: self.config.quest_pool_fee_bps,
                    token: format!("offline:{}", self.config.quest_token_symbol),
                    symbol: self.config.quest_token_symbol.clone(),
                    decimals: self.config.quest_token_decimals,
                    reference,
                });
            }
            Intent::Deliver {
                player,
                campaign,
                reference,
            } => {
                let for_the_merchant = self
                    .campaigns
                    .get(&campaign)
                    .is_some_and(|c| c.template == "spice_run" && !c.closed);
                if !for_the_merchant {
                    out.push(failed(&reference, "SpiceMerchant__NotASpiceRun"));
                    return;
                }
                let amount = self.tokens.remove(&player).unwrap_or(0);
                if amount == 0 {
                    out.push(failed(&reference, "SpiceMerchant__NothingToDeliver"));
                    return;
                }
                out.push(Observation::Delivered {
                    campaign,
                    player,
                    token: self.config.quest_token_symbol.clone(),
                    amount,
                    reference,
                    tx,
                });
            }
            Intent::RegisterName { player, label } => {
                if !self.names.insert(player.clone()) {
                    return;
                }
                let name = format!("{label}.{}", self.rules.ens.parent);
                out.push(Observation::NameRegistered {
                    player,
                    label,
                    name,
                    tx,
                });
            }
            Intent::SetRecords { player, records } => {
                if !self.names.contains(&player) {
                    out.push(failed(&format!("records:{player}"), "no name to write on"));
                    return;
                }
                out.push(Observation::RecordsSet {
                    player,
                    records,
                    tx,
                });
            }
            Intent::Split => {
                if self.treasury == 0 {
                    return;
                }
                let total = std::mem::take(&mut self.treasury);
                let t = self.rules.treasury;
                let (fixed, safety, ops) = (
                    share(total, t.fixed_bps),
                    share(total, t.safety_bps),
                    share(total, t.ops_bps),
                );
                let team = total - fixed - safety - ops;
                self.pools[index(Bucket::Fixed)] += fixed;
                self.pools[index(Bucket::Safety)] += safety;
                out.push(Observation::Split {
                    total,
                    fixed,
                    safety,
                    ops,
                    team,
                    tx,
                });
                out.push(self.pool_balances());
            }
            Intent::Rebalance | Intent::HarvestYield => {
                // No venues offline: the float is all liquid, and earns nothing.
                let liabilities: Usdc = self
                    .campaigns
                    .values()
                    .filter(|c| !c.closed)
                    .map(|c| c.remaining)
                    .sum();
                out.push(Observation::FloatState {
                    total_assets: liabilities,
                    liquid: liabilities,
                    invested: 0,
                    buffer: liabilities,
                    liabilities,
                    loss_reserve: 0,
                    yield_earned: 0,
                });
            }
            Intent::CommitDraw {
                week,
                seed_hash,
                count,
                prize,
                ..
            } => {
                if self.draws.contains_key(&week) {
                    return;
                }
                self.draws.insert(week, (count, prize));
                out.push(Observation::DrawCommitted {
                    week,
                    seed_hash,
                    root: "offline".to_string(),
                    count,
                    prize,
                    tx,
                });
            }
            Intent::RevealDraw { week, seed } => {
                let Some((count, _)) = self.draws.get(&week).copied() else {
                    out.push(failed(
                        &format!("draw-reveal:{week}"),
                        "LuckyLedger__NotCommitted",
                    ));
                    return;
                };
                let hash = keccak_hex(seed.as_bytes());
                let roll = u64::from_str_radix(&hash[2..18], 16).unwrap_or(0);
                out.push(Observation::DrawRevealed {
                    week,
                    seed,
                    winner_index: roll % count.max(1),
                    tx,
                });
            }
            Intent::ClaimDraw { week, player, .. } => {
                let Some((_, prize)) = self.draws.get(&week).copied() else {
                    return;
                };
                let surprise = &mut self.pools[index(Bucket::Surprise)];
                let prize = prize.min(*surprise);
                *surprise -= prize;
                *self.usdc.entry(player.clone()).or_insert(0) += prize;
                out.push(Observation::DrawClaimed {
                    week,
                    player: player.clone(),
                    prize,
                    tx,
                });
                out.push(self.balance(&player));
                out.push(self.pool_balances());
            }
            Intent::CheckHolding {
                player,
                campaign,
                reference,
            } => {
                let amount = self.tokens.get(&player).copied().unwrap_or(0);
                out.push(Observation::Holding {
                    player,
                    campaign,
                    amount,
                    reference,
                });
            }
        }
    }

    /// What `usdc_in` buys from the quest pool now: Uniswap's constant product, after the pool's fee.
    fn quest_quote(&self, usdc_in: Usdc) -> u128 {
        let (usdc, tokens) = self.quest_pool;
        let fee = u128::from(self.config.quest_pool_fee_bps);
        let in_after_fee = u128::from(usdc_in) * (1_000_000 - fee) / 1_000_000;
        tokens * in_after_fee / (usdc + in_after_fee)
    }

    /// HousePool's checks: today's budget, the balance, and the per-human daily cap.
    fn pay_from(
        &mut self,
        bucket: Bucket,
        human: &HumanId,
        amount: Usdc,
    ) -> Result<(), &'static str> {
        self.roll_day();
        let i = index(bucket);
        let paid = self.human_paid.get(human).copied().unwrap_or(0);
        if amount > self.budget_left[i] {
            return Err("HousePool__OverDailyBudget");
        }
        if amount > self.pools[i] {
            return Err("HousePool__OverBalance");
        }
        if paid + amount > self.rules.house.per_human_daily_cap {
            return Err("HousePool__PerHumanDailyCap");
        }
        self.budget_left[i] -= amount;
        self.pools[i] -= amount;
        self.human_paid.insert(human.clone(), paid + amount);
        Ok(())
    }

    /// Wraps observations made outside a poll (rehearsals) as the next block, like any other.
    pub fn stamp(&mut self, observations: Vec<Observation>) -> Vec<Observed> {
        if observations.is_empty() {
            return Vec::new();
        }
        self.block += 1;
        let time = unix_now();
        observations
            .into_iter()
            .enumerate()
            .map(|(i, observed)| {
                let log_index = match observed {
                    Observation::Balances { .. }
                    | Observation::PoolBalances { .. }
                    | Observation::FloatState { .. }
                    | Observation::WalletReady { .. }
                    | Observation::Holding { .. }
                    | Observation::SwapQuoted { .. }
                    | Observation::IntentFailed { .. } => NOT_A_LOG,
                    _ => i as u64,
                };
                Observed {
                    block: self.block,
                    log_index,
                    time,
                    observed,
                }
            })
            .collect()
    }
}

impl Ledger for OfflineLedger {
    fn submit(&mut self, intent: Intent) {
        self.queue.push(intent);
    }

    fn poll(&mut self) -> Vec<Observed> {
        let mut out = Vec::new();
        if !self.started {
            self.started = true;
            out.push(self.pool_balances());
            for c in self.config.campaigns.clone() {
                match self.open_campaign(&c) {
                    Ok(more) => out.extend(more),
                    Err(problem) => {
                        eprintln!("offline campaign {} not opened: {problem}", c.template)
                    }
                }
            }
        }
        for intent in std::mem::take(&mut self.queue) {
            self.settle(intent, &mut out);
        }
        if self.budget_day != Some(self.day) && self.started {
            out.push(self.pool_balances());
        }
        self.stamp(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const RULES: &str = include_str!("../../../rules.toml");

    fn kinds(observed: &[Observed]) -> Vec<String> {
        observed
            .iter()
            .map(|o| {
                serde_json::to_value(&o.observed).unwrap()["type"]
                    .as_str()
                    .unwrap()
                    .to_string()
            })
            .collect()
    }

    #[test]
    fn the_first_poll_reports_the_pools_and_opens_the_configured_campaigns() {
        let mut ledger = OfflineLedger::new(RULES).unwrap();
        let first = ledger.poll();
        let seen = kinds(&first);
        assert_eq!(seen[0], "PoolBalances");
        assert!(
            seen.iter().filter(|k| *k == "CampaignCreated").count() >= 1,
            "{seen:?}"
        );
        assert!(ledger.poll().is_empty(), "nothing new");
    }

    #[test]
    fn a_ref_settles_once_and_a_payout_needs_budget_and_balance() {
        let mut ledger = OfflineLedger::new(RULES).unwrap();
        ledger.poll();
        let pay = |amount| Intent::PayHouse {
            player: "sam".into(),
            human_id: HumanId("0x1".into()),
            bucket: Bucket::Fixed,
            amount,
            reference: format!("pay-{amount}"),
        };
        ledger.submit(pay(1000));
        ledger.submit(pay(1000));
        let paid = kinds(&ledger.poll());
        assert_eq!(
            paid.iter().filter(|k| *k == "Paid").count(),
            1,
            "the same ref twice pays once: {paid:?}"
        );
        ledger.submit(pay(900_000_000));
        let refused = kinds(&ledger.poll());
        assert_eq!(
            refused,
            ["IntentFailed"],
            "4% of the bucket is the most a day"
        );
    }

    #[test]
    fn the_kiosk_quotes_from_the_same_pool_it_swaps_in() {
        let mut ledger = OfflineLedger::new(RULES).unwrap();
        ledger.poll();
        let funded = ledger.fund("sam", 0);
        assert!(funded.is_err(), "no wallet yet");
        ledger.submit(Intent::EnsureWallet {
            player: "sam".into(),
        });
        ledger.poll();
        ledger.fund("sam", 2_000_000).unwrap();
        let quote = |ledger: &mut OfflineLedger, reference: &str| {
            ledger.submit(Intent::QuoteSwap {
                player: "sam".into(),
                campaign: 1,
                usdc_in: 500_000,
                reference: reference.into(),
            });
            ledger
                .poll()
                .into_iter()
                .find_map(|o| match o.observed {
                    Observation::SwapQuoted {
                        amount_out,
                        fee_bps,
                        decimals,
                        symbol,
                        ..
                    } => {
                        assert_eq!((fee_bps, decimals, symbol.as_str()), (3000, 18, "MANGO"));
                        Some(amount_out)
                    }
                    _ => None,
                })
                .unwrap()
        };
        // 0.5 USDC less 0.3% into 5 USDC and 100 MANGO: 100 × 0.4985 ÷ 5.4985 MANGO.
        let first = quote(&mut ledger, "q1");
        assert_eq!(first, 100 * 10u128.pow(18) * 498_500 / 5_498_500);
        assert_eq!(quote(&mut ledger, "q2"), first, "a quote moves nothing");
        ledger.submit(Intent::SwapForQuest {
            player: "sam".into(),
            campaign: 1,
            usdc_in: 500_000,
            min_out: first,
            reference: "s1".into(),
        });
        let swapped = ledger.poll().into_iter().find_map(|o| match o.observed {
            Observation::QuestSwap { amount_out, .. } => Some(amount_out),
            _ => None,
        });
        assert_eq!(swapped, Some(first), "the swap gets what the quote said");
        assert!(
            quote(&mut ledger, "q3") < first,
            "and the next quote is dearer"
        );
        ledger.submit(Intent::SwapForQuest {
            player: "sam".into(),
            campaign: 1,
            usdc_in: 500_000,
            min_out: first,
            reference: "s2".into(),
        });
        let refused = kinds(&ledger.poll());
        assert_eq!(refused, ["IntentFailed"], "less than the least: refused");
    }

    #[test]
    fn a_campaign_below_the_25_percent_rule_is_refused() {
        let mut ledger = OfflineLedger::new(RULES).unwrap();
        let cheap = OfflineCampaign {
            template: "spice_run".into(),
            sponsor: "x".into(),
            budget: 10_000_000,
            payout_per_claim: 150_000,
            energy_cost: 50,
            max_claims: 10,
            per_human_cap: 1,
            days: 1,
            kind: 0,
        };
        // 50 energy is 5 FOOD, 0.04 USDC at the ceiling; four times that is over the 0.15 payout.
        assert!(ledger.open_campaign(&cheap).is_err());
        let fair = OfflineCampaign {
            energy_cost: 30,
            ..cheap
        };
        assert!(ledger.open_campaign(&fair).is_ok());
    }
}
