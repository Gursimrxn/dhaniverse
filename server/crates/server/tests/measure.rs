//! Not a check but a measurement, for DEPLOY.md: how much one client receives with people walking around.
//!
//!     cargo test -p server --test measure -- --ignored --nocapture

mod common;

use common::*;
use serde_json::json;
use std::time::{Duration, Instant};
use tungstenite::Message;

const PLAYERS: usize = 10;
const SECONDS: u64 = 20;

#[test]
#[ignore = "takes a while, and only prints a number"]
fn what_one_client_receives_with_people_walking_about() {
    let save = fresh_save("measure");
    let server = Server::start(&save, &[]);
    let mut clients: Vec<Client> = (0..PLAYERS)
        .map(|n| {
            let mut client = Client::connect(&server.addr);
            client.hello(&format!("player{n}"));
            client
        })
        .collect();
    for client in &clients {
        if let tungstenite::stream::MaybeTlsStream::Plain(stream) = client.socket.get_ref() {
            stream
                .set_read_timeout(Some(Duration::from_millis(5)))
                .unwrap();
        }
    }
    let start = Instant::now();
    let (mut bytes, mut messages, mut x) = (0usize, 0usize, 0.0);
    while start.elapsed() < Duration::from_secs(SECONDS) {
        x += 0.1;
        for client in &mut clients {
            client.send(
                json!({"type": "move", "x": x, "y": 0.0, "z": 1.5, "yaw": 0.5, "anim": "walk"}),
            );
        }
        for (n, client) in clients.iter_mut().enumerate() {
            while let Ok(message) = client.socket.read() {
                if let (0, Message::Text(text)) = (n, &message) {
                    bytes += text.len();
                    messages += 1;
                }
            }
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    let per_second = bytes as u64 / SECONDS;
    println!("{PLAYERS} players and 20 residents: one client receives {per_second} bytes a second, in {} messages a second", messages as u64 / SECONDS);
    drop(server);
    let _ = std::fs::remove_file(&save);
}
