//! `--arkiv <publisher URL>`: the save rebuilt from Arkiv before the city starts.
//!
//! The publisher holds `DHANIVERSE_LOG_KEY`. Its `GET /log` reads the town's `dhaniverse.log.v1` batches from Arkiv
//! in order, decrypts each one, checks the hash chain (every `prevHash` link, every batch's SHA-256, no gaps), and
//! streams the plain lines, ending with `{"error": …}` if any of that fails. Its `x-arkiv-tip` header says the last
//! line Arkiv holds, so a stream cut short is caught too. This side checks the token travels only over loopback, that
//! the setup line is the town asked for and the lines run in order up to the tip, and writes nothing until the whole
//! answer is good. Then the save opens as always: every line is replayed and checked against the rules.

use std::fs::{File, OpenOptions};
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::path::{Path, PathBuf};
use std::time::Duration;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);
/// Each page is an Arkiv query; a slow RPC can take a while between lines.
const READ_TIMEOUT: Duration = Duration::from_secs(180);

/// The publisher path for a public Arkiv read the game asks this server for (`/arkiv/<path>`), or None if it isn't
/// one. Never `/log`: the save stays between the server and the publisher.
pub fn read_path(path: &str, query: &str) -> Option<String> {
    let rest = path.strip_prefix("/arkiv/")?;
    let plain = |s: &str, extra: &[u8]| {
        s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || extra.contains(&b))
    };
    let allowed = match rest.split_once('/') {
        Some(("profiles", name)) => !name.is_empty() && name.len() <= 192 && plain(name, b"_.-%"),
        Some(("papers", day)) => day == "latest" || (!day.is_empty() && plain(day, b"")),
        _ => [
            "boards/rush",
            "prices",
            "prices/history",
            "chests",
            "feed",
            "pool",
            "seasons",
        ]
        .contains(&rest),
    };
    if !allowed || query.len() > 128 || !plain(query, b"=&_-") {
        return None;
    }
    Some(if query.is_empty() {
        format!("/{rest}")
    } else {
        format!("/{rest}?{query}")
    })
}

/// What a restore did.
#[derive(Debug, PartialEq, Eq)]
pub struct Restored {
    pub town: String,
    /// Lines added from Arkiv (the setup line not counted).
    pub lines: u64,
    /// The last line Arkiv holds.
    pub tip: u64,
    /// The local save's last line before the restore (0 when there was none).
    pub had: u64,
}

/// `--arkiv`, with the token from `DHANIVERSE_RESTORE_TOKEN`.
pub fn restore_from_env(
    save: &Path,
    publisher: &str,
    town: Option<&str>,
) -> Result<Restored, String> {
    let token = std::env::var("DHANIVERSE_RESTORE_TOKEN")
        .ok()
        .filter(|t| !t.trim().is_empty())
        .ok_or("--arkiv needs DHANIVERSE_RESTORE_TOKEN (the publisher's restore token) in the environment")?;
    restore(save, publisher, token.trim(), town)
}

/// Brings the save up to Arkiv's tip. A missing save is rebuilt whole (`town` is then required); an existing one gets
/// the lines Arkiv has beyond it, and lines it has beyond Arkiv's tip (written, not yet landed) are kept.
pub fn restore(
    save: &Path,
    publisher: &str,
    token: &str,
    town: Option<&str>,
) -> Result<Restored, String> {
    let local = local_end(save)?;
    let town = match (&local, town) {
        (Some(l), Some(t)) if l.town != t => {
            return Err(format!(
                "{} is town {}, not {t}; point --save at a new file to restore {t}",
                save.display(),
                l.town
            ))
        }
        (Some(l), _) => l.town.clone(),
        (None, Some(t)) => t.to_string(),
        (None, None) => {
            return Err(format!(
                "{} doesn't exist, so --arkiv needs --town <id> to know which town to rebuild",
                save.display()
            ))
        }
    };
    if town.is_empty()
        || town.len() > 128
        || !town
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
    {
        return Err(format!("{town:?} is not a town id"));
    }
    let had = local.as_ref().map_or(0, |l| l.seq);
    let from = if local.is_some() { had + 1 } else { 0 };
    let (tip, body) = get_log(publisher, token, &town, from)?;
    let temp = PathBuf::from(format!("{}.arkiv-restore", save.display()));
    let result = receive(body, &temp, &town, from, tip);
    let lines = match result {
        Ok(n) => n,
        Err(problem) => {
            let _ = std::fs::remove_file(&temp);
            return Err(format!(
                "ARKIV RESTORE FAILED, nothing was written: {problem}"
            ));
        }
    };
    match &local {
        None => std::fs::rename(&temp, save).map_err(|e| format!("{}: {e}", save.display()))?,
        Some(l) => {
            if lines > 0 {
                // A half line a crash left at the end goes first, as replay would drop it anyway.
                let file = OpenOptions::new()
                    .write(true)
                    .open(save)
                    .map_err(|e| format!("{}: {e}", save.display()))?;
                file.set_len(l.good_bytes).map_err(|e| e.to_string())?;
                let mut out = OpenOptions::new()
                    .append(true)
                    .open(save)
                    .map_err(|e| e.to_string())?;
                let mut add = File::open(&temp).map_err(|e| e.to_string())?;
                std::io::copy(&mut add, &mut out)
                    .map_err(|e| format!("{}: {e}", save.display()))?;
                out.sync_data().map_err(|e| e.to_string())?;
            }
            let _ = std::fs::remove_file(&temp);
        }
    }
    Ok(Restored {
        town,
        lines,
        tip,
        had,
    })
}

struct LocalEnd {
    town: String,
    seq: u64,
    /// Bytes up to the end of the last whole line.
    good_bytes: u64,
}

fn local_end(save: &Path) -> Result<Option<LocalEnd>, String> {
    let name = save.display();
    let file = match File::open(save) {
        Ok(f) => f,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(format!("{name}: {e}")),
    };
    let mut reader = BufReader::new(file);
    let mut text = String::new();
    let read = reader
        .read_line(&mut text)
        .map_err(|e| format!("{name}: {e}"))?;
    if read == 0 || !text.ends_with('\n') {
        return Err(format!(
            "{name} has no whole setup line; move it aside to restore the town whole"
        ));
    }
    let setup: serde_json::Value =
        serde_json::from_str(&text).map_err(|e| format!("{name}: first line: {e}"))?;
    let town = setup["town_id"].as_str().unwrap_or_default().to_string();
    let mut good_bytes = read as u64;
    let mut seq = 0;
    loop {
        text.clear();
        let read = reader
            .read_line(&mut text)
            .map_err(|e| format!("{name}: {e}"))?;
        if read == 0 || !text.ends_with('\n') {
            break;
        }
        let line: serde_json::Value =
            serde_json::from_str(&text).map_err(|e| format!("{name}: after line {seq}: {e}"))?;
        seq = line["seq"]
            .as_u64()
            .ok_or_else(|| format!("{name}: a line with no seq after line {seq}"))?;
        good_bytes += read as u64;
    }
    Ok(Some(LocalEnd {
        town,
        seq,
        good_bytes,
    }))
}

/// Checks every line and writes them to `temp`. Returns how many save lines (not the setup) came.
fn receive(
    body: impl BufRead,
    temp: &Path,
    town: &str,
    from: u64,
    tip: u64,
) -> Result<u64, String> {
    let mut out = File::create(temp).map_err(|e| format!("{}: {e}", temp.display()))?;
    let mut want_setup = from == 0;
    let mut next = from.max(1);
    let mut lines = 0;
    for raw in body.split(b'\n') {
        let raw = raw.map_err(|e| format!("the answer broke off: {e}"))?;
        if raw.is_empty() {
            continue;
        }
        let text = std::str::from_utf8(&raw).map_err(|_| "a line that isn't UTF-8".to_string())?;
        let value: serde_json::Value = serde_json::from_str(text)
            .map_err(|e| format!("line {next} isn't whole JSON ({e})"))?;
        if let Some(error) = value.get("error").and_then(|e| e.as_str()) {
            return Err(format!("the publisher stopped: {error}"));
        }
        if want_setup {
            if value["town_id"].as_str() != Some(town) {
                return Err(format!("the setup line from Arkiv isn't town {town}"));
            }
            want_setup = false;
        } else {
            let seq = value["seq"].as_u64();
            if seq != Some(next) {
                return Err(format!(
                    "expected line {next}, got {}",
                    seq.map_or("no seq".to_string(), |s| s.to_string())
                ));
            }
            next += 1;
            lines += 1;
        }
        out.write_all(&raw)
            .and_then(|_| out.write_all(b"\n"))
            .map_err(|e| e.to_string())?;
    }
    if want_setup {
        return Err("no setup line came".to_string());
    }
    if from <= tip && next != tip + 1 {
        return Err(format!(
            "the answer ended at line {}, but Arkiv holds lines up to {tip}",
            next - 1
        ));
    }
    out.sync_data().map_err(|e| e.to_string())?;
    Ok(lines)
}

/// `GET /log` on the publisher, which must be on this machine: the token and the save travel in clear.
fn get_log(
    publisher: &str,
    token: &str,
    town: &str,
    from: u64,
) -> Result<(u64, BufReader<TcpStream>), String> {
    let rest = publisher.strip_prefix("http://").ok_or(
        "--arkiv takes the publisher's http:// URL on this machine, e.g. http://127.0.0.1:8787",
    )?;
    let (host, base) = rest
        .split_once('/')
        .map_or((rest, ""), |(h, p)| (h, p.trim_end_matches('/')));
    let name = host.rsplit_once(':').map_or(host, |(n, _)| n);
    if !["127.0.0.1", "localhost", "[::1]"].contains(&name) {
        return Err(format!("--arkiv only talks to a publisher on this machine (127.0.0.1, localhost or [::1]), not {name}"));
    }
    let address = if host.ends_with(']') || !host.contains(':') {
        format!("{host}:80")
    } else {
        host.to_string()
    };
    let socket = address
        .to_socket_addrs()
        .map_err(|e| e.to_string())?
        .next()
        .ok_or("no address")?;
    let mut stream = TcpStream::connect_timeout(&socket, CONNECT_TIMEOUT)
        .map_err(|e| format!("the publisher at {publisher} isn't answering: {e}"))?;
    stream
        .set_read_timeout(Some(READ_TIMEOUT))
        .map_err(|e| e.to_string())?;
    let path = if base.is_empty() {
        "/log".to_string()
    } else {
        format!("/{base}/log")
    };
    // HTTP/1.0: the answer is the body until the connection closes, never chunked.
    let head = format!(
        "GET {path}?town={town}&from={from} HTTP/1.0\r\nHost: {host}\r\nAuthorization: Bearer {token}\r\nAccept: application/x-ndjson\r\n\r\n"
    );
    stream
        .write_all(head.as_bytes())
        .map_err(|e| e.to_string())?;
    let mut reader = BufReader::new(stream);
    let mut status_line = String::new();
    reader
        .read_line(&mut status_line)
        .map_err(|e| e.to_string())?;
    let status: u16 = status_line
        .split_whitespace()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .ok_or("the publisher sent no status")?;
    let mut tip = None;
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line).map_err(|e| e.to_string())? == 0 || line.trim().is_empty() {
            break;
        }
        if let Some((k, v)) = line.split_once(':') {
            if k.trim().eq_ignore_ascii_case("x-arkiv-tip") {
                tip = v.trim().parse::<u64>().ok();
            }
        }
    }
    if status != 200 {
        let mut body = String::new();
        let _ = reader.take(2048).read_to_string(&mut body);
        return Err(format!("the publisher answered {status}: {}", body.trim()));
    }
    let tip = tip.ok_or("the publisher didn't say how far Arkiv goes (x-arkiv-tip); update it")?;
    Ok((tip, reader))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::TcpListener;
    use std::sync::mpsc;

    /// A one-shot publisher: answers with `answer` and hands back the request it got.
    fn publisher(answer: String) -> (String, mpsc::Receiver<String>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        let (tx, rx) = mpsc::channel();
        std::thread::spawn(move || {
            let (mut s, _) = listener.accept().unwrap();
            let mut buf = [0u8; 4096];
            let n = s.read(&mut buf).unwrap();
            let _ = tx.send(String::from_utf8_lossy(&buf[..n]).to_string());
            s.write_all(answer.as_bytes()).unwrap();
        });
        (url, rx)
    }

    fn ok(tip: u64, body: &str) -> String {
        format!("HTTP/1.1 200 OK\r\ncontent-type: application/x-ndjson\r\nx-arkiv-tip: {tip}\r\n\r\n{body}")
    }

    fn save(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join("arkiv-restore-unit");
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join(name);
        let _ = std::fs::remove_file(&path);
        path
    }

    const SETUP: &str = r#"{"seed":1,"town_id":"t1"}"#;

    #[test]
    fn a_whole_town_comes_back_and_the_token_goes_along() {
        let path = save("whole.jsonl");
        let (url, got) = publisher(ok(2, &format!("{SETUP}\n{{\"seq\":1}}\n{{\"seq\":2}}\n")));
        let done = restore(&path, &url, "secret-token", Some("t1")).unwrap();
        assert_eq!(
            done,
            Restored {
                town: "t1".into(),
                lines: 2,
                tip: 2,
                had: 0
            }
        );
        assert_eq!(
            std::fs::read_to_string(&path).unwrap(),
            format!("{SETUP}\n{{\"seq\":1}}\n{{\"seq\":2}}\n")
        );
        let request = got.recv().unwrap();
        assert!(request.starts_with("GET /log?town=t1&from=0 HTTP/1.0"));
        assert!(request.contains("Authorization: Bearer secret-token"));
    }

    #[test]
    fn a_save_ahead_of_arkiv_is_kept_and_one_behind_is_topped_up() {
        let path = save("partial.jsonl");
        std::fs::write(&path, format!("{SETUP}\n{{\"seq\":1}}\n{{\"se")).unwrap();
        let (url, got) = publisher(ok(3, "{\"seq\":2}\n{\"seq\":3}\n"));
        assert_eq!(restore(&path, &url, "tok", None).unwrap().lines, 2);
        assert!(got.recv().unwrap().contains("from=2 "));
        assert_eq!(
            std::fs::read_to_string(&path).unwrap(),
            format!("{SETUP}\n{{\"seq\":1}}\n{{\"seq\":2}}\n{{\"seq\":3}}\n")
        );
        // Now ahead of a tip of 2: nothing changes.
        let (url, _) = publisher(ok(2, ""));
        assert_eq!(restore(&path, &url, "tok", None).unwrap().lines, 0);
        assert_eq!(std::fs::read_to_string(&path).unwrap().lines().count(), 4);
    }

    #[test]
    fn a_broken_chain_a_gap_or_a_short_answer_writes_nothing() {
        let cases = [
            ok(2, &format!("{SETUP}\n{{\"seq\":1}}\n{{\"error\":\"broken chain: batch 2-2 does not follow the batch before it\"}}\n")),
            ok(3, &format!("{SETUP}\n{{\"seq\":1}}\n{{\"seq\":3}}\n")),
            ok(5, &format!("{SETUP}\n{{\"seq\":1}}\n")),
            ok(1, "{\"seed\":1,\"town_id\":\"other\"}\n{\"seq\":1}\n"),
            "HTTP/1.1 401 Unauthorized\r\n\r\n{\"error\":\"a bearer token is required\"}".to_string(),
        ];
        for (i, answer) in cases.into_iter().enumerate() {
            let path = save(&format!("bad-{i}.jsonl"));
            let (url, _) = publisher(answer);
            let problem = restore(&path, &url, "tok", Some("t1")).unwrap_err();
            assert!(!path.exists(), "case {i}: {problem}");
            assert!(!PathBuf::from(format!("{}.arkiv-restore", path.display())).exists());
        }
    }

    #[test]
    fn the_game_reads_public_boards_through_the_server_but_never_the_save() {
        assert_eq!(
            read_path("/arkiv/boards/rush", "day=4").as_deref(),
            Some("/boards/rush?day=4")
        );
        assert_eq!(
            read_path("/arkiv/profiles/asha", "").as_deref(),
            Some("/profiles/asha")
        );
        assert_eq!(
            read_path("/arkiv/prices/history", "days=7").as_deref(),
            Some("/prices/history?days=7")
        );
        for path in [
            "/arkiv/chests",
            "/arkiv/feed",
            "/arkiv/pool",
            "/arkiv/papers/latest",
        ] {
            assert!(read_path(path, "").is_some(), "{path}");
        }
        assert_eq!(read_path("/arkiv/log", "town=t1&from=0"), None);
        assert_eq!(read_path("/arkiv/profiles/../log", ""), None);
        assert_eq!(read_path("/arkiv/feed", "day=1%0d%0aX:1"), None);
        assert_eq!(read_path("/arkiv/swarm/campaign-bundle", ""), None);
    }

    #[test]
    fn the_token_never_leaves_this_machine() {
        let problem = restore(
            &save("remote.jsonl"),
            "http://203.0.113.9:8787",
            "tok",
            Some("t1"),
        )
        .unwrap_err();
        assert!(problem.contains("this machine"), "{problem}");
        assert!(restore(
            &save("https.jsonl"),
            "https://127.0.0.1:8787",
            "tok",
            Some("t1")
        )
        .is_err());
        assert!(
            restore(&save("notown.jsonl"), "http://127.0.0.1:1", "tok", None)
                .unwrap_err()
                .contains("--town")
        );
    }
}
