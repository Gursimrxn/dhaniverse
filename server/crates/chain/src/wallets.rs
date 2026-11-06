//! Server-held player wallets (spec §3.3): `WALLET_SEED` (BIP-39) → `m/44'/60'/0'/0/<index>`.
//!
//! A player's index is assigned once and persisted in `wallets.jsonl` (append-only), so a player keeps their address
//! across restarts. Keys are derived on demand and never written or logged.

use crate::store::{JsonLines, StoreError};
use crate::types::PlayerId;
use alloy::primitives::Address;
use alloy::signers::local::coins_bip39::English;
use alloy::signers::local::{MnemonicBuilder, MnemonicKey, PrivateKeySigner};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fmt;
use std::path::Path;

/// Checks that a phrase is a valid English BIP-39 mnemonic, without saying anything about it in the error.
pub fn validate_seed(phrase: &str) -> Result<(), String> {
    MnemonicBuilder::<English>::default()
        .phrase(phrase.trim())
        .build_parent_key()
        .map(|_| ())
        .map_err(|_| "not a valid English BIP-39 phrase".to_string())
}

/// The extended key at `m/44'/60'/0'/0`, from which every player key is one child step.
#[derive(Clone)]
pub struct HdRoot(MnemonicKey);

impl HdRoot {
    pub fn from_phrase(phrase: &str) -> Result<HdRoot, String> {
        // The builder's default path is m/44'/60'/0'/0/0; its parent is m/44'/60'/0'/0.
        MnemonicBuilder::<English>::default()
            .phrase(phrase.trim())
            .build_parent_key()
            .map(HdRoot)
            .map_err(|_| "not a valid English BIP-39 phrase".to_string())
    }

    /// The signer at `m/44'/60'/0'/0/<index>`.
    pub fn signer(&self, index: u32) -> PrivateKeySigner {
        assert!(index < 0x8000_0000, "player indexes are non-hardened");
        self.0
            .child(index)
            .expect("non-hardened child derivation cannot fail")
            .signer()
    }
}

impl fmt::Debug for HdRoot {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("HdRoot(<redacted>)")
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "t", rename_all = "snake_case")]
enum Record {
    /// A player got an index (once, ever).
    Assigned {
        player: PlayerId,
        index: u32,
        address: Address,
    },
    /// A player's ENS label was registered.
    Named { player: PlayerId, label: String },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Wallet {
    pub player: PlayerId,
    pub index: u32,
    pub address: Address,
    pub label: Option<String>,
}

/// Player ↔ index ↔ address, persisted.
#[derive(Debug)]
pub struct WalletBook {
    root: HdRoot,
    log: JsonLines,
    by_player: HashMap<PlayerId, Wallet>,
    by_address: HashMap<Address, PlayerId>,
    next_index: u32,
    signers: HashMap<u32, PrivateKeySigner>,
}

impl WalletBook {
    /// Loads `<dir>/wallets.jsonl`. Refuses to start if a stored address doesn't match the seed (wrong `WALLET_SEED`).
    pub fn open(dir: &Path, root: HdRoot) -> Result<WalletBook, WalletError> {
        let (log, records) = JsonLines::open::<Record>(dir.join("wallets.jsonl"))?;
        let mut book = WalletBook {
            root,
            log,
            by_player: HashMap::new(),
            by_address: HashMap::new(),
            next_index: 0,
            signers: HashMap::new(),
        };
        for r in records {
            match r {
                Record::Assigned {
                    player,
                    index,
                    address,
                } => {
                    let derived = book.root.signer(index).address();
                    if derived != address {
                        return Err(WalletError::SeedMismatch { player, index });
                    }
                    book.next_index = book.next_index.max(index + 1);
                    book.by_address.insert(address, player.clone());
                    book.by_player.insert(
                        player.clone(),
                        Wallet {
                            player,
                            index,
                            address,
                            label: None,
                        },
                    );
                }
                Record::Named { player, label } => {
                    if let Some(w) = book.by_player.get_mut(&player) {
                        w.label = Some(label);
                    }
                }
            }
        }
        Ok(book)
    }

    /// The player's wallet, assigning the next index (and persisting it) the first time.
    pub fn ensure(&mut self, player: &str) -> Result<Wallet, WalletError> {
        if let Some(w) = self.by_player.get(player) {
            return Ok(w.clone());
        }
        let index = self.next_index;
        if index >= 0x8000_0000 {
            return Err(WalletError::Exhausted);
        }
        let address = self.root.signer(index).address();
        self.log.append(&Record::Assigned {
            player: player.to_string(),
            index,
            address,
        })?;
        self.next_index += 1;
        let w = Wallet {
            player: player.to_string(),
            index,
            address,
            label: None,
        };
        self.by_address.insert(address, player.to_string());
        self.by_player.insert(player.to_string(), w.clone());
        Ok(w)
    }

    pub fn get(&self, player: &str) -> Option<&Wallet> {
        self.by_player.get(player)
    }

    pub fn player_of(&self, address: &Address) -> Option<&PlayerId> {
        self.by_address.get(address)
    }

    /// The signing key for a player who already has a wallet.
    pub fn signer(&mut self, player: &str) -> Option<PrivateKeySigner> {
        let index = self.by_player.get(player)?.index;
        let root = &self.root;
        Some(
            self.signers
                .entry(index)
                .or_insert_with(|| root.signer(index))
                .clone(),
        )
    }

    pub fn set_label(&mut self, player: &str, label: &str) -> Result<(), WalletError> {
        let w = self
            .by_player
            .get_mut(player)
            .ok_or_else(|| WalletError::Unknown(player.to_string()))?;
        if w.label.as_deref() != Some(label) {
            self.log.append(&Record::Named {
                player: player.to_string(),
                label: label.to_string(),
            })?;
            w.label = Some(label.to_string());
        }
        Ok(())
    }

    /// Brings `wallets.jsonl` back in line with the save, which records every player's address (`WalletReady`). A town
    /// restored from Arkiv on a new machine has the save but not the data dir; without this, the next `ensure` would
    /// hand index 0 (an existing player's wallet) to someone else. Each missing player's index is found by deriving
    /// addresses from the seed. Refuses, and writes nothing, if the save and the book disagree or an address isn't
    /// one of the seed's. Returns how many wallets were recovered.
    pub fn recover(&mut self, known: &[(PlayerId, Address)]) -> Result<usize, WalletError> {
        let mut missing = Vec::new();
        for (player, address) in known {
            match self.by_player.get(player) {
                Some(w) if w.address == *address => {}
                Some(w) => {
                    return Err(WalletError::SaveMismatch {
                        player: player.clone(),
                        book: w.address,
                        save: *address,
                    })
                }
                None => {
                    if let Some(other) = self.by_address.get(address) {
                        return Err(WalletError::AddressTaken {
                            player: player.clone(),
                            other: other.clone(),
                            address: *address,
                        });
                    }
                    missing.push((player.clone(), *address));
                }
            }
        }
        if missing.is_empty() {
            return Ok(0);
        }
        // Indexes are handed out in order, so every one in use is below the number of wallets ever made. The slack
        // covers wallets made for players the save never saw get one (a draw's `ensure`).
        let limit = (self.next_index as usize + known.len() + RECOVERY_SLACK).min(0x8000_0000) as u32;
        let mut by_address = HashMap::new();
        for index in 0..limit {
            if missing.iter().all(|(_, a)| by_address.contains_key(a)) {
                break;
            }
            by_address.insert(self.root.signer(index).address(), index);
        }
        let mut found = Vec::with_capacity(missing.len());
        for (player, address) in missing {
            let index = *by_address
                .get(&address)
                .ok_or_else(|| WalletError::NotFromSeed(player.clone(), address))?;
            found.push((player, index, address));
        }
        found.sort_by_key(|(_, index, _)| *index);
        for (player, index, address) in &found {
            self.log.append(&Record::Assigned {
                player: player.clone(),
                index: *index,
                address: *address,
            })?;
            self.next_index = self.next_index.max(index + 1);
            self.by_address.insert(*address, player.clone());
            self.by_player.insert(
                player.clone(),
                Wallet {
                    player: player.clone(),
                    index: *index,
                    address: *address,
                    label: None,
                },
            );
        }
        Ok(found.len())
    }

    pub fn all(&self) -> impl Iterator<Item = &Wallet> {
        self.by_player.values()
    }

    pub fn len(&self) -> usize {
        self.by_player.len()
    }

    pub fn is_empty(&self) -> bool {
        self.by_player.is_empty()
    }
}

#[derive(Debug, thiserror::Error)]
pub enum WalletError {
    #[error(transparent)]
    Store(#[from] StoreError),
    #[error(
        "wallets.jsonl was made with a different WALLET_SEED (player {player}, index {index})"
    )]
    SeedMismatch { player: PlayerId, index: u32 },
    #[error("no wallet for player {0}")]
    Unknown(PlayerId),
    #[error("all wallet indexes are used")]
    Exhausted,
    #[error("the save gives {player} wallet {save}, but wallets.jsonl has {book}")]
    SaveMismatch {
        player: PlayerId,
        book: Address,
        save: Address,
    },
    #[error("the save gives {player} wallet {address}, but wallets.jsonl gives it to {other}")]
    AddressTaken {
        player: PlayerId,
        other: PlayerId,
        address: Address,
    },
    #[error("the save gives {0} wallet {1}, which WALLET_SEED doesn't make (wrong seed?)")]
    NotFromSeed(PlayerId, Address),
}

/// Indexes searched past the known wallets when recovering from the save.
const RECOVERY_SLACK: usize = 1_024;

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::tests::ANVIL_MNEMONIC;

    #[test]
    fn derives_the_standard_path() {
        let root = HdRoot::from_phrase(ANVIL_MNEMONIC).unwrap();
        // anvil's first two accounts come from the same mnemonic at m/44'/60'/0'/0/{0,1}.
        assert_eq!(
            root.signer(0).address(),
            "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
                .parse::<Address>()
                .unwrap()
        );
        assert_eq!(
            root.signer(1).address(),
            "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
                .parse::<Address>()
                .unwrap()
        );
    }

    #[test]
    fn a_lost_book_is_rebuilt_from_the_save_and_never_reuses_an_index() {
        let root = HdRoot::from_phrase(ANVIL_MNEMONIC).unwrap();
        let first = tempfile::tempdir().unwrap();
        let known: Vec<(PlayerId, Address)> = {
            let mut book = WalletBook::open(first.path(), root.clone()).unwrap();
            ["asha", "ben", "cara"]
                .iter()
                .map(|p| (p.to_string(), book.ensure(p).unwrap().address))
                .collect()
        };
        // A new machine: the save (and so `known`) came back from Arkiv, the data dir didn't.
        let fresh = tempfile::tempdir().unwrap();
        // Out of order, as a save's map may give them.
        let shuffled = vec![known[2].clone(), known[0].clone(), known[1].clone()];
        {
            let mut book = WalletBook::open(fresh.path(), root.clone()).unwrap();
            assert_eq!(book.recover(&shuffled).unwrap(), 3);
            for (p, a) in &known {
                assert_eq!(book.get(p).unwrap().address, *a);
            }
            // The next player gets a new wallet, not asha's.
            assert_eq!(book.ensure("dev").unwrap().index, 3);
            // Running it again finds nothing to do.
            assert_eq!(book.recover(&shuffled).unwrap(), 0);
        }
        // And it was written down.
        let book = WalletBook::open(fresh.path(), root).unwrap();
        assert_eq!(book.get("cara").unwrap().index, 2);
        assert_eq!(book.len(), 4);
    }

    #[test]
    fn recovery_refuses_a_book_or_seed_that_disagrees_with_the_save() {
        let root = HdRoot::from_phrase(ANVIL_MNEMONIC).unwrap();
        let dir = tempfile::tempdir().unwrap();
        let mut book = WalletBook::open(dir.path(), root.clone()).unwrap();
        let asha = book.ensure("asha").unwrap().address;
        let ben = root.signer(1).address();
        assert!(matches!(
            book.recover(&[("asha".into(), ben)]),
            Err(WalletError::SaveMismatch { .. })
        ));
        assert!(matches!(
            book.recover(&[("ben".into(), asha)]),
            Err(WalletError::AddressTaken { .. })
        ));
        let stranger: Address = "0x000000000000000000000000000000000000dEaD".parse().unwrap();
        assert!(matches!(
            book.recover(&[("ben".into(), stranger)]),
            Err(WalletError::NotFromSeed(..))
        ));
        assert_eq!(book.len(), 1, "a refused recovery writes nothing");
    }

    #[test]
    fn indexes_assigned_once_and_persisted() {
        let dir = tempfile::tempdir().unwrap();
        let root = HdRoot::from_phrase(ANVIL_MNEMONIC).unwrap();
        let (a, b);
        {
            let mut book = WalletBook::open(dir.path(), root.clone()).unwrap();
            a = book.ensure("asha").unwrap();
            b = book.ensure("ben").unwrap();
            assert_eq!(book.ensure("asha").unwrap(), a);
            assert_eq!((a.index, b.index), (0, 1));
            book.set_label("asha", "asha").unwrap();
            assert_eq!(book.signer("ben").unwrap().address(), b.address);
        }
        let mut book = WalletBook::open(dir.path(), root).unwrap();
        assert_eq!(book.get("asha").unwrap().label.as_deref(), Some("asha"));
        assert_eq!(book.player_of(&b.address).map(String::as_str), Some("ben"));
        assert_eq!(book.ensure("cara").unwrap().index, 2);
        assert_eq!(book.len(), 3);
    }

    #[test]
    fn wrong_seed_refuses_to_load() {
        let dir = tempfile::tempdir().unwrap();
        {
            let mut book =
                WalletBook::open(dir.path(), HdRoot::from_phrase(ANVIL_MNEMONIC).unwrap()).unwrap();
            book.ensure("asha").unwrap();
        }
        let other = HdRoot::from_phrase(
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
        )
        .unwrap();
        assert!(matches!(
            WalletBook::open(dir.path(), other),
            Err(WalletError::SeedMismatch { .. })
        ));
    }

    #[test]
    fn seed_validation_and_redaction() {
        assert!(validate_seed(ANVIL_MNEMONIC).is_ok());
        assert!(validate_seed("one two three").is_err());
        let root = HdRoot::from_phrase(ANVIL_MNEMONIC).unwrap();
        assert_eq!(format!("{root:?}"), "HdRoot(<redacted>)");
    }
}
