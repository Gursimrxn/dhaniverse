//! How much one address may ask for, so a hosted town can't be flooded or have its names all taken at once.

use std::collections::HashMap;
use std::time::{Duration, Instant};

const MINUTE: Duration = Duration::from_secs(60);
const HOUR: Duration = Duration::from_secs(3600);
/// A whole hotspot shares one address, so these leave room for a table of laptops.
pub const OPEN_CONNECTIONS_PER_ADDRESS: usize = 32;
const FORGET_ABOVE: usize = 10_000;

/// So many per window, for each address. The count restarts when the window ends.
#[derive(Debug)]
pub struct RateLimit {
    max: u32,
    window: Duration,
    seen: HashMap<String, (Instant, u32)>,
}

impl RateLimit {
    pub fn new(max: u32, window: Duration) -> Self {
        RateLimit {
            max,
            window,
            seen: HashMap::new(),
        }
    }

    /// Counts one more, and says whether it's allowed. `now` comes in so a test can choose it.
    pub fn allow(&mut self, address: &str, now: Instant) -> bool {
        if self.seen.len() > FORGET_ABOVE {
            let window = self.window;
            self.seen
                .retain(|_, (start, _)| now.duration_since(*start) < window);
        }
        let entry = self.seen.entry(address.to_string()).or_insert((now, 0));
        if now.duration_since(entry.0) >= self.window {
            *entry = (now, 0);
        }
        entry.1 = entry.1.saturating_add(1);
        entry.1 <= self.max
    }
}

#[derive(Debug)]
pub struct Limits {
    pub connections: RateLimit,
    pub name_tries: RateLimit,
    pub new_names: RateLimit,
    pub mentor_questions: RateLimit,
    /// Per player. Every command goes in the save, so this keeps one client from filling the disk.
    pub commands: RateLimit,
}

impl Default for Limits {
    fn default() -> Self {
        Limits {
            connections: RateLimit::new(120, MINUTE),
            name_tries: RateLimit::new(60, MINUTE),
            new_names: RateLimit::new(10, HOUR),
            mentor_questions: RateLimit::new(30, MINUTE),
            commands: RateLimit::new(300, MINUTE),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn it_stops_at_the_limit_for_that_address_only_and_restarts_after_the_window() {
        let start = Instant::now();
        let mut limit = RateLimit::new(2, MINUTE);
        assert!(limit.allow("a", start));
        assert!(limit.allow("a", start));
        assert!(!limit.allow("a", start));
        assert!(limit.allow("b", start), "another address has its own count");
        assert!(!limit.allow("a", start + MINUTE / 2));
        assert!(limit.allow("a", start + MINUTE));
    }
}
