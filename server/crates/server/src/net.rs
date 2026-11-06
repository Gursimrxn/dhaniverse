//! The sockets. One thread per connection, moving text between its WebSocket and the city thread. Everything the game
//! decides happens on the city thread; these only carry messages.

use crate::http::{self, HttpDesk};
use crate::ledger::HumanId;
use std::io::{ErrorKind, Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};
use tungstenite::handshake::server::{Request, Response};
use tungstenite::protocol::WebSocketConfig;
use tungstenite::{accept_hdr_with_config, Error, Message, WebSocket};

pub type ConnId = u64;

/// How long a connection thread waits for the client before checking for outgoing messages.
const POLL: Duration = Duration::from_millis(10);
/// A client that won't take its messages for this long is dropped, so it can't hold anyone else up.
const WRITE_TIMEOUT: Duration = Duration::from_secs(5);
/// No message in the protocol comes near this. It stops a bad client filling the server's memory.
const MAX_MESSAGE_BYTES: usize = 64 * 1024;
/// A connection that won't finish opening doesn't get to hold a thread.
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(5);
/// No request worth answering has a bigger head.
const MAX_HTTP_HEAD: usize = 8192;
/// A body slower than this to arrive isn't worth waiting for.
const BODY_TIMEOUT: Duration = Duration::from_secs(20);

pub enum ToCity {
    Opened {
        conn: ConnId,
        address: String,
        out: Sender<ToClient>,
    },
    Text {
        conn: ConnId,
        text: String,
    },
    Closed {
        conn: ConnId,
    },
    /// World ID said this player is a person. The answer is their ENS name if they have one, or the refusal's name.
    Verified {
        player: String,
        human_id: HumanId,
        reply: Sender<Result<Option<String>, String>>,
    },
}

pub enum ToClient {
    Text(String),
    Close,
}

/// Starts accepting connections, and returns the address it's listening on.
pub fn listen(
    addr: &str,
    behind_proxy: bool,
    desk: Arc<HttpDesk>,
    to_city: Sender<ToCity>,
) -> Result<SocketAddr, String> {
    let listener = TcpListener::bind(addr).map_err(|e| format!("{addr}: {e}"))?;
    listen_on(listener, behind_proxy, desk, to_city)
}

/// Starts accepting connections on a socket already bound.
pub fn listen_on(
    listener: TcpListener,
    behind_proxy: bool,
    desk: Arc<HttpDesk>,
    to_city: Sender<ToCity>,
) -> Result<SocketAddr, String> {
    let local = listener.local_addr().map_err(|e| e.to_string())?;
    thread::spawn(move || {
        for (conn, stream) in listener.incoming().flatten().enumerate() {
            let to_city = to_city.clone();
            let desk = Arc::clone(&desk);
            thread::spawn(move || serve(stream, conn as ConnId, behind_proxy, desk, to_city));
        }
    });
    Ok(local)
}

// The Err in the handshake callback is tungstenite's own type, and this one never returns it.
#[allow(clippy::result_large_err)]
fn serve(
    stream: TcpStream,
    conn: ConnId,
    behind_proxy: bool,
    desk: Arc<HttpDesk>,
    to_city: Sender<ToCity>,
) {
    let _ = stream.set_nodelay(true);
    let _ = stream.set_write_timeout(Some(WRITE_TIMEOUT));
    let _ = stream.set_read_timeout(Some(HANDSHAKE_TIMEOUT));
    let mut address = stream
        .peer_addr()
        .map_or(String::new(), |a| a.ip().to_string());
    // The same port serves plain HTTP, so one proxy rule covers both.
    if let Some(head) = plain_http_request(&stream) {
        answer_plain_http(stream, &head, behind_proxy, &address, &desk);
        return;
    }
    let read_proxy_header = |request: &Request, response: Response| {
        if let Some(forwarded) = forwarded_address(request).filter(|_| behind_proxy) {
            address = forwarded;
        }
        Ok(response)
    };
    let config = WebSocketConfig::default().max_message_size(Some(MAX_MESSAGE_BYTES));
    let Ok(mut socket) = accept_hdr_with_config(stream, read_proxy_header, Some(config)) else {
        return;
    };
    if socket.get_ref().set_read_timeout(Some(POLL)).is_err() {
        return;
    }
    let (out, from_city) = channel();
    if to_city.send(ToCity::Opened { conn, address, out }).is_err() {
        return;
    }
    // Whichever way the connection ends, the city hears about it once.
    pump(&mut socket, conn, &to_city, &from_city);
    let _ = to_city.send(ToCity::Closed { conn });
}

/// Looks at what's arrived without taking it. Returns the head, up to its blank line, of a request that isn't asking
/// for a WebSocket.
fn plain_http_request(stream: &TcpStream) -> Option<String> {
    let start = Instant::now();
    let mut buffer = [0; MAX_HTTP_HEAD];
    loop {
        let seen = stream.peek(&mut buffer).ok()?;
        let text = String::from_utf8_lossy(&buffer[..seen]);
        if let Some(end) = text.find("\r\n\r\n") {
            let head = &text[..end + 4];
            return (!head.to_lowercase().contains("upgrade: websocket")).then(|| head.to_string());
        }
        if seen == 0 || seen == MAX_HTTP_HEAD || start.elapsed() > HANDSHAKE_TIMEOUT {
            return None;
        }
        thread::sleep(POLL);
    }
}

fn answer_plain_http(
    mut stream: TcpStream,
    head: &str,
    behind_proxy: bool,
    address: &str,
    desk: &HttpDesk,
) {
    // The head comes off the stream first, then the body it announced, up to what that path may send.
    let mut unread = vec![0; head.len()];
    if stream.read_exact(&mut unread).is_err() {
        return;
    }
    let mut request = http::Request::parse_head(head.trim_end());
    let length: usize = request
        .header("content-length")
        .and_then(|l| l.parse().ok())
        .unwrap_or(0);
    if length > http::body_limit(&request.path) {
        let _ = stream.write_all(
            b"HTTP/1.1 413 Payload Too Large\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
        );
        return;
    }
    let mut body = vec![0; length];
    let _ = stream.set_read_timeout(Some(BODY_TIMEOUT));
    if stream.read_exact(&mut body).is_err() {
        return;
    }
    request.body = body;
    let forwarded = forwarded_in_head(head).filter(|_| behind_proxy);
    let address = forwarded.as_deref().unwrap_or(address);
    desk.answer(stream, request, address);
}

fn forwarded_in_head(head: &str) -> Option<String> {
    let line = head
        .lines()
        .find(|line| line.to_lowercase().starts_with("x-forwarded-for:"))?;
    Some(
        line.rsplit(',')
            .next()?
            .rsplit(':')
            .next()?
            .trim()
            .to_string(),
    )
}

/// The address our proxy saw. It adds to the end of this header, so only the last value can be trusted.
fn forwarded_address(request: &Request) -> Option<String> {
    let header = request.headers().get("x-forwarded-for")?.to_str().ok()?;
    Some(header.rsplit(',').next()?.trim().to_string())
}

fn pump(
    socket: &mut WebSocket<TcpStream>,
    conn: ConnId,
    to_city: &Sender<ToCity>,
    from_city: &Receiver<ToClient>,
) {
    loop {
        match socket.read() {
            Ok(Message::Text(text)) => {
                let text = text.as_str().to_string();
                if to_city.send(ToCity::Text { conn, text }).is_err() {
                    return;
                }
            }
            Ok(Message::Close(_)) => return,
            Ok(_) => {}
            Err(Error::Io(e))
                if matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) => {}
            Err(_) => return,
        }
        while let Ok(message) = from_city.try_recv() {
            match message {
                ToClient::Text(text) => {
                    if socket.send(Message::text(text)).is_err() {
                        return;
                    }
                }
                ToClient::Close => {
                    let _ = socket.close(None);
                    let _ = socket.flush();
                    return;
                }
            }
        }
    }
}
