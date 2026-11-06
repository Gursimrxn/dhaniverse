//! EIP-712 tickets and vouchers (spec §2.13): domain `{name: "Tallyport", version: "1", chainId, verifyingContract}`.

use crate::bindings::{AdvanceVoucher, CampaignClaim, MealTicket, PayoutVoucher};
use alloy::primitives::{keccak256, Address, Bytes, B256};
use alloy::signers::local::PrivateKeySigner;
use alloy::signers::SignerSync;
use alloy::sol_types::{Eip712Domain, SolValue};
use std::borrow::Cow;

/// `ref = keccak256(utf8(server_ref_string))`.
pub fn ref_hash(server_ref: &str) -> B256 {
    keccak256(server_ref.as_bytes())
}

/// `item = keccak256(utf8(menu item name))`.
pub fn item_hash(item: &str) -> B256 {
    keccak256(item.as_bytes())
}

/// The Tallyport domain for one verifying contract.
pub fn domain(chain_id: u64, verifying_contract: Address) -> Eip712Domain {
    Eip712Domain {
        name: Some(Cow::Borrowed("Tallyport")),
        version: Some(Cow::Borrowed("1")),
        chain_id: Some(alloy::primitives::U256::from(chain_id)),
        verifying_contract: Some(verifying_contract),
        salt: None,
    }
}

/// A struct signed under EIP-712. The type strings are spelled out here rather than taken from `sol!`, because
/// `sol!` renders a field named `ref` as `r#ref` in the type string, which would never match the contracts.
pub trait Typed {
    /// The EIP-712 type string, exactly as in spec §2.13.
    const TYPE: &'static str;
    /// `abi.encode` of the fields in order (every field is a static type, so this is EIP-712 `encodeData`).
    fn encode_data(&self) -> Vec<u8>;

    fn type_hash() -> B256 {
        keccak256(Self::TYPE.as_bytes())
    }

    /// `hashStruct(s) = keccak256(typeHash || encodeData(s))`.
    fn struct_hash(&self) -> B256 {
        let mut buf = Self::type_hash().to_vec();
        buf.extend_from_slice(&self.encode_data());
        keccak256(&buf)
    }

    /// `keccak256(0x1901 || domainSeparator || hashStruct(s))`.
    fn signing_hash(&self, domain: &Eip712Domain) -> B256 {
        let mut buf = vec![0x19, 0x01];
        buf.extend_from_slice(domain.separator().as_slice());
        buf.extend_from_slice(self.struct_hash().as_slice());
        keccak256(&buf)
    }
}

impl Typed for MealTicket {
    const TYPE: &'static str =
        "MealTicket(address player,bytes32 item,uint256 food,uint256 maxUsdc,bytes32 ref,uint64 expiry)";
    fn encode_data(&self) -> Vec<u8> {
        (
            self.player,
            self.item,
            self.food,
            self.maxUsdc,
            self.r#ref,
            self.expiry,
        )
            .abi_encode()
    }
}

impl Typed for PayoutVoucher {
    const TYPE: &'static str =
        "PayoutVoucher(address player,bytes32 humanId,uint8 source,uint256 amount,bytes32 ref,uint64 expiry)";
    fn encode_data(&self) -> Vec<u8> {
        // uint8 encodes as one left-padded word, the same as a uint256 of the same value.
        let source = alloy::primitives::U256::from(self.source);
        (
            self.player,
            self.humanId,
            source,
            self.amount,
            self.r#ref,
            self.expiry,
        )
            .abi_encode()
    }
}

impl Typed for CampaignClaim {
    const TYPE: &'static str =
        "CampaignClaim(uint256 campaignId,address player,bytes32 humanId,uint256 amount,bytes32 ref,uint64 expiry)";
    fn encode_data(&self) -> Vec<u8> {
        (
            self.campaignId,
            self.player,
            self.humanId,
            self.amount,
            self.r#ref,
            self.expiry,
        )
            .abi_encode()
    }
}

impl Typed for AdvanceVoucher {
    const TYPE: &'static str =
        "AdvanceVoucher(uint256 campaignId,address player,bytes32 humanId,uint256 amount,bytes32 ref,uint64 expiry)";
    fn encode_data(&self) -> Vec<u8> {
        (
            self.campaignId,
            self.player,
            self.humanId,
            self.amount,
            self.r#ref,
            self.expiry,
        )
            .abi_encode()
    }
}

/// The 65-byte `r || s || v` signature (v = 27/28) the contracts' ECDSA check takes, over the EIP-712 digest.
pub fn sign<T: Typed>(signer: &PrivateKeySigner, value: &T, domain: &Eip712Domain) -> Bytes {
    let digest = value.signing_hash(domain);
    let sig = signer
        .sign_hash_sync(&digest)
        .expect("local secp256k1 signing cannot fail");
    Bytes::from(sig.as_bytes().to_vec())
}

/// Recovers the signer of a 65-byte signature over `value`.
pub fn recover<T: Typed>(value: &T, domain: &Eip712Domain, sig: &[u8]) -> Option<Address> {
    let sig = alloy::primitives::Signature::try_from(sig).ok()?;
    sig.recover_address_from_prehash(&value.signing_hash(domain))
        .ok()
}

/// A ticket or voucher signer for one chain.
#[derive(Clone)]
pub struct VoucherSigner {
    signer: PrivateKeySigner,
    chain_id: u64,
}

impl std::fmt::Debug for VoucherSigner {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "VoucherSigner({}, chain {})",
            self.signer.address(),
            self.chain_id
        )
    }
}

impl VoucherSigner {
    pub fn new(signer: PrivateKeySigner, chain_id: u64) -> VoucherSigner {
        VoucherSigner { signer, chain_id }
    }

    pub fn address(&self) -> Address {
        self.signer.address()
    }

    pub fn meal_ticket(&self, meal_counter: Address, t: &MealTicket) -> Bytes {
        sign(&self.signer, t, &domain(self.chain_id, meal_counter))
    }

    pub fn payout(&self, house_pool: Address, v: &PayoutVoucher) -> Bytes {
        sign(&self.signer, v, &domain(self.chain_id, house_pool))
    }

    pub fn campaign_claim(&self, escrow: Address, c: &CampaignClaim) -> Bytes {
        sign(&self.signer, c, &domain(self.chain_id, escrow))
    }

    pub fn advance(&self, escrow: Address, a: &AdvanceVoucher) -> Bytes {
        sign(&self.signer, a, &domain(self.chain_id, escrow))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::tests::ANVIL_KEYS;
    use alloy::primitives::{address, b256, U256};

    fn ticket() -> MealTicket {
        MealTicket {
            player: address!("70997970C51812dc3A010C7d01b50e0d17dc79C8"),
            item: item_hash("chai"),
            food: U256::from(1_000_000u64),
            maxUsdc: U256::from(4_080u64),
            r#ref: ref_hash("meal:asha:1"),
            expiry: 1_800_000_000,
        }
    }

    #[test]
    fn type_strings_are_exactly_the_spec() {
        assert_eq!(
            MealTicket::TYPE,
            "MealTicket(address player,bytes32 item,uint256 food,uint256 maxUsdc,bytes32 ref,uint64 expiry)"
        );
        assert_eq!(
            PayoutVoucher::TYPE,
            "PayoutVoucher(address player,bytes32 humanId,uint8 source,uint256 amount,bytes32 ref,uint64 expiry)"
        );
        assert_eq!(
            CampaignClaim::TYPE,
            "CampaignClaim(uint256 campaignId,address player,bytes32 humanId,uint256 amount,bytes32 ref,uint64 expiry)"
        );
        assert_eq!(
            AdvanceVoucher::TYPE,
            "AdvanceVoucher(uint256 campaignId,address player,bytes32 humanId,uint256 amount,bytes32 ref,uint64 expiry)"
        );
        // The structs in bindings.rs have the same fields in the same order: sol!'s rendering differs only in
        // spelling `ref` as `r#ref` (the reason `Typed` exists).
        use alloy::sol_types::SolStruct;
        assert_eq!(
            MealTicket::eip712_encode_type().replace("r#ref", "ref"),
            MealTicket::TYPE
        );
        assert_eq!(
            PayoutVoucher::eip712_encode_type().replace("r#ref", "ref"),
            PayoutVoucher::TYPE
        );
        assert_eq!(
            CampaignClaim::eip712_encode_type().replace("r#ref", "ref"),
            CampaignClaim::TYPE
        );
        assert_eq!(
            AdvanceVoucher::eip712_encode_type().replace("r#ref", "ref"),
            AdvanceVoucher::TYPE
        );
        let t = ticket();
        assert_eq!(t.encode_data(), t.eip712_encode_data());
    }

    #[test]
    fn hashes_of_strings() {
        assert_eq!(
            ref_hash(""),
            b256!("c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
        );
        assert_eq!(item_hash("chai"), keccak256(b"chai"));
    }

    #[test]
    fn domain_separator_matches_manual_encoding() {
        let mc = address!("5FbDB2315678afecb367f032d93F642f64180aa3");
        let d = domain(31_337, mc);
        let type_hash = keccak256(
            b"EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)",
        );
        let mut enc = Vec::new();
        enc.extend_from_slice(type_hash.as_slice());
        enc.extend_from_slice(keccak256(b"Tallyport").as_slice());
        enc.extend_from_slice(keccak256(b"1").as_slice());
        enc.extend_from_slice(&U256::from(31_337u64).to_be_bytes::<32>());
        enc.extend_from_slice(B256::left_padding_from(mc.as_slice()).as_slice());
        assert_eq!(d.separator(), keccak256(&enc));
    }

    #[test]
    fn signatures_recover_to_the_signer_and_bind_the_domain() {
        let signer: PrivateKeySigner = ANVIL_KEYS[1].parse().unwrap();
        let vs = VoucherSigner::new(signer.clone(), 31_337);
        let mc = address!("5FbDB2315678afecb367f032d93F642f64180aa3");
        let t = ticket();
        let sig = vs.meal_ticket(mc, &t);
        assert_eq!(sig.len(), 65);
        assert!(sig[64] == 27 || sig[64] == 28);
        assert_eq!(
            recover(&t, &domain(31_337, mc), &sig),
            Some(signer.address())
        );
        let other = address!("e7f1725E7734CE288F8367e1Bb143E90bb3F0512");
        assert_ne!(
            recover(&t, &domain(31_337, other), &sig),
            Some(signer.address())
        );
        assert_ne!(
            recover(&t, &domain(11_155_111, mc), &sig),
            Some(signer.address())
        );

        let v = PayoutVoucher {
            player: t.player,
            humanId: B256::repeat_byte(7),
            source: 1,
            amount: U256::from(250_000u64),
            r#ref: ref_hash("chest:asha:1"),
            expiry: 1_800_000_000,
        };
        let sig = vs.payout(other, &v);
        assert_eq!(
            recover(&v, &domain(31_337, other), &sig),
            Some(signer.address())
        );
    }

    /// Cross-checks the digest against Foundry's independent EIP-712 implementation (`cast hash-message`-free path:
    /// `cast wallet sign --data` signs typed data from JSON). Skips when `cast` isn't on PATH.
    #[test]
    fn signature_matches_cast() {
        let Ok(out) = std::process::Command::new("cast").arg("--version").output() else {
            eprintln!("skip: cast not on PATH");
            return;
        };
        if !out.status.success() {
            return;
        }
        let t = ticket();
        let mc = address!("5FbDB2315678afecb367f032d93F642f64180aa3");
        let typed = serde_json::json!({
            "types": {
                "EIP712Domain": [
                    {"name": "name", "type": "string"}, {"name": "version", "type": "string"},
                    {"name": "chainId", "type": "uint256"}, {"name": "verifyingContract", "type": "address"}
                ],
                "MealTicket": [
                    {"name": "player", "type": "address"}, {"name": "item", "type": "bytes32"},
                    {"name": "food", "type": "uint256"}, {"name": "maxUsdc", "type": "uint256"},
                    {"name": "ref", "type": "bytes32"}, {"name": "expiry", "type": "uint64"}
                ]
            },
            "primaryType": "MealTicket",
            "domain": {"name": "Tallyport", "version": "1", "chainId": 31337, "verifyingContract": mc.to_string()},
            "message": {
                "player": t.player.to_string(), "item": t.item.to_string(), "food": t.food.to_string(),
                "maxUsdc": t.maxUsdc.to_string(), "ref": t.r#ref.to_string(), "expiry": t.expiry
            }
        });
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("ticket.json");
        std::fs::write(&file, typed.to_string()).unwrap();
        let out = std::process::Command::new("cast")
            .args(["wallet", "sign", "--data", "--from-file"])
            .arg(&file)
            .args(["--private-key", ANVIL_KEYS[1]])
            .output()
            .unwrap();
        assert!(
            out.status.success(),
            "cast failed: {}",
            String::from_utf8_lossy(&out.stderr)
        );
        let from_cast = String::from_utf8(out.stdout).unwrap().trim().to_string();
        let signer: PrivateKeySigner = ANVIL_KEYS[1].parse().unwrap();
        let ours = sign(&signer, &t, &domain(31_337, mc));
        assert_eq!(from_cast, ours.to_string());
    }
}
