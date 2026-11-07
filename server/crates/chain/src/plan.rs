//! Intent → the transactions that carry it out (spec §3.2/§3.3). Reads the chain only to decide whether an approval
//! is needed and how much cargo to deliver; signs tickets and vouchers; sends nothing itself.

use crate::bindings::*;
use crate::config::ChainConfig;
use crate::deployments::{Deployments, SwapRoute};
use crate::eip712::{item_hash, ref_hash, VoucherSigner};
use crate::types::{Bucket, HumanId, Intent};
use alloy::primitives::{aliases::U48, Address, Bytes, B256, I256, U160, U256};
use alloy::sol_types::{SolCall, SolValue};
use std::collections::BTreeMap;

/// Who sends a transaction.
#[derive(Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Sender {
    Keeper,
    Names,
    GasStation,
    Player(String),
}

/// One transaction to send.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TxCall {
    pub sender: Sender,
    pub to: Address,
    pub data: Bytes,
    pub value: U256,
    /// For logs: `"approve"`, `"buyMeal"`…
    pub what: &'static str,
}

/// What the executor reports itself once every transaction succeeded (events the indexer can't see).
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum After {
    /// The indexer reports the outcome from the contract's event.
    Indexed,
    NameRegistered {
        player: String,
        label: String,
        name: String,
    },
    RecordsSet {
        player: String,
        records: BTreeMap<String, String>,
    },
    Withdrawn {
        player: String,
        to: String,
        amount: u64,
        reference: String,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Plan {
    pub txs: Vec<TxCall>,
    pub after: After,
}

/// A player's wallet as the planner needs it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PlayerInfo {
    pub address: Address,
    pub label: Option<String>,
}

/// Chain reads the planner needs (a trait so tests can answer them).
pub(crate) trait Reads {
    async fn erc20_allowance(
        &self,
        token: Address,
        owner: Address,
        spender: Address,
    ) -> Result<U256, String>;
    async fn erc20_balance(&self, token: Address, owner: Address) -> Result<U256, String>;
    /// Permit2's (amount, expiration) for owner → spender on token.
    async fn permit2_allowance(
        &self,
        permit2: Address,
        owner: Address,
        token: Address,
        spender: Address,
    ) -> Result<(U256, u64), String>;
    /// V4Quoter's price for an exact-input single-pool swap (simulated with `eth_call`).
    async fn quote_exact_in(
        &self,
        quoter: Address,
        key: PoolKey,
        zero_for_one: bool,
        amount_in: u64,
    ) -> Result<U256, String>;
    /// `CampaignEscrow.questToken(campaign)`: the token a campaign's quest uses (zero if none).
    async fn campaign_quest_token(&self, escrow: Address, campaign: u64)
        -> Result<Address, String>;
    /// `VerifiableFactory.predictProxyAddress(deployer, salt)`.
    async fn predict_proxy(
        &self,
        factory: Address,
        deployer: Address,
        salt: U256,
    ) -> Result<Address, String>;
    /// Whether an address has code (a deployed contract).
    async fn has_code(&self, address: Address) -> Result<bool, String>;
    /// `registry.getResolver(label)`: a player's own resolver.
    async fn ens_resolver(&self, registry: Address, label: &str) -> Result<Address, String>;
    /// The owner of `label` in the city registry, `Address::ZERO` if unregistered.
    async fn ens_owner(&self, registry: Address, label: &str) -> Result<Address, String>;
}

pub(crate) struct PlanCtx<'a> {
    pub cfg: &'a ChainConfig,
    pub dep: &'a Deployments,
    pub tickets: &'a VoucherSigner,
    pub vouchers: &'a VoucherSigner,
    /// Unix seconds.
    pub now: u64,
    /// For `CommitDraw` (the tickets' root) and `ClaimDraw` (the winner's proof), worked out by the executor.
    pub draw: Option<DrawPrep>,
}

/// What a draw intent needs from the ticket tree.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DrawPrep {
    pub root: B256,
    pub proof: Vec<B256>,
}

fn call<C: SolCall>(sender: Sender, to: Address, c: C, what: &'static str) -> TxCall {
    TxCall {
        sender,
        to,
        data: Bytes::from(c.abi_encode()),
        value: U256::ZERO,
        what,
    }
}

fn human(h: &HumanId) -> Result<B256, String> {
    h.0.parse::<B256>()
        .map_err(|_| format!("human id {} is not 32-byte hex", h.0))
}

fn b32(field: &str, s: &str) -> Result<B256, String> {
    s.parse::<B256>()
        .map_err(|_| format!("{field} {s} is not 32-byte hex"))
}

fn need<'a>(p: Option<&'a PlayerInfo>, player: &str) -> Result<&'a PlayerInfo, String> {
    p.ok_or_else(|| format!("player {player} has no wallet"))
}

/// A player resolver's salt: `uint256(keccak256(abi.encode("tallyport.names.player.v1", parentLabel, label)))`.
pub fn player_resolver_salt(parent_label: &str, label: &str) -> U256 {
    let enc = (
        "tallyport.names.player.v1".to_string(),
        parent_label.to_string(),
        label.to_string(),
    )
        .abi_encode_params();
    U256::from_be_bytes(alloy::primitives::keccak256(enc).0)
}

/// ENS labels we register: lowercase letters, digits and inner hyphens, 1 to 63 bytes.
pub fn valid_label(label: &str) -> bool {
    let b = label.as_bytes();
    !b.is_empty()
        && b.len() <= 63
        && b.iter()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || *c == b'-')
        && b[0] != b'-'
        && b[b.len() - 1] != b'-'
}

/// ENS DNS wire format: each label prefixed by its length, then a zero byte.
pub fn dns_encode(name: &str) -> Result<Bytes, String> {
    let mut out = Vec::with_capacity(name.len() + 2);
    for label in name.split('.') {
        if label.is_empty() || label.len() > 255 {
            return Err(format!("bad name {name}"));
        }
        out.push(label.len() as u8);
        out.extend_from_slice(label.as_bytes());
    }
    out.push(0);
    Ok(out.into())
}

fn mul_u48(v: u64) -> U48 {
    U48::from(v.min((1u64 << 48) - 1))
}

impl PlanCtx<'_> {
    fn expiry(&self) -> u64 {
        self.now + self.cfg.voucher_ttl.as_secs()
    }

    /// The parent label (`tallyport`), for player resolver salts.
    fn ens_parent_label(&self) -> &str {
        match &self.dep.ens_parent_label {
            Some(l) => l,
            None => self
                .ens_parent()
                .strip_suffix(".eth")
                .unwrap_or(self.ens_parent()),
        }
    }

    /// The ENS parent name: the deployment's, else the config's.
    fn ens_parent(&self) -> &str {
        self.dep
            .ens_parent
            .as_deref()
            .unwrap_or(&self.cfg.ens_parent)
    }

    fn contract(&self, name: &str) -> Result<Address, String> {
        self.dep.contract(name).map_err(|e| e.to_string())
    }
}

/// `approve(spender, max)` from the player if the allowance is below `amount` ("approves once").
async fn approve_if_needed<R: Reads>(
    reads: &R,
    txs: &mut Vec<TxCall>,
    (player, owner): (&str, Address),
    token: Address,
    spender: Address,
    amount: U256,
) -> Result<(), String> {
    if reads.erc20_allowance(token, owner, spender).await? < amount {
        txs.push(call(
            Sender::Player(player.into()),
            token,
            IERC20::approveCall {
                spender,
                amount: U256::MAX,
            },
            "approve",
        ));
    }
    Ok(())
}

pub(crate) async fn plan<R: Reads>(
    intent: &Intent,
    ctx: &PlanCtx<'_>,
    player: Option<&PlayerInfo>,
    reads: &R,
) -> Result<Plan, String> {
    let indexed = |txs| {
        Ok(Plan {
            txs,
            after: After::Indexed,
        })
    };
    let keeper = Sender::Keeper;
    match intent {
        Intent::EnsureWallet { .. } => Ok(Plan {
            txs: vec![],
            after: After::Indexed,
        }),

        Intent::BuyMeal {
            player: id,
            item,
            food,
            max_usdc,
            reference,
        } => {
            let p = need(player, id)?;
            let mc = ctx.contract("MealCounter")?;
            let t = MealTicket {
                player: p.address,
                item: item_hash(item),
                food: U256::from(*food),
                maxUsdc: U256::from(*max_usdc),
                r#ref: ref_hash(reference),
                expiry: ctx.expiry(),
            };
            let sig = ctx.tickets.meal_ticket(mc, &t);
            let mut txs = vec![];
            approve_if_needed(
                reads,
                &mut txs,
                (id, p.address),
                ctx.dep.usdc,
                mc,
                U256::from(*max_usdc),
            )
            .await?;
            txs.push(call(
                Sender::Player(id.clone()),
                mc,
                IMealCounter::buyMealCall { t, sig },
                "buyMeal",
            ));
            indexed(txs)
        }

        Intent::SellHarvest { food, reference } => {
            let farm = ctx.contract("Farm")?;
            indexed(vec![call(
                keeper,
                farm,
                IFarm::sellCall {
                    food: U256::from(*food),
                    r#ref: ref_hash(reference),
                },
                "sell",
            )])
        }

        Intent::PayHouse {
            player: id,
            human_id,
            bucket,
            amount,
            reference,
        } => {
            let p = need(player, id)?;
            let pool = ctx.contract("HousePool")?;
            let v = PayoutVoucher {
                player: p.address,
                humanId: human(human_id)?,
                source: bucket.source(),
                amount: U256::from(*amount),
                r#ref: ref_hash(reference),
                expiry: ctx.expiry(),
            };
            let sig = ctx.vouchers.payout(pool, &v);
            indexed(vec![call(
                keeper,
                pool,
                IHousePool::payCall { v, sig },
                "pay",
            )])
        }

        Intent::PayRescueMeal {
            player: id,
            human_id,
            item,
            food,
            max_usdc,
            reference,
        } => {
            let p = need(player, id)?;
            let pool = ctx.contract("HousePool")?;
            let v = PayoutVoucher {
                player: p.address,
                humanId: human(human_id)?,
                source: Bucket::Safety.source(),
                amount: U256::from(*max_usdc),
                r#ref: ref_hash(reference),
                expiry: ctx.expiry(),
            };
            let sig = ctx.vouchers.payout(pool, &v);
            let c = IHousePool::payMealCall {
                v,
                item: item_hash(item),
                food: U256::from(*food),
                sig,
            };
            // HousePool.payMeal must be sent by the player's own wallet (it picks the menu item).
            indexed(vec![call(Sender::Player(id.clone()), pool, c, "payMeal")])
        }

        Intent::ClaimCampaign {
            campaign,
            player: id,
            human_id,
            amount,
            reference,
        } => {
            let p = need(player, id)?;
            let escrow = ctx.contract("CampaignEscrow")?;
            let c = CampaignClaim {
                campaignId: U256::from(*campaign),
                player: p.address,
                humanId: human(human_id)?,
                amount: U256::from(*amount),
                r#ref: ref_hash(reference),
                expiry: ctx.expiry(),
            };
            let sig = ctx.vouchers.campaign_claim(escrow, &c);
            indexed(vec![call(
                keeper,
                escrow,
                ICampaignEscrow::claimCall { c, sig },
                "claim",
            )])
        }

        Intent::Advance {
            campaign,
            player: id,
            human_id,
            amount,
            reference,
        } => {
            let p = need(player, id)?;
            let escrow = ctx.contract("CampaignEscrow")?;
            let a = AdvanceVoucher {
                campaignId: U256::from(*campaign),
                player: p.address,
                humanId: human(human_id)?,
                amount: U256::from(*amount),
                r#ref: ref_hash(reference),
                expiry: ctx.expiry(),
            };
            let sig = ctx.vouchers.advance(escrow, &a);
            indexed(vec![call(
                keeper,
                escrow,
                ICampaignEscrow::advanceCall { a, sig },
                "advance",
            )])
        }

        Intent::SwapForQuest {
            player: id,
            campaign,
            usdc_in,
            min_out,
            ..
        } => {
            let p = need(player, id)?;
            let route = ctx
                .dep
                .swap_route
                .as_ref()
                .ok_or("deployments have no swap router")?;
            // The campaign's own quest token (CampaignEscrow knows it), else the deployment's demo token.
            let token = match ctx.dep.contracts.get("CampaignEscrow") {
                Some(escrow) => reads.campaign_quest_token(*escrow, *campaign).await?,
                None => ctx
                    .dep
                    .quest_pool
                    .as_ref()
                    .map(|q| q.token)
                    .unwrap_or_default(),
            };
            if token == Address::ZERO {
                return Err(format!(
                    "campaign {campaign} has no quest token to swap for"
                ));
            }
            let qp = ctx.dep.quest_pool_for(token);
            let usdc = ctx.dep.usdc;
            let amount_in = U256::from(*usdc_in);
            let zero_for_one = qp.key.currency0 == usdc;
            // min_out 0: quote it on chain and allow the configured slippage.
            let min_out = match (*min_out, ctx.dep.quoter) {
                (0, Some(quoter)) => {
                    let quoted = reads
                        .quote_exact_in(quoter, qp.key.clone(), zero_for_one, *usdc_in)
                        .await?;
                    let bps = U256::from(10_000u64.saturating_sub(ctx.cfg.swap_slippage_bps));
                    u128::try_from(quoted * bps / U256::from(10_000u64)).unwrap_or(u128::MAX)
                }
                (m, _) => m,
            };
            let min_out = &min_out;
            let mut txs = vec![];
            let sender = Sender::Player(id.clone());
            match route {
                SwapRoute::UniversalRouter { router, permit2 } => {
                    approve_if_needed(reads, &mut txs, (id, p.address), usdc, *permit2, amount_in)
                        .await?;
                    let deadline = ctx.now + ctx.cfg.swap_deadline.as_secs();
                    let (allowed, expiration) = reads
                        .permit2_allowance(*permit2, p.address, usdc, *router)
                        .await?;
                    if allowed < amount_in || expiration <= deadline {
                        txs.push(call(
                            sender.clone(),
                            *permit2,
                            IPermit2::approveCall {
                                token: usdc,
                                spender: *router,
                                amount: U160::MAX,
                                expiration: mul_u48(ctx.now + 30 * 86_400),
                            },
                            "permit2.approve",
                        ));
                    }
                    let (commands, inputs) =
                        universal_router_swap(qp.key.clone(), zero_for_one, *usdc_in, *min_out);
                    txs.push(call(
                        sender,
                        *router,
                        IUniversalRouter::executeCall {
                            commands,
                            inputs,
                            deadline: U256::from(deadline),
                        },
                        "execute",
                    ));
                }
                SwapRoute::PoolSwapTest { router } => {
                    approve_if_needed(reads, &mut txs, (id, p.address), usdc, *router, amount_in)
                        .await?;
                    let limit = if zero_for_one {
                        U160::from(uniswap::MIN_SQRT_PRICE_PLUS_ONE)
                    } else {
                        uniswap::MAX_SQRT_PRICE_MINUS_ONE
                            .parse::<U160>()
                            .expect("constant")
                    };
                    let c = IPoolSwapTest::swapCall {
                        key: qp.key.clone(),
                        params: SwapParams {
                            zeroForOne: zero_for_one,
                            amountSpecified: -I256::try_from(amount_in)
                                .map_err(|_| "usdc_in too large")?,
                            sqrtPriceLimitX96: limit,
                        },
                        testSettings: TestSettings {
                            takeClaims: false,
                            settleUsingBurn: false,
                        },
                        hookData: Bytes::new(),
                    };
                    txs.push(call(sender, *router, c, "swap"));
                }
            }
            indexed(txs)
        }

        Intent::Deliver {
            player: id,
            campaign,
            reference,
        } => {
            let p = need(player, id)?;
            let merchant = ctx.contract("SpiceMerchant")?;
            let escrow = ctx.contract("CampaignEscrow")?;
            let token = reads.campaign_quest_token(escrow, *campaign).await?;
            if token == Address::ZERO {
                return Err(format!("campaign {campaign} has no quest token to deliver"));
            }
            let amount = reads.erc20_balance(token, p.address).await?;
            if amount.is_zero() {
                return Err("no quest tokens to deliver".into());
            }
            let mut txs = vec![];
            approve_if_needed(reads, &mut txs, (id, p.address), token, merchant, amount).await?;
            txs.push(call(
                Sender::Player(id.clone()),
                merchant,
                ISpiceMerchant::deliverCall {
                    campaignId: U256::from(*campaign),
                    token,
                    amount,
                    questRef: ref_hash(reference),
                },
                "deliver",
            ));
            indexed(txs)
        }

        Intent::Withdraw {
            player: id,
            to,
            amount,
            reference,
        } => {
            let p = need(player, id)?;
            let dest: Address = to.parse().map_err(|_| format!("{to:?} is not an address"))?;
            if dest == p.address || dest == Address::ZERO {
                return Err("a withdrawal goes somewhere else".into());
            }
            Ok(Plan {
                txs: vec![call(
                    Sender::Player(id.clone()),
                    ctx.dep.usdc,
                    IERC20::transferCall {
                        to: dest,
                        amount: U256::from(*amount),
                    },
                    "withdraw",
                )],
                after: After::Withdrawn {
                    player: id.clone(),
                    to: to.clone(),
                    amount: *amount,
                    reference: reference.clone(),
                },
            })
        }

        Intent::RegisterName { player: id, label } => {
            let p = need(player, id)?;
            if !valid_label(label) {
                return Err(format!(
                    "{label:?} is not a valid name (a-z, 0-9, inner hyphens, up to 63)"
                ));
            }
            let registry = ctx
                .dep
                .ens_registry
                .ok_or("deployments have no ens.registry")?;
            let factory = ctx
                .dep
                .ens_factory
                .ok_or("deployments have no ens.factory")?;
            let implementation = ctx
                .dep
                .ens_resolver_impl
                .ok_or("deployments have no ens.resolverImpl")?;
            let names_key = ctx
                .cfg
                .secrets
                .names
                .as_ref()
                .map(|k| k.address())
                .ok_or("NAMES_KEY is not set")?;
            let admin = ctx
                .cfg
                .ens_admin
                .or(ctx.dep.ens_admin)
                .ok_or("no ENS admin (deployments keys.admin or ENS_ADMIN_ADDRESS)")?;
            let name = format!("{label}.{}", ctx.ens_parent());
            let owner = reads.ens_owner(registry, label).await?;
            if owner == p.address {
                // Already done (e.g. a resumed intent): nothing to send, report it.
                return Ok(Plan {
                    txs: vec![],
                    after: After::NameRegistered {
                        player: id.clone(),
                        label: label.clone(),
                        name,
                    },
                });
            }
            if owner != Address::ZERO {
                return Err(format!("{name} is taken"));
            }
            // The player's own PermissionedResolver (CityNames.registerPlayer), at a predictable address.
            let salt = player_resolver_salt(ctx.ens_parent_label(), label);
            let resolver = reads.predict_proxy(factory, names_key, salt).await?;
            let dns = dns_encode(&name)?;
            let mut txs = vec![];
            if !reads.has_code(resolver).await? {
                let set_text = |k: &str, v: &str| -> Bytes {
                    IPermissionedResolver::setTextCall {
                        name: dns.clone(),
                        key: k.into(),
                        value: v.into(),
                    }
                    .abi_encode()
                    .into()
                };
                let mut calls: Vec<Bytes> = ctx
                    .cfg
                    .ens_coin_types
                    .iter()
                    .map(|coin| {
                        IPermissionedResolver::setAddressCall {
                            name: dns.clone(),
                            coinType: U256::from(*coin),
                            addressBytes: Bytes::copy_from_slice(p.address.as_slice()),
                        }
                        .abi_encode()
                        .into()
                    })
                    .collect();
                calls.push(set_text("avatar", &ctx.cfg.ens_default_avatar));
                calls.push(set_text("tallyport.human", "verified"));
                let writer = ens::role(ens::ROLE_SET_ADDRESS) | ens::role(ens::ROLE_SET_TEXT);
                let upgrade = ens::role(ens::ROLE_UPGRADE);
                let grants = vec![
                    Grant {
                        account: names_key,
                        roleBitmap: writer | ens::admin(ens::role(ens::ROLE_SET_TEXT)),
                    },
                    Grant {
                        account: admin,
                        roleBitmap: upgrade | ens::admin(upgrade),
                    },
                ];
                let init = IPermissionedResolver::initializeCall { grants, calls }.abi_encode();
                txs.push(call(
                    Sender::Names,
                    factory,
                    IVerifiableFactory::deployProxyCall {
                        implementation,
                        salt,
                        data: init.into(),
                    },
                    "deployResolver",
                ));
            }
            // The player's wallet may write its own description and avatar ("paint your shop sign").
            for key in &ctx.cfg.player_record_keys {
                let setter = IPermissionedResolver::setTextCall {
                    name: Bytes::new(),
                    key: key.clone(),
                    value: String::new(),
                }
                .abi_encode();
                txs.push(call(
                    Sender::Names,
                    resolver,
                    IPermissionedResolver::grantSetterRolesCall {
                        setter: setter.into(),
                        account: p.address,
                    },
                    "grantText",
                ));
            }
            txs.push(call(
                Sender::Names,
                registry,
                IEnsRegistry::registerCall {
                    label: label.clone(),
                    owner: p.address,
                    registry: Address::ZERO,
                    resolver,
                    roleBitmap: U256::ZERO,
                    expiry: ctx.now + ctx.cfg.name_duration.as_secs(),
                },
                "register",
            ));
            Ok(Plan {
                txs,
                after: After::NameRegistered {
                    player: id.clone(),
                    label: label.clone(),
                    name,
                },
            })
        }

        Intent::SetRecords {
            player: id,
            records,
        } => {
            let p = need(player, id)?;
            let label = p
                .label
                .as_ref()
                .ok_or_else(|| format!("player {id} has no name yet"))?;
            let registry = ctx
                .dep
                .ens_registry
                .ok_or("deployments have no ens.registry")?;
            let resolver = reads.ens_resolver(registry, label).await?;
            if resolver == Address::ZERO {
                return Err(format!("{label}.{} has no resolver", ctx.ens_parent()));
            }
            let dns = dns_encode(&format!("{label}.{}", ctx.ens_parent()))?;
            let (mine, ours): (Vec<_>, Vec<_>) = records
                .iter()
                .partition(|(k, _)| ctx.cfg.player_record_keys.iter().any(|pk| pk == *k));
            let mut txs = vec![];
            for (sender, set) in [(Sender::Player(id.clone()), mine), (Sender::Names, ours)] {
                let mut calls: Vec<Bytes> = set
                    .iter()
                    .map(|(k, v)| {
                        IPermissionedResolver::setTextCall {
                            name: dns.clone(),
                            key: (*k).clone(),
                            value: (*v).clone(),
                        }
                        .abi_encode()
                        .into()
                    })
                    .collect();
                match calls.len() {
                    0 => {}
                    1 => txs.push(TxCall {
                        sender,
                        to: resolver,
                        data: calls.remove(0),
                        value: U256::ZERO,
                        what: "setText",
                    }),
                    _ => txs.push(call(
                        sender,
                        resolver,
                        IPermissionedResolver::multicallCall { calls },
                        "setText",
                    )),
                }
            }
            if txs.is_empty() {
                return Err("no records to set".into());
            }
            Ok(Plan {
                txs,
                after: After::RecordsSet {
                    player: id.clone(),
                    records: records.clone(),
                },
            })
        }

        Intent::Split => indexed(vec![call(
            keeper,
            ctx.contract("Treasury")?,
            ITreasury::splitCall {},
            "split",
        )]),
        Intent::Rebalance => indexed(vec![call(
            keeper,
            ctx.contract("FloatManager")?,
            IFloatManager::rebalanceCall {},
            "rebalance",
        )]),
        Intent::HarvestYield => indexed(vec![call(
            keeper,
            ctx.contract("FloatManager")?,
            IFloatManager::harvestYieldCall {},
            "harvestYield",
        )]),
        Intent::CommitDraw {
            week,
            seed_hash,
            root,
            count,
            prize,
            ..
        } => {
            let built = ctx.draw.as_ref().map(|d| d.root);
            let given = if root.trim().is_empty() {
                None
            } else {
                Some(b32("root", root)?)
            };
            let root = match (given, built) {
                (Some(g), Some(b)) if g != b => {
                    return Err(format!("root {g} doesn't match the tickets' root {b}"));
                }
                (Some(r), _) | (None, Some(r)) => r,
                (None, None) => return Err("no root and no tickets".into()),
            };
            indexed(vec![call(
                keeper,
                ctx.contract("LuckyLedger")?,
                ILuckyLedger::commitCall {
                    week: U256::from(*week),
                    seedHash: b32("seed_hash", seed_hash)?,
                    ticketsRoot: root,
                    ticketCount: U256::from(*count),
                    prize: U256::from(*prize),
                },
                "commit",
            )])
        }
        Intent::ClaimDraw {
            week,
            player: id,
            from,
            to,
            ..
        } => {
            let p = need(player, id)?;
            let proof = ctx
                .draw
                .as_ref()
                .map(|d| d.proof.clone())
                .ok_or("no committed tickets for this draw")?;
            indexed(vec![call(
                keeper,
                ctx.contract("LuckyLedger")?,
                ILuckyLedger::claimCall {
                    week: U256::from(*week),
                    player: p.address,
                    from: U256::from(*from),
                    // LuckyLedger's ranges are half-open.
                    to: U256::from(*to) + U256::from(1u8),
                    proof,
                },
                "claim",
            )])
        }
        Intent::CheckHolding { .. } | Intent::QuoteSwap { .. } => Ok(Plan {
            txs: vec![],
            after: After::Indexed,
        }),
        Intent::RevealDraw { week, seed } => indexed(vec![call(
            keeper,
            ctx.contract("LuckyLedger")?,
            ILuckyLedger::revealCall {
                week: U256::from(*week),
                seed: b32("seed", seed)?,
            },
            "reveal",
        )]),
    }
}

/// UniversalRouter `execute` arguments for one exact-input single-pool v4 swap:
/// command `V4_SWAP` with actions `SWAP_EXACT_IN_SINGLE`, `SETTLE_ALL` (pay the input), `TAKE_ALL` (receive the output).
pub fn universal_router_swap(
    key: PoolKey,
    zero_for_one: bool,
    amount_in: u64,
    min_out: u128,
) -> (Bytes, Vec<Bytes>) {
    let (cin, cout) = if zero_for_one {
        (key.currency0, key.currency1)
    } else {
        (key.currency1, key.currency0)
    };
    let swap = ExactInputSingleParams {
        poolKey: key,
        zeroForOne: zero_for_one,
        amountIn: amount_in as u128,
        amountOutMinimum: min_out,
        hookData: Bytes::new(),
    };
    let actions = Bytes::from(vec![
        uniswap::SWAP_EXACT_IN_SINGLE,
        uniswap::SETTLE_ALL,
        uniswap::TAKE_ALL,
    ]);
    let params: Vec<Bytes> = vec![
        swap.abi_encode().into(),
        (cin, U256::from(amount_in)).abi_encode_params().into(),
        (cout, U256::from(min_out)).abi_encode_params().into(),
    ];
    let input = (actions, params).abi_encode_params();
    (Bytes::from(vec![uniswap::V4_SWAP]), vec![input.into()])
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::tests::anvil_config;
    use crate::deployments::Deployments;
    use crate::eip712::{domain, recover};
    use std::cell::RefCell;

    const DEP: &str = r#"{
      "chainId": 31337,
      "contracts": {
        "MealCounter": "0x00000000000000000000000000000000000000a1",
        "Farm": "0x00000000000000000000000000000000000000a2",
        "Treasury": "0x00000000000000000000000000000000000000a3",
        "HousePool": "0x00000000000000000000000000000000000000a4",
        "CampaignEscrow": "0x00000000000000000000000000000000000000a5",
        "FloatManager": "0x00000000000000000000000000000000000000a6",
        "SpiceMerchant": "0x00000000000000000000000000000000000000a7",
        "LuckyLedger": "0x00000000000000000000000000000000000000a8",
        "QuestToken": "0x00000000000000000000000000000000000000f0"
      },
      "uniswap": {
        "poolManager": "0x00000000000000000000000000000000000000b1",
        "universalRouter": "0x00000000000000000000000000000000000000b2",
        "permit2": "0x00000000000000000000000000000000000000b3",
        "v4Quoter": "0x00000000000000000000000000000000000000b4"
      },
      "usdc": "0x00000000000000000000000000000000000000c1",
      "ens": {
        "parent": "tallyport.eth",
        "parentLabel": "tallyport",
        "coinType": 60,
        "registry": "0x00000000000000000000000000000000000000d1",
        "factory": "0x00000000000000000000000000000000000000d3",
        "resolverImpl": "0x00000000000000000000000000000000000000d4",
        "players": "per-player resolver: see playerResolverSalt"
      },
      "keys": { "admin": "0x00000000000000000000000000000000000000d5" }
    }"#;

    #[derive(Default)]
    struct FakeReads {
        allowance: U256,
        balance: U256,
        permit2: (U256, u64),
        owner: Address,
        resolver_exists: bool,
        asked: RefCell<Vec<String>>,
    }

    impl Reads for FakeReads {
        async fn erc20_allowance(
            &self,
            token: Address,
            owner: Address,
            spender: Address,
        ) -> Result<U256, String> {
            self.asked
                .borrow_mut()
                .push(format!("allowance {token} {owner} {spender}"));
            Ok(self.allowance)
        }
        async fn erc20_balance(&self, _: Address, _: Address) -> Result<U256, String> {
            Ok(self.balance)
        }
        async fn permit2_allowance(
            &self,
            _: Address,
            _: Address,
            _: Address,
            _: Address,
        ) -> Result<(U256, u64), String> {
            Ok(self.permit2)
        }
        async fn quote_exact_in(
            &self,
            _: Address,
            _: PoolKey,
            _: bool,
            _: u64,
        ) -> Result<U256, String> {
            Ok(U256::from(1_000u64))
        }
        async fn campaign_quest_token(&self, _: Address, _: u64) -> Result<Address, String> {
            Ok(Address::repeat_byte(0xf0))
        }
        async fn predict_proxy(&self, _: Address, _: Address, _: U256) -> Result<Address, String> {
            Ok(Address::repeat_byte(0xe5))
        }
        async fn has_code(&self, _: Address) -> Result<bool, String> {
            Ok(self.resolver_exists)
        }
        async fn ens_resolver(&self, _: Address, _: &str) -> Result<Address, String> {
            Ok(Address::repeat_byte(0xe5))
        }
        async fn ens_owner(&self, _: Address, _: &str) -> Result<Address, String> {
            Ok(self.owner)
        }
    }

    struct Fixture {
        cfg: ChainConfig,
        dep: Deployments,
        tickets: VoucherSigner,
        vouchers: VoucherSigner,
        _dir: tempfile::TempDir,
    }

    impl Fixture {
        fn new() -> Fixture {
            let dir = tempfile::tempdir().unwrap();
            let cfg = anvil_config(dir.path());
            let dep = Deployments::parse(DEP, 31_337).unwrap();
            let tickets = VoucherSigner::new(cfg.secrets.ticket_signer.0.clone(), 31_337);
            let vouchers = VoucherSigner::new(cfg.secrets.voucher_signer.0.clone(), 31_337);
            Fixture {
                cfg,
                dep,
                tickets,
                vouchers,
                _dir: dir,
            }
        }
        fn ctx(&self) -> PlanCtx<'_> {
            PlanCtx {
                cfg: &self.cfg,
                dep: &self.dep,
                tickets: &self.tickets,
                vouchers: &self.vouchers,
                now: 1_000,
                draw: Some(DrawPrep {
                    root: B256::repeat_byte(0x33),
                    proof: vec![B256::repeat_byte(0x44)],
                }),
            }
        }
    }

    fn asha() -> PlayerInfo {
        PlayerInfo {
            address: Address::repeat_byte(0xaa),
            label: Some("asha".into()),
        }
    }

    fn run<R: Reads>(
        i: &Intent,
        f: &Fixture,
        p: Option<&PlayerInfo>,
        r: &R,
    ) -> Result<Plan, String> {
        tokio::runtime::Builder::new_current_thread()
            .build()
            .unwrap()
            .block_on(plan(i, &f.ctx(), p, r))
    }

    #[test]
    fn buy_meal_approves_once_then_buys_with_a_valid_ticket() {
        let f = Fixture::new();
        let i = Intent::BuyMeal {
            player: "asha".into(),
            item: "chai".into(),
            food: 1_000_000,
            max_usdc: 4_080,
            reference: "m1".into(),
        };
        let p = run(&i, &f, Some(&asha()), &FakeReads::default()).unwrap();
        assert_eq!(p.txs.len(), 2);
        assert_eq!(p.txs[0].what, "approve");
        assert_eq!(p.txs[0].to, f.dep.usdc);
        let buy = &p.txs[1];
        assert_eq!(buy.sender, Sender::Player("asha".into()));
        let c = IMealCounter::buyMealCall::abi_decode(&buy.data).unwrap();
        assert_eq!(c.t.player, asha().address);
        assert_eq!(c.t.r#ref, ref_hash("m1"));
        assert_eq!(c.t.item, item_hash("chai"));
        assert_eq!(c.t.maxUsdc, U256::from(4_080u64));
        assert_eq!(c.t.expiry, 1_000 + 3_600);
        let d = domain(31_337, f.dep.contract("MealCounter").unwrap());
        assert_eq!(recover(&c.t, &d, &c.sig), Some(f.tickets.address()));

        let rich = FakeReads {
            allowance: U256::MAX,
            ..Default::default()
        };
        let p = run(&i, &f, Some(&asha()), &rich).unwrap();
        assert_eq!(p.txs.len(), 1);
        assert!(run(&i, &f, None, &rich).unwrap_err().contains("no wallet"));
    }

    #[test]
    fn payouts_are_keeper_sent_vouchers_from_the_voucher_signer() {
        let f = Fixture::new();
        let h = HumanId(format!("0x{}", "11".repeat(32)));
        let i = Intent::PayHouse {
            player: "asha".into(),
            human_id: h.clone(),
            bucket: Bucket::Surprise,
            amount: 250_000,
            reference: "c1".into(),
        };
        let p = run(&i, &f, Some(&asha()), &FakeReads::default()).unwrap();
        assert_eq!(p.txs.len(), 1);
        assert_eq!(p.txs[0].sender, Sender::Keeper);
        let c = IHousePool::payCall::abi_decode(&p.txs[0].data).unwrap();
        assert_eq!(c.v.source, 1);
        assert_eq!(c.v.humanId, B256::repeat_byte(0x11));
        let d = domain(31_337, f.dep.contract("HousePool").unwrap());
        assert_eq!(recover(&c.v, &d, &c.sig), Some(f.vouchers.address()));

        let i = Intent::PayRescueMeal {
            player: "asha".into(),
            human_id: h.clone(),
            item: "thali".into(),
            food: 6_000_000,
            max_usdc: 30_000,
            reference: "r1".into(),
        };
        let p = run(&i, &f, Some(&asha()), &FakeReads::default()).unwrap();
        let c = IHousePool::payMealCall::abi_decode(&p.txs[0].data).unwrap();
        assert_eq!(p.txs[0].sender, Sender::Player("asha".into()));
        assert_eq!(c.v.source, 2);
        assert_eq!(c.food, U256::from(6_000_000u64));

        let i = Intent::ClaimCampaign {
            campaign: 1,
            player: "asha".into(),
            human_id: h.clone(),
            amount: 400_000,
            reference: "q1".into(),
        };
        let p = run(&i, &f, Some(&asha()), &FakeReads::default()).unwrap();
        let c = ICampaignEscrow::claimCall::abi_decode(&p.txs[0].data).unwrap();
        let d = domain(31_337, f.dep.contract("CampaignEscrow").unwrap());
        assert_eq!(c.c.campaignId, U256::from(1u64));
        assert_eq!(recover(&c.c, &d, &c.sig), Some(f.vouchers.address()));

        let i = Intent::Advance {
            campaign: 1,
            player: "asha".into(),
            human_id: h,
            amount: 1_000_000,
            reference: "a1".into(),
        };
        let p = run(&i, &f, Some(&asha()), &FakeReads::default()).unwrap();
        let c = ICampaignEscrow::advanceCall::abi_decode(&p.txs[0].data).unwrap();
        assert_eq!(recover(&c.a, &d, &c.sig), Some(f.vouchers.address()));

        let bad = Intent::PayHouse {
            player: "asha".into(),
            human_id: HumanId("nope".into()),
            bucket: Bucket::Fixed,
            amount: 1,
            reference: "x".into(),
        };
        assert!(run(&bad, &f, Some(&asha()), &FakeReads::default())
            .unwrap_err()
            .contains("human id"));
    }

    #[test]
    fn swap_goes_through_permit2_and_the_universal_router() {
        let f = Fixture::new();
        let i = Intent::SwapForQuest {
            player: "asha".into(),
            campaign: 1,
            usdc_in: 2_000_000,
            min_out: 5,
            reference: "s1".into(),
        };
        let p = run(&i, &f, Some(&asha()), &FakeReads::default()).unwrap();
        let whats: Vec<_> = p.txs.iter().map(|t| t.what).collect();
        assert_eq!(whats, vec!["approve", "permit2.approve", "execute"]);
        let ex = IUniversalRouter::executeCall::abi_decode(&p.txs[2].data).unwrap();
        assert_eq!(ex.commands.as_ref(), &[uniswap::V4_SWAP]);
        let (actions, params) = <(Bytes, Vec<Bytes>)>::abi_decode_params(&ex.inputs[0]).unwrap();
        assert_eq!(actions.as_ref(), &[0x06, 0x0c, 0x0f]);
        let swap = ExactInputSingleParams::abi_decode(&params[0]).unwrap();
        assert_eq!(swap.amountIn, 2_000_000);
        assert_eq!(swap.amountOutMinimum, 5);
        // USDC (0x…c1) sorts above the quest token (0x…f0)? No: 0xc1 < 0xf0, so USDC is currency0 and we swap 0→1.
        assert!(swap.zeroForOne);
        assert_eq!(ex.deadline, U256::from(1_000 + 600u64));

        // min_out 0: quoted on chain (the fake quoter says 1,000) less 1% slippage.
        let quoted = Intent::SwapForQuest {
            player: "asha".into(),
            campaign: 1,
            usdc_in: 2_000_000,
            min_out: 0,
            reference: "s2".into(),
        };
        let p = run(&quoted, &f, Some(&asha()), &FakeReads::default()).unwrap();
        let ex = IUniversalRouter::executeCall::abi_decode(&p.txs[2].data).unwrap();
        let (_, params) = <(Bytes, Vec<Bytes>)>::abi_decode_params(&ex.inputs[0]).unwrap();
        assert_eq!(
            ExactInputSingleParams::abi_decode(&params[0])
                .unwrap()
                .amountOutMinimum,
            990
        );

        let ready = FakeReads {
            allowance: U256::MAX,
            permit2: (U256::MAX, 1_000_000),
            ..Default::default()
        };
        let p = run(&i, &f, Some(&asha()), &ready).unwrap();
        assert_eq!(p.txs.len(), 1);
    }

    #[test]
    fn deliver_sends_the_whole_cargo() {
        let f = Fixture::new();
        let i = Intent::Deliver {
            player: "asha".into(),
            campaign: 1,
            reference: "d1".into(),
        };
        assert!(run(&i, &f, Some(&asha()), &FakeReads::default())
            .unwrap_err()
            .contains("no quest tokens"));
        let r = FakeReads {
            balance: U256::from(77u64),
            allowance: U256::MAX,
            ..Default::default()
        };
        let p = run(&i, &f, Some(&asha()), &r).unwrap();
        let c = ISpiceMerchant::deliverCall::abi_decode(&p.txs[0].data).unwrap();
        assert_eq!(c.amount, U256::from(77u64));
        assert_eq!(c.questRef, ref_hash("d1"));
    }

    #[test]
    fn names_register_with_a_resolver_of_their_own() {
        let f = Fixture::new();
        let i = Intent::RegisterName {
            player: "asha".into(),
            label: "asha".into(),
        };
        let p = run(&i, &f, Some(&asha()), &FakeReads::default()).unwrap();
        let whats: Vec<_> = p.txs.iter().map(|t| t.what).collect();
        assert_eq!(
            whats,
            vec!["deployResolver", "grantText", "grantText", "register"]
        );
        assert!(p.txs.iter().all(|t| t.sender == Sender::Names));
        // (a) the player's resolver from ENS's factory, initialized with the names key's and admin's roles and the
        //     first records.
        let d = IVerifiableFactory::deployProxyCall::abi_decode(&p.txs[0].data).unwrap();
        assert_eq!(p.txs[0].to, f.dep.ens_factory.unwrap());
        assert_eq!(d.implementation, f.dep.ens_resolver_impl.unwrap());
        assert_eq!(d.salt, player_resolver_salt("tallyport", "asha"));
        let init = IPermissionedResolver::initializeCall::abi_decode(&d.data).unwrap();
        let names = f.cfg.secrets.names.as_ref().unwrap().address();
        let set_text = ens::role(ens::ROLE_SET_TEXT);
        assert_eq!(init.grants[0].account, names);
        assert_eq!(
            init.grants[0].roleBitmap,
            ens::role(ens::ROLE_SET_ADDRESS) | set_text | ens::admin(set_text)
        );
        assert_eq!(init.grants[1].account, f.dep.ens_admin.unwrap());
        let upgrade = ens::role(ens::ROLE_UPGRADE);
        assert_eq!(init.grants[1].roleBitmap, upgrade | ens::admin(upgrade));
        assert_eq!(init.calls.len(), 4);
        let a60 = IPermissionedResolver::setAddressCall::abi_decode(&init.calls[0]).unwrap();
        let evm = IPermissionedResolver::setAddressCall::abi_decode(&init.calls[1]).unwrap();
        assert_eq!(
            (a60.coinType, evm.coinType),
            (U256::from(60u64), U256::from(0x8000_0000u64))
        );
        assert_eq!(a60.name, dns_encode("asha.tallyport.eth").unwrap());
        assert_eq!(a60.addressBytes.as_ref(), asha().address.as_slice());
        let human = IPermissionedResolver::setTextCall::abi_decode(&init.calls[3]).unwrap();
        assert_eq!(
            (human.key.as_str(), human.value.as_str()),
            ("tallyport.human", "verified")
        );
        // (b) the player may write its own avatar and description.
        let g = IPermissionedResolver::grantSetterRolesCall::abi_decode(&p.txs[1].data).unwrap();
        assert_eq!(g.account, asha().address);
        assert_eq!(p.txs[1].to, Address::repeat_byte(0xe5));
        let setter = IPermissionedResolver::setTextCall::abi_decode(&g.setter).unwrap();
        assert_eq!(
            (
                setter.name.len(),
                setter.key.as_str(),
                setter.value.as_str()
            ),
            (0, "avatar", "")
        );
        // (c) the name, owned by the player's wallet, pointing at its resolver, no roles.
        let r = IEnsRegistry::registerCall::abi_decode(&p.txs[3].data).unwrap();
        assert_eq!(
            (r.owner, r.resolver, r.roleBitmap),
            (asha().address, Address::repeat_byte(0xe5), U256::ZERO)
        );
        assert!(
            matches!(p.after, After::NameRegistered { ref name, .. } if name == "asha.tallyport.eth")
        );

        // A resolver already deployed (a resumed intent) isn't deployed again.
        let deployed = FakeReads {
            resolver_exists: true,
            ..Default::default()
        };
        assert_eq!(run(&i, &f, Some(&asha()), &deployed).unwrap().txs.len(), 3);
        // Already ours: nothing to send; someone else's: refused; a bad label: refused.
        let mine = FakeReads {
            owner: asha().address,
            ..Default::default()
        };
        assert!(run(&i, &f, Some(&asha()), &mine).unwrap().txs.is_empty());
        let taken = FakeReads {
            owner: Address::repeat_byte(1),
            ..Default::default()
        };
        assert!(run(&i, &f, Some(&asha()), &taken)
            .unwrap_err()
            .contains("taken"));
        let bad = Intent::RegisterName {
            player: "asha".into(),
            label: "Asha!".into(),
        };
        assert!(run(&bad, &f, Some(&asha()), &mine).is_err());
    }

    /// The salt matches Solidity's `abi.encode` as computed by `cast` (skipped without cast on PATH).
    #[test]
    fn player_resolver_salt_matches_cast() {
        let Ok(enc) = std::process::Command::new("cast")
            .args([
                "abi-encode",
                "f(string,string,string)",
                "tallyport.names.player.v1",
                "tallyport",
                "asha",
            ])
            .output()
        else {
            eprintln!("skip: cast not on PATH");
            return;
        };
        let enc = String::from_utf8(enc.stdout).unwrap().trim().to_string();
        let out = std::process::Command::new("cast")
            .args(["keccak", &enc])
            .output()
            .unwrap();
        let hash: B256 = String::from_utf8(out.stdout)
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        assert_eq!(
            player_resolver_salt("tallyport", "asha"),
            U256::from_be_bytes(hash.0)
        );
    }

    #[test]
    fn player_resolver_salt_is_abi_encode_of_three_strings() {
        // abi.encode(string, string, string): three offsets, then each string's length and padded bytes.
        let enc = (
            "tallyport.names.player.v1".to_string(),
            "tallyport".to_string(),
            "asha".to_string(),
        )
            .abi_encode_params();
        assert_eq!(enc.len(), 3 * 32 + 3 * 64);
        assert_eq!(U256::from_be_slice(&enc[..32]), U256::from(96u64));
        assert_eq!(
            player_resolver_salt("tallyport", "asha"),
            U256::from_be_bytes(alloy::primitives::keccak256(&enc).0)
        );
        assert_ne!(
            player_resolver_salt("tallyport", "asha"),
            player_resolver_salt("tallyport", "ben")
        );
    }

    #[test]
    fn records_split_between_player_and_names_key() {
        let f = Fixture::new();
        let mut records = BTreeMap::new();
        records.insert("description".to_string(), "Best chai in Fort".to_string());
        records.insert("tallyport.stamps".to_string(), "spice-run".to_string());
        let i = Intent::SetRecords {
            player: "asha".into(),
            records,
        };
        let p = run(&i, &f, Some(&asha()), &FakeReads::default()).unwrap();
        assert_eq!(p.txs.len(), 2);
        assert_eq!(p.txs[0].sender, Sender::Player("asha".into()));
        assert_eq!(p.txs[1].sender, Sender::Names);
        // Both go to the player's own resolver (registry.getResolver); a single record is a plain setText.
        assert!(p.txs.iter().all(|t| t.to == Address::repeat_byte(0xe5)));
        let sign = IPermissionedResolver::setTextCall::abi_decode(&p.txs[0].data).unwrap();
        assert_eq!(
            (sign.key.as_str(), sign.value.as_str()),
            ("description", "Best chai in Fort")
        );
        let unnamed = PlayerInfo {
            label: None,
            ..asha()
        };
        assert!(run(&i, &f, Some(&unnamed), &FakeReads::default())
            .unwrap_err()
            .contains("no name"));
    }

    #[test]
    fn keeper_housekeeping_and_draws() {
        let f = Fixture::new();
        let r = FakeReads::default();
        for (i, to) in [
            (Intent::Split, "Treasury"),
            (Intent::Rebalance, "FloatManager"),
            (Intent::HarvestYield, "FloatManager"),
        ] {
            let p = run(&i, &f, None, &r).unwrap();
            assert_eq!(p.txs[0].to, f.dep.contract(to).unwrap());
            assert_eq!(p.txs[0].sender, Sender::Keeper);
        }
        let h = format!("0x{}", "22".repeat(32));
        let i = Intent::CommitDraw {
            week: 4,
            seed_hash: h.clone(),
            root: String::new(),
            count: 120,
            prize: 5_000_000,
            tickets: vec![],
        };
        let c = ILuckyLedger::commitCall::abi_decode(&run(&i, &f, None, &r).unwrap().txs[0].data)
            .unwrap();
        assert_eq!(c.ticketCount, U256::from(120u64));
        assert_eq!(c.ticketsRoot, B256::repeat_byte(0x33));
        let mismatch = Intent::CommitDraw {
            week: 4,
            seed_hash: h.clone(),
            root: h.clone(),
            count: 120,
            prize: 5_000_000,
            tickets: vec![],
        };
        assert!(run(&mismatch, &f, None, &r)
            .unwrap_err()
            .contains("doesn't match"));
        let i = Intent::ClaimDraw {
            week: 4,
            player: "asha".into(),
            from: 10,
            to: 19,
            reference: "w4".into(),
        };
        let c = ILuckyLedger::claimCall::abi_decode(
            &run(&i, &f, Some(&asha()), &r).unwrap().txs[0].data,
        )
        .unwrap();
        assert_eq!((c.from, c.to), (U256::from(10u64), U256::from(20u64)));
        assert_eq!(c.player, asha().address);
        assert_eq!(c.proof, vec![B256::repeat_byte(0x44)]);
        let i = Intent::RevealDraw {
            week: 4,
            seed: "0x12".into(),
        };
        assert!(run(&i, &f, None, &r).is_err());
        let i = Intent::SellHarvest {
            food: 50_000_000,
            reference: "h1".into(),
        };
        let c = IFarm::sellCall::abi_decode(&run(&i, &f, None, &r).unwrap().txs[0].data).unwrap();
        assert_eq!(c.r#ref, ref_hash("h1"));
    }

    #[test]
    fn labels_and_dns() {
        assert!(valid_label("asha-92"));
        assert!(!valid_label("-asha"));
        assert!(!valid_label(""));
        assert!(!valid_label("a.b"));
        assert!(!valid_label(&"a".repeat(64)));
        assert_eq!(dns_encode("ab.eth").unwrap().as_ref(), b"\x02ab\x03eth\x00");
        assert!(dns_encode("a..eth").is_err());
    }
}
