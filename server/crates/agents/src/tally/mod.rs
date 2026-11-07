//! The Tally, Tallyport's morning paper. `facts` reads what happened from the events, and `writer` turns those facts
//! into words. If it didn't happen, it isn't in the paper.

mod facts;
mod writer;

pub use facts::{Facts, Reporter};
pub use writer::{write, FrontPage};

#[cfg(test)]
mod tests {
    use super::facts::*;
    use super::*;
    use rules::{Event, First, MenuItem};

    fn menu() -> Vec<MenuItem> {
        let item = |name: &str, food, energy| MenuItem {
            name: name.into(),
            food,
            energy,
        };
        vec![item("chai", 1_000_000, 10), item("burger", 4_500_000, 40)]
    }

    fn reporter() -> Reporter {
        Reporter::new(&menu(), 1000, 10_000)
    }

    fn page(events: &[Event]) -> FrontPage {
        let mut r = reporter();
        events.iter().for_each(|e| r.observe(e));
        write(&r.take_facts())
    }

    fn all_text(page: &FrontPage) -> String {
        format!("{} {}", page.headline, page.stories.join(" "))
    }

    fn food(day_price: u64, food_index_bps: u32) -> Event {
        Event::FoodIndexSet {
            day: 3,
            day_price,
            food_index_bps,
        }
    }

    #[test]
    fn nothing_happened_so_nothing_is_printed() {
        let page = page(&[]);
        assert_eq!(page.headline, "A quiet day in Dhaniverse");
        assert_eq!(page.stories.len(), 0);
    }

    #[test]
    fn food_moves_and_the_menu_changes_it_caused_are_reported_in_usdc() {
        let mut r = reporter();
        r.observe(&food(1000, 10_000));
        r.take_facts();
        r.observe(&food(1060, 10_600));
        r.observe(&Event::FoodBought {
            day: 3,
            wanted: 100,
            bought: 40,
            usdc_paid: 1,
            reference: "x".into(),
        });
        let page = write(&r.take_facts());
        assert_eq!(page.headline, "Food prices jump 6.0%");
        assert_eq!(
            page.stories[0],
            "A unit of food cost 0.00106 USDC on average yesterday, up 6.0%. A chai now costs 0.00106 USDC, up from 0.001. A burger now costs 0.00477 USDC, up from 0.0045. The market hit its daily limit, and some stalls ran short."
        );
    }

    #[test]
    fn a_full_batch_doesnt_claim_the_stalls_ran_short() {
        let text = all_text(&page(&[Event::FoodBought {
            day: 3,
            wanted: 100,
            bought: 100,
            usdc_paid: 1,
            reference: "x".into(),
        }]));
        assert!(!text.contains("ran short"), "{text}");
    }

    #[test]
    fn a_quiet_market_says_nobody_traded_and_doesnt_make_up_a_move() {
        let text = all_text(&page(&[food(0, 10_000)]));
        assert!(text.contains("Nobody traded food yesterday"), "{text}");
        assert!(!text.contains("up"), "{text}");
    }

    #[test]
    fn festivals_harvests_and_droughts_only_appear_when_they_start() {
        let festival = Event::CityEventStarted {
            day: 3,
            kind: "festival".into(),
            days: 3,
        };
        let page = page(&[festival]);
        assert_eq!(page.headline, "A festival brings a crowd to town");
        assert!(page.stories[0].contains("for 3 days"));
        let drought = Event::CityEventStarted {
            day: 3,
            kind: "drought".into(),
            days: 1,
        };
        assert_eq!(
            self::page(&[drought]).headline,
            "A poor harvest hits the market"
        );
        let quiet = all_text(&self::page(&[food(1000, 10_000)]));
        assert!(!quiet.contains("festival") && !quiet.contains("harvest"));
    }

    #[test]
    fn firsts_name_the_player_and_the_list_stays_short() {
        let earned = |name: &str| Event::FirstEarned {
            account: name.into(),
            first: First::FirstMeal,
        };
        let page = page(&[
            earned("sam"),
            earned("priya"),
            earned("mira"),
            earned("arthur"),
        ]);
        assert_eq!(page.headline, "sam bought a first meal");
        assert_eq!(
            page.stories[0],
            "sam bought a first meal, and priya bought a first meal, and mira bought a first meal. 1 more first was earned around town."
        );
    }

    #[test]
    fn what_someone_paid_for_a_meal_is_never_in_the_paper() {
        let meal = Event::MealEaten {
            account: "sam".into(),
            item: "chai".into(),
            usdc: 1234,
            food: 1_000_000,
            energy: 50,
            from_ration: 0,
            reference: "r".into(),
            tx: String::new(),
        };
        let page = page(&[meal]);
        assert_eq!(page.headline, "A quiet day in Dhaniverse");
        assert_eq!(page.stories.len(), 0);
    }

    #[test]
    fn a_new_paper_starts_from_nothing() {
        let mut r = reporter();
        r.observe(&food(1060, 10_600));
        assert!(!write(&r.take_facts()).stories.is_empty());
        assert_eq!(r.take_facts(), Facts::default());
    }

    #[test]
    fn usdc_reads_as_a_plain_decimal() {
        assert_eq!(writer::usdc(1020), "0.00102");
        assert_eq!(writer::usdc(1_500_000), "1.5");
        assert_eq!(writer::usdc(2_000_000), "2");
    }
}
