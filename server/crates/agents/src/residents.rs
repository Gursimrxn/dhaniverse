//! The people who live here, so the town isn't empty with one player on stage. They walk between the town's places.
//! Where they are is worked out from the seed and the clock alone, so it never needs saving.

use crate::Rng;
use serde::Deserialize;

/// A player's name can't hold a `:`, so these can't be taken. Rules treat anything with one as not a person.
pub const RESIDENT_PREFIX: &str = "resident:";
pub const PLACES: [&str; 5] = ["market", "table", "bank", "homes", "square"];

#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
pub struct ResidentsConfig {
    pub names: Vec<String>,
    /// How long someone stays at a place, walking included. Each person's is their own, between these.
    pub least_stay_ms: u64,
    pub most_stay_ms: u64,
    /// The first part of each stay is spent walking there.
    pub walk_ms: u64,
}

/// Where one resident is right now.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Whereabouts {
    pub name: String,
    pub from: &'static str,
    pub place: &'static str,
    pub walking: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Residents {
    config: ResidentsConfig,
    seed: u64,
}

impl Residents {
    pub fn new(config: ResidentsConfig, seed: u64) -> Self {
        // Their own dice, so adding people never changes the market's.
        let seed = seed ^ 0x5245_5349_4445_4E54;
        Residents { config, seed }
    }

    pub fn account(name: &str) -> String {
        format!("{RESIDENT_PREFIX}{}", name.to_lowercase())
    }

    /// Where everyone is at this moment of the city's clock. The same moment always gives the same answer.
    pub fn whereabouts(&self, city_ms: u64) -> Vec<Whereabouts> {
        let people = self.config.names.iter().enumerate();
        people
            .map(|(person, name)| {
                let (from, place, into_stay) = self.stop(person, city_ms);
                Whereabouts {
                    name: name.clone(),
                    from: PLACES[from],
                    place: PLACES[place],
                    walking: into_stay < self.config.walk_ms,
                }
            })
            .collect()
    }

    /// For one person at one moment: (the place they came from, where they are, how far into the stay).
    fn stop(&self, person: usize, city_ms: u64) -> (usize, usize, u64) {
        let person = person as u64;
        let c = &self.config;
        let spread = c.most_stay_ms.saturating_sub(c.least_stay_ms) + 1;
        let stay = c.least_stay_ms + self.dice(person, 0).below(spread);
        // Everyone starts at their own moment, so they don't all set off together.
        let clock = city_ms + self.dice(person, 1).below(stay);
        let step = clock / stay;
        let place = |step: u64| self.dice(person, step + 2).below(PLACES.len() as u64) as usize;
        // At the very start, they came from where they are.
        (place(step.saturating_sub(1)), place(step), clock % stay)
    }

    /// A number that depends only on who and when.
    fn dice(&self, person: u64, step: u64) -> Rng {
        Rng::new(self.seed ^ (person << 48) ^ step.wrapping_mul(0x9E37_79B9))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::town::TownConfig;
    use std::collections::BTreeSet;

    const RULES: &str = include_str!("../../../rules.toml");

    fn config() -> ResidentsConfig {
        let town: TownConfig = toml::from_str(RULES).unwrap();
        town.residents
    }

    #[test]
    fn about_twenty_people_live_here() {
        assert!(config().names.len() >= 20);
    }

    #[test]
    fn where_someone_is_depends_only_on_the_seed_and_the_clock() {
        let config = config();
        let (one, two) = (
            Residents::new(config.clone(), 1),
            Residents::new(config.clone(), 1),
        );
        let other = Residents::new(config, 2);
        let at = 7_654_321;
        assert_eq!(one.whereabouts(at), two.whereabouts(at));
        assert_ne!(one.whereabouts(at), other.whereabouts(at));
    }

    #[test]
    fn people_walk_between_every_named_place_and_come_from_where_they_were() {
        let residents = Residents::new(config(), 1);
        let mut seen = BTreeSet::new();
        let mut previous = residents.whereabouts(0);
        let mut walking_now_and_then = false;
        for second in 1..3600 {
            let now = residents.whereabouts(second * 1000);
            for (before, after) in previous.iter().zip(&now) {
                seen.insert(after.place);
                walking_now_and_then |= after.walking;
                if before.place != after.place {
                    assert_eq!(after.from, before.place, "{after:?}");
                    assert!(after.walking, "they set off walking: {after:?}");
                }
            }
            previous = now;
        }
        assert_eq!(seen.len(), PLACES.len());
        assert!(walking_now_and_then);
    }

    #[test]
    fn a_resident_can_never_be_mistaken_for_a_person() {
        let account = Residents::account("Asha");
        assert_eq!(account, "resident:asha");
        assert!(!rules::is_person(&account));
    }
}
