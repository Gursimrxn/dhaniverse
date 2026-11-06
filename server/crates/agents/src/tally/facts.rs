//! What actually happened since the last paper, read from the events and nothing else. If there's no event for it,
//! it isn't here, and the writer can't print it.

use rules::market::meal_price;
use rules::{AccountId, Event, First, MenuItem, Usdc};

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Facts {
    pub food: Option<FoodFacts>,
    /// Batches the day's limit stopped part-way, buying and selling.
    pub short_batches: u32,
    pub unsold_slices: u32,
    pub menu_changes: Vec<MenuChange>,
    pub city_events: Vec<CityFact>,
    pub firsts: Vec<(AccountId, First)>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FoodFacts {
    /// Zero if nobody traded.
    pub day_price: Usdc,
    /// The last day that had a price, if there was one.
    pub previous_day_price: Option<Usdc>,
}

/// A meal's price moved with the food index. In USDC base units.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MenuChange {
    pub name: String,
    pub from: Usdc,
    pub to: Usdc,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CityFact {
    pub kind: String,
    pub days: u32,
}

/// Gathers facts as events go by, and hands over a finished set when the paper goes out.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Reporter {
    menu: Vec<MenuItem>,
    base_price: Usdc,
    food_index_bps: u32,
    last_day_price: Option<Usdc>,
    facts: Facts,
}

impl Reporter {
    pub fn new(menu: &[MenuItem], base_price: Usdc, food_index_bps: u32) -> Self {
        Reporter {
            menu: menu.to_vec(),
            base_price,
            food_index_bps,
            last_day_price: None,
            facts: Facts::default(),
        }
    }

    /// The facts since the last paper. The next paper starts fresh.
    pub fn take_facts(&mut self) -> Facts {
        std::mem::take(&mut self.facts)
    }

    pub fn observe(&mut self, event: &Event) {
        match event {
            Event::FoodIndexSet {
                day_price,
                food_index_bps,
                ..
            } => self.on_food_index(*day_price, *food_index_bps),
            Event::FoodBought { wanted, bought, .. } if bought < wanted => {
                self.facts.short_batches += 1;
            }
            Event::FoodSold { offered, sold, .. } if sold < offered => {
                self.facts.unsold_slices += 1;
            }
            Event::CityEventStarted { kind, days, .. } => self.facts.city_events.push(CityFact {
                kind: kind.clone(),
                days: *days,
            }),
            Event::FirstEarned { account, first } => {
                self.facts.firsts.push((account.clone(), *first));
            }
            _ => {}
        }
    }

    fn on_food_index(&mut self, day_price: Usdc, food_index_bps: u32) {
        self.facts.food = Some(FoodFacts {
            day_price,
            previous_day_price: self.last_day_price,
        });
        if day_price != 0 {
            self.last_day_price = Some(day_price);
        }
        for item in &self.menu {
            let from = meal_price(item.food, self.base_price, self.food_index_bps);
            let to = meal_price(item.food, self.base_price, food_index_bps);
            if from != to {
                self.facts.menu_changes.push(MenuChange {
                    name: item.name.clone(),
                    from,
                    to,
                });
            }
        }
        self.food_index_bps = food_index_bps;
    }
}
