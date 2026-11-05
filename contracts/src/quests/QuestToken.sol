// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @title QuestToken (MANGO for the demo)
/// @notice The demo sponsor's token: a plain ERC-20 (18 decimals, EIP-2612 permit) the admin can mint. It trades in a
///         plain Uniswap v4 pool against USDC (fee 0.3%, no hook), so a Spice Run swap goes through Uniswap's real
///         Universal Router. In production the sponsor brings their own token and pool.
/// @dev Spec: docs/architecture/spec.json, contract "QuestToken".
contract QuestToken is ERC20, ERC20Permit, Ownable2Step {
    /// @notice Asked to mint nothing.
    error QuestToken__ZeroAmount();
    /// @notice The admin role can be handed over, but never thrown away.
    error QuestToken__AdminCantBeRemoved();

    constructor(string memory name_, string memory symbol_, address admin)
        ERC20(name_, symbol_)
        ERC20Permit(name_)
        Ownable(admin)
    {}

    /// @notice Mints `amount` (18-decimal base units) to `to`. Emits Transfer(0, to, amount).
    function mint(address to, uint256 amount) external onlyOwner {
        if (amount == 0) revert QuestToken__ZeroAmount();
        _mint(to, amount);
    }

    /// @notice Always refuses.
    function renounceOwnership() public pure override {
        revert QuestToken__AdminCantBeRemoved();
    }
}
