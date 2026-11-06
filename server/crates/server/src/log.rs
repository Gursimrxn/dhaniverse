//! The save: one append-only file of JSON lines. The first line holds what the city started from (seed, rules, quest
//! book and chain mode), and each later line is an input with the events it caused, intents for the chain included. Loading replays the inputs through the rules and checks
//! they still cause the same events, so a save can't quietly drift from the rules that wrote it.

use crate::world::{Input, Setup, World};
use rules::Event;
use serde::{Deserialize, Serialize};
use std::fs::{File, OpenOptions};
use std::io::{BufRead, BufReader, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};

/// A new save's town id: 8 random bytes, as hex.
const TOWN_ID_BYTES: usize = 8;

#[derive(Serialize, Deserialize)]
struct Line {
    seq: u64,
    input: Input,
    events: Vec<Event>,
}

#[derive(Debug)]
pub struct Log {
    file: File,
    seq: u64,
}

impl Log {
    /// Opens a save, or starts a new offline one from these rules. An existing save keeps the rules it started with.
    pub fn open(path: &Path, rules_toml: &str, seed: u64) -> Result<(Log, World), String> {
        Self::open_city(path, &Setup::offline(rules_toml, seed))
    }

    /// Opens a save, or starts a new one from this setup. An existing save keeps the setup it started with, except
    /// that it must settle money where it always did.
    pub fn open_city(path: &Path, setup: &Setup) -> Result<(Log, World), String> {
        if path.exists() {
            let (log, world) = Self::replay(path)?;
            if world.chain() != setup.chain {
                return Err(format!(
                    "{}: this save is a {} city, and the server was asked for {}. Point --save at a new file.",
                    path.display(),
                    world.chain().name(),
                    setup.chain.name()
                ));
            }
            return Ok((log, world));
        }
        let mut setup = setup.clone();
        if setup.town_id.is_empty() {
            setup.town_id = crate::ledger::hex(&crate::ledger::random_bytes(TOWN_ID_BYTES)?);
        }
        let world = World::start(&setup)?;
        let mut file = File::create(path).map_err(|e| format!("{}: {e}", path.display()))?;
        let text = serde_json::to_string(&setup).map_err(|e| e.to_string())?;
        writeln!(file, "{text}").map_err(|e| format!("{}: {e}", path.display()))?;
        Ok((Log { file, seq: 0 }, world))
    }

    /// Like `open`, but a save that won't replay is moved aside, never deleted, and a new city starts in its place.
    /// Returns where the old save went. For a shipped game, where a stopped server would lock the player out.
    /// `timestamp` names the moved file: the clock stays outside this, so a test can choose it.
    pub fn open_or_start_new(
        path: &Path,
        rules_toml: &str,
        seed: u64,
        timestamp: u64,
    ) -> Result<(Log, World, Option<PathBuf>), String> {
        Self::open_city_or_start_new(path, &Setup::offline(rules_toml, seed), timestamp)
    }

    /// `open_or_start_new` with a whole setup.
    pub fn open_city_or_start_new(
        path: &Path,
        setup: &Setup,
        timestamp: u64,
    ) -> Result<(Log, World, Option<PathBuf>), String> {
        match Self::open_city(path, setup) {
            Ok((log, world)) => Ok((log, world, None)),
            Err(_) if path.exists() => {
                let aside = unused_name(path, timestamp);
                std::fs::rename(path, &aside)
                    .map_err(|e| format!("{}: can't move it aside: {e}", path.display()))?;
                let (log, world) = Self::open_city(path, setup)?;
                Ok((log, world, Some(aside)))
            }
            Err(problem) => Err(problem),
        }
    }

    /// Adds one line. If this fails the world has moved past its save, so the caller must stop.
    pub fn append(&mut self, input: &Input, events: &[Event]) -> Result<u64, String> {
        self.seq += 1;
        let line = LineRef {
            seq: self.seq,
            input,
            events,
        };
        let text = serde_json::to_string(&line).map_err(|e| e.to_string())?;
        writeln!(self.file, "{text}").map_err(|e| e.to_string())?;
        Ok(self.seq)
    }

    /// Pushes the file to the disk. Slower than an append, so it's done on the clock and not per line.
    pub fn sync(&self) -> Result<(), String> {
        self.file.sync_data().map_err(|e| e.to_string())
    }

    pub fn seq(&self) -> u64 {
        self.seq
    }

    fn replay(path: &Path) -> Result<(Log, World), String> {
        let name = path.display();
        let file = File::open(path).map_err(|e| format!("{name}: {e}"))?;
        let mut reader = BufReader::new(file);
        let mut text = String::new();
        reader
            .read_line(&mut text)
            .map_err(|e| format!("{name}: {e}"))?;
        let setup: Setup =
            serde_json::from_str(&text).map_err(|e| format!("{name}: first line: {e}"))?;
        let mut world = World::start(&setup)?;
        let mut good_bytes = text.len() as u64;
        let mut seq = 0;
        loop {
            text.clear();
            let read = reader
                .read_line(&mut text)
                .map_err(|e| format!("{name}: {e}"))?;
            if read == 0 {
                break;
            }
            // A crash can leave half a line at the very end. Nothing was built on it, so it's dropped.
            if !text.ends_with('\n') {
                break;
            }
            let line: Line =
                serde_json::from_str(&text).map_err(|e| format!("{name}: line {seq}: {e}"))?;
            let events = world
                .step(line.input)
                .map_err(|r| format!("{name}: line {}: refused on replay: {r:?}", line.seq))?;
            if events != line.events {
                return Err(format!(
                    "{name}: line {} replays differently, so this save was written by other rules. \
                     Point --save at a new file to start a new city.",
                    line.seq
                ));
            }
            seq = line.seq;
            good_bytes += read as u64;
        }
        let mut file = OpenOptions::new()
            .write(true)
            .open(path)
            .map_err(|e| format!("{name}: {e}"))?;
        file.set_len(good_bytes)
            .map_err(|e| format!("{name}: {e}"))?;
        file.seek(SeekFrom::End(0))
            .map_err(|e| format!("{name}: {e}"))?;
        Ok((Log { file, seq }, world))
    }
}

/// `city.jsonl` becomes `city.jsonl.old-<timestamp>`. Two moves in the same second get a number, so nothing is overwritten.
fn unused_name(path: &Path, timestamp: u64) -> PathBuf {
    let plain = PathBuf::from(format!("{}.old-{timestamp}", path.display()));
    if !plain.exists() {
        return plain;
    }
    (1..)
        .map(|n| PathBuf::from(format!("{}-{n}", plain.display())))
        .find(|candidate| !candidate.exists())
        .expect("some number is free")
}

#[derive(Serialize)]
struct LineRef<'a> {
    seq: u64,
    input: &'a Input,
    events: &'a [Event],
}
