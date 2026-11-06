//! The read-only view for the Town Terminal, the website and the publisher. The city thread rebuilds it every few
//! seconds and hands over finished text, so however many people ask, it costs the game nothing and can't reach
//! anything but that text.

use crate::limits::RateLimit;
use std::sync::{Mutex, RwLock};
use std::time::{Duration, Instant};

pub const REBUILD_EVERY: Duration = Duration::from_secs(5);
/// A city that hasn't rebuilt this in so long has stopped.
const STALLED_AFTER: Duration = Duration::from_secs(30);
const REQUESTS_PER_MINUTE: u32 = 120;

#[derive(Debug)]
struct Texts {
    city: String,
    health: String,
    built: Instant,
}

#[derive(Debug)]
pub struct PublicView {
    texts: RwLock<Option<Texts>>,
    limit: Mutex<RateLimit>,
}

impl Default for PublicView {
    fn default() -> Self {
        PublicView {
            texts: RwLock::new(None),
            limit: Mutex::new(RateLimit::new(REQUESTS_PER_MINUTE, Duration::from_secs(60))),
        }
    }
}

impl PublicView {
    pub fn publish(&self, city: String, health: String) {
        if let Ok(mut texts) = self.texts.write() {
            *texts = Some(Texts {
                city,
                health,
                built: Instant::now(),
            });
        }
    }

    /// Counts one more request from this address, and says whether it's allowed.
    pub fn allow(&self, address: &str) -> bool {
        self.limit
            .lock()
            .is_ok_and(|mut limit| limit.allow(address, Instant::now()))
    }

    /// The city's public JSON, once it's been built.
    pub fn city(&self) -> Option<String> {
        self.texts.read().ok()?.as_ref().map(|t| t.city.clone())
    }

    /// The health JSON, unless the city has stopped rebuilding it.
    pub fn health(&self) -> Option<String> {
        let texts = self.texts.read().ok()?;
        texts
            .as_ref()
            .filter(|t| t.built.elapsed() < STALLED_AFTER)
            .map(|t| t.health.clone())
    }
}
