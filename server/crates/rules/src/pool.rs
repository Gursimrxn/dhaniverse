//! A no-fee, full-range constant-product pool, like FoodHook's Uniswap v4 pool. Uniswap keeps a liquidity and a
//! sqrt price; this keeps the same two facts as `k` (liquidity²) and the stock of the traded thing. The USDC side
//! is always k ÷ stock, so rounding never builds up, and it rounds as Uniswap does: up on what the pool takes,
//! down on what it pays.
//!
//! Prices are USDC base units per whole unit, and stock is in base units (1 unit = 1,000,000), as FOOD is on chain.

use crate::math::ceil_sqrt;
use crate::Usdc;

pub const UNIT: u128 = 1_000_000;
const BPS: u128 = 10_000;

/// How far a price may go: `band_bps` either way from the day's open, and always within floor and ceiling.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Limits {
    pub band_bps: u32,
    pub floor: Usdc,
    pub ceiling: Usdc,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Pool {
    k: u128,
    stock: u64,
}

impl Pool {
    pub fn new(stock: u64, price: Usdc) -> Self {
        let stock_wide = u128::from(stock);
        Pool {
            k: stock_wide * stock_wide * u128::from(price) / UNIT,
            stock,
        }
    }

    pub fn stock(&self) -> u64 {
        self.stock
    }

    /// The live price, rounded down, as FoodHook.centsPerFood does.
    pub fn price(&self) -> Usdc {
        self.price_at(self.stock)
    }

    pub fn price_at(&self, stock: u64) -> Usdc {
        let stock = u128::from(stock);
        (self.k * UNIT / (stock * stock)) as Usdc
    }

    /// The least and most stock today's limits allow, given the stock at the day's open. Buying lowers stock and
    /// raises the price, so the least stock is the dearest price. Rounded inward, so a limit is never crossed.
    pub fn bounds(&self, open_stock: u64, limits: Limits) -> (u64, u64) {
        let open = u128::from(open_stock);
        let open_sq = open * open;
        let band = u128::from(limits.band_bps);
        let dearest_band = ceil_sqrt((open_sq * BPS).div_ceil(BPS + band));
        let dearest_ceiling = ceil_sqrt((self.k * UNIT).div_ceil(u128::from(limits.ceiling)));
        let cheapest_band = (open_sq * BPS / (BPS - band)).isqrt();
        let cheapest_floor = (self.k * UNIT / u128::from(limits.floor)).isqrt();
        (
            dearest_band.max(dearest_ceiling) as u64,
            cheapest_band.min(cheapest_floor) as u64,
        )
    }

    /// Buys up to `wanted`, stopping at `least_stock`, which must be below the live stock. Returns (bought, paid).
    pub fn buy(&mut self, wanted: u64, least_stock: u64) -> (u64, Usdc) {
        let after = self.stock.saturating_sub(wanted).max(least_stock);
        let bought = self.stock - after;
        let paid = (self.k * u128::from(bought)).div_ceil(self.stock_product(after));
        self.stock = after;
        (bought, paid as Usdc)
    }

    /// Sells up to `offered`, stopping at `most_stock`, which must be above the live stock. Returns (sold, got).
    pub fn sell(&mut self, offered: u64, most_stock: u64) -> (u64, Usdc) {
        let after = (self.stock + offered).min(most_stock);
        let sold = after - self.stock;
        let got = self.k * u128::from(sold) / self.stock_product(after);
        self.stock = after;
        (sold, got as Usdc)
    }

    fn stock_product(&self, after: u64) -> u128 {
        u128::from(self.stock) * u128::from(after)
    }
}
