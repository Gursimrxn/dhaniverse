//! Chance, without a random number generator: a roll is a hash of the city's seed and what's being rolled for, so the
//! same world always rolls the same, and a replay matches. A player can't reroll, because the inputs are fixed.

const BPS: u64 = 10_000;

/// SplitMix64's finaliser.
fn mix(mut z: u64) -> u64 {
    z = z.wrapping_add(0x9E37_79B9_7F4A_7C15);
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^ (z >> 31)
}

/// A number from the seed, a word saying what it's for, a name and a count.
pub fn roll(seed: u64, what: &str, who: &str, n: u64) -> u64 {
    let mut h = mix(seed ^ 0x5441_4C4C_5950_4F52);
    for byte in what.bytes().chain([0]).chain(who.bytes()) {
        h = mix(h ^ u64::from(byte));
    }
    mix(h ^ n)
}

/// True with a chance of `bps` in 10,000.
pub fn chance(seed: u64, what: &str, who: &str, n: u64, bps: u32) -> bool {
    roll(seed, what, who, n) % BPS < u64::from(bps)
}

/// A whole number below `n`, or 0 when `n` is 0.
pub fn below(seed: u64, what: &str, who: &str, k: u64, n: u64) -> u64 {
    if n == 0 {
        return 0;
    }
    roll(seed, what, who, k) % n
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_same_inputs_always_roll_the_same_and_others_differ() {
        assert_eq!(roll(1, "chest", "sam", 3), roll(1, "chest", "sam", 3));
        assert_ne!(roll(1, "chest", "sam", 3), roll(1, "chest", "sam", 4));
        assert_ne!(roll(1, "chest", "sam", 3), roll(2, "chest", "sam", 3));
        assert_ne!(roll(1, "chest", "sa", 3), roll(1, "ches", "tsa", 3));
    }

    #[test]
    fn a_chance_comes_up_about_as_often_as_it_says() {
        let hits = (0..10_000)
            .filter(|n| chance(7, "x", "y", *n, 2500))
            .count();
        assert!((2200..2800).contains(&hits), "{hits}");
    }
}
