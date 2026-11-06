//! World ID 4 (IDKit 4): the Town Pass.
//!
//! 1. [`WorldIdVerifier::session_context`]: for each verify session the server signs an RP context, exactly like
//!    `signRequest` in `@worldcoin/idkit-server` 1.2.0: EIP-191 `personal_sign` by `RP_SIGNING_KEY` over
//!    `0x01 || nonce (32) || created_at (u64 BE) || expires_at (u64 BE) || hashToField(action) (32)`, where
//!    `nonce = hashToField(32 random bytes)` and `hashToField(x) = keccak256(x) >> 8`. 65-byte signature, v = 27/28.
//! 2. [`WorldIdVerifier::verify`]: the IDKit result is forwarded unchanged to
//!    `POST https://developer.world.org/api/v4/verify/{rp_id}`. Before that, the result must carry a nonce this server
//!    issued for this wallet (unexpired, used once), our action, and a signal hash binding it to the wallet. After,
//!    the answer's `environment` must match `WORLD_ENVIRONMENT`. The human id is the nullifier.
//!
//! The signal is the player's wallet address; the verify page passes it as IDKit's `signal`. Both IDKit encodings
//! of an address signal are accepted: `hashToField(20 address bytes)` and `hashToField(utf8 address string)`.

use crate::config::WorldIdConfig;
use crate::types::HumanId;
use alloy::primitives::{hex, keccak256, Address, B256, U256};
use alloy::signers::SignerSync;
use serde::Serialize;
use serde_json::Value;
use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Duration;

/// A JSON POST, behind a trait so tests never call the real API.
pub trait HttpPost: Send + Sync {
    /// Returns the HTTP status and the parsed JSON body (`Value::Null` if the body isn't JSON).
    fn post_json(&self, url: &str, body: &Value, timeout: Duration)
        -> Result<(u16, Value), String>;
}

/// The real HTTP client. Runs each request on its own short-lived thread and runtime, so it's safe to call from any
/// context (the server's synchronous threads or inside another runtime).
#[derive(Debug, Default, Clone, Copy)]
pub struct ReqwestPost;

impl HttpPost for ReqwestPost {
    fn post_json(
        &self,
        url: &str,
        body: &Value,
        timeout: Duration,
    ) -> Result<(u16, Value), String> {
        use alloy::transports::http::reqwest;
        let url = url.to_string();
        let body = serde_json::to_vec(body).map_err(|e| e.to_string())?;
        std::thread::spawn(move || {
            let rt = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .map_err(|e| e.to_string())?;
            rt.block_on(async move {
                let client = reqwest::Client::builder()
                    .timeout(timeout)
                    .build()
                    .map_err(|e| e.to_string())?;
                let resp = client
                    .post(&url)
                    .header("content-type", "application/json")
                    .header("user-agent", "tallyport-server")
                    .body(body)
                    .send()
                    .await
                    .map_err(|e| format!("World ID unreachable: {e}"))?;
                let status = resp.status().as_u16();
                let bytes = resp.bytes().await.map_err(|e| e.to_string())?;
                Ok((
                    status,
                    serde_json::from_slice(&bytes).unwrap_or(Value::Null),
                ))
            })
        })
        .join()
        .map_err(|_| "World ID request thread panicked".to_string())?
    }
}

/// `hashToField(x) = keccak256(x) >> 8`, as 32 bytes.
pub fn hash_to_field(input: &[u8]) -> B256 {
    let h: U256 = U256::from_be_bytes(keccak256(input).0) >> 8usize;
    B256::from(h.to_be_bytes::<32>())
}

/// The bytes `signRequest` signs: `0x01 || nonce || created_at BE || expires_at BE || hashToField(action)`.
pub fn rp_signature_message(
    nonce: B256,
    created_at: u64,
    expires_at: u64,
    action: Option<&str>,
) -> Vec<u8> {
    let mut m = Vec::with_capacity(81);
    m.push(1);
    m.extend_from_slice(nonce.as_slice());
    m.extend_from_slice(&created_at.to_be_bytes());
    m.extend_from_slice(&expires_at.to_be_bytes());
    if let Some(a) = action {
        m.extend_from_slice(hash_to_field(a.as_bytes()).as_slice());
    }
    m
}

/// The signal hashes that bind a proof to `wallet` (IDKit's two encodings of an address signal).
pub fn signal_hashes(wallet: &str) -> Result<[B256; 3], String> {
    let a: Address = wallet
        .trim()
        .parse()
        .map_err(|_| format!("{wallet} is not an address"))?;
    Ok([
        hash_to_field(a.as_slice()),
        hash_to_field(a.to_checksum(None).as_bytes()),
        hash_to_field(format!("{a:#x}").as_bytes()),
    ])
}

/// What the verify page hands to IDKit (`rp_context`), signed by the server.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct RpContext {
    pub rp_id: String,
    /// `0x…` 32 bytes.
    pub nonce: String,
    pub created_at: u64,
    pub expires_at: u64,
    /// `0x…` 65 bytes, v = 27/28.
    pub signature: String,
    /// Extra for the page: the action, the app id and the environment to give IDKit.
    pub action: String,
    pub app_id: Option<String>,
    pub environment: String,
}

struct Issued {
    player: String,
    wallet: Address,
    expires_at: u64,
}

/// Verifies Town Pass proofs with World ID 4. Implements the server's `HumanVerifier` shape.
pub struct WorldIdVerifier {
    cfg: WorldIdConfig,
    http: Box<dyn HttpPost>,
    issued: Mutex<HashMap<B256, Issued>>,
    clock: Box<dyn Fn() -> u64 + Send + Sync>,
}

impl std::fmt::Debug for WorldIdVerifier {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("WorldIdVerifier")
            .field("rp_id", &self.cfg.rp_id)
            .field("action", &self.cfg.action)
            .field("environment", &self.cfg.environment)
            .finish_non_exhaustive()
    }
}

fn unix_now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// A hex field element (any length up to 32 bytes, with or without `0x`) as 32 bytes.
fn field(v: &Value) -> Option<B256> {
    let s = v.as_str()?.trim();
    let h = s.strip_prefix("0x").unwrap_or(s);
    if h.is_empty() || h.len() > 64 || !h.bytes().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    let bytes = hex::decode(format!("{h:0>64}")).ok()?;
    Some(B256::from_slice(&bytes))
}

impl WorldIdVerifier {
    pub fn new(cfg: WorldIdConfig) -> WorldIdVerifier {
        WorldIdVerifier::with_http(cfg, Box::new(ReqwestPost))
    }

    pub fn with_http(cfg: WorldIdConfig, http: Box<dyn HttpPost>) -> WorldIdVerifier {
        WorldIdVerifier {
            cfg,
            http,
            issued: Mutex::new(HashMap::new()),
            clock: Box::new(unix_now),
        }
    }

    #[cfg(test)]
    fn with_clock(mut self, clock: impl Fn() -> u64 + Send + Sync + 'static) -> WorldIdVerifier {
        self.clock = Box::new(clock);
        self
    }

    pub fn action(&self) -> &str {
        &self.cfg.action
    }

    /// Signs a fresh RP context for one verify session of `player`, whose wallet is `wallet`.
    pub fn session_context(&self, player: &str, wallet: &str) -> Result<RpContext, String> {
        let wallet: Address = wallet
            .trim()
            .parse()
            .map_err(|_| format!("{wallet} is not an address"))?;
        self.sign_context(player, wallet, B256::random())
    }

    fn sign_context(
        &self,
        player: &str,
        wallet: Address,
        entropy: B256,
    ) -> Result<RpContext, String> {
        let nonce = hash_to_field(entropy.as_slice());
        let created_at = (self.clock)();
        let expires_at = created_at + self.cfg.context_ttl.as_secs();
        let msg = rp_signature_message(nonce, created_at, expires_at, Some(&self.cfg.action));
        let sig = self
            .cfg
            .signing_key
            .0
            .sign_message_sync(&msg)
            .map_err(|e| format!("RP signing failed: {e}"))?;
        let mut issued = self.issued.lock().expect("issued lock");
        issued.retain(|_, i| i.expires_at >= created_at);
        issued.insert(
            nonce,
            Issued {
                player: player.to_string(),
                wallet,
                expires_at,
            },
        );
        Ok(RpContext {
            rp_id: self.cfg.rp_id.clone(),
            nonce: nonce.to_string(),
            created_at,
            expires_at,
            signature: format!("0x{}", hex::encode(sig.as_bytes())),
            action: self.cfg.action.clone(),
            app_id: self.cfg.app_id.clone(),
            environment: self.cfg.environment.clone(),
        })
    }

    /// Checks IDKit's `result` against the session it was issued for, forwards it unchanged to World ID, and returns
    /// the nullifier as the human id. One human ↔ one player is enforced by the caller (the server).
    pub fn verify(&self, player_wallet: &str, result: &Value) -> Result<HumanId, String> {
        let wallet: Address = player_wallet
            .trim()
            .parse()
            .map_err(|_| format!("{player_wallet} is not an address"))?;
        let nonce = result
            .get("nonce")
            .and_then(field)
            .ok_or("the result has no nonce")?;
        // The nonce is spent whatever happens next: a result is tried once.
        let issued = self
            .issued
            .lock()
            .expect("issued lock")
            .remove(&nonce)
            .ok_or("unknown or already used session")?;
        if issued.wallet != wallet {
            return Err("this verify session was started for another wallet".into());
        }
        if (self.clock)() > issued.expires_at {
            return Err("the verify session expired; start again".into());
        }
        if let Some(a) = result.get("action").and_then(Value::as_str) {
            if a != self.cfg.action {
                return Err(format!(
                    "the proof is for action {a:?}, not {:?}",
                    self.cfg.action
                ));
            }
        }
        let responses = result
            .get("responses")
            .and_then(Value::as_array)
            .ok_or("the result has no responses")?;
        if responses.is_empty() {
            return Err("the result has no responses".into());
        }
        let wanted = signal_hashes(player_wallet)?;
        for r in responses {
            let s = r
                .get("signal_hash")
                .and_then(field)
                .ok_or("a response has no signal hash")?;
            if !wanted.contains(&s) {
                return Err("the proof's signal isn't this wallet".into());
            }
        }
        let sent: Vec<B256> = responses
            .iter()
            .filter_map(|r| r.get("nullifier").and_then(field))
            .collect();

        let url = format!(
            "{}/{}",
            self.cfg.verify_base_url.trim_end_matches('/'),
            self.cfg.rp_id
        );
        let (status, resp) = self.http.post_json(&url, result, self.cfg.timeout)?;
        let ok = status == 200 && resp.get("success").and_then(Value::as_bool) == Some(true);
        if !ok {
            let first = resp
                .get("results")
                .and_then(Value::as_array)
                .and_then(|r| r.iter().find_map(|x| x.get("code")));
            let code = resp
                .get("code")
                .or(first)
                .and_then(Value::as_str)
                .unwrap_or("error");
            let detail = resp
                .get("detail")
                .or(resp.get("message"))
                .and_then(Value::as_str)
                .unwrap_or("");
            return Err(match code {
                "max_verifications_reached" | "already_verified" => {
                    "this person already has a Town Pass".to_string()
                }
                "invalid_proof" => "the World ID proof didn't verify".to_string(),
                _ if detail.is_empty() => format!("World ID refused the proof ({status} {code})"),
                _ => format!("World ID refused the proof ({status} {code}: {detail})"),
            });
        }
        let env = resp
            .get("environment")
            .and_then(Value::as_str)
            .unwrap_or("production");
        if env != self.cfg.environment {
            return Err(format!(
                "World ID verified a {env} proof, but this server runs {}",
                self.cfg.environment
            ));
        }
        let from_results = resp
            .get("results")
            .and_then(Value::as_array)
            .and_then(|r| {
                r.iter()
                    .find(|x| x.get("success").and_then(Value::as_bool) != Some(false))
            })
            .and_then(|x| x.get("nullifier"))
            .and_then(field);
        let nullifier = resp
            .get("nullifier")
            .and_then(field)
            .or(from_results)
            .or(sent.first().copied())
            .ok_or("no nullifier")?;
        if !sent.is_empty() && !sent.contains(&nullifier) {
            return Err("World ID answered for a different nullifier".into());
        }
        tracing::info!(player = %issued.player, "Town Pass verified");
        Ok(HumanId(nullifier.to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::tests::ANVIL_KEYS;
    use crate::config::Key;
    use serde_json::json;
    use std::sync::Arc;

    #[derive(Clone)]
    struct Mock {
        reply: (u16, Value),
        seen: Arc<Mutex<Vec<(String, Value)>>>,
    }

    impl HttpPost for Mock {
        fn post_json(&self, url: &str, body: &Value, _: Duration) -> Result<(u16, Value), String> {
            self.seen
                .lock()
                .unwrap()
                .push((url.to_string(), body.clone()));
            Ok(self.reply.clone())
        }
    }

    const WALLET: &str = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
    const NULLIFIER: &str = "0x2bf8406809dcefb1486dadc96c0a897db9bab002053054cf64272db512c6fbd8";

    fn cfg() -> WorldIdConfig {
        WorldIdConfig::new(
            "rp_test_123",
            Key::parse("RP_SIGNING_KEY", ANVIL_KEYS[0]).unwrap(),
        )
    }

    type Seen = Arc<Mutex<Vec<(String, Value)>>>;

    fn verifier(reply: (u16, Value)) -> (WorldIdVerifier, Seen) {
        let seen = Arc::new(Mutex::new(vec![]));
        let v = WorldIdVerifier::with_http(
            cfg(),
            Box::new(Mock {
                reply,
                seen: seen.clone(),
            }),
        )
        .with_clock(|| 1_000);
        (v, seen)
    }

    fn result_for(ctx: &RpContext, signal: B256) -> Value {
        json!({
            "protocol_version": "4.0",
            "nonce": ctx.nonce,
            "action": "tallyport-town-pass",
            "responses": [{
                "identifier": "proof_of_human",
                "issuer_schema_id": 1,
                "nullifier": NULLIFIER,
                "expires_at_min": 49_012_345,
                "proof": ["0x111", "0x222", "0x333", "0x444", "0x555"],
                "signal_hash": signal.to_string()
            }]
        })
    }

    fn ok_reply() -> (u16, Value) {
        (
            200,
            json!({"success": true, "nullifier": NULLIFIER, "environment": "production", "action": "tallyport-town-pass",
                     "results": [{"identifier": "proof_of_human", "success": true, "nullifier": NULLIFIER}]}),
        )
    }

    #[test]
    fn rp_context_signature_is_eip191_over_the_idkit_message() {
        let (v, _) = verifier(ok_reply());
        let ctx = v
            .sign_context("asha", WALLET.parse().unwrap(), B256::repeat_byte(7))
            .unwrap();
        assert_eq!(ctx.rp_id, "rp_test_123");
        assert_eq!((ctx.created_at, ctx.expires_at), (1_000, 1_300));
        assert_eq!(
            ctx.nonce,
            hash_to_field(B256::repeat_byte(7).as_slice()).to_string()
        );
        assert!(
            ctx.nonce.starts_with("0x00"),
            "a field element: top byte zero"
        );
        let sig = hex::decode(&ctx.signature).unwrap();
        assert_eq!(sig.len(), 65);
        assert!(sig[64] == 27 || sig[64] == 28);
        let msg = rp_signature_message(
            ctx.nonce.parse().unwrap(),
            1_000,
            1_300,
            Some("tallyport-town-pass"),
        );
        assert_eq!(msg.len(), 81);
        assert_eq!(msg[0], 1);
        assert_eq!(&msg[33..41], &1_000u64.to_be_bytes());
        let sig = alloy::primitives::Signature::try_from(sig.as_slice()).unwrap();
        let signer = cfg().signing_key.address();
        assert_eq!(sig.recover_address_from_msg(&msg).unwrap(), signer);
    }

    /// Cross-checks the EIP-191 signature against Foundry's `cast wallet sign` (deterministic RFC 6979, so the bytes
    /// must be identical). Skips when `cast` isn't on PATH.
    #[test]
    fn rp_signature_matches_cast() {
        let Ok(out) = std::process::Command::new("cast").arg("--version").output() else {
            eprintln!("skip: cast not on PATH");
            return;
        };
        if !out.status.success() {
            return;
        }
        let (v, _) = verifier(ok_reply());
        let ctx = v
            .sign_context("asha", WALLET.parse().unwrap(), B256::repeat_byte(9))
            .unwrap();
        let msg = rp_signature_message(
            ctx.nonce.parse().unwrap(),
            ctx.created_at,
            ctx.expires_at,
            Some(v.action()),
        );
        let out = std::process::Command::new("cast")
            .args(["wallet", "sign", "--private-key", ANVIL_KEYS[0]])
            .arg(format!("0x{}", hex::encode(&msg)))
            .output()
            .unwrap();
        assert!(
            out.status.success(),
            "{}",
            String::from_utf8_lossy(&out.stderr)
        );
        assert_eq!(String::from_utf8(out.stdout).unwrap().trim(), ctx.signature);
    }

    #[test]
    fn hash_to_field_vectors() {
        // keccak256("") = c5d2…a470; shifted right one byte. Matches the API docs' example signal_hash for "".
        assert_eq!(
            hash_to_field(b"").to_string(),
            "0x00c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a4"
        );
    }

    #[test]
    fn verify_forwards_the_result_unchanged_and_returns_the_nullifier() {
        let (v, seen) = verifier(ok_reply());
        let ctx = v.session_context("asha", WALLET).unwrap();
        let result = result_for(&ctx, signal_hashes(WALLET).unwrap()[0]);
        assert_eq!(
            v.verify(WALLET, &result).unwrap(),
            HumanId(NULLIFIER.into())
        );
        let seen = seen.lock().unwrap();
        assert_eq!(
            seen[0].0,
            "https://developer.world.org/api/v4/verify/rp_test_123"
        );
        assert_eq!(seen[0].1, result);
    }

    #[test]
    fn sessions_are_single_use_bound_to_the_wallet_and_expire() {
        let (v, seen) = verifier(ok_reply());
        let ctx = v.session_context("asha", WALLET).unwrap();
        let good = result_for(&ctx, signal_hashes(WALLET).unwrap()[1]);
        assert!(v.verify(WALLET, &good).is_ok());
        assert!(v
            .verify(WALLET, &good)
            .unwrap_err()
            .contains("already used"));

        let ctx = v.session_context("asha", WALLET).unwrap();
        let other = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC";
        assert!(v
            .verify(other, &result_for(&ctx, signal_hashes(other).unwrap()[0]))
            .unwrap_err()
            .contains("another wallet"));

        let ctx = v.session_context("asha", WALLET).unwrap();
        assert!(v
            .verify(WALLET, &result_for(&ctx, B256::repeat_byte(1)))
            .unwrap_err()
            .contains("signal"));

        let ctx = v.session_context("asha", WALLET).unwrap();
        let mut wrong_action = result_for(&ctx, signal_hashes(WALLET).unwrap()[0]);
        wrong_action["action"] = json!("something-else");
        assert!(v
            .verify(WALLET, &wrong_action)
            .unwrap_err()
            .contains("action"));
        assert_eq!(
            seen.lock().unwrap().len(),
            1,
            "refused results never reach the API"
        );

        let (v, _) = verifier(ok_reply());
        let ctx = v.session_context("asha", WALLET).unwrap();
        let v = v.with_clock(|| 2_000);
        assert!(v
            .verify(WALLET, &result_for(&ctx, signal_hashes(WALLET).unwrap()[0]))
            .unwrap_err()
            .contains("expired"));
    }

    #[test]
    fn refusals_and_environment_mismatches_are_explained() {
        for (reply, want) in [
            (
                (400, json!({"success": false, "code": "invalid_proof"})),
                "didn't verify",
            ),
            (
                (
                    400,
                    json!({"success": false, "results": [{"success": false, "code": "max_verifications_reached"}]}),
                ),
                "already has",
            ),
            ((500, Value::Null), "500"),
            (
                (
                    200,
                    json!({"success": true, "nullifier": NULLIFIER, "environment": "staging"}),
                ),
                "staging",
            ),
            (
                (
                    200,
                    json!({"success": true, "nullifier": "0x01", "environment": "production"}),
                ),
                "different nullifier",
            ),
        ] {
            let (v, _) = verifier(reply);
            let ctx = v.session_context("asha", WALLET).unwrap();
            let err = v
                .verify(WALLET, &result_for(&ctx, signal_hashes(WALLET).unwrap()[0]))
                .unwrap_err();
            assert!(err.contains(want), "{err} should mention {want}");
        }
    }
}
