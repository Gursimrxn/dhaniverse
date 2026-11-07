//! The town's rules, with no clock, network, disk or randomness: `apply(state, role, command)` returns what
//! happened, or a named refusal that changed nothing. Players, the farm, the paper, the clock and the chain's
//! reports all come through here.
//!
//! The only money is USDC, in base units (1 USDC = 1,000,000). FOOD is in base units too (1 FOOD = 1,000,000), and
//! rates are basis points. The food market's rules and rounding follow FoodHook and FoodRouter. Money moves only on
//! chain: the rules ask for it with an `Intent` event and learn it happened from an `Observe` command.

pub mod book;
pub mod campaigns;
pub mod chain;
mod chest;
mod clock;
mod command;
mod config;
pub mod dice;
mod event;
pub mod games;
pub mod house;
mod human;
pub mod life;
pub mod market;
mod math;
mod loot;
mod meals;
pub mod observe;
pub mod pool;
pub mod quests;
mod rush;
pub mod social;
mod town;

pub use book::QuestBook;
pub use chain::{ChainMode, Intent, Observation};
pub use command::{Command, Role};
pub use config::*;
pub use event::{ChestContents, Event, QuestReward, Refusal, Tier};
pub use life::{Call, First, Life};
pub use market::Market;
use serde::Serialize;
pub use social::Social;
use std::collections::BTreeMap;

const MOST_IN_A_QUESTION: usize = 200;

/// USDC in base units: 1 USDC is 1,000,000.
pub type Usdc = u64;
pub type Food = u64;
pub type AccountId = String;
pub type Ref = String;

/// Players can't have a `:` in their name, so one marks a resident: someone in town, but not a person with firsts, a
/// rank or a profile.
pub fn is_person(account: &str) -> bool {
    !account.contains(':')
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct State {
    pub config: Config,
    pub book: QuestBook,
    pub seed: u64,
    pub mode: ChainMode,
    /// This town's id, which every ref and draw week it sends to the chain carries. Empty for none (tests).
    pub town_id: String,
    /// The real clock, in ms since the city began.
    pub now_ms: u64,
    pub season: u32,
    pub market: Market,
    pub life: Life,
    pub social: Social,
    pub house: house::House,
    pub campaigns: campaigns::Campaigns,
    pub games: games::Games,
    /// Intents sent and not yet answered, by ref.
    pub outbox: BTreeMap<Ref, observe::Outbound>,
    pub chain: observe::ChainBook,
    /// The city event running now and its last day. `days` days from the day it was announced.
    pub city_event: Option<(String, u64)>,
    /// Today's front page, for anyone who connects after it went out.
    pub paper: Option<Paper>,
    /// The last loot crate to fall: out, claimed or gone.
    pub loot: Option<loot::Loot>,
}

/// One day's front page.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Paper {
    pub day: u64,
    pub headline: String,
    pub stories: Vec<String>,
}

impl State {
    /// A new offline world with no quests and seed 0, refusing settings FoodHook's constructor would refuse.
    pub fn new(config: &Config) -> Result<Self, Refusal> {
        Self::with(config, QuestBook::default(), 0, ChainMode::Offline)
    }

    /// A new world.
    pub fn with(
        config: &Config,
        book: QuestBook,
        seed: u64,
        mode: ChainMode,
    ) -> Result<Self, Refusal> {
        if book != QuestBook::default() {
            book.check()?;
        }
        Ok(State {
            market: Market::new(&config.food)?,
            life: Life::default(),
            social: Social::new(config.social.clone()),
            house: house::House::default(),
            campaigns: campaigns::Campaigns::default(),
            games: games::Games::default(),
            outbox: BTreeMap::new(),
            chain: observe::ChainBook::default(),
            config: config.clone(),
            book,
            seed,
            mode,
            town_id: String::new(),
            now_ms: 0,
            season: 1,
            city_event: None,
            paper: None,
            loot: None,
        })
    }

    /// What anyone may call this player. It names no amounts.
    pub fn title(&self, account: &str) -> String {
        let Some(player) = self.life.player(account) else {
            return "Newcomer".to_string();
        };
        if let Some(title) = player.titles.last() {
            return title.clone();
        }
        if player.firsts.is_empty() {
            "Newcomer".to_string()
        } else {
            "Regular".to_string()
        }
    }

    /// Today's city event, if one is running.
    pub fn city_event_today(&self) -> &str {
        match &self.city_event {
            Some((kind, last_day)) if self.market.today() <= *last_day => kind,
            _ => "",
        }
    }

    /// The real day: 24 real hours from the city's start, counted from 0.
    pub fn real_day(&self) -> u64 {
        self.now_ms / self.config.clock.real_day_ms.max(1)
    }

    /// The real week: 7 real days.
    pub fn week(&self) -> u64 {
        self.real_day() / 7
    }

    /// When the real day after this one starts.
    pub fn next_real_day_at(&self) -> u64 {
        (self.real_day() + 1) * self.config.clock.real_day_ms.max(1)
    }

    pub fn menu_item(&self, item: &str) -> Option<&MenuItem> {
        self.config.menu.iter().find(|m| m.name == item)
    }

    /// Whether this ref has gone to the chain, been settled, or is owed.
    pub(crate) fn ref_known(&self, reference: &str) -> bool {
        self.outbox.contains_key(reference)
            || self.chain.settled.contains(reference)
            || self.chain.failed.contains_key(reference)
            || self.house.owed.contains_key(reference)
    }
}

/// The one way anything changes. `by` is the role of whoever is asking, as `msg.sender` is on chain.
pub fn apply(state: &mut State, by: Role, command: Command) -> Result<Vec<Event>, Refusal> {
    let needs = command.role();
    if by != needs {
        return Err(Refusal::NotAllowed { has: by, needs });
    }
    let mut events = dispatch(state, command)?;
    state.life.award_firsts(&mut events);
    Ok(events)
}

fn dispatch(state: &mut State, command: Command) -> Result<Vec<Event>, Refusal> {
    match command {
        Command::Arrive { account } => state.arrive(account),
        Command::Login { account } => state.login(account),
        Command::StartRush { account } => state.start_rush(account),
        Command::ServeOrder { account, reference } => state.serve_order(account, reference),
        Command::EndRush { account } => state.end_rush(account, false),
        Command::FreeMeal { account } => state.free_meal(account),
        Command::BuyMeal {
            account,
            item,
            voucher,
            reference,
        } => state.buy_meal(account, item, voucher, reference),
        Command::OpenChest { account, weekly } => state.open_chest(account, weekly),
        Command::TakeQuest { account, quest } => state.take_quest(account, quest),
        Command::QuestStep {
            account,
            quest,
            step,
        } => state.quest_step(account, quest, step),
        Command::AbandonQuest { account, quest } => state.abandon_quest(account, quest),
        Command::Swap {
            account,
            quest,
            reference,
        } => state.swap(account, quest, reference),
        Command::Deliver {
            account,
            quest,
            reference,
        } => state.deliver(account, quest, reference),
        Command::Withdraw {
            account,
            to,
            amount,
            reference,
        } => state.withdraw(account, to, amount, reference),
        Command::ClaimLoot {
            account,
            id,
            reference,
        } => state.claim_loot(account, id, reference),
        Command::QuoteSwap { account, quest } => state.quote_swap(account, quest),
        Command::PaintSign { account, text } => state.paint_sign(account, text),
        Command::PriceCall { account, call } => state.price_call(account, call),
        Command::Refer { account, player } => state.refer(account, player),
        Command::CarveFirst { account, first } => state.life.carve_first(account, first),
        Command::AskMentor { account, question } => {
            state.life.check_arrived(&account)?;
            if question.chars().count() > MOST_IN_A_QUESTION {
                return Err(Refusal::QuestionTooLong {
                    max: MOST_IN_A_QUESTION,
                });
            }
            Ok(vec![Event::MentorAsked { account, question }])
        }
        Command::React {
            account,
            post,
            emote,
        } => {
            state.life.check_arrived(&account)?;
            state.social.react(account, post, emote)
        }
        Command::Follow { account, player } => state.social.follow(account, player, &state.life),
        Command::Unfollow { account, player } => state.social.unfollow(account, player),
        Command::Observe {
            block,
            log_index,
            time,
            observed,
        } => state.observe(block, log_index, time, observed),
        Command::VerifyHuman { account, human_id } => state.verify_human(account, human_id),
        Command::MentorSay {
            account,
            about,
            text,
        } => Ok(vec![Event::MentorSays {
            account,
            about,
            text,
        }]),
        Command::PublishPost { kind, text, about } => {
            Ok(state
                .social
                .publish(state.market.today(), kind, text, about))
        }
        Command::PublishPaper { headline, stories } => {
            let day = state.market.today();
            state.paper = Some(Paper {
                day,
                headline: headline.clone(),
                stories: stories.clone(),
            });
            Ok(vec![Event::PaperPublished {
                day,
                headline,
                stories,
            }])
        }
        Command::StartSeason { season, shock } => {
            state.season = season;
            Ok(vec![Event::SeasonChanged { season, shock }])
        }
        Command::BuyFood { wanted, reference } => state.market.buy_food(wanted, reference),
        Command::SellFood { offered, reference } => state.market.sell_food(offered, reference),
        Command::OfferHarvest { offered, reference } => state.offer_harvest(offered, reference),
        Command::Tick { now_ms } => state.tick(now_ms),
        Command::NewDay { day } => state.new_city_day(day),
        Command::AnnounceCityEvent { kind, days } => {
            let day = state.market.today();
            state.city_event = Some((kind.clone(), day + u64::from(days.max(1)) - 1));
            Ok(vec![Event::CityEventStarted { day, kind, days }])
        }
        Command::CommitDraw {
            week,
            seed,
            seed_hash,
        } => state.commit_draw(week, seed, seed_hash),
        Command::ReadyChest { account } => {
            state.life.get_mut(&account)?.chest_at = None;
            Ok(Vec::new())
        }
    }
}
