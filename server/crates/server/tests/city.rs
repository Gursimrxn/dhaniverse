//! The live city with its agents: the town runs on its own clock, and nobody can do another's job.

mod common;

use common::eat;
use rules::{apply, Command, Event, Refusal, Role};
use server::world::{Input, World};

const RULES: &str = include_str!("../../../rules.toml");
const DAY: u64 = 3_600_000;

fn city() -> World {
    World::new(RULES, 1).unwrap()
}

fn advance(world: &mut World, ms: u64) -> Vec<Event> {
    world.step(Input::Advance { ms }).unwrap()
}

fn connect(world: &mut World, player: &str) {
    let player = player.to_string();
    world.step(Input::Connect { player }).unwrap();
}

fn play(world: &mut World, command: Command) -> Result<Vec<Event>, Refusal> {
    world.step(Input::Command {
        by: Role::Player,
        command,
    })
}

#[test]
fn the_city_runs_with_nobody_connected() {
    let mut world = city();
    let events = advance(&mut world, 10 * DAY);
    assert_eq!(world.today(), 10);
    assert_eq!(world.town.refusals, []);
    let sold = events
        .iter()
        .filter(|e| matches!(e, Event::FoodSold { sold, .. } if *sold > 0))
        .count();
    assert!(sold > 0, "Kofi sells his harvest");
    let papers = events
        .iter()
        .filter(|e| matches!(e, Event::PaperPublished { .. }))
        .count();
    assert_eq!(papers, 10, "a paper every morning");
    let price = world.state.market.price();
    assert!(
        (500..=3000).contains(&price),
        "the price stays in its band: {price}"
    );
}

#[test]
fn logging_off_walks_you_away_from_the_stall() {
    let mut world = city();
    connect(&mut world, "sam");
    play(
        &mut world,
        Command::StartRush {
            account: "sam".into(),
        },
    )
    .unwrap();
    let serve = Command::ServeOrder {
        account: "sam".into(),
        reference: "o".into(),
    };
    play(&mut world, serve).unwrap();
    let events = world
        .step(Input::Disconnect {
            player: "sam".into(),
        })
        .unwrap();
    assert!(events.contains(&Event::RushEnded {
        account: "sam".into(),
        served: 1
    }));
    assert!(!world.state.life.player("sam").unwrap().in_rush);
    assert_eq!(world.season.best_run("sam"), 1, "the run still counts");
}

#[test]
fn offline_a_meals_food_is_bought_from_the_pool_at_once_and_the_price_moves() {
    let mut world = city();
    connect(&mut world, "sam");
    let before = world.state.market.price();
    let events = eat(&mut world, "sam", "thali", 24_000, "m");
    assert!(events
        .iter()
        .any(|e| matches!(e, Event::FoodBought { wanted, .. } if *wanted == 6_000_000)));
    assert!(world.state.market.price() > before, "the town's pool moved");
    let named = events
        .iter()
        .any(|e| matches!(e, Event::FoodBought { reference, .. } if reference.contains("sam")));
    assert!(!named, "the pool's trade doesn't say whose meal it was");
}

#[test]
fn nobody_can_do_anothers_job() {
    let mut world = city();
    connect(&mut world, "sam");
    let meal = || Command::Observe {
        block: 1,
        log_index: 0,
        time: 0,
        observed: rules::chain::Observation::MealEaten {
            player: "sam".into(),
            item: "chai".into(),
            usdc: 1,
            food: 1,
            from_ration: 0,
            reference: "free".into(),
            tx: "0x".into(),
        },
    };
    for role in [
        Role::Player,
        Role::Buyer,
        Role::Seller,
        Role::Clock,
        Role::Tally,
        Role::Mentor,
        Role::Verifier,
    ] {
        let refused = apply(&mut world.state, role, meal());
        assert_eq!(
            refused,
            Err(Refusal::NotAllowed {
                has: role,
                needs: Role::Chain
            }),
            "only the chain's indexer reports a meal"
        );
    }
    let buy = Command::BuyFood {
        wanted: 1_000_000,
        reference: "b".into(),
    };
    assert!(
        play(&mut world, buy).is_err(),
        "a player can't trade the pool"
    );
    let sell = Command::SellFood {
        offered: 1_000_000,
        reference: "s".into(),
    };
    assert!(
        apply(&mut world.state, Role::Buyer, sell).is_err(),
        "the buyer can't sell"
    );
}

#[test]
fn the_paper_only_reports_what_really_happened() {
    let mut world = city();
    let mut events = Vec::new();
    for _ in 0..30 {
        events.extend(advance(&mut world, DAY));
    }
    let known = [
        "A quiet day in Dhaniverse",
        "A festival brings a crowd to town",
        "A good harvest reaches the market",
        "A poor harvest hits the market",
    ];
    for event in &events {
        if let Event::PaperPublished {
            headline, stories, ..
        } = event
        {
            let food_move = headline.starts_with("Food prices ");
            assert!(
                known.contains(&headline.as_str()) || food_move,
                "{headline}"
            );
            for story in stories {
                for banned in ["coins", "loan", "savings", "rate", "Central Bank"] {
                    assert!(!story.contains(banned), "{story}");
                }
            }
        }
    }
}

#[test]
fn the_paper_can_only_write_the_paper() {
    let mut world = city();
    let paper = Command::PublishPaper {
        headline: "Made up".into(),
        stories: vec![],
    };
    assert!(apply(&mut world.state, Role::Player, paper.clone()).is_err());
    assert!(apply(&mut world.state, Role::Tally, paper).is_ok());
}
