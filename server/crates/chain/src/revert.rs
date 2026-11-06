//! Turns RPC errors and revert data into short reasons for `IntentFailed`, naming custom errors when the compiled
//! ABIs (`contracts/out`) are available.

use alloy::dyn_abi::{DynSolValue, JsonAbiExt};
use alloy::json_abi::Error as AbiError;
use alloy::primitives::{hex, Bytes};
use alloy::sol_types::{Panic, Revert, SolError};
use alloy::transports::{RpcError, TransportErrorKind};
use std::collections::HashMap;
use std::path::Path;

/// Custom errors by selector.
#[derive(Debug, Default, Clone)]
pub struct ErrorBook {
    errors: HashMap<[u8; 4], AbiError>,
}

impl ErrorBook {
    /// Reads every `*.json` artifact under `dir` (forge's `out/`) and collects their `error` entries.
    pub fn from_forge_out(dir: &Path) -> ErrorBook {
        let mut book = ErrorBook::default();
        let Ok(entries) = std::fs::read_dir(dir) else {
            return book;
        };
        for sub in entries.flatten() {
            let Ok(files) = std::fs::read_dir(sub.path()) else {
                continue;
            };
            for f in files.flatten() {
                if f.path().extension().and_then(|e| e.to_str()) != Some("json") {
                    continue;
                }
                let Ok(raw) = std::fs::read_to_string(f.path()) else {
                    continue;
                };
                book.add_artifact(&raw);
            }
        }
        book
    }

    /// Adds the errors of one forge artifact (`{"abi": [...]}`) or a bare ABI array.
    pub fn add_artifact(&mut self, json: &str) {
        let Ok(v) = serde_json::from_str::<serde_json::Value>(json) else {
            return;
        };
        let abi = v.get("abi").cloned().unwrap_or(v);
        let Ok(abi) = serde_json::from_value::<alloy::json_abi::JsonAbi>(abi) else {
            return;
        };
        for e in abi.errors() {
            self.errors.insert(e.selector().0, e.clone());
        }
    }

    pub fn len(&self) -> usize {
        self.errors.len()
    }

    pub fn is_empty(&self) -> bool {
        self.errors.is_empty()
    }

    /// `Error(string)`, `Panic(uint256)`, a known custom error with its arguments, or the raw selector.
    pub fn describe(&self, data: &[u8]) -> String {
        if data.is_empty() {
            return "reverted without a reason".into();
        }
        if let Ok(r) = Revert::abi_decode(data) {
            return format!("reverted: {}", r.reason);
        }
        if let Ok(p) = Panic::abi_decode(data) {
            return format!("panicked: {}", p);
        }
        if data.len() >= 4 {
            let sel: [u8; 4] = data[..4].try_into().expect("four bytes");
            if let Some(e) = self.errors.get(&sel) {
                return match e.abi_decode_input(&data[4..]) {
                    Ok(args) => format!(
                        "{}({})",
                        e.name,
                        args.iter().map(show).collect::<Vec<_>>().join(", ")
                    ),
                    Err(_) => format!("{} (undecodable arguments)", e.name),
                };
            }
        }
        format!("reverted with 0x{}", hex::encode(data))
    }

    /// A reason for an RPC error: the decoded revert if there is one, otherwise the node's message.
    pub fn explain(&self, err: &RpcError<TransportErrorKind>) -> String {
        if let RpcError::ErrorResp(payload) = err {
            if let Some(data) = payload.as_revert_data() {
                return self.describe(&data);
            }
            return payload.message.to_string();
        }
        err.to_string()
    }

    /// Revert data hidden in an error, if any.
    pub fn revert_data(err: &RpcError<TransportErrorKind>) -> Option<Bytes> {
        match err {
            RpcError::ErrorResp(p) => p.as_revert_data(),
            _ => None,
        }
    }
}

fn show(v: &DynSolValue) -> String {
    match v {
        DynSolValue::Uint(u, _) => u.to_string(),
        DynSolValue::Int(i, _) => i.to_string(),
        DynSolValue::Address(a) => a.to_string(),
        DynSolValue::Bool(b) => b.to_string(),
        DynSolValue::String(s) => format!("{s:?}"),
        DynSolValue::FixedBytes(w, n) => format!("0x{}", hex::encode(&w[..*n])),
        DynSolValue::Bytes(b) => format!("0x{}", hex::encode(b)),
        other => format!("{other:?}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloy::sol_types::SolError;

    #[test]
    fn standard_reverts() {
        let book = ErrorBook::default();
        let data = Revert::from("ref used").abi_encode();
        assert_eq!(book.describe(&data), "reverted: ref used");
        assert_eq!(book.describe(&[]), "reverted without a reason");
        assert!(book
            .describe(&[1, 2, 3, 4, 5])
            .starts_with("reverted with 0x0102030405"));
    }

    #[test]
    fn custom_errors_from_artifacts() {
        let mut book = ErrorBook::default();
        book.add_artifact(
            r#"{"abi":[{"type":"error","name":"MealCounter__TooDear","inputs":[
                {"name":"cost","type":"uint256"},{"name":"maxUsdc","type":"uint256"}]}]}"#,
        );
        assert_eq!(book.len(), 1);
        alloy::sol! { error MealCounter__TooDear(uint256 cost, uint256 maxUsdc); }
        let data = MealCounter__TooDear {
            cost: alloy::primitives::U256::from(5_000u64),
            maxUsdc: alloy::primitives::U256::from(4_080u64),
        }
        .abi_encode();
        assert_eq!(book.describe(&data), "MealCounter__TooDear(5000, 4080)");
    }

    #[test]
    fn reads_forge_out_when_present() {
        let out = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../contracts/out");
        let book = ErrorBook::from_forge_out(&out);
        if out.exists() {
            // FoodRouter's errors are in the tree today.
            assert!(!book.is_empty());
        }
    }
}
