//! Kofi, the farm. Food arrives each day and he sells it in slices. He aims for a price a little over base, sells
//! faster above his aim and holds back below it. Unsold food partly spoils.

use crate::{share, Rng, BPS};
use rules::{Food, Usdc};
use serde::Deserialize;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
pub struct KofiConfig {
    pub harvest: Food,
    pub harvest_noise_bps: u64,
    pub starting_stock: Food,
    pub spoilage_bps: u64,
    pub sell_share_bps: u64,
    pub sell_share_gain: u64,
    pub least_share_bps: u64,
    pub most_share_bps: u64,
    pub push_bps: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Kofi {
    config: KofiConfig,
    stock: Food,
    left_today: Food,
}

impl Kofi {
    pub fn new(config: KofiConfig) -> Self {
        Kofi {
            config,
            stock: config.starting_stock,
            left_today: 0,
        }
    }

    /// The price he's aiming for: base plus his push.
    pub fn aim(&self, base_price: Usdc) -> Usdc {
        share(base_price, BPS + self.config.push_bps)
    }

    /// Food arrives (times any harvest multiplier), and he decides how much to offer today.
    pub fn start_day(&mut self, price: Usdc, aim: Usdc, supply_bps: u64, rng: &mut Rng) {
        let c = self.config;
        self.stock += share(
            share(c.harvest, supply_bps),
            rng.around_one(c.harvest_noise_bps),
        );
        let gap_bps = (i128::from(price) - i128::from(aim)) * i128::from(BPS) / i128::from(aim);
        let share_bps = i128::from(c.sell_share_bps) + gap_bps * i128::from(c.sell_share_gain);
        let share_bps =
            share_bps.clamp(i128::from(c.least_share_bps), i128::from(c.most_share_bps));
        self.left_today = share(self.stock, share_bps as u64);
    }

    /// The next slice he offers, 0 when today's offer is done.
    pub fn next_slice(&mut self, slices_left: u64) -> Food {
        let offered = self.left_today / slices_left.max(1);
        self.left_today -= offered;
        offered
    }

    /// What actually sold leaves his crates. What didn't fill stays for tomorrow.
    pub fn sold(&mut self, sold: Food) {
        self.stock -= sold;
    }

    /// Part of what's left goes off overnight.
    pub fn end_day(&mut self) {
        self.stock -= share(self.stock, self.config.spoilage_bps);
    }

    pub fn stock(&self) -> Food {
        self.stock
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const CONFIG: KofiConfig = KofiConfig {
        harvest: 750_000_000,
        harvest_noise_bps: 0,
        starting_stock: 0,
        spoilage_bps: 3000,
        sell_share_bps: 5500,
        sell_share_gain: 1,
        least_share_bps: 2500,
        most_share_bps: 9000,
        push_bps: 500,
    };

    /// What he offers on a day with an empty shed before the harvest.
    fn offer(price: Usdc) -> Food {
        let mut kofi = Kofi::new(CONFIG);
        let aim = kofi.aim(1000);
        kofi.start_day(price, aim, BPS, &mut Rng::new(1));
        kofi.left_today
    }

    #[test]
    fn he_aims_a_little_over_base() {
        assert_eq!(Kofi::new(CONFIG).aim(1000), 1050, "5% over base");
    }

    #[test]
    fn he_sells_more_when_the_price_is_high_within_his_limits() {
        assert!(offer(1100) > offer(1000));
        assert_eq!(offer(3000), 750_000_000 * 9 / 10, "most he'll offer");
        assert_eq!(offer(500), 750_000_000 / 4, "least he'll offer");
    }

    #[test]
    fn what_doesnt_sell_stays_and_partly_spoils() {
        let mut kofi = Kofi::new(CONFIG);
        kofi.start_day(1050, 1050, BPS, &mut Rng::new(1));
        kofi.sold(100_000_000);
        assert_eq!(kofi.stock(), 650_000_000);
        kofi.end_day();
        assert_eq!(kofi.stock(), 455_000_000);
    }
}
