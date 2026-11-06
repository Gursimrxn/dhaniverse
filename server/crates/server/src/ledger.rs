//! The seams between the town and the outside: the `Ledger`, which carries the rules' intents to the chain and brings
//! back what the chain did, and the `HumanVerifier`, which says whether someone is one real person. The `chain` crate
//! implements both for anvil and Sepolia; `OfflineLedger` and `OfflineVerifier` stand in for them with no network, so
//! every flow runs and is tested without a chain.
//!
//! The words themselves (`Intent`, `Observation`, `Observed`) live in `rules::chain`, because the rules speak them.
//! They're re-exported here so the chain crate needs only this module.

pub use crate::offline::{OfflineCampaign, OfflineConfig, OfflineLedger};
pub use rules::chain::{
    Bucket, ChainMode, HumanId, Intent, Observation, Observed, TicketRange, NOT_A_LOG,
};
use serde_json::{json, Value};
use sha3::{Digest, Keccak256};

/// The World ID action every Town Pass proves.
pub const TOWN_PASS_ACTION: &str = "tallyport-town-pass";

/// The chain, as the city thread sees it. Neither call may block: the city thread calls both from its loop.
pub trait Ledger: Send {
    /// Ask for something to happen on chain. The outcome comes back from `poll`. Intents with a `ref` may be submitted
    /// more than once (after a restart, or again after an `IntentFailed`): each must happen at most once.
    fn submit(&mut self, intent: Intent);
    /// What the chain did since the last call: confirmed, in block order. The hub turns each into a logged input.
    fn poll(&mut self) -> Vec<Observed>;
}

/// Says whether a proof shows one real person, for the Town Pass.
pub trait HumanVerifier: Send + Sync {
    /// Checks a proof whose signal is the player's wallet. Returns the World ID nullifier hash as `0x…` hex.
    fn verify(&self, player_wallet: &str, proof: &Value) -> Result<HumanId, String>;

    /// What `GET /verify/session` adds for the verify page: `app_id`, `action`, `environment`, `allow_legacy_proofs`,
    /// `rp_context` (a fresh signed one on every call) and `rehearsal`. The server adds the player, wallet, expiry and
    /// whether they're verified.
    fn session_context(&self, player: &str, player_wallet: &str) -> Result<Value, String>;

    /// The World ID app id the pages show, if there is one.
    fn app_id(&self) -> Option<String> {
        None
    }

    /// Whether this server can stamp a Town Pass at all: World ID is set up, or it's a rehearsal (`--debug`) server.
    /// The game asks every passenger for the pass at the gangway only when it can be had.
    fn can_verify(&self) -> bool {
        false
    }
}

/// Rehearsal only: accepts the proof `{"offline": true}`, and only when the server runs with `--debug`. The id it gives
/// is stable for a wallet and says what it is: `keccak256("offline:" + wallet)`. The verify page says "rehearsal".
#[derive(Clone, Copy, Debug)]
pub struct OfflineVerifier {
    debug: bool,
}

impl OfflineVerifier {
    pub fn new(debug: bool) -> Self {
        OfflineVerifier { debug }
    }
}

impl HumanVerifier for OfflineVerifier {
    fn verify(&self, player_wallet: &str, proof: &Value) -> Result<HumanId, String> {
        if !self.debug {
            return Err(
                "this server has no World ID: start it with --debug to rehearse the Town Pass"
                    .to_string(),
            );
        }
        if proof.get("offline") != Some(&Value::Bool(true)) {
            return Err("a rehearsal server only takes the proof {\"offline\": true}".to_string());
        }
        Ok(HumanId(keccak_hex(
            format!("offline:{player_wallet}").as_bytes(),
        )))
    }

    fn session_context(&self, _player: &str, _player_wallet: &str) -> Result<Value, String> {
        Ok(json!({
            "app_id": null,
            "action": TOWN_PASS_ACTION,
            "environment": "staging",
            "allow_legacy_proofs": true,
            "rp_context": null,
            "rehearsal": true,
        }))
    }

    fn can_verify(&self) -> bool {
        self.debug
    }
}

/// Keccak-256, as `0x…` hex.
pub fn keccak_hex(bytes: &[u8]) -> String {
    format!("0x{}", hex(&Keccak256::digest(bytes)))
}

/// Keccak-256 of the bytes a `0x…` hex string spells, as `0x…` hex. For draw seeds.
pub fn keccak_of_hex(text: &str) -> Option<String> {
    Some(keccak_hex(&unhex(text)?))
}

pub fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

pub fn unhex(text: &str) -> Option<Vec<u8>> {
    let digits = text.strip_prefix("0x").unwrap_or(text);
    if !digits.len().is_multiple_of(2) {
        return None;
    }
    (0..digits.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(digits.get(i..i + 2)?, 16).ok())
        .collect()
}

/// `n` bytes from the operating system's random source.
pub fn random_bytes(n: usize) -> Result<Vec<u8>, String> {
    let mut bytes = vec![0; n];
    getrandom::getrandom(&mut bytes).map_err(|e| format!("no randomness: {e}"))?;
    Ok(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keccak_matches_the_known_empty_hash() {
        assert_eq!(
            keccak_hex(b""),
            "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
        );
        assert_eq!(unhex("0x00ff"), Some(vec![0, 255]));
        assert_eq!(unhex("0x0"), None);
    }

    #[test]
    fn the_offline_verifier_takes_only_its_own_proof_and_only_when_rehearsing() {
        let rehearsing = OfflineVerifier::new(true);
        let id = rehearsing
            .verify("0xabc", &json!({"offline": true}))
            .unwrap();
        assert_eq!(
            id,
            rehearsing
                .verify("0xabc", &json!({"offline": true}))
                .unwrap(),
            "stable"
        );
        assert_ne!(
            id,
            rehearsing
                .verify("0xdef", &json!({"offline": true}))
                .unwrap()
        );
        assert!(rehearsing.verify("0xabc", &json!({"proof": "x"})).is_err());
        assert!(OfflineVerifier::new(false)
            .verify("0xabc", &json!({"offline": true}))
            .is_err());
        let context = rehearsing.session_context("sam", "0xabc").unwrap();
        assert_eq!(context["rehearsal"], true);
    }
}
