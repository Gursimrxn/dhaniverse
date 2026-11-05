// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice A server-signed permission for one player to buy one meal (build spec 2.2). Amounts in base units.
struct MealTicket {
    address player;
    bytes32 item; // keccak256(utf8(menu item name)), e.g. keccak256("thali")
    uint256 food; // FOOD base units in the meal
    uint256 maxUsdc; // the most the player will pay, USDC base units
    bytes32 ref; // keccak256(utf8(server ref string)); works once
    uint64 expiry; // unix seconds
}

/// @notice A server-signed house payout (build spec 2.5). `source`: 0 FIXED, 1 SURPRISE, 2 SAFETY.
struct PayoutVoucher {
    address player;
    bytes32 humanId; // the World ID nullifier hash; never zero
    uint8 source;
    uint256 amount; // USDC base units
    bytes32 ref;
    uint64 expiry;
}

/// @notice A server-signed payout from one sponsor campaign (build spec 2.6, 2.13).
struct CampaignClaim {
    uint256 campaignId;
    address player;
    bytes32 humanId;
    uint256 amount; // USDC base units, at most the campaign's payoutPerClaim
    bytes32 ref;
    uint64 expiry;
}

/// @notice A server-signed advance ("cargo") from one sponsor campaign, repaid from the human's next claim.
struct AdvanceVoucher {
    uint256 campaignId;
    address player;
    bytes32 humanId;
    uint256 amount; // USDC base units, at most CampaignEscrow.maxAdvance
    bytes32 ref;
    uint64 expiry;
}

/// @title Vouchers
/// @notice The EIP-712 type strings of build spec 2.13, and the struct hashes our contracts verify. The domain is
///         {name: "Tallyport", version: "1", chainId, verifyingContract} for each verifying contract.
library Vouchers {
    bytes32 internal constant MEAL_TICKET_TYPEHASH =
        keccak256("MealTicket(address player,bytes32 item,uint256 food,uint256 maxUsdc,bytes32 ref,uint64 expiry)");
    bytes32 internal constant PAYOUT_VOUCHER_TYPEHASH = keccak256(
        "PayoutVoucher(address player,bytes32 humanId,uint8 source,uint256 amount,bytes32 ref,uint64 expiry)"
    );
    bytes32 internal constant CAMPAIGN_CLAIM_TYPEHASH = keccak256(
        "CampaignClaim(uint256 campaignId,address player,bytes32 humanId,uint256 amount,bytes32 ref,uint64 expiry)"
    );
    bytes32 internal constant ADVANCE_VOUCHER_TYPEHASH = keccak256(
        "AdvanceVoucher(uint256 campaignId,address player,bytes32 humanId,uint256 amount,bytes32 ref,uint64 expiry)"
    );

    /// @notice The EIP-712 domain name and version every Tallyport contract signs under.
    string internal constant DOMAIN_NAME = "Tallyport";
    string internal constant DOMAIN_VERSION = "1";

    function hash(MealTicket calldata t) internal pure returns (bytes32) {
        return keccak256(abi.encode(MEAL_TICKET_TYPEHASH, t.player, t.item, t.food, t.maxUsdc, t.ref, t.expiry));
    }

    function hash(PayoutVoucher calldata v) internal pure returns (bytes32) {
        return keccak256(abi.encode(PAYOUT_VOUCHER_TYPEHASH, v.player, v.humanId, v.source, v.amount, v.ref, v.expiry));
    }

    function hash(CampaignClaim calldata c) internal pure returns (bytes32) {
        return
            keccak256(abi.encode(CAMPAIGN_CLAIM_TYPEHASH, c.campaignId, c.player, c.humanId, c.amount, c.ref, c.expiry));
    }

    function hash(AdvanceVoucher calldata a) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(ADVANCE_VOUCHER_TYPEHASH, a.campaignId, a.player, a.humanId, a.amount, a.ref, a.expiry)
            );
    }
}
