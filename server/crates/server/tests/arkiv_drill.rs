//! The restore drill: write a save, publish it to a fake Arkiv node (the real publisher code, encrypted and
//! hash-chained), wipe it, restore it with `--arkiv`, and get the identical world back. And a broken chain on Arkiv
//! stops the server before it writes anything.
//!
//! The publisher half is `services/publisher/scripts/drill.ts --fake`, so this needs Node 24 on the PATH; without it
//! the test says so and passes.

use rules::{Command as Cmd, Role};
use server::log::Log;
use server::world::{Input, World};
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};

const RULES_FILE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../rules.toml");
const DRILL: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../../services/publisher/scripts/drill.ts"
);
const KEY: &str = "5d1f00c0ffee5d1f00c0ffee5d1f00c0ffee5d1f00c0ffee5d1f00c0ffee5d1f";
const TOKEN: &str = "drill-token-drill-token-drill-token-0001";
const MINUTE: u64 = 60_000;

fn save_path(name: &str) -> PathBuf {
    let path = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join(format!("drill-{name}.jsonl"));
    let _ = std::fs::remove_file(&path);
    path
}

fn take(world: &mut World, log: &mut Log, input: Input) {
    if let Ok(events) = world.step(input.clone()) {
        log.append(&input, &events).unwrap();
    }
}

/// A day and a half of a small town: a player arrives, runs the Rush, opens a chest, and the market trades.
fn play(path: &Path) -> (World, u64) {
    let rules = std::fs::read_to_string(RULES_FILE).unwrap();
    let (mut log, mut world) = Log::open(path, &rules, 7).unwrap();
    let sam = || "sam".to_string();
    let player = |command| Input::Command {
        by: Role::Player,
        command,
    };
    take(&mut world, &mut log, Input::Connect { player: sam() });
    take(
        &mut world,
        &mut log,
        player(Cmd::StartRush { account: sam() }),
    );
    for order in 0..4 {
        take(
            &mut world,
            &mut log,
            player(Cmd::ServeOrder {
                account: sam(),
                reference: format!("o{order}"),
            }),
        );
    }
    take(
        &mut world,
        &mut log,
        player(Cmd::EndRush { account: sam() }),
    );
    take(
        &mut world,
        &mut log,
        player(Cmd::OpenChest {
            account: sam(),
            weekly: false,
        }),
    );
    take(&mut world, &mut log, Input::Advance { ms: 150 * MINUTE });
    log.sync().unwrap();
    (world, log.seq())
}

/// The publisher with a fake Arkiv node, holding this save. Killed when dropped.
struct Publisher {
    child: Child,
    url: String,
    town: String,
    tip: u64,
}

impl Drop for Publisher {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn publish(save: &Path, extra: &[&str]) -> Option<Publisher> {
    if Command::new("node").arg("--version").output().is_err() {
        eprintln!("SKIPPED: the restore drill needs Node 24 on the PATH for the publisher half");
        return None;
    }
    let mut child = Command::new("node")
        .arg(DRILL)
        .args(["--fake", "--save"])
        .arg(save)
        .args(extra)
        .env("DHANIVERSE_LOG_KEY", KEY)
        .env("DHANIVERSE_RESTORE_TOKEN", TOKEN)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .expect("node starts");
    let mut line = String::new();
    BufReader::new(child.stdout.take().unwrap())
        .read_line(&mut line)
        .unwrap();
    let parts: Vec<&str> = line.split_whitespace().collect();
    assert_eq!(parts.first(), Some(&"READY"), "the publisher said: {line}");
    Some(Publisher {
        url: format!("http://127.0.0.1:{}", parts[1]),
        town: parts[2].to_string(),
        tip: parts[3].parse().unwrap(),
        child,
    })
}

#[test]
fn a_wiped_save_comes_back_from_arkiv_identical() {
    let path = save_path("whole");
    let (world, seq) = play(&path);
    let original = std::fs::read(&path).unwrap();
    let Some(publisher) = publish(&path, &[]) else {
        return;
    };
    assert_eq!(publisher.tip, seq, "every line is on Arkiv");

    std::fs::remove_file(&path).unwrap();
    let done = server::arkiv::restore(&path, &publisher.url, TOKEN, Some(&publisher.town)).unwrap();
    assert_eq!((done.lines, done.tip, done.had), (seq, seq, 0));
    assert_eq!(std::fs::read(&path).unwrap(), original, "byte for byte");

    // Replayed through the rules, as the server opens it: the same world.
    let (log, rebuilt) = Log::open(&path, "ignored: a save keeps its rules", 999).unwrap();
    assert_eq!(rebuilt, world);
    assert_eq!(log.seq(), seq);
    drop(log);

    // A save that lost its last lines gets just those back.
    let keep = original
        .iter()
        .enumerate()
        .filter(|(_, b)| **b == b'\n')
        .nth(3)
        .unwrap()
        .0
        + 1;
    std::fs::write(&path, &original[..keep]).unwrap();
    let done = server::arkiv::restore(&path, &publisher.url, TOKEN, None).unwrap();
    assert_eq!((done.had, done.lines), (3, seq - 3));
    assert_eq!(std::fs::read(&path).unwrap(), original);
}

#[test]
fn the_server_starts_from_arkiv_alone_with_the_flag() {
    let path = save_path("flag");
    let (_, seq) = play(&path);
    let original = std::fs::read(&path).unwrap();
    let Some(publisher) = publish(&path, &[]) else {
        return;
    };
    std::fs::remove_file(&path).unwrap();

    let mut server = Command::new(env!("CARGO_BIN_EXE_server"))
        .args([
            "--addr",
            "127.0.0.1:0",
            "--heartbeat-ms",
            "0",
            "--rules",
            RULES_FILE,
            "--arkiv",
            &publisher.url,
            "--town",
            &publisher.town,
        ])
        .arg("--save")
        .arg(&path)
        .env("DHANIVERSE_RESTORE_TOKEN", TOKEN)
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut out = BufReader::new(server.stdout.take().unwrap());
    let mut said = Vec::new();
    while !said
        .last()
        .is_some_and(|l: &String| l.starts_with("listening on"))
    {
        let mut line = String::new();
        assert!(
            out.read_line(&mut line).unwrap() > 0,
            "the server stopped after: {said:?}"
        );
        said.push(line);
    }
    let _ = server.kill();
    let _ = server.wait();
    assert!(
        said.iter().any(|l| l.contains(&format!(
            "restored from Arkiv: town {}, {seq} new line(s)",
            publisher.town
        ))),
        "{said:?}"
    );
    assert!(std::fs::read(&path).unwrap().starts_with(&original));
}

#[test]
fn a_broken_chain_on_arkiv_stops_the_server_and_writes_nothing() {
    let path = save_path("broken");
    play(&path);
    let Some(publisher) = publish(&path, &["--break"]) else {
        return;
    };
    std::fs::remove_file(&path).unwrap();

    let problem =
        server::arkiv::restore(&path, &publisher.url, TOKEN, Some(&publisher.town)).unwrap_err();
    assert!(
        problem.contains("ARKIV RESTORE FAILED") && problem.contains("broken chain"),
        "{problem}"
    );
    assert!(!path.exists());

    let run = Command::new(env!("CARGO_BIN_EXE_server"))
        .args([
            "--addr",
            "127.0.0.1:0",
            "--heartbeat-ms",
            "0",
            "--rules",
            RULES_FILE,
            "--arkiv",
            &publisher.url,
            "--town",
            &publisher.town,
        ])
        .arg("--save")
        .arg(&path)
        .env("DHANIVERSE_RESTORE_TOKEN", TOKEN)
        .output()
        .unwrap();
    assert!(!run.status.success());
    assert!(String::from_utf8_lossy(&run.stderr).contains("broken chain"));
    assert!(!path.exists(), "no new city was started in its place");
}
