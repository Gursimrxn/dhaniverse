// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title FoodToken (FOOD)
/// @notice 1 FOOD is one serving of Tallyport's food. Every FOOD that will ever exist is created once, at deploy,
///         and handed to one holder (the admin key), who gives stock to the supplier and the pool.
///         Nobody can make more. Eaten FOOD is burned, so the town's food supply really shrinks.
///         FOOD only exists inside the game: a transfer goes through only if BOTH the sender and the receiver are on
///         the allowlist (Uniswap's PoolManager, FoodRouter, Farm, MealCounter and the holder). Both sides, not
///         either, because the PoolManager can `take` tokens out to any address: with both sides an outsider can
///         never receive FOOD, so no other pool can ever be seeded and nobody outside the game can hold it.
///         The holder sets the allowlist once at deploy and then locks it forever.
/// @dev 6 decimals, like USDC. No mint after deploy, no pause, no upgrade. Minting (deploy only) and burning are the
///      only movements that skip the allowlist. Spec: docs/architecture/spec.json, contract "FoodToken".
contract FoodToken is ERC20 {
    /// @notice FOOD uses 6 decimals, the same as USDC, so 1 FOOD = 1,000,000 base units.
    uint8 private constant DECIMALS = 6;

    /// @dev The holder at deploy: the only key that may set the allowlist, and only until it locks it.
    address private immutable ALLOWLISTER;
    /// @notice True once the allowlist can never change again.
    bool public allowlistLocked;
    /// @notice Who may send and receive FOOD.
    mapping(address account => bool) public allowed;

    /// @notice An address was put on, or taken off, the allowlist.
    event AllowedSet(address indexed account, bool allowed);
    /// @notice The allowlist is locked for good.
    event AllowlistLocked();

    /// @notice A deploy with no FOOD at all is a mistake, so it is refused.
    error FoodToken__ZeroSupply();
    /// @notice The holder sets the allowlist, so it can't be the zero address.
    error FoodToken__ZeroHolder();
    /// @notice FOOD can't move to or from this address: it isn't part of the game.
    error FoodToken__NotAllowed(address account);
    /// @notice Only the allowlister may change the allowlist.
    error FoodToken__NotAllowlister(address caller);
    /// @notice The allowlist is locked and can never change again.
    error FoodToken__AllowlistLocked();

    /// @param holder Receives the whole supply, is on the allowlist and sets the rest of it.
    /// @param supply Every FOOD there will ever be, in base units (6 decimals).
    constructor(address holder, uint256 supply) ERC20("Dhaniverse Food", "FOOD") {
        if (holder == address(0)) revert FoodToken__ZeroHolder();
        if (supply == 0) revert FoodToken__ZeroSupply();
        ALLOWLISTER = holder;
        allowed[holder] = true;
        emit AllowedSet(holder, true);
        _mint(holder, supply);
    }

    /// @notice Puts `account` on the allowlist, or takes it off. Only before the allowlist is locked.
    function setAllowed(address account, bool ok) external {
        _onlyAllowlister();
        allowed[account] = ok;
        emit AllowedSet(account, ok);
    }

    /// @notice Locks the allowlist forever. After this, nothing about who may hold FOOD can change.
    function lockAllowlist() external {
        _onlyAllowlister();
        allowlistLocked = true;
        emit AllowlistLocked();
    }

    /// @notice The holder at deploy: the only key that may set the allowlist, and only until it locks it.
    function allowlister() external view returns (address) {
        return ALLOWLISTER;
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

    /// @dev Every transfer (including transferFrom) needs both sides on the allowlist. Mint and burn don't.
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            if (!allowed[from]) revert FoodToken__NotAllowed(from);
            if (!allowed[to]) revert FoodToken__NotAllowed(to);
        }
        super._update(from, to, value);
    }

    function _onlyAllowlister() private view {
        if (msg.sender != ALLOWLISTER) revert FoodToken__NotAllowlister(msg.sender);
        if (allowlistLocked) revert FoodToken__AllowlistLocked();
    }
}
