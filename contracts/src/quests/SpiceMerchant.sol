// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {ICampaignBook} from "../money/Links.sol";

/// @title SpiceMerchant (a QuestDelivery)
/// @notice The Spice Run's NPC, at spice-merchant.tallyport.eth. The player delivers the quest token they bought on
///         Uniswap (e.g. MANGO); the merchant forwards it straight to the campaign's `deliverTo` and records the
///         delivery. The server then checks the player's Uniswap swap in the chain logs and signs the claim voucher
///         (cargo back + reward = the campaign's payoutPerClaim), which CampaignEscrow pays.
/// @dev Holds nothing and has no admin. A quest ref works once. Spec: docs/architecture/spec.json, "SpiceMerchant".
contract SpiceMerchant is ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    /// @notice CampaignEscrow, which says where each campaign's deliveries go.
    ICampaignBook public immutable escrow;

    mapping(bytes32 questRef => bool) private _refUsed;

    /// @notice A player delivered `amount` of `token` for a campaign's quest; it went to the campaign's deliverTo.
    event Delivered(
        uint256 indexed campaignId, address indexed player, address indexed token, uint256 amount, bytes32 questRef
    );

    /// @notice The campaign isn't running (unknown, not started, ended, paused, cancelled or refunded).
    error SpiceMerchant__CampaignNotLive(uint256 campaignId);
    /// @notice The delivered token isn't the campaign's quest token.
    error SpiceMerchant__WrongToken(address token, address questToken);
    /// @notice This quest ref was already delivered: the retry was blocked.
    error SpiceMerchant__RefUsed(bytes32 questRef);
    /// @notice Asked to deliver nothing.
    error SpiceMerchant__ZeroAmount();
    /// @notice An address that must be set was zero.
    error SpiceMerchant__ZeroAddress();

    constructor(ICampaignBook escrow_) {
        if (address(escrow_) == address(0)) revert SpiceMerchant__ZeroAddress();
        escrow = escrow_;
    }

    /// @notice The player (msg.sender) delivers `amount` of `token` for campaign `campaignId`. The player must have
    ///         approved this contract for the token, which must be the campaign's questToken.
    function deliver(uint256 campaignId, address token, uint256 amount, bytes32 questRef) external nonReentrant {
        if (token == address(0)) revert SpiceMerchant__ZeroAddress();
        if (amount == 0) revert SpiceMerchant__ZeroAmount();
        if (_refUsed[questRef]) revert SpiceMerchant__RefUsed(questRef);
        if (!escrow.isLive(campaignId)) revert SpiceMerchant__CampaignNotLive(campaignId);
        address expected = escrow.questToken(campaignId);
        if (token != expected) revert SpiceMerchant__WrongToken(token, expected);
        address to = escrow.deliverTo(campaignId);

        _refUsed[questRef] = true;
        IERC20(token).safeTransferFrom(msg.sender, to, amount);
        emit Delivered(campaignId, msg.sender, token, amount, questRef);
    }

    /// @notice Whether a quest ref has been delivered.
    function refUsed(bytes32 questRef) external view returns (bool) {
        return _refUsed[questRef];
    }
}
