//! SplitMix64: a seedable generator in a few lines, so a seed always replays the same city.

use crate::BPS;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Rng(u64);

impl Rng {
    pub fn new(seed: u64) -> Self {
        Rng(seed)
    }

    fn next_u64(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    /// A whole number from 0 up to `n`, not including it.
    pub fn below(&mut self, n: u64) -> u64 {
        self.next_u64() % n
    }

    /// True with a chance of `bps` in 10,000.
    pub fn chance(&mut self, bps: u64) -> bool {
        self.below(BPS) < bps
    }

    /// A factor in basis points, 10,000 ± `spread`.
    pub fn around_one(&mut self, spread: u64) -> u64 {
        BPS - spread + self.below(2 * spread + 1)
    }
}
