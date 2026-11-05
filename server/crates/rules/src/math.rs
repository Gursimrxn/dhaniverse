//! The little integer maths the rules need.

/// The smallest r with r² ≥ n.
pub fn ceil_sqrt(n: u128) -> u128 {
    let root = n.isqrt();
    root + u128::from(root * root < n)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ceil_sqrt_rounds_up() {
        assert_eq!(ceil_sqrt(16), 4);
        assert_eq!(ceil_sqrt(17), 5);
        assert_eq!(ceil_sqrt(0), 0);
    }
}
