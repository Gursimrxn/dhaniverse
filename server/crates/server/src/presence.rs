//! Where everyone is standing. Not game state: it's held in memory only, never logged, and starts empty after a restart.

use agents::Whereabouts;
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::time::Duration;

pub const SEND_EVERY: Duration = Duration::from_millis(200);
pub const MAX_ANIM: usize = 24;

#[derive(Clone, Debug, PartialEq)]
pub struct Position {
    pub x: f64,
    pub y: f64,
    pub z: f64,
    pub yaw: f64,
    pub anim: String,
}

#[derive(Debug, Default)]
pub struct Presence {
    players: BTreeMap<String, Position>,
    changed: bool,
    residents: Vec<Whereabouts>,
}

impl Presence {
    pub fn moved(&mut self, name: &str, position: Position) {
        self.players.insert(name.to_string(), position);
        self.changed = true;
    }

    /// Takes someone off the list. True if they were on it, so others should be told.
    pub fn left(&mut self, name: &str) -> bool {
        let was_there = self.players.remove(name).is_some();
        self.changed |= was_there;
        was_there
    }

    /// Something a client should see has changed, such as a title or someone new to send the list to.
    pub fn touch(&mut self) {
        self.changed = true;
    }

    /// The message to send, if there's anything new. Sending it clears the flag.
    pub fn take_message(
        &mut self,
        residents: Vec<Whereabouts>,
        title: impl Fn(&str) -> String,
    ) -> Option<Value> {
        let moved = std::mem::take(&mut self.changed);
        if !moved && residents == self.residents {
            return None;
        }
        self.residents = residents;
        let mut players: Vec<Value> = self
            .players
            .iter()
            .map(|(name, p)| {
                json!({
                    "name": name,
                    "x": p.x,
                    "y": p.y,
                    "z": p.z,
                    "yaw": p.yaw,
                    "anim": p.anim,
                    "title": title(name),
                })
            })
            .collect();
        players.extend(self.residents.iter().map(|r| {
            let anim = if r.walking { "walk" } else { "idle" };
            json!({
                "name": r.name,
                "resident": true,
                "from": r.from,
                "place": r.place,
                "anim": anim,
                "title": "Resident",
            })
        }));
        Some(json!({"type": "presence", "players": players}))
    }
}
