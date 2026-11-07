//! The messages in PROTOCOL.md: what clients may send, and how the world looks to them.

use crate::boards;
use crate::world::World;
use rules::book::QuestText;
use rules::chain::Bucket;
use rules::house::{share, Category};
use rules::life::Player;
use rules::quests::{min_out, ActiveQuest, QuestKind};
use rules::{is_person, AccountId, Call, Command, Event, First};
use serde::Deserialize;
use serde_json::{json, Value};

pub const PROTOCOL_VERSION: u64 = 3;
const FEED_ON_CONNECT: usize = 30;
const KNOWN_DAYS: u64 = 3;
const RELIABLE_DAYS: u64 = 30;
const PILLAR_DAYS: u64 = 120;

#[derive(Debug, Deserialize)]
#[serde(tag = "type")]
pub enum ClientMessage {
    #[serde(rename = "hello")]
    Hello {
        protocol: u64,
        /// Left out by a new player, who hasn't written their name yet.
        #[serde(default)]
        player: String,
        /// Missing reads as empty, so an older client gets a `BadSecret` it can show, not an error.
        #[serde(default)]
        secret: String,
    },
    #[serde(rename = "move")]
    Move {
        x: f64,
        y: f64,
        z: f64,
        yaw: f64,
        anim: String,
    },
    #[serde(rename = "profile")]
    Profile { name: String },
    #[serde(rename = "command")]
    Command {
        #[serde(rename = "ref")]
        reference: String,
        command: PlayerCommand,
    },
    #[serde(rename = "debug")]
    Debug { action: DebugAction },
}

/// What a client may ask for. The account always comes from the connection, never from the message, so nobody can
/// act for someone else, and the chain, the clock and the market aren't here at all.
#[derive(Debug, Deserialize)]
#[serde(tag = "type")]
pub enum PlayerCommand {
    /// The hub answers this one itself: it decides who the connection is, so no account exists yet.
    ClaimName {
        name: String,
    },
    /// The hub answers this one too: it hands out a one-time verify link.
    TownPass,
    StartRush,
    ServeOrder,
    EndRush,
    FreeMeal,
    BuyMeal {
        item: String,
        #[serde(default)]
        voucher: bool,
    },
    OpenChest {
        #[serde(default)]
        weekly: bool,
    },
    OpenCrate,
    TakeQuest {
        quest: String,
    },
    QuestStep {
        quest: String,
        step: String,
    },
    AbandonQuest {
        quest: String,
    },
    Swap {
        quest: String,
    },
    Deliver {
        quest: String,
    },
    QuoteSwap {
        quest: String,
    },
    /// Send USDC from your wallet to an address (base units: 1000000 is 1 USDC).
    Withdraw {
        to: String,
        amount: u64,
    },
    ClaimLoot {
        id: u64,
    },
    PaintSign {
        text: String,
    },
    PriceCall {
        call: Call,
    },
    Refer {
        player: AccountId,
    },
    CarveFirst {
        first: First,
    },
    AskMentor {
        question: String,
    },
    React {
        post: u64,
        emote: String,
    },
    Follow {
        player: AccountId,
    },
    Unfollow {
        player: AccountId,
    },
}

impl PlayerCommand {
    /// The rules' command, for this player. Refs are the player's own, so two players can't collide.
    pub fn into_command(self, player: &str, reference: &str) -> Option<Command> {
        let account = player.to_string();
        let reference = format!("{player}:{reference}");
        Some(match self {
            PlayerCommand::ClaimName { .. } | PlayerCommand::TownPass => return None,
            PlayerCommand::StartRush => Command::StartRush { account },
            PlayerCommand::ServeOrder => Command::ServeOrder { account, reference },
            PlayerCommand::EndRush => Command::EndRush { account },
            PlayerCommand::FreeMeal => Command::FreeMeal { account },
            PlayerCommand::BuyMeal { item, voucher } => Command::BuyMeal {
                account,
                item,
                voucher,
                reference,
            },
            PlayerCommand::OpenChest { weekly } => Command::OpenChest { account, weekly },
            PlayerCommand::OpenCrate => Command::OpenCrate { account },
            PlayerCommand::TakeQuest { quest } => Command::TakeQuest { account, quest },
            PlayerCommand::QuestStep { quest, step } => Command::QuestStep {
                account,
                quest,
                step,
            },
            PlayerCommand::AbandonQuest { quest } => Command::AbandonQuest { account, quest },
            PlayerCommand::Swap { quest } => Command::Swap {
                account,
                quest,
                reference,
            },
            PlayerCommand::Deliver { quest } => Command::Deliver {
                account,
                quest,
                reference,
            },
            PlayerCommand::QuoteSwap { quest } => Command::QuoteSwap { account, quest },
            PlayerCommand::Withdraw { to, amount } => Command::Withdraw {
                account,
                to,
                amount,
                reference,
            },
            PlayerCommand::ClaimLoot { id } => Command::ClaimLoot {
                account,
                id,
                reference,
            },
            PlayerCommand::PaintSign { text } => Command::PaintSign { account, text },
            PlayerCommand::PriceCall { call } => Command::PriceCall { account, call },
            PlayerCommand::Refer { player } => Command::Refer { account, player },
            PlayerCommand::CarveFirst { first } => Command::CarveFirst { account, first },
            PlayerCommand::AskMentor { question } => Command::AskMentor { account, question },
            PlayerCommand::React { post, emote } => Command::React {
                account,
                post,
                emote,
            },
            PlayerCommand::Follow { player } => Command::Follow { account, player },
            PlayerCommand::Unfollow { player } => Command::Unfollow { account, player },
        })
    }
}

#[derive(Debug, Deserialize)]
#[serde(tag = "type")]
pub enum DebugAction {
    Skip {
        ms: u64,
    },
    NextSeason,
    /// Offline only: USDC into your wallet, as a faucet would.
    Fund {
        usdc: u64,
    },
    /// Offline only: USDC into a HousePool bucket.
    FundBucket {
        bucket: Bucket,
        usdc: u64,
    },
    /// Your daily chest is ready now.
    ReadyChest,
    /// Offline only: the Town Pass, as the verify page's rehearsal would.
    PassTown,
    /// Offline only: a sponsor opens a campaign.
    NewCampaign {
        template: String,
        payout: u64,
        energy: u32,
        slots: u32,
        #[serde(default)]
        boosted: bool,
    },
}

/// Whether everyone should see this event, whoever it names.
pub fn is_public(event: &Event) -> bool {
    named_in(event).is_none() || matches!(event, Event::Reacted { .. })
}

/// Events no client ever sees: what the server asks of the chain.
pub fn is_internal(event: &Event) -> bool {
    matches!(event, Event::Intent { .. })
}

/// A private event that still changes what everyone sees in `city`.
pub fn changes_city(event: &Event) -> bool {
    matches!(
        event,
        Event::RushEnded { .. }
            | Event::FirstEarned { .. }
            | Event::MealEaten { .. }
            | Event::QuestTaken { .. }
            | Event::QuestDone { .. }
            | Event::QuestAbandoned { .. }
            | Event::QuestFailed { .. }
            | Event::RewardPaid { .. }
            | Event::TicketsEarned { .. }
            | Event::HumanVerified { .. }
            | Event::NameRegistered { .. }
    )
}

/// The players an event is about, or None if it's about the whole city.
pub fn named_in(event: &Event) -> Option<Vec<AccountId>> {
    let one = |account: &AccountId| Some(vec![account.clone()]);
    match event {
        Event::Arrived { account, .. }
        | Event::LoggedIn { account, .. }
        | Event::RushStarted { account, .. }
        | Event::OrderServed { account, .. }
        | Event::RushTimeUp { account, .. }
        | Event::RushEnded { account, .. }
        | Event::FreeMealEaten { account, .. }
        | Event::MealOrdered { account, .. }
        | Event::MealEaten { account, .. }
        | Event::MealFailed { account, .. }
        | Event::VoucherUsed { account, .. }
        | Event::WalletReady { account, .. }
        | Event::BalanceChanged { account, .. }
        | Event::HumanVerified { account }
        | Event::NameRegistered { account, .. }
        | Event::SignPainting { account, .. }
        | Event::CrateDropped { account, .. }
        | Event::CrateOpened { account, .. }
        | Event::WithdrawSent { account, .. }
        | Event::Withdrawn { account, .. }
        | Event::WithdrawFailed { account, .. }
        | Event::RecordsSet { account, .. }
        | Event::QuestTaken { account, .. }
        | Event::QuestStepSent { account, .. }
        | Event::QuestStepDone { account, .. }
        | Event::QuestSwapped { account, .. }
        | Event::QuestStepFailed { account, .. }
        | Event::QuestDone { account, .. }
        | Event::SwapQuoted { account, .. }
        | Event::QuoteFailed { account, .. }
        | Event::QuestAbandoned { account, .. }
        | Event::QuestFailed { account, .. }
        | Event::ChestOpened { account, .. }
        | Event::TicketsEarned { account, .. }
        | Event::RewardPending { account, .. }
        | Event::RewardPaid { account, .. }
        | Event::PriceCalled { account, .. }
        | Event::PriceCallSettled { account, .. }
        | Event::RescueComing { account, .. }
        | Event::RescueMeal { account, .. }
        | Event::Referred { account, .. }
        | Event::DrawWon { account, .. }
        | Event::FirstEarned { account, .. }
        | Event::FirstCarved { account, .. }
        | Event::Reacted { account, .. }
        | Event::Followed { account, .. }
        | Event::Unfollowed { account, .. }
        | Event::MentorAsked { account, .. }
        | Event::MentorSays { account, .. } => one(account),
        Event::ReferralRewarded {
            account, friend, ..
        } => Some(vec![account.clone(), friend.clone()]),
        // Never sent; listed so a new event has to choose.
        Event::Intent { .. } => Some(Vec::new()),
        Event::DayOpened { .. }
        | Event::TradeCounted { .. }
        | Event::FoodBought { .. }
        | Event::FoodSold { .. }
        | Event::FoodIndexSet { .. }
        | Event::CityEventStarted { .. }
        | Event::PaperPublished { .. }
        | Event::SeasonChanged { .. }
        | Event::FeedPost { .. }
        | Event::TownGoalReached { .. }
        | Event::DrawCommitted { .. }
        | Event::DrawRevealed { .. }
        | Event::BountyPosted { .. }
        | Event::BountyClosed { .. }
        | Event::LootDropped { .. }
        | Event::LootClaimed { .. }
        | Event::LootGone { .. }
        | Event::LedgerUpdated { .. } => None,
    }
}

/// The book's words for a quest someone is on.
fn quest_text<'a>(world: &'a World, quest: &ActiveQuest) -> Option<&'a QuestText> {
    let book = &world.state.book;
    match &quest.kind {
        QuestKind::Errand { template } => book.errand(template),
        QuestKind::Campaign { template, .. } => book.templates.get(template),
        QuestKind::Grandma => book.grandma.as_ref(),
        QuestKind::Mystery { template, .. } => book.mystery(template),
    }
}

fn quest_json(world: &World, quest: &ActiveQuest) -> Value {
    let text = quest_text(world, quest);
    let spice = world.state.config.templates.spice_run;
    let slippage_bps = spice.slippage_bps;
    let steps: Vec<Value> = quest
        .steps
        .iter()
        .map(|s| {
            let words = text.and_then(|t| t.steps.iter().find(|w| w.id == s.id));
            json!({
                "id": s.id,
                "kind": s.kind,
                "text": words.map_or("", |w| w.text.as_str()),
                "place": words.map_or("", |w| w.place.as_str()),
                "done": s.done,
                "waiting": s.waiting.is_some(),
                "quote": s.quote.as_ref().map(|q| json!({
                    "usdc_in": q.usdc_in,
                    "amount_out": q.amount_out.to_string(),
                    "min_out": min_out(q.amount_out, slippage_bps).to_string(),
                    "fee_bps": q.fee_bps,
                    "slippage_bps": slippage_bps,
                    "token": q.token,
                    "symbol": q.symbol,
                    "decimals": q.decimals,
                    "quoted_at": q.quoted_at,
                    "fresh_until": q.quoted_at + spice.quote_fresh_ms,
                })),
                "quote_ready_at": s.quote_asked_at.map(|at| at + spice.quote_every_ms),
            })
        })
        .collect();
    let campaign = match &quest.kind {
        QuestKind::Campaign { campaign, .. } => Some(*campaign),
        QuestKind::Mystery { boosted_by, .. } => *boosted_by,
        _ => None,
    };
    let hold = quest
        .hold
        .as_ref()
        .map(|h| json!({"ends": h.ends, "checks_left": h.due.len(), "passed": h.passed}));
    json!({
        "quest": quest.quest,
        "title": quest.title,
        "story": text.map_or("", |t| t.story.as_str()),
        "kind": quest.kind,
        "campaign": campaign,
        "energy": quest.energy,
        "any_order": quest.any_order,
        "steps": steps,
        "hold": hold,
        // what the quest has given you to carry: the advance owed until the payout repays it, and the tokens the swap got
        "advanced": quest.advanced,
        "cargo_usdc": if quest.steps.iter().any(|s| s.kind == rules::book::StepKind::Cargo) { spice.cargo } else { 0 },
        "swapped": quest.swapped.to_string(),
    })
}

fn left_today(used: (u64, u32), today: u64, most: u32) -> u32 {
    let used = if used.0 == today { used.1 } else { 0 };
    most.saturating_sub(used)
}

/// A player as they should see themselves. Empty for someone who hasn't arrived.
pub fn you(world: &World, name: &str) -> Value {
    let state = &world.state;
    let Some(player) = state.life.player(name) else {
        return json!({});
    };
    let c = &state.config;
    let (now, today, week) = (state.now_ms, state.real_day(), state.week());
    let standings = world.boards();
    let quests: Vec<Value> = player
        .quests
        .values()
        .map(|q| quest_json(world, q))
        .collect();
    let pending: Vec<Value> = state
        .house
        .owed
        .iter()
        .filter(|(_, o)| o.account == name)
        .map(|(r, o)| json!({"ref": r, "amount": o.amount, "why": o.why, "waiting": o.waiting}))
        .collect();
    let price_call = player
        .price_call
        .filter(|(day, _)| *day == state.market.today())
        .map(|(day, call)| json!({"day": day, "call": call}));
    json!({
        "name": name,
        "title": state.title(name),
        "energy": player.energy_now(now, &c.energy),
        "energy_max": c.energy.max,
        "energy_regen_at": player.next_regen_at(now, &c.energy),
        "in_rush": player.in_rush,
        "served": player.served,
        "rush_ends_at": player.in_rush.then_some(player.rush_ends_at),
        "runs_left": left_today(player.runs, today, c.rush.runs_per_day),
        "best_run": world.season.best_run(name),
        "best_today": if player.rush_best.0 == today { player.rush_best.1 } else { 0 },
        "firsts": player.firsts,
        "following": state.social.following(name).collect::<Vec<_>>(),
        "ranks": boards::ranks_json(&standings, name),
        "best_board": boards::best_board(&standings, name),
        "neighbours": boards::neighbours_json(state, &standings, name),
        "wallet": player.wallet,
        "usdc": player.usdc,
        "human": player.human.is_some(),
        "ens": player.ens,
        "sign": player.sign,
        "quests": quests,
        "errands_left": left_today(player.errands, today, c.errands.per_day),
        "mystery_left": left_today(player.mysteries, today, c.mystery.per_day),
        "grandma_done": player.grandma_season == Some(state.season),
        "chest": chest_json(world, name, player),
        "crate": player.crate_waiting,
        "streak": {
            "days": player.streak,
            "week_days": player.days_in_window(today, c.streak.window_days),
            "need": c.streak.days_needed,
        },
        "tickets": player.tickets_in(week),
        "vouchers": player.vouchers,
        "pending": state.house.owed_to(name),
        "pending_rewards": pending,
        "meal_pending": player.pending_meal,
        "free_meal_at": state.free_meal_at(name),
        "rescue_at": player.rescue_at,
        "price_call": price_call,
        "titles": player.titles,
        "stamps": player.stamps,
        "referrer": player.referrer,
    })
}

fn chest_json(world: &World, name: &str, player: &Player) -> Value {
    let state = &world.state;
    let c = &state.config;
    json!({
        "ready_at": state.chest_ready_at(name),
        "tier": state.chest_tier(name),
        "pity": player.since_drop,
        "pity_every": c.chest.pity_every,
        "weekly_ready_at": state.weekly_ready_at(name),
    })
}

/// The live campaigns as Bounty Board cards, and the rest with their status, for the sponsor's dashboard.
fn bounty(world: &World) -> Vec<Value> {
    let state = &world.state;
    let time = state.campaigns.time;
    state
        .campaigns
        .all()
        .map(|campaign| {
            let status = if campaign.closed {
                "closed"
            } else if time != 0 && time < campaign.start {
                "upcoming"
            } else if time != 0 && time >= campaign.end {
                "ended"
            } else if campaign.slots_left() == 0 {
                "full"
            } else {
                "live"
            };
            let title = state
                .book
                .templates
                .get(&campaign.template)
                .map_or(campaign.template.as_str(), |t| t.title.as_str());
            let swarm = (!campaign.meta_hash.is_empty()).then_some(campaign.meta_hash.as_str());
            // where the quest starts, for the badge the game puts over its giver (ux07)
            let place = state.book.templates.get(&campaign.template).and_then(|t| t.steps.first()).map_or("", |s| s.place.as_str());
            json!({
                "place": place,
                "id": campaign.id,
                "quest": format!("campaign:{}", campaign.id),
                "kind": if campaign.boosted() { "boosted" } else { "sponsored" },
                "sponsor": campaign.sponsor,
                "title": title,
                "template": campaign.template,
                "payout": campaign.payout,
                "energy": campaign.energy,
                "slots": campaign.max_claims,
                "slots_left": campaign.slots_left(),
                "claims": campaign.claims,
                "humans": campaign.humans.len(),
                "budget": campaign.budget,
                "spendable": campaign.budget,
                "paid": campaign.spent,
                "remaining": campaign.remaining(),
                "daily_cap": campaign.daily_cap(time),
                "starts": campaign.start,
                "ends": campaign.end,
                "status": status,
                "swarm": swarm,
            })
        })
        .collect()
}

fn house(world: &World) -> Value {
    let house = &world.state.house;
    let bucket = |b: Bucket| {
        let book = house.book(b);
        json!({
            "balance": book.balance,
            "budget": book.day_budget,
            "spent": book.day_budget.saturating_sub(book.budget_left),
            "budget_left": book.budget_left,
            "available": house.available(b),
        })
    };
    let s = house.stats;
    json!({
        "budget_bps": world.state.config.house.budget_bps,
        "seen": house.seen,
        "fixed": bucket(Bucket::Fixed),
        "surprise": bucket(Bucket::Surprise),
        "safety": bucket(Bucket::Safety),
        "paid_today": s.paid_today,
        "rescue_meals": {"today": s.rescues_today, "total": s.rescues_total, "usdc_total": s.rescue_usdc_total},
        "draw_reserved": house.draw_reserved,
    })
}

fn treasury(world: &World) -> Value {
    let t = world.state.house.treasury;
    let bps = world.state.config.treasury;
    json!({
        "balance": t.revenue_total.saturating_sub(t.split_total),
        "revenue_today": t.revenue_today,
        "harvest_today": t.revenue_today,
        "revenue_total": t.revenue_total,
        "split": {"fixed": t.to_fixed, "safety": t.to_safety, "ops": t.to_ops, "team": t.to_team},
        "split_bps": {"fixed": bps.fixed_bps, "safety": bps.safety_bps, "ops": bps.ops_bps, "team": bps.team_bps},
        "last_split_at": world.state.house.stats.last_split_at,
    })
}

fn float(world: &World) -> Value {
    let f = world.state.house.float;
    let time = world.state.campaigns.time;
    let caps: u64 = world
        .state
        .campaigns
        .all()
        .filter(|c| c.live(time))
        .map(|c| c.daily_cap(time))
        .sum();
    json!({
        "total": f.total_assets,
        "liquid": f.liquid,
        "invested": f.invested,
        "buffer": f.buffer,
        "daily_caps_sum": caps,
        "liabilities": f.liabilities,
        "yield_earned": f.yield_earned,
        "loss_reserve": f.loss_reserve,
    })
}

/// The city as everyone sees it. Money is USDC base units. Only town-wide numbers: nothing about one player.
pub fn city(world: &World) -> Value {
    let state = &world.state;
    let (market, c) = (&state.market, &state.config);
    let menu: Vec<Value> = c
        .menu
        .iter()
        .map(|item| {
            let (price, max_usdc) = state.meal_ticket(item.food);
            json!({
                "name": item.name,
                "food": item.food,
                "price": price,
                "max_usdc": max_usdc,
                "was": market.quote_yesterday(item.food),
                "energy": item.energy,
            })
        })
        .collect();
    let season_days = world.town.config().seasons.season_days.max(1);
    let errands: Vec<Value> = state
        .book
        .errands
        .iter()
        .map(|e| json!({"quest": format!("errand:{}", e.id), "title": e.title, "story": e.story, "place": e.steps.first().map_or("", |s| s.place.as_str())}))
        .collect();
    let mystery = state.todays_mystery().map(|(text, boosted_by)| {
        json!({
            "quest": format!("mystery:{}", text.id),
            "title": text.title,
            "place": text.steps.first().map_or("", |s| s.place.as_str()),
            "story": text.story,
            "energy": c.mystery.energy,
            "payout": state.mystery_payout(),
            "boosted_by": boosted_by,
        })
    });
    let grandma = state.book.grandma.as_ref().map(|g| {
        json!({"quest": "grandma", "title": g.title, "story": g.story, "energy": c.grandma.energy})
    });
    let week = state.week();
    let tickets: u64 = state.ticket_ranges(week).last().map_or(0, |r| r.to + 1);
    let prize = share(state.house.book(Bucket::Surprise).balance, c.draw.prize_bps)
        .min(state.house.free_balance(Bucket::Surprise));
    let goal = &state.games.goal;
    let progress = if goal.week == week { goal.meals } else { 0 };
    json!({
        "day": world.today(),
        "day_ms": world.town.city().day_ms,
        "day_elapsed_ms": world.day_elapsed_ms(),
        "now_ms": state.now_ms,
        "real_day": state.real_day(),
        "real_day_ms": c.clock.real_day_ms,
        "next_real_day_at": state.next_real_day_at(),
        "chain": state.mode.name(),
        "price": market.price(),
        "open_price": market.open_price(market.today()),
        "food_index_bps": market.food_index_bps(),
        "menu": menu,
        "food": {
            "price": market.price(),
            "floor": c.food.floor,
            "ceiling": c.food.ceiling,
            "meals_today": state.house.stats.meals_today,
            "usdc_today": state.house.stats.usdc_today,
        },
        "free_meal_energy": c.meals.free_meal_energy,
        "rush": {
            "run_ms": c.rush.run_ms,
            "runs_per_day": c.rush.runs_per_day,
            "most_orders": c.rush.most_orders_per_run,
            "pot": state.house.category_left(Category::Rush, c),
            "today": state.rush_standings(state.real_day()).iter().enumerate()
                .map(|(i, (name, _))| json!({"rank": i + 1, "name": name, "title": state.title(name)}))
                .collect::<Vec<_>>(),
        },
        "most_orders_per_run": c.rush.most_orders_per_run,
        "errands": {
            "rate": state.errand_rate(),
            "per_day": c.errands.per_day,
            "energy": c.errands.energy,
            "list": errands,
        },
        "mystery": mystery,
        "grandma": grandma,
        "golden_drop": c.chest.golden_drop,
        "bounty": bounty(world),
        "house": house(world),
        "treasury": treasury(world),
        "float": float(world),
        "town_goal": {"week": week, "target": c.town_goal.meals, "progress": progress, "reached": goal.week == week && goal.reached},
        "draw": {"week": week, "tickets": tickets, "prize": prize},
        "shock": state.city_event_today(),
        "paper": state.paper,
        "loot": state.loot.as_ref().map(|l| json!({"id": l.id, "spot": l.spot, "prize": l.prize, "ends_at": l.ends_at, "claimed_by": l.claimed_by, "out": l.out(state.now_ms)})),
        "resident_walk_ms": world.town.config().residents.walk_ms,
        "emotes": state.social.emotes(),
        "boards": boards::to_json(state, &world.boards()),
        "season": {
            "number": world.season.number,
            "shock": world.season.shock,
            "ends_day": (world.today() / season_days + 1) * season_days,
        },
    })
}

/// What anyone on the internet may read. It's built from a list of what's allowed, rather than by taking things out of
/// `city`, so a field added there later can't leak here.
pub fn public_view(world: &World, world_app_id: Option<&str>) -> Value {
    let state = &world.state;
    let market = &state.market;
    let c = city(world);
    let pick = |from: &Value, keys: &[&str]| -> Value {
        let picked = keys
            .iter()
            .map(|key| ((*key).to_string(), from[*key].clone()));
        Value::Object(picked.collect())
    };
    let list = |key: &str, keys: &[&str]| -> Vec<Value> {
        let items = c[key].as_array().cloned().unwrap_or_default();
        items.iter().map(|item| pick(item, keys)).collect()
    };
    let mut people: Vec<Value> = state
        .life
        .players()
        .filter(|(name, _)| is_person(name))
        .map(|(name, p)| {
            json!({"name": name, "title": state.title(name), "stamps": p.stamps, "ens": p.ens})
        })
        .collect();
    people.sort_by(|a, b| a["name"].as_str().cmp(&b["name"].as_str()));
    let bounty_keys = [
        "id",
        "kind",
        "sponsor",
        "title",
        "template",
        "payout",
        "energy",
        "slots",
        "slots_left",
        "claims",
        "humans",
        "budget",
        "spendable",
        "paid",
        "remaining",
        "daily_cap",
        "starts",
        "ends",
        "status",
        "swarm",
    ];
    let mut food = pick(
        &c["food"],
        &["price", "floor", "ceiling", "meals_today", "usdc_today"],
    );
    food["open_price"] = json!(market.open_price(market.today()));
    food["food_index_bps"] = json!(market.food_index_bps());
    food["shock"] = json!(state.city_event_today());
    food["menu"] = json!(list("menu", &["name", "price", "was"]));
    json!({
        "protocol": PROTOCOL_VERSION,
        "chain": state.mode.name(),
        "world_app_id": world_app_id,
        "day": world.today(),
        "day_ms": world.town.city().day_ms,
        "season": c["season"],
        "price": market.price(),
        "food": food,
        "paper": state.paper,
        "boards": c["boards"],
        "bounty": list("bounty", &bounty_keys),
        "house": c["house"],
        "treasury": c["treasury"],
        "float": c["float"],
        "town_goal": c["town_goal"],
        "draw": c["draw"],
        "feed": feed(world),
        "people": people,
        "online": world.connected().count(),
        "residents": world.town.config().residents.names.len(),
    })
}

/// The latest posts, for someone connecting.
pub fn feed(world: &World) -> Value {
    let posts: Vec<&rules::social::Post> = world.state.social.latest(FEED_ON_CONNECT).collect();
    json!(posts)
}

/// What anyone may know about a player. Reputation only rises and never says why.
pub fn profile(world: &World, name: &str) -> Value {
    let state = &world.state;
    let Some(player) = state.life.player(name).filter(|_| is_person(name)) else {
        return json!({"type": "profile", "found": false, "name": name});
    };
    let firsts: Vec<First> = player.firsts.iter().map(|e| e.first).collect();
    json!({
        "type": "profile",
        "found": true,
        "name": name,
        "title": state.title(name),
        "firsts": firsts,
        "stamps": player.stamps,
        "ens": player.ens,
        "sign": player.sign,
        "town_pass": player.human.is_some(),
        "days_active": world.days_active(name),
        "reputation": reputation(world, name),
    })
}

fn reputation(world: &World, name: &str) -> &'static str {
    let days = world.days_active(name);
    if days >= PILLAR_DAYS {
        "Pillar of the town"
    } else if days >= RELIABLE_DAYS {
        "Reliable"
    } else if days >= KNOWN_DAYS {
        "Known around town"
    } else {
        "New in town"
    }
}

pub fn time(world: &World) -> Value {
    let city = world.town.city();
    json!({
        "type": "time",
        "day": world.today(),
        "day_ms": city.day_ms,
        "day_elapsed_ms": world.day_elapsed_ms(),
        "now_ms": world.state.now_ms,
    })
}
