//! Plain HTTP on the WebSocket's port: the public view, health, the web pages, the deployments file for the pages, the
//! Town Pass's verify endpoints, and the publisher's Arkiv and Swarm endpoints passed through. Each request is answered
//! on its connection's own thread; the only thing that reaches the city thread is a verified Town Pass, as a message.

use crate::ledger::{hex, random_bytes, HumanId, HumanVerifier};
use crate::net::ToCity;
use crate::public::PublicView;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::path::{Component, Path, PathBuf};
use std::sync::mpsc::{channel, Sender};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

/// No request worth answering is bigger, except a campaign's story and image for Swarm.
pub const MAX_BODY: usize = 64 * 1024;
pub const MAX_UPLOAD: usize = 8 * 1024 * 1024;
/// A Town Pass link works once, for this long.
const SESSION_TTL: Duration = Duration::from_secs(15 * 60);
const ARKIV_CACHE: Duration = Duration::from_secs(10);
const PUBLISHER_TIMEOUT: Duration = Duration::from_secs(5);
const CITY_ANSWER_WAIT: Duration = Duration::from_secs(10);
/// Folders in `web/` that are for building and checking the pages, never for serving.
const NOT_SERVED: [&str; 2] = ["dev", "tools"];

/// The biggest body this path may send.
pub fn body_limit(path: &str) -> usize {
    if path == "/swarm/campaign-bundle" {
        MAX_UPLOAD
    } else {
        MAX_BODY
    }
}

pub struct Request {
    pub method: String,
    pub path: String,
    pub query: String,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

impl Request {
    /// Reads the head's first line and headers. The body is added by whoever read it.
    pub fn parse_head(head: &str) -> Request {
        let mut lines = head.split("\r\n");
        let mut first = lines.next().unwrap_or("").split_whitespace();
        let method = first.next().unwrap_or("").to_string();
        let target = first.next().unwrap_or("");
        let (path, query) = target.split_once('?').unwrap_or((target, ""));
        let headers = lines
            .filter_map(|line| line.split_once(':'))
            .map(|(k, v)| (k.trim().to_lowercase(), v.trim().to_string()))
            .collect();
        Request {
            method,
            path: path.to_string(),
            query: query.to_string(),
            headers,
            body: Vec::new(),
        }
    }

    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(k, _)| k == name)
            .map(|(_, v)| v.as_str())
    }

    fn param(&self, name: &str) -> Option<String> {
        self.query.split('&').find_map(|pair| {
            let (k, v) = pair.split_once('=')?;
            (k == name).then(|| v.to_string())
        })
    }
}

pub struct Response {
    pub status: u16,
    pub content_type: String,
    pub body: Vec<u8>,
    pub cache: &'static str,
    pub cors: bool,
}

impl Response {
    fn json(status: u16, body: Value) -> Response {
        Response {
            status,
            content_type: "application/json".to_string(),
            body: body.to_string().into_bytes(),
            cache: "no-store",
            cors: true,
        }
    }

    fn error(status: u16, code: &str, message: &str) -> Response {
        Response::json(status, json!({"error": code, "message": message}))
    }

    fn write(&self, stream: &mut TcpStream, head_only: bool) {
        let reason = match self.status {
            200 => "OK",
            201 => "Created",
            400 => "Bad Request",
            404 => "Not Found",
            405 => "Method Not Allowed",
            409 => "Conflict",
            410 => "Gone",
            413 => "Payload Too Large",
            429 => "Too Many Requests",
            502 => "Bad Gateway",
            _ => "Service Unavailable",
        };
        let cors = if self.cors {
            "Access-Control-Allow-Origin: *\r\n"
        } else {
            ""
        };
        let head = format!(
            "HTTP/1.1 {} {reason}\r\nContent-Type: {}\r\nContent-Length: {}\r\n{cors}Cache-Control: {}\r\n\
             X-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n",
            self.status,
            self.content_type,
            self.body.len(),
            self.cache
        );
        let _ = stream.write_all(head.as_bytes());
        if !head_only {
            let _ = stream.write_all(&self.body);
        }
        let _ = stream.flush();
    }
}

/// Where the HTTP side finds things. Nothing here is a secret.
#[derive(Clone, Debug, Default)]
pub struct HttpConfig {
    /// The `web/` folder, served as static files.
    pub web_dir: Option<PathBuf>,
    /// `contracts/deployments/<network>.json`.
    pub deployments: Option<PathBuf>,
    /// A public, keyless read RPC for the browser.
    pub rpc_url: Option<String>,
    /// The publisher sidecar, `http://host:port`.
    pub publisher_url: Option<String>,
    /// The World ID app id the pages show.
    pub world_app_id: Option<String>,
}

/// One Town Pass link.
#[derive(Clone, Debug)]
struct Session {
    player: String,
    wallet: String,
    expires: Instant,
    expires_at: u64,
    used: bool,
    human_id: Option<String>,
    ens: Option<String>,
}

/// The Town Pass links handed out. Not game state: held in memory only, gone after a restart, when the player just
/// asks for a new link.
pub struct VerifyDesk {
    sessions: Mutex<HashMap<String, Session>>,
    public_url: String,
}

fn unix_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs())
}

impl VerifyDesk {
    /// `public_url` is how a player's browser reaches this server, such as `https://town.example.com`.
    pub fn new(public_url: &str) -> Self {
        VerifyDesk {
            sessions: Mutex::new(HashMap::new()),
            public_url: public_url.trim_end_matches('/').to_string(),
        }
    }

    /// A new one-time link for this player and wallet.
    pub fn open(&self, player: &str, wallet: &str) -> Result<String, String> {
        let token = hex(&random_bytes(24)?);
        let mut sessions = self
            .sessions
            .lock()
            .map_err(|_| "the verify desk broke".to_string())?;
        sessions.retain(|_, s| s.expires.elapsed() < SESSION_TTL);
        sessions.insert(
            token.clone(),
            Session {
                player: player.to_string(),
                wallet: wallet.to_string(),
                expires: Instant::now() + SESSION_TTL,
                expires_at: unix_now() + SESSION_TTL.as_secs(),
                used: false,
                human_id: None,
                ens: None,
            },
        );
        Ok(format!("{}/verify?token={token}", self.public_url))
    }

    fn get(&self, token: &str) -> Result<Session, Response> {
        let sessions = self
            .sessions
            .lock()
            .map_err(|_| Response::error(503, "busy", "try again"))?;
        let Some(session) = sessions.get(token) else {
            return Err(Response::error(
                404,
                "token_unknown",
                "That link isn't one this server gave out. Ask for a new one in the game.",
            ));
        };
        if session.used {
            return Err(Response::error(
                410,
                "token_used",
                "That link was used already.",
            ));
        }
        if Instant::now() >= session.expires {
            return Err(Response::error(
                410,
                "token_expired",
                "That link has expired. Ask for a new one in the game.",
            ));
        }
        Ok(session.clone())
    }

    fn mark_used(&self, token: &str, human_id: &str, ens: Option<String>) {
        if let Ok(mut sessions) = self.sessions.lock() {
            if let Some(s) = sessions.get_mut(token) {
                s.used = true;
                s.human_id = Some(human_id.to_string());
                s.ens = ens;
            }
        }
    }
}

pub struct HttpDesk {
    public: Arc<PublicView>,
    config: HttpConfig,
    verify: Arc<VerifyDesk>,
    verifier: Arc<dyn HumanVerifier>,
    to_city: Mutex<Sender<ToCity>>,
    arkiv: Mutex<Option<(Instant, Response)>>,
}

impl HttpDesk {
    pub fn new(
        public: Arc<PublicView>,
        config: HttpConfig,
        verify: Arc<VerifyDesk>,
        verifier: Arc<dyn HumanVerifier>,
        to_city: Sender<ToCity>,
    ) -> Self {
        HttpDesk {
            public,
            config,
            verify,
            verifier,
            to_city: Mutex::new(to_city),
            arkiv: Mutex::new(None),
        }
    }

    pub fn public(&self) -> &PublicView {
        &self.public
    }

    /// Answers one request and closes.
    pub fn answer(&self, mut stream: TcpStream, request: Request, address: &str) {
        let head_only = request.method == "HEAD";
        let response = self.reply(&request, address);
        response.write(&mut stream, head_only);
    }

    fn reply(&self, request: &Request, address: &str) -> Response {
        let get = matches!(request.method.as_str(), "GET" | "HEAD");
        let post = request.method == "POST";
        match (request.path.as_str(), get, post) {
            ("/health", true, _) => match self.public.health() {
                Some(text) => {
                    Response::json(200, serde_json::from_str(&text).unwrap_or(Value::Null))
                }
                None => Response::error(503, "stopped", "the city has stopped"),
            },
            ("/city", true, _) => {
                if !self.public.allow(address) {
                    return Response::error(429, "slow_down", "slow down");
                }
                match self.public.city() {
                    Some(text) => Response {
                        status: 200,
                        content_type: "application/json".to_string(),
                        body: text.into_bytes(),
                        cache: "public, max-age=5",
                        cors: true,
                    },
                    None => Response::error(503, "not_ready", "not ready"),
                }
            }
            ("/deployments.json", true, _) => self.deployments(),
            ("/verify/session", true, _) => self.session(request),
            ("/verify", _, true) => self.verify_post(request),
            ("/arkiv/campaigns", true, _) => self.arkiv_campaigns(),
            ("/swarm/campaign-bundle", _, true) => self.swarm_bundle(request),
            (_, true, _) => self.static_file(&request.path),
            _ => Response::error(405, "method", "not here"),
        }
    }

    fn deployments(&self) -> Response {
        let Some(path) = &self.config.deployments else {
            return Response::error(404, "no_deployments", "this server runs without a chain");
        };
        let text = match std::fs::read_to_string(path) {
            Ok(text) => text,
            Err(_) => {
                return Response::error(
                    404,
                    "no_deployments",
                    "the deployments file isn't there yet",
                )
            }
        };
        let Ok(mut file) = serde_json::from_str::<Value>(&text) else {
            return Response::error(503, "bad_deployments", "the deployments file isn't JSON");
        };
        if let (Some(url), Some(map)) = (&self.config.rpc_url, file.as_object_mut()) {
            map.insert("rpcUrl".to_string(), json!(url));
        }
        Response::json(200, file)
    }

    fn session(&self, request: &Request) -> Response {
        let token = request.param("token").unwrap_or_default();
        let session = match self.verify.get(&token) {
            Ok(session) => session,
            Err(response) => return response,
        };
        let context = match self
            .verifier
            .session_context(&session.player, &session.wallet)
        {
            Ok(context) => context,
            Err(problem) => return Response::error(503, "verifier_unavailable", &problem),
        };
        let mut answer = json!({
            "player": session.player,
            "wallet": session.wallet,
            "expires_at": session.expires_at,
            "verified": session.human_id.is_some(),
            "human_id": session.human_id,
            "ens": session.ens,
        });
        if let (Some(answer), Some(context)) = (answer.as_object_mut(), context.as_object()) {
            for (key, value) in context {
                answer.insert(key.clone(), value.clone());
            }
        }
        Response::json(200, answer)
    }

    fn verify_post(&self, request: &Request) -> Response {
        let refuse = |status: u16, code: &str, message: &str| {
            Response::json(
                status,
                json!({"ok": false, "error": code, "message": message}),
            )
        };
        let Ok(body) = serde_json::from_slice::<Value>(&request.body) else {
            return refuse(
                400,
                "invalid_proof",
                "send JSON: {\"token\": …, \"result\": …}",
            );
        };
        let token = body["token"].as_str().unwrap_or_default().to_string();
        let session = match self.verify.get(&token) {
            Ok(session) => session,
            Err(response) => {
                let code = serde_json::from_slice::<Value>(&response.body)
                    .ok()
                    .and_then(|v| v["error"].as_str().map(str::to_string))
                    .unwrap_or_default();
                let code = if code == "token_used" {
                    "token_used"
                } else {
                    "token_expired"
                };
                return refuse(response.status, code, "ask for a new link in the game");
            }
        };
        let proof = body
            .get("result")
            .or(body.get("proof"))
            .cloned()
            .unwrap_or(Value::Null);
        let rehearsal = proof.get("offline") == Some(&Value::Bool(true));
        let human_id = match self.verifier.verify(&session.wallet, &proof) {
            Ok(id) => id,
            Err(problem) => return refuse(400, "invalid_proof", &problem),
        };
        match self.tell_city(&session.player, human_id.clone()) {
            Ok(ens) => {
                self.verify
                    .mark_used(&token, human_id.as_str(), ens.clone());
                let mut answer = json!({"ok": true, "human_id": human_id.as_str(), "ens": ens});
                if rehearsal {
                    answer["rehearsal"] = json!(true);
                }
                Response::json(200, answer)
            }
            Err(refusal) if refusal == "AlreadyHuman" => {
                refuse(409, "already_verified", "you already have the Town Pass")
            }
            Err(refusal) if refusal == "HumanTaken" => refuse(
                409,
                "already_verified",
                "this World ID already holds another player: one person, one player",
            ),
            Err(problem) => refuse(503, "invalid_proof", &problem),
        }
    }

    /// Hands a verified person to the city thread, and waits for its answer.
    fn tell_city(&self, player: &str, human_id: HumanId) -> Result<Option<String>, String> {
        let (reply, answer) = channel();
        let message = ToCity::Verified {
            player: player.to_string(),
            human_id,
            reply,
        };
        let sent = self
            .to_city
            .lock()
            .is_ok_and(|to_city| to_city.send(message).is_ok());
        if !sent {
            return Err("the city is stopping".to_string());
        }
        answer
            .recv_timeout(CITY_ANSWER_WAIT)
            .map_err(|_| "the city didn't answer".to_string())?
    }

    fn arkiv_campaigns(&self) -> Response {
        let Some(base) = &self.config.publisher_url else {
            return Response::error(
                503,
                "unavailable",
                "this server has no publisher (set PUBLISHER_URL)",
            );
        };
        if let Ok(cache) = self.arkiv.lock() {
            if let Some((at, response)) = cache.as_ref() {
                if at.elapsed() < ARKIV_CACHE {
                    return Response {
                        status: response.status,
                        content_type: response.content_type.clone(),
                        body: response.body.clone(),
                        cache: "public, max-age=10",
                        cors: true,
                    };
                }
            }
        }
        let url = format!("{}/campaigns", base.trim_end_matches('/'));
        match fetch(&url, "GET", None, &[]) {
            Ok((200, content_type, body)) => {
                let response = Response {
                    status: 200,
                    content_type,
                    body,
                    cache: "public, max-age=10",
                    cors: true,
                };
                if let Ok(mut cache) = self.arkiv.lock() {
                    *cache = Some((
                        Instant::now(),
                        Response {
                            status: 200,
                            content_type: response.content_type.clone(),
                            body: response.body.clone(),
                            cache: "public, max-age=10",
                            cors: true,
                        },
                    ));
                }
                response
            }
            Ok((status, _, _)) => Response::error(
                503,
                "unavailable",
                &format!("the publisher answered {status}; the Bounty Board's Arkiv cards are unavailable"),
            ),
            Err(problem) => Response::error(
                503,
                "unavailable",
                &format!("the publisher isn't answering ({problem}); the Bounty Board's Arkiv cards are unavailable"),
            ),
        }
    }

    fn swarm_bundle(&self, request: &Request) -> Response {
        let Some(base) = &self.config.publisher_url else {
            return Response::error(
                503,
                "unavailable",
                "this server has no publisher (set PUBLISHER_URL)",
            );
        };
        let url = format!("{}/swarm/campaign-bundle", base.trim_end_matches('/'));
        let content_type = request.header("content-type");
        match fetch(&url, "POST", content_type, &request.body) {
            Ok((status, content_type, body)) => Response {
                status,
                content_type,
                body,
                cache: "no-store",
                cors: false,
            },
            Err(problem) => Response::error(
                502,
                "unavailable",
                &format!("the publisher isn't answering ({problem})"),
            ),
        }
    }

    fn static_file(&self, path: &str) -> Response {
        let Some(root) = &self.config.web_dir else {
            return Response::error(404, "not_here", "not here");
        };
        let relative = match path {
            "/verify" => "verify.html",
            "/console" => "console.html",
            "/dashboard" => "dashboard.html",
            "/" => "dashboard.html",
            other => other.trim_start_matches('/'),
        };
        let Some(file) = safe_path(root, relative) else {
            return Response::error(404, "not_here", "not here");
        };
        match std::fs::read(&file) {
            Ok(body) => Response {
                status: 200,
                content_type: content_type(&file).to_string(),
                body,
                cache: "no-cache",
                cors: false,
            },
            Err(_) => Response::error(404, "not_here", "not here"),
        }
    }
}

/// A file under `root`, or None for anything that could leave it, hidden files, and the folders not served.
fn safe_path(root: &Path, relative: &str) -> Option<PathBuf> {
    if relative.is_empty() || relative.contains('\\') || relative.contains('%') {
        return None;
    }
    let path = Path::new(relative);
    let mut parts = Vec::new();
    for component in path.components() {
        match component {
            Component::Normal(part) => {
                let part = part.to_str()?;
                if part.starts_with('.') {
                    return None;
                }
                parts.push(part);
            }
            _ => return None,
        }
    }
    if parts
        .first()
        .is_some_and(|first| NOT_SERVED.contains(first))
    {
        return None;
    }
    let full = parts
        .iter()
        .fold(root.to_path_buf(), |p, part| p.join(part));
    full.is_file().then_some(full)
}

fn content_type(path: &Path) -> &'static str {
    match path.extension().and_then(|e| e.to_str()).unwrap_or("") {
        "html" => "text/html; charset=utf-8",
        "js" | "mjs" => "text/javascript; charset=utf-8",
        "css" => "text/css; charset=utf-8",
        "json" => "application/json",
        "svg" => "image/svg+xml",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "webp" => "image/webp",
        "otf" => "font/otf",
        "woff2" => "font/woff2",
        "ico" => "image/x-icon",
        _ => "application/octet-stream",
    }
}

/// A plain-HTTP request to the publisher sidecar. Returns the status, content type and body.
pub fn fetch(
    url: &str,
    method: &str,
    content_type: Option<&str>,
    body: &[u8],
) -> Result<(u16, String, Vec<u8>), String> {
    let rest = url
        .strip_prefix("http://")
        .ok_or("the publisher URL must be http:// (it runs beside the server)")?;
    let (host, path) = rest
        .split_once('/')
        .map_or((rest, "/".to_string()), |(h, p)| (h, format!("/{p}")));
    let address = if host.contains(':') {
        host.to_string()
    } else {
        format!("{host}:80")
    };
    let socket = address
        .to_socket_addrs()
        .map_err(|e| e.to_string())?
        .next()
        .ok_or("no address")?;
    let mut stream =
        TcpStream::connect_timeout(&socket, PUBLISHER_TIMEOUT).map_err(|e| e.to_string())?;
    stream
        .set_read_timeout(Some(PUBLISHER_TIMEOUT))
        .map_err(|e| e.to_string())?;
    stream
        .set_write_timeout(Some(PUBLISHER_TIMEOUT))
        .map_err(|e| e.to_string())?;
    let mut head = format!("{method} {path} HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\nAccept: application/json\r\n");
    if let Some(content_type) = content_type {
        head.push_str(&format!("Content-Type: {content_type}\r\n"));
    }
    if method != "GET" {
        head.push_str(&format!("Content-Length: {}\r\n", body.len()));
    }
    head.push_str("\r\n");
    stream
        .write_all(head.as_bytes())
        .map_err(|e| e.to_string())?;
    stream.write_all(body).map_err(|e| e.to_string())?;
    let mut raw = Vec::new();
    stream
        .take((MAX_UPLOAD * 2) as u64)
        .read_to_end(&mut raw)
        .map_err(|e| e.to_string())?;
    let split = raw
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .ok_or("no answer")?;
    let head = String::from_utf8_lossy(&raw[..split]).to_string();
    let response = Request::parse_head(&head);
    let status: u16 = head
        .split_whitespace()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .ok_or("no status")?;
    let mut payload = raw[split + 4..].to_vec();
    if response
        .header("transfer-encoding")
        .is_some_and(|t| t.eq_ignore_ascii_case("chunked"))
    {
        payload = unchunk(&payload).ok_or("a broken chunked answer")?;
    }
    let content_type = response
        .header("content-type")
        .unwrap_or("application/json")
        .to_string();
    Ok((status, content_type, payload))
}

fn unchunk(mut data: &[u8]) -> Option<Vec<u8>> {
    let mut out = Vec::new();
    loop {
        let line_end = data.windows(2).position(|w| w == b"\r\n")?;
        let size_text = std::str::from_utf8(&data[..line_end]).ok()?;
        let size = usize::from_str_radix(size_text.split(';').next()?.trim(), 16).ok()?;
        data = &data[line_end + 2..];
        if size == 0 {
            return Some(out);
        }
        out.extend_from_slice(data.get(..size)?);
        data = data.get(size + 2..)?;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_files_inside_the_web_folder_and_outside_dev_and_tools_are_served() {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("src");
        assert!(safe_path(&root, "http.rs").is_some());
        assert!(safe_path(&root, "../Cargo.toml").is_none());
        assert!(safe_path(&root, "/etc/passwd").is_none());
        assert!(safe_path(&root, "dev/city.json").is_none());
        assert!(safe_path(&root, "tools/x.mjs").is_none());
        assert!(safe_path(&root, ".hidden").is_none());
        assert!(safe_path(&root, "feed\\mod.rs").is_none());
        assert!(safe_path(&root, "%2e%2e/Cargo.toml").is_none());
    }

    #[test]
    fn a_chunked_answer_reads_whole() {
        assert_eq!(
            unchunk(b"3\r\nabc\r\n2\r\nde\r\n0\r\n\r\n"),
            Some(b"abcde".to_vec())
        );
    }

    #[test]
    fn a_request_head_reads_its_path_query_and_headers() {
        let r = Request::parse_head(
            "GET /verify/session?token=abc HTTP/1.1\r\nHost: x\r\nContent-Type: a/b",
        );
        assert_eq!(r.path, "/verify/session");
        assert_eq!(r.param("token").as_deref(), Some("abc"));
        assert_eq!(r.header("content-type"), Some("a/b"));
    }
}
