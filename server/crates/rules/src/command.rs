//! What can be asked of the rules, and who may ask.

use crate::chain::{HumanId, Observation};
use crate::life::Call;
use crate::{AccountId, First, Food, Ref, Usdc};
use serde::{Deserialize, Serialize};

/// What a key may do. Each maps to one contract role or one server part, plus `Clock`, which stands in for the
/// chain's block clock.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum Role {
    /// The server, acting for one player who is connected and asked.
    Player,
    /// FoodRouter's buyer. Offline, the town's own pool is bought from directly; this is what a test uses.
    Buyer,
    /// FoodRouter's seller: the farm, selling the harvest into the pool.
    Seller,
    Clock,
    /// The mentor. It can say things to one player, and nothing else.
    Mentor,
    /// The morning paper and the feed. They read everything and can touch nothing but what they publish.
    Tally,
    /// The chain's indexer: it reports what the chain did, and nothing else.
    Chain,
    /// The World ID check: it says who is a person.
    Verifier,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum Command {
    // A player's own actions.
    Arrive {
        account: AccountId,
    },
    /// Being in town on a real day: the streak and its ticket. Nothing on a second visit the same day.
    Login {
        account: AccountId,
    },
    /// Market Rush: a 90-second run behind the stall. Free; the day's best runs share the Rush pot.
    StartRush {
        account: AccountId,
    },
    ServeOrder {
        account: AccountId,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    EndRush {
        account: AccountId,
    },
    /// The community thali at the Common Table.
    FreeMeal {
        account: AccountId,
    },
    /// A meal from the menu, paid in USDC on chain, or with a chest's meal voucher.
    BuyMeal {
        account: AccountId,
        item: String,
        voucher: bool,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    OpenChest {
        account: AccountId,
        weekly: bool,
    },
    /// The crate a quest dropped at your feet.
    OpenCrate {
        account: AccountId,
    },
    TakeQuest {
        account: AccountId,
        quest: String,
    },
    /// A step the client sees happen: talking to someone, going somewhere, reading the paper, opening the strongbox.
    QuestStep {
        account: AccountId,
        quest: String,
        step: String,
    },
    AbandonQuest {
        account: AccountId,
        quest: String,
    },
    Swap {
        account: AccountId,
        quest: String,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    Deliver {
        account: AccountId,
        quest: String,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    /// Sends USDC from the player's wallet to an address they name, from the phone's wallet.
    Withdraw {
        account: AccountId,
        to: String,
        amount: Usdc,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    /// First to the loot crate: its prize.
    ClaimLoot {
        account: AccountId,
        id: u64,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    /// The exchange kiosk's Uniswap quote for the cargo.
    QuoteSwap {
        account: AccountId,
        quest: String,
    },
    PaintSign {
        account: AccountId,
        text: String,
    },
    PriceCall {
        account: AccountId,
        call: Call,
    },
    /// Names who sent them to Tallyport.
    Refer {
        account: AccountId,
        player: AccountId,
    },
    CarveFirst {
        account: AccountId,
        first: First,
    },
    AskMentor {
        account: AccountId,
        question: String,
    },
    React {
        account: AccountId,
        post: u64,
        emote: String,
    },
    Follow {
        account: AccountId,
        player: AccountId,
    },
    Unfollow {
        account: AccountId,
        player: AccountId,
    },
    // The chain and World ID.
    /// Something the chain did, where it happened. `time` is the block's unix seconds, 0 if unknown.
    Observe {
        block: u64,
        log_index: u64,
        time: u64,
        observed: Observation,
    },
    /// World ID says this player is a person.
    VerifyHuman {
        account: AccountId,
        human_id: HumanId,
    },
    // The mentor. Off-chain.
    MentorSay {
        account: AccountId,
        about: String,
        text: String,
    },
    // The paper and the feed. Off-chain.
    /// The morning paper goes out. It changes no money, and the facts it's written from are in the log.
    PublishPaper {
        headline: String,
        stories: Vec<String>,
    },
    /// A post on the town's feed, written from real events. Only the same role as the paper may send one.
    PublishPost {
        kind: String,
        text: String,
        about: Option<AccountId>,
    },
    // FoodRouter, or the farm's offer to the chain.
    BuyFood {
        wanted: Food,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    SellFood {
        offered: Food,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    /// On a chain: the farm offers harvest, sold by the keeper through `Farm`.
    OfferHarvest {
        offered: Food,
        #[serde(rename = "ref")]
        reference: Ref,
    },
    // The clock.
    /// The real clock moving on. Runs end, rescues arrive, days and weeks close.
    Tick {
        now_ms: u64,
    },
    /// A new city day: the chain's clock moving on, plus the server's price reader turning yesterday's price
    /// into the food index.
    NewDay {
        day: u64,
    },
    /// A festival, a harvest or a drought arrives. Not a contract call: it goes on the record so the paper can report it.
    AnnounceCityEvent {
        kind: String,
        days: u32,
    },
    /// A new season, with the shock it brings.
    StartSeason {
        season: u32,
        shock: String,
    },
    /// The week's draw, with a seed the server drew at random. Only its hash goes to the chain until the reveal.
    CommitDraw {
        week: u64,
        seed: String,
        seed_hash: String,
    },
    /// Rehearsal only: this player's daily chest is ready now.
    ReadyChest {
        account: AccountId,
    },
}

impl Command {
    /// The role a key needs for this command.
    pub fn role(&self) -> Role {
        match self {
            Command::Arrive { .. }
            | Command::Login { .. }
            | Command::StartRush { .. }
            | Command::ServeOrder { .. }
            | Command::EndRush { .. }
            | Command::FreeMeal { .. }
            | Command::BuyMeal { .. }
            | Command::OpenChest { .. }
            | Command::OpenCrate { .. }
            | Command::TakeQuest { .. }
            | Command::QuestStep { .. }
            | Command::AbandonQuest { .. }
            | Command::Swap { .. }
            | Command::Deliver { .. }
            | Command::Withdraw { .. }
            | Command::ClaimLoot { .. }
            | Command::QuoteSwap { .. }
            | Command::PaintSign { .. }
            | Command::PriceCall { .. }
            | Command::Refer { .. }
            | Command::CarveFirst { .. }
            | Command::AskMentor { .. }
            | Command::React { .. }
            | Command::Follow { .. }
            | Command::Unfollow { .. } => Role::Player,
            Command::Observe { .. } => Role::Chain,
            Command::VerifyHuman { .. } => Role::Verifier,
            Command::BuyFood { .. } => Role::Buyer,
            Command::SellFood { .. } | Command::OfferHarvest { .. } => Role::Seller,
            Command::MentorSay { .. } => Role::Mentor,
            Command::PublishPaper { .. } | Command::PublishPost { .. } => Role::Tally,
            Command::Tick { .. }
            | Command::NewDay { .. }
            | Command::AnnounceCityEvent { .. }
            | Command::StartSeason { .. }
            | Command::CommitDraw { .. }
            | Command::ReadyChest { .. } => Role::Clock,
        }
    }
}
