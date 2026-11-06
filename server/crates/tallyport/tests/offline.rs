//! The same binary still runs an offline town: no chain, no keys, the in-process ledger.

use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};
use std::time::Duration;
use tungstenite::stream::MaybeTlsStream;
use tungstenite::{connect, Message};

#[test]
fn offline_is_the_default_and_needs_no_chain() {
    let dir = std::env::temp_dir().join(format!("tallyport-offline-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let rules = concat!(env!("CARGO_MANIFEST_DIR"), "/../../rules.toml");
    let mut child = Command::new(env!("CARGO_BIN_EXE_tallyport"))
        .args([
            "--addr",
            "127.0.0.1:0",
            "--debug",
            "--heartbeat-ms",
            "0",
            "--rules",
            rules,
        ])
        .arg("--save")
        .arg(dir.join("town.jsonl"))
        .env_remove("CHAIN_MODE")
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut reader = BufReader::new(child.stdout.take().unwrap());
    let addr = loop {
        let mut line = String::new();
        assert!(reader.read_line(&mut line).unwrap() > 0, "exited early");
        if let Some(a) = line.trim().strip_prefix("listening on ") {
            break a.to_string();
        }
    };
    let (mut ws, _) = connect(format!("ws://{addr}")).unwrap();
    if let MaybeTlsStream::Plain(s) = ws.get_ref() {
        s.set_read_timeout(Some(Duration::from_secs(20))).unwrap();
    }
    let hello =
        r#"{"type":"hello","protocol":3,"player":"sam","secret":"a-test-secret-of-sam-0123"}"#;
    ws.send(Message::text(hello)).unwrap();
    let snapshot = loop {
        if let Message::Text(t) = ws.read().unwrap() {
            let v: serde_json::Value = serde_json::from_str(t.as_str()).unwrap();
            if v["type"] == "snapshot" {
                break v;
            }
        }
    };
    assert_eq!(snapshot["city"]["chain"], "offline");
    assert!(snapshot["you"]["wallet"]
        .as_str()
        .unwrap()
        .starts_with("0x"));
    let _ = child.kill();
    let _ = child.wait();
    let _ = std::fs::remove_dir_all(&dir);
}
