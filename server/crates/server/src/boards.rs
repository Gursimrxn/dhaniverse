//! The season's rankings. Scores stay in here: what leaves is the order, a name and a title.

use crate::seasons::Season;
use rules::{is_person, State};
use serde_json::{json, Value};
use std::collections::BTreeMap;

/// The season's boards. Market Rush's best run is the only one for now.
pub const BOARDS: [&str; 1] = ["rush"];
const TOP: usize = 10;
const NEIGHBOURS: usize = 2;

/// Each board, best first. A board only holds people who have a score on it this season.
pub fn standings(state: &State, season: &Season) -> BTreeMap<&'static str, Vec<String>> {
    let mut scored: Vec<(u32, &String)> = state
        .life
        .players()
        .map(|(name, _)| name)
        .filter(|name| is_person(name))
        .map(|name| (season.best_run(name), name))
        .filter(|(best, _)| *best > 0)
        .collect();
    // Best first, and names break ties so the order never depends on a hash.
    scored.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.cmp(b.1)));
    let rush = scored.into_iter().map(|(_, name)| name.clone()).collect();
    BTreeMap::from([("rush", rush)])
}

/// `city.boards`: rank, name and title, and nothing else ever.
pub fn to_json(state: &State, boards: &BTreeMap<&'static str, Vec<String>>) -> Value {
    let mut out = serde_json::Map::new();
    for (board, names) in boards {
        let top: Vec<Value> = names
            .iter()
            .take(TOP)
            .enumerate()
            .map(|(i, name)| json!({"rank": i + 1, "name": name, "title": state.title(name)}))
            .collect();
        out.insert((*board).to_string(), Value::Array(top));
    }
    Value::Object(out)
}

/// Your best board, by rank.
pub fn best_board(
    boards: &BTreeMap<&'static str, Vec<String>>,
    name: &str,
) -> Option<&'static str> {
    BOARDS
        .iter()
        .filter_map(|board| {
            let rank = boards.get(board)?.iter().position(|n| n == name)?;
            Some((rank, *board))
        })
        .min_by_key(|(rank, _)| *rank)
        .map(|(_, board)| board)
}

/// `you.neighbours`: you and a couple of people either side, on each board. Rank, name and title, as ever.
pub fn neighbours_json(
    state: &State,
    boards: &BTreeMap<&'static str, Vec<String>>,
    name: &str,
) -> Value {
    let mut out = serde_json::Map::new();
    for (board, names) in boards {
        let rows: Vec<Value> = match names.iter().position(|n| n == name) {
            Some(at) => {
                let from = at.saturating_sub(NEIGHBOURS);
                let to = (at + NEIGHBOURS + 1).min(names.len());
                (from..to)
                    .map(|i| json!({"rank": i + 1, "name": names[i], "title": state.title(&names[i])}))
                    .collect()
            }
            None => Vec::new(),
        };
        out.insert((*board).to_string(), Value::Array(rows));
    }
    Value::Object(out)
}

/// `you.ranks`: your own place on each board, or null.
pub fn ranks_json(boards: &BTreeMap<&'static str, Vec<String>>, name: &str) -> Value {
    let mut out = serde_json::Map::new();
    for (board, names) in boards {
        let rank = names.iter().position(|n| n == name).map(|i| i + 1);
        out.insert((*board).to_string(), json!(rank));
    }
    Value::Object(out)
}
