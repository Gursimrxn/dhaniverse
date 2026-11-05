// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title FoodToken (FOOD)
/// @notice 1 FOOD is one serving of Tallyport's food. Every FOOD that will ever exist is created once, at deploy,
///         and handed to one holder (the admin key), who gives stock to the supplier and the pool.
///         Nobody can make more. Eaten FOOD is burned, so the town's food supply really shrinks.
/// @dev A plain ERC-20 with 6 decimals, like USDC. No owner, no mint, no pause, no upgrade: there is nothing
///      to switch off and nothing anyone can change. Spec: docs/architecture/spec.json, contract "FoodToken".
contract FoodToken is ERC20 {
    /// @notice FOOD uses 6 decimals, the same as USDC, so 1 FOOD = 1,000,000 base units.
    uint8 private constant DECIMALS = 6;

    /// @notice A deploy with no FOOD at all is a mistake, so it is refused.
    error FoodToken__ZeroSupply();

    /// @param holder Receives the whole supply. OpenZeppelin refuses the zero address (ERC20InvalidReceiver).
    /// @param supply Every FOOD there will ever be, in base units (6 decimals).
    constructor(address holder, uint256 supply) ERC20("Dhaniverse Food", "FOOD") {
        if (supply == 0) revert FoodToken__ZeroSupply();
        _mint(holder, supply);
    }

    /// @notice Destroys `amount` of the caller's own FOOD. FoodRouter calls this for food that has been eaten.
    /// @dev Emits Transfer(caller, address(0), amount). Reverts with ERC20InsufficientBalance if the caller has less.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
}
