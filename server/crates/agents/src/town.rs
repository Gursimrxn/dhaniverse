//! The town running itself: each city day shocks roll, and through the day Kofi sells the harvest. Offline he sells
//! into the town's own pool; on a chain his offer goes to the keeper, and what sold comes back as an observation.
//! Everything goes through `rules::apply`, and it's all decided from the seed and the state, so the same inputs always
//! make the same city.

use crate::kofi::{Kofi, KofiConfig};
use crate::mentor::Mentor;
use crate::residents::{Residents, ResidentsConfig, Whereabouts};
use crate::rng::Rng;
use crate::tally::{self, Reporter};
use rules::market::food_index_bps;
use rules::{apply, Command, Event, FoodConfig, MenuItem, Refusal, Role, State, Usdc};
use serde::Deserialize;

const NO_CHANGE_BPS: u64 = 10_000;
/// Kofi's sales carry refs starting with this.
const KOFI_REF: &str = "kofi-";

/// The town's part of rules.toml. The rules crate reads its part from the same file.
#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
pub struct TownConfig {
    pub city: CityConfig,
    pub kofi: KofiConfig,
    pub shocks: ShocksConfig,
    pub residents: ResidentsConfig,
    pub seasons: SeasonsConfig,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
pub struct CityConfig {
    pub slices_per_day: u64,
    pub day_ms: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
pub struct ShocksConfig {
    pub festival_chance_bps: u64,
    pub festival_days: u32,
    pub harvest_chance_bps: u64,
    pub harvest_supply_bps: u64,
    pub harvest_days: u32,
    pub drought_chance_bps: u64,
    pub drought_supply_bps: u64,
    pub drought_days: u32,
}

/// One real week a season, and the shock each one brings.
#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
pub struct SeasonsConfig {
    pub season_days: u64,
    pub shocks: Vec<String>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct Shock {
    days_left: u32,
    supply_bps: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Town {
    config: TownConfig,
    base_price: Usdc,
    kofi: Kofi,
    residents: Residents,
    mentor: Mentor,
    reporter: Reporter,
    rng: Rng,
    shock: Shock,
    /// Whether the harvest is sold on a chain, rather than into the town's own pool.
    on_chain: bool,
    /// Anything the rules refused an agent. Always empty unless an agent has a bug.
    pub refusals: Vec<Refusal>,
}

impl Town {
    pub fn new(
        config: TownConfig,
        food: &FoodConfig,
        menu: &[MenuItem],
        seed: u64,
        on_chain: bool,
    ) -> Self {
        let index = food_index_bps(food.start_price, food.base_price);
        Town {
            kofi: Kofi::new(config.kofi),
            residents: Residents::new(config.residents.clone(), seed),
            mentor: Mentor::default(),
            reporter: Reporter::new(menu, food.base_price, index),
            rng: Rng::new(seed),
            shock: Shock::default(),
            on_chain,
            refusals: Vec::new(),
            base_price: food.base_price,
            config,
        }
    }

    /// The morning: the clock moves on, shocks roll, Kofi's harvest comes in, and the paper goes out.
    pub fn start_day(&mut self, state: &mut State, day: u64) -> Vec<Event> {
        let mut events = Vec::new();
        if day > 0 {
            self.send(state, Role::Clock, Command::NewDay { day }, &mut events);
        }
        self.roll_shock(state, &mut events);
        let price = state.market.price();
        let aim = self.kofi.aim(self.base_price);
        let supply_bps = self.supply_today();
        self.kofi.start_day(price, aim, supply_bps, &mut self.rng);
        if day > 0 {
            self.publish_paper(state, &mut events);
        }
        events
    }

    /// One slice of the day: a slice of the harvest goes on sale.
    pub fn run_slice(&mut self, state: &mut State, day: u64, slice: u64) -> Vec<Event> {
        let mut events = Vec::new();
        let left = self.config.city.slices_per_day - slice;
        let reference = format!("{KOFI_REF}{day}-{slice}");
        let offered = self.kofi.next_slice(left);
        if offered > 0 {
            let offer = if self.on_chain {
                Command::OfferHarvest { offered, reference }
            } else {
                Command::SellFood { offered, reference }
            };
            self.send(state, Role::Seller, offer, &mut events);
        }
        if slice + 1 == self.config.city.slices_per_day {
            self.kofi.end_day();
        }
        events
    }

    /// The mentor reads what just happened and says what it has to. Whatever it says goes through the rules too.
    pub fn mentor_speaks(&mut self, state: &mut State, events: &[Event]) -> Vec<Event> {
        let says = self.mentor.read(events);
        let mut said = Vec::new();
        for say in says {
            self.send(state, Role::Mentor, say, &mut said);
        }
        said
    }

    /// Lets the agents see what happened: The Tally reads it all, and Kofi learns what of his harvest sold, whether
    /// the town's own pool or the chain said so.
    pub fn observe(&mut self, events: &[Event]) {
        for event in events {
            self.reporter.observe(event);
            if let Event::FoodSold {
                sold, reference, ..
            } = event
            {
                if reference.starts_with(KOFI_REF) {
                    self.kofi.sold(*sold);
                }
            }
        }
    }

    /// The morning paper: everything since yesterday's.
    fn publish_paper(&mut self, state: &mut State, events: &mut Vec<Event>) {
        let page = tally::write(&self.reporter.take_facts());
        let paper = Command::PublishPaper {
            headline: page.headline,
            stories: page.stories,
        };
        self.send(state, Role::Tally, paper, events);
    }

    pub fn whereabouts(&self, city_ms: u64) -> Vec<Whereabouts> {
        self.residents.whereabouts(city_ms)
    }

    pub fn config(&self) -> &TownConfig {
        &self.config
    }

    pub fn kofi_stock(&self) -> rules::Food {
        self.kofi.stock()
    }

    pub fn city(&self) -> CityConfig {
        self.config.city
    }

    /// Today's supply multiplier from any shock.
    fn supply_today(&self) -> u64 {
        if self.shock.days_left == 0 {
            return NO_CHANGE_BPS;
        }
        self.shock.supply_bps
    }

    fn roll_shock(&mut self, state: &mut State, events: &mut Vec<Event>) {
        self.shock.days_left = self.shock.days_left.saturating_sub(1);
        if self.shock.days_left > 0 {
            return;
        }
        let s = self.config.shocks;
        if self.rng.chance(s.festival_chance_bps) {
            self.start_shock(state, "festival", events);
        } else if self.rng.chance(s.harvest_chance_bps) {
            self.start_shock(state, "harvest", events);
        } else if self.rng.chance(s.drought_chance_bps) {
            self.start_shock(state, "drought", events);
        }
    }

    fn start_shock(&mut self, state: &mut State, kind: &'static str, events: &mut Vec<Event>) {
        let s = self.config.shocks;
        let (days_left, supply_bps) = match kind {
            "festival" => (s.festival_days, NO_CHANGE_BPS),
            "harvest" => (s.harvest_days, s.harvest_supply_bps),
            _ => (s.drought_days, s.drought_supply_bps),
        };
        self.shock = Shock {
            days_left,
            supply_bps,
        };
        let announce = Command::AnnounceCityEvent {
            kind: kind.to_string(),
            days: days_left,
        };
        self.send(state, Role::Clock, announce, events);
    }

    /// The shock this season brings. Season 2 takes the first on the list, and they go round in turn.
    pub fn shock_for(&self, season: u32) -> String {
        let shocks = &self.config.seasons.shocks;
        let at = season.saturating_sub(2) as usize % shocks.len().max(1);
        shocks.get(at).cloned().unwrap_or_default()
    }

    /// A new season, with its shock working through the same rules as any other day's.
    pub fn start_season(&mut self, state: &mut State, season: u32) -> Vec<Event> {
        let shock = self.shock_for(season);
        let mut events = Vec::new();
        let start = Command::StartSeason {
            season,
            shock: shock.clone(),
        };
        self.send(state, Role::Clock, start, &mut events);
        match shock.as_str() {
            "harvest" => self.start_shock(state, "harvest", &mut events),
            "festival" => self.start_shock(state, "festival", &mut events),
            "drought" => self.start_shock(state, "drought", &mut events),
            _ => {}
        }
        events
    }

    /// An agent can't stop the city: a refusal is kept for the logs, and the day goes on.
    fn send(&mut self, state: &mut State, by: Role, command: Command, events: &mut Vec<Event>) {
        match apply(state, by, command) {
            Ok(more) => {
                self.observe(&more);
                events.extend(more);
            }
            Err(refusal) => self.refusals.push(refusal),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rules::Config;

    const RULES: &str = include_str!("../../../rules.toml");

    fn city() -> (State, Town) {
        let config: Config = toml::from_str(RULES).unwrap();
        let town_config: TownConfig = toml::from_str(RULES).unwrap();
        let state = State::new(&config).unwrap();
        let town = Town::new(town_config, &config.food, &config.menu, 1, false);
        (state, town)
    }

    #[test]
    fn the_town_runs_for_weeks_with_no_players_and_no_agent_is_ever_refused() {
        let (mut state, mut town) = city();
        let mut papers = 0;
        for day in 0..200 {
            let events = town.start_day(&mut state, day);
            papers += events
                .iter()
                .filter(|e| matches!(e, Event::PaperPublished { .. }))
                .count();
            for slice in 0..12 {
                town.run_slice(&mut state, day, slice);
            }
        }
        assert_eq!(town.refusals, []);
        assert_eq!(papers, 199, "a paper every morning after the first");
    }

    #[test]
    fn offline_kofi_sells_into_the_pool_and_on_a_chain_he_offers_to_the_keeper() {
        let (mut state, mut town) = city();
        town.start_day(&mut state, 0);
        let events = town.run_slice(&mut state, 0, 0);
        assert!(events.iter().any(|e| matches!(e, Event::FoodSold { .. })));

        let config: Config = toml::from_str(RULES).unwrap();
        let town_config: TownConfig = toml::from_str(RULES).unwrap();
        let mut state = State::new(&config).unwrap();
        let mut chain_town = Town::new(town_config, &config.food, &config.menu, 1, true);
        chain_town.start_day(&mut state, 0);
        let events = chain_town.run_slice(&mut state, 0, 0);
        assert!(!events.iter().any(|e| matches!(e, Event::FoodSold { .. })));
        let offered = events.iter().any(|e| {
            matches!(
                e,
                Event::Intent {
                    intent: rules::Intent::SellHarvest { .. }
                }
            )
        });
        assert!(offered, "{events:?}");
        assert_eq!(chain_town.refusals, []);
    }

    #[test]
    fn every_season_brings_a_shock_from_the_list() {
        let (mut state, mut town) = city();
        town.start_day(&mut state, 0);
        for season in 2..6 {
            let events = town.start_season(&mut state, season);
            assert!(events
                .iter()
                .any(|e| matches!(e, Event::SeasonChanged { .. })));
            assert!(events
                .iter()
                .any(|e| matches!(e, Event::CityEventStarted { .. })));
        }
        assert_eq!(town.refusals, []);
    }
}
