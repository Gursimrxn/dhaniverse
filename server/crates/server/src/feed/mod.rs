//! The town's feed, split as The Tally is: `facts` decides what may be said from the events alone, and `writer` turns
//! those facts into words. A fact has no field for an amount anyone paid, so the words can't include one.

mod facts;
mod writer;

pub use facts::{read, Fact};
pub use writer::{write, Words};

#[cfg(test)]
mod tests {
    use super::*;
    use rules::house::Waiting;
    use rules::{ChestContents, Event, First, QuestReward, Tier};

    /// An amount nobody else may learn. If its digits turn up in a post, something private leaked.
    const SECRET: u64 = 987_654_321;

    fn sam() -> String {
        "sam".into()
    }

    fn r() -> String {
        "ref".into()
    }

    /// One of every event, with SECRET wherever an amount goes.
    fn every_event() -> Vec<Event> {
        vec![
            Event::Arrived {
                account: sam(),
                energy: 100,
            },
            Event::RushStarted {
                account: sam(),
                ends_at: 90_000,
                runs_left: 2,
            },
            Event::OrderServed {
                account: sam(),
                served: 3,
                reference: r(),
            },
            Event::RushEnded {
                account: sam(),
                served: 3,
            },
            Event::MealEaten {
                account: sam(),
                item: "chai".into(),
                usdc: SECRET,
                food: SECRET,
                energy: 50,
                from_ration: SECRET,
                reference: r(),
                tx: r(),
            },
            Event::MealOrdered {
                account: sam(),
                item: "thali".into(),
                food: SECRET,
                max_usdc: SECRET,
                reference: r(),
            },
            Event::BalanceChanged {
                account: sam(),
                usdc: SECRET,
            },
            Event::RewardPending {
                account: sam(),
                amount: SECRET,
                why: "x".into(),
                reference: r(),
                waiting: Waiting::TownPass,
            },
            Event::RewardPaid {
                account: sam(),
                amount: SECRET,
                advance_repaid: 0,
                why: "x".into(),
                reference: r(),
                tx: r(),
            },
            Event::ChestOpened {
                account: sam(),
                weekly: false,
                tier: Tier::Gold,
                contents: ChestContents {
                    energy: 1,
                    tickets: 1,
                    voucher: true,
                    golden_drop: SECRET,
                },
            },
            Event::QuestDone {
                account: sam(),
                quest: "campaign:1".into(),
                title: "The Spice Run".into(),
                reward: QuestReward {
                    usdc: SECRET,
                    tickets: 1,
                    title: None,
                    stamp: None,
                },
            },
            Event::DrawWon {
                account: sam(),
                week: 1,
                prize: SECRET,
                tx: r(),
            },
            Event::RescueMeal {
                account: sam(),
                energy: 70,
                direct: false,
            },
            Event::FirstEarned {
                account: sam(),
                first: First::FirstMeal,
            },
            Event::FirstCarved {
                account: sam(),
                first: First::FirstMeal,
            },
            Event::SeasonChanged {
                season: 2,
                shock: "drought".into(),
            },
            Event::MentorAsked {
                account: sam(),
                question: "x".into(),
            },
            Event::MentorSays {
                account: sam(),
                about: "x".into(),
                text: "x".into(),
            },
            Event::FeedPost {
                id: 1,
                day: 1,
                kind: "x".into(),
                text: "x".into(),
                about: None,
            },
            Event::Reacted {
                post: 1,
                account: sam(),
                emote: "clap".into(),
            },
            Event::Followed {
                account: sam(),
                player: "priya".into(),
            },
            Event::Unfollowed {
                account: sam(),
                player: "priya".into(),
            },
            Event::PaperPublished {
                day: 1,
                headline: "x".into(),
                stories: vec![],
            },
            Event::DayOpened {
                day: 1,
                open_price: SECRET,
            },
            Event::TradeCounted {
                day: 1,
                usdc: SECRET,
                food: SECRET,
                price_after: SECRET,
            },
            Event::FoodBought {
                day: 1,
                wanted: SECRET,
                bought: 1,
                usdc_paid: SECRET,
                reference: r(),
            },
            Event::FoodSold {
                day: 1,
                offered: SECRET,
                sold: SECRET,
                usdc_got: SECRET,
                reference: r(),
            },
            Event::FoodIndexSet {
                day: 1,
                day_price: SECRET,
                food_index_bps: 1,
            },
            Event::CityEventStarted {
                day: 1,
                kind: "festival".into(),
                days: 3,
            },
        ]
    }

    #[test]
    fn no_post_holds_an_amount_anyone_paid() {
        let secret = SECRET.to_string();
        for event in every_event() {
            if let Some(fact) = read(&event) {
                let words = write(&fact);
                assert!(!words.text.contains(&secret), "{event:?}: {}", words.text);
            }
        }
    }

    #[test]
    fn a_meal_and_the_mentor_are_never_posted() {
        for event in every_event() {
            if matches!(
                event,
                Event::MealEaten { .. }
                    | Event::MentorAsked { .. }
                    | Event::MentorSays { .. }
                    | Event::RescueMeal { .. }
                    | Event::RewardPaid { .. }
                    | Event::BalanceChanged { .. }
            ) {
                assert_eq!(read(&event), None, "{event:?}");
            }
        }
    }

    #[test]
    fn the_town_hears_of_firsts_shocks_seasons_and_a_short_market() {
        let posted: Vec<String> = every_event()
            .iter()
            .filter_map(read)
            .map(|fact| write(&fact).text)
            .collect();
        assert_eq!(
            posted,
            [
                "sam finished The Spice Run.",
                "sam won this week's draw.",
                "sam bought a first meal.",
                "Season 2 begins. A dry season: food is scarce.",
                "Kofi is short of food today.",
                "A festival has come to town.",
            ]
        );
    }

    #[test]
    fn a_full_batch_isnt_news() {
        let full = Event::FoodBought {
            day: 1,
            wanted: 10,
            bought: 10,
            usdc_paid: 1,
            reference: r(),
        };
        assert_eq!(read(&full), None);
    }

    #[test]
    fn a_new_rush_leader_is_named_with_nothing_but_the_board() {
        let words = write(&Fact::NewLeader {
            account: sam(),
            board: "rush",
        });
        assert_eq!(words.text, "sam is now the fastest at the stall in town.");
        assert_eq!(words.about, Some(sam()));
    }
}
