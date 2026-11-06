//! A fact in plain words. It only sees the fact, so a model can replace this function later and still can't reveal more.

use super::Fact;
use rules::{AccountId, First};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Words {
    pub kind: &'static str,
    pub text: String,
    pub about: Option<AccountId>,
}

pub fn write(fact: &Fact) -> Words {
    let by = |account: &AccountId, kind, text| Words {
        kind,
        text,
        about: Some(account.clone()),
    };
    let town = |kind, text: String| Words {
        kind,
        text,
        about: None,
    };
    match fact {
        Fact::First { account, first } => {
            by(account, "first", format!("{account} {}.", did(*first)))
        }
        Fact::NewLeader { account, board } => by(
            account,
            "board",
            format!("{account} is now {}.", leader(board)),
        ),
        Fact::CityEvent { kind } => town("city", city_event(kind)),
        Fact::Season { season, shock } => town(
            "season",
            format!("Season {season} begins. {}", season_shock(shock)),
        ),
        Fact::ShortOfFood => town("city", "Kofi is short of food today.".to_string()),
        Fact::QuestDone { account, title } => {
            by(account, "quest", format!("{account} finished {title}."))
        }
        Fact::PriceCallRight { account } => by(
            account,
            "call",
            format!("{account} called the market right."),
        ),
        Fact::TownGoal => town(
            "goal",
            "The town reached this week's goal. Everyone's next chest is one better.".to_string(),
        ),
        Fact::DrawWon { account } => {
            by(account, "draw", format!("{account} won this week's draw."))
        }
        Fact::NewBounty => town(
            "bounty",
            "A new bounty is up on the board in the square.".to_string(),
        ),
    }
}

fn did(first: First) -> &'static str {
    match first {
        First::FirstMeal => "bought a first meal",
        First::FirstQuest => "finished a first quest",
        First::TownPass => "got the Town Pass",
    }
}

fn leader(board: &str) -> &'static str {
    match board {
        "rush" => "the fastest at the stall in town",
        _ => "top of a board",
    }
}

fn city_event(kind: &str) -> String {
    match kind {
        "festival" => "A festival has come to town.".to_string(),
        "harvest" => "A good harvest is coming in.".to_string(),
        "drought" => "The harvest is poor this time.".to_string(),
        other => format!("Something's happening in town: {other}."),
    }
}

fn season_shock(shock: &str) -> String {
    match shock {
        "harvest" => "Harvest season: food is plentiful.".to_string(),
        "festival" => "Festival season: the town is full.".to_string(),
        "drought" => "A dry season: food is scarce.".to_string(),
        other => format!("This season: {other}."),
    }
}
