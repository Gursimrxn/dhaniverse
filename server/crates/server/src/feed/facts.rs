//! What may be said about an event in public. There's no catch-all below, so a new event has to choose here.

use rules::{is_person, AccountId, Event, First};

/// Something the whole town may know. No field here can hold an amount anyone paid.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Fact {
    First {
        account: AccountId,
        first: First,
    },
    NewLeader {
        account: AccountId,
        board: &'static str,
    },
    CityEvent {
        kind: String,
    },
    Season {
        season: u32,
        shock: String,
    },
    ShortOfFood,
    /// A sponsored quest, a mystery or Grandma's Ledger finished. Errands are everyday, so they aren't news.
    QuestDone {
        account: AccountId,
        title: String,
    },
    PriceCallRight {
        account: AccountId,
    },
    TownGoal,
    DrawWon {
        account: AccountId,
    },
    NewBounty,
}

/// The fact in this event, if it holds one anyone may know.
pub fn read(event: &Event) -> Option<Fact> {
    match event {
        Event::FirstEarned { account, first } => is_person(account).then(|| Fact::First {
            account: account.clone(),
            first: *first,
        }),
        Event::CityEventStarted { kind, .. } => Some(Fact::CityEvent { kind: kind.clone() }),
        Event::SeasonChanged { season, shock } => Some(Fact::Season {
            season: *season,
            shock: shock.clone(),
        }),
        Event::FoodBought { wanted, bought, .. } => (bought < wanted).then_some(Fact::ShortOfFood),
        Event::QuestDone {
            account,
            quest,
            title,
            ..
        } => (is_person(account) && !quest.starts_with("errand:")).then(|| Fact::QuestDone {
            account: account.clone(),
            title: title.clone(),
        }),
        Event::PriceCallSettled {
            account,
            right: true,
            ..
        } => Some(Fact::PriceCallRight {
            account: account.clone(),
        }),
        Event::TownGoalReached { .. } => Some(Fact::TownGoal),
        // Who won, never what.
        Event::DrawWon { account, .. } => Some(Fact::DrawWon {
            account: account.clone(),
        }),
        Event::BountyPosted { .. } => Some(Fact::NewBounty),

        // Private, by the rule: what someone paid or was paid, their wallet, what's owed, whether they needed rescuing,
        // and what the mentor told them.
        Event::MealEaten { .. }
        | Event::MealOrdered { .. }
        | Event::MealFailed { .. }
        | Event::VoucherUsed { .. }
        | Event::WalletReady { .. }
        | Event::BalanceChanged { .. }
        | Event::RewardPending { .. }
        | Event::RewardPaid { .. }
        | Event::RescueComing { .. }
        | Event::RescueMeal { .. }
        | Event::ChestOpened { .. }
        | Event::Intent { .. }
        | Event::MentorAsked { .. }
        | Event::MentorSays { .. } => None,

        // A player's day, and the market's own ticking. Nobody needs a post for these. A Rush run reaches the feed
        // only when it changes who leads a board.
        Event::Arrived { .. }
        | Event::RushStarted { .. }
        | Event::OrderServed { .. }
        | Event::RushEnded { .. }
        | Event::FirstCarved { .. }
        | Event::Followed { .. }
        | Event::Unfollowed { .. }
        | Event::Reacted { .. }
        | Event::FeedPost { .. }
        | Event::PaperPublished { .. }
        | Event::DayOpened { .. }
        | Event::TradeCounted { .. }
        | Event::FoodSold { .. }
        | Event::FoodIndexSet { .. }
        | Event::LoggedIn { .. }
        | Event::RushTimeUp { .. }
        | Event::FreeMealEaten { .. }
        | Event::HumanVerified { .. }
        | Event::NameRegistered { .. }
        | Event::SignPainting { .. }
        | Event::WithdrawSent { .. }
        | Event::Withdrawn { .. }
        | Event::WithdrawFailed { .. }
        | Event::CrateDropped { .. }
        | Event::CrateOpened { .. }
        | Event::LootDropped { .. }
        | Event::LootClaimed { .. }
        | Event::LootGone { .. }
        | Event::RecordsSet { .. }
        | Event::QuestTaken { .. }
        | Event::QuestStepSent { .. }
        | Event::SwapQuoted { .. }
        | Event::QuoteFailed { .. }
        | Event::QuestStepDone { .. }
        | Event::QuestSwapped { .. }
        | Event::QuestStepFailed { .. }
        | Event::QuestAbandoned { .. }
        | Event::QuestFailed { .. }
        | Event::TicketsEarned { .. }
        | Event::PriceCalled { .. }
        | Event::PriceCallSettled { .. }
        | Event::Referred { .. }
        | Event::ReferralRewarded { .. }
        | Event::DrawCommitted { .. }
        | Event::DrawRevealed { .. }
        | Event::BountyClosed { .. }
        | Event::LedgerUpdated { .. } => None,
    }
}
