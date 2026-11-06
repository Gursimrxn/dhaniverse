//! The town's rule-based agents: Kofi the farm, the residents, the mentor and The Tally. They only read the rules'
//! state and send commands through `rules::apply`, as players do, so nothing here can break a rule.

mod kofi;
pub mod mentor;
mod residents;
mod rng;
pub mod tally;
mod town;

pub use kofi::KofiConfig;
pub use residents::{Residents, ResidentsConfig, Whereabouts, RESIDENT_PREFIX};
pub use rng::Rng;
pub use town::{CityConfig, SeasonsConfig, ShocksConfig, Town, TownConfig};

const BPS: u64 = 10_000;

/// `amount` × `bps` ÷ 10,000, rounded down.
fn share(amount: u64, bps: u64) -> u64 {
    (u128::from(amount) * u128::from(bps) / u128::from(BPS)) as u64
}
