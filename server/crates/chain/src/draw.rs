//! The weekly draw's tickets: LuckyLedger's Merkle tree (OpenZeppelin `MerkleProof`, sorted-pair hashing) and the
//! committed ticket lists, kept under `<data dir>/draws/<week>.json` so the winner's proof can be built later.
//!
//! Leaf (LuckyLedger): `keccak256(bytes.concat(keccak256(abi.encode(player, from, to))))` with `[from, to)` half-open.
//! The server's `TicketRange` is inclusive, so the leaf uses `to + 1`.

use crate::store::{read_json, write_json, StoreError};
use alloy::primitives::{keccak256, Address, B256, U256};
use alloy::sol_types::SolValue;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

/// A ticket range bound to the wallet that holds it.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Entry {
    pub player: String,
    pub address: Address,
    /// Inclusive, as the server sends them.
    pub from: u64,
    pub to: u64,
}

impl Entry {
    pub fn leaf(&self) -> B256 {
        leaf(self.address, self.from, self.to)
    }
}

/// LuckyLedger's leaf for tickets `from..=to`.
pub fn leaf(player: Address, from: u64, to_inclusive: u64) -> B256 {
    let inner = keccak256(
        (
            player,
            U256::from(from),
            U256::from(to_inclusive) + U256::from(1u8),
        )
            .abi_encode(),
    );
    keccak256(inner)
}

fn hash_pair(a: B256, b: B256) -> B256 {
    let (x, y) = if a <= b { (a, b) } else { (b, a) };
    let mut buf = [0u8; 64];
    buf[..32].copy_from_slice(x.as_slice());
    buf[32..].copy_from_slice(y.as_slice());
    keccak256(buf)
}

/// A Merkle tree over sorted, de-duplicated leaves. An odd node out is carried up a level unchanged.
#[derive(Clone, Debug)]
pub struct Tree {
    levels: Vec<Vec<B256>>,
}

impl Tree {
    pub fn new(mut leaves: Vec<B256>) -> Option<Tree> {
        leaves.sort();
        leaves.dedup();
        if leaves.is_empty() {
            return None;
        }
        let mut levels = vec![leaves];
        while levels.last().expect("non-empty").len() > 1 {
            let prev = levels.last().expect("non-empty");
            let next = prev
                .chunks(2)
                .map(|c| {
                    if c.len() == 2 {
                        hash_pair(c[0], c[1])
                    } else {
                        c[0]
                    }
                })
                .collect();
            levels.push(next);
        }
        Some(Tree { levels })
    }

    pub fn root(&self) -> B256 {
        self.levels.last().expect("non-empty")[0]
    }

    /// The sibling path for `leaf`, as `MerkleProof.verify` takes it.
    pub fn proof(&self, leaf: B256) -> Option<Vec<B256>> {
        let mut i = self.levels[0].binary_search(&leaf).ok()?;
        let mut proof = vec![];
        for level in &self.levels[..self.levels.len() - 1] {
            let sibling = i ^ 1;
            if sibling < level.len() {
                proof.push(level[sibling]);
            }
            i /= 2;
        }
        Some(proof)
    }
}

/// OpenZeppelin's `MerkleProof.verify`.
pub fn verify(proof: &[B256], root: B256, leaf: B256) -> bool {
    proof.iter().fold(leaf, |acc, p| hash_pair(acc, *p)) == root
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Committed {
    pub week: u64,
    pub root: B256,
    pub entries: Vec<Entry>,
}

fn path(dir: &Path, week: u64) -> PathBuf {
    dir.join("draws").join(format!("{week}.json"))
}

pub fn save(dir: &Path, c: &Committed) -> Result<(), StoreError> {
    write_json(&path(dir, c.week), c)
}

pub fn load(dir: &Path, week: u64) -> Result<Option<Committed>, StoreError> {
    read_json(&path(dir, week))
}

/// Builds the tree for a week's entries.
pub fn tree(entries: &[Entry]) -> Option<Tree> {
    Tree::new(entries.iter().map(Entry::leaf).collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entries(n: u64) -> Vec<Entry> {
        (0..n)
            .map(|i| Entry {
                player: format!("p{i}"),
                address: Address::repeat_byte(i as u8 + 1),
                from: i * 10,
                to: i * 10 + 9,
            })
            .collect()
    }

    #[test]
    fn every_entry_proves_against_the_root() {
        for n in [1, 2, 3, 5, 8, 13] {
            let es = entries(n);
            let t = tree(&es).unwrap();
            for e in &es {
                let p = t.proof(e.leaf()).unwrap();
                assert!(verify(&p, t.root(), e.leaf()), "n={n}");
            }
            assert!(t.proof(leaf(Address::ZERO, 0, 0)).is_none());
        }
        assert!(tree(&[]).is_none());
    }

    #[test]
    fn leaf_is_double_hashed_half_open() {
        let a = Address::repeat_byte(7);
        let inner = keccak256((a, U256::from(5u64), U256::from(10u64)).abi_encode());
        assert_eq!(leaf(a, 5, 9), keccak256(inner));
        // One leaf: the root is the leaf and the proof is empty.
        let t = Tree::new(vec![leaf(a, 5, 9)]).unwrap();
        assert_eq!(t.root(), leaf(a, 5, 9));
        assert!(t.proof(leaf(a, 5, 9)).unwrap().is_empty());
    }

    #[test]
    fn committed_draws_persist() {
        let dir = tempfile::tempdir().unwrap();
        let es = entries(3);
        let c = Committed {
            week: 4,
            root: tree(&es).unwrap().root(),
            entries: es,
        };
        save(dir.path(), &c).unwrap();
        assert_eq!(load(dir.path(), 4).unwrap(), Some(c));
        assert_eq!(load(dir.path(), 5).unwrap(), None);
    }

    /// Cross-checks the tree against OpenZeppelin's `MerkleProof` via `cast` (`forge` isn't needed): skipped without
    /// cast. Uses `cast keccak` on the sorted pair to recompute one level independently.
    #[test]
    fn pair_hash_matches_cast() {
        let Ok(out) = std::process::Command::new("cast").arg("--version").output() else {
            return;
        };
        if !out.status.success() {
            return;
        }
        let (a, b) = (B256::repeat_byte(2), B256::repeat_byte(1));
        let out = std::process::Command::new("cast")
            .args([
                "keccak",
                &format!(
                    "0x{}{}",
                    alloy::primitives::hex::encode(b),
                    alloy::primitives::hex::encode(a)
                ),
            ])
            .output()
            .unwrap();
        assert_eq!(
            String::from_utf8(out.stdout).unwrap().trim(),
            hash_pair(a, b).to_string()
        );
    }
}
