// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {FoodRouter} from "./FoodRouter.sol";

/// @title Farm
/// @notice Tallyport's food supplier (Kofi's farm in the game). Holds the harvest's FOOD and FoodRouter's Seller role.
///         The keeper key sells harvest tranches into the pool through the day; every USDC the sale fetches goes
///         straight to Treasury in the same call. The admin moves stock in (FOOD's supply is fixed at deploy).
/// @dev Holds no USDC between calls. Spec: docs/architecture/spec.json, contract "Farm".
contract Farm is Ownable2Step, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    IERC20 private immutable USDC;
    IERC20 private immutable FOOD;
    /// @notice Where every sale's USDC goes.
    address public immutable treasury;

    /// @notice FoodRouter (replaceable).
    FoodRouter public router;
    /// @notice The only key allowed to sell.
    address public keeper;

    /// @notice A harvest tranche was offered to the pool. sold below offered means today's limit was reached;
    ///         usdc (base units) went to Treasury.
    event HarvestSold(bytes32 indexed ref, uint256 offered, uint256 sold, uint256 usdc);
    /// @notice FOOD was moved into the farm's stock.
    event Restocked(address indexed from, uint256 food);
    event KeeperSet(address indexed oldKeeper, address indexed newKeeper);
    event RouterSet(address indexed oldRouter, address indexed newRouter);

    /// @notice Only the keeper key may sell the harvest.
    error Farm__NotKeeper(address sender, address keeper);
    /// @notice Asked to sell or stock nothing.
    error Farm__ZeroAmount();
    /// @notice The farm holds less FOOD than offered (base units).
    error Farm__NotEnoughStock(uint256 offered, uint256 stock);
    /// @notice An address that must be set was zero.
    error Farm__ZeroAddress();
    /// @notice The admin role can be handed over, but never thrown away.
    error Farm__AdminCantBeRemoved();

    constructor(FoodRouter router_, IERC20 usdc, IERC20 foodToken, address treasury_, address keeper_, address admin)
        Ownable(admin)
    {
        if (
            address(router_) == address(0) || address(usdc) == address(0) || address(foodToken) == address(0)
                || treasury_ == address(0) || keeper_ == address(0)
        ) revert Farm__ZeroAddress();
        USDC = usdc;
        FOOD = foodToken;
        treasury = treasury_;
        router = router_;
        keeper = keeper_;
        emit RouterSet(address(0), address(router_));
        emit KeeperSet(address(0), keeper_);
    }

    /// @notice Sells up to `food` of the harvest into the pool (stopping at today's limit) and sends the USDC to
    ///         Treasury. A ref works once (FoodRouter keeps the refs).
    /// @return sold FOOD actually sold (base units).
    /// @return usdc USDC sent to Treasury (base units).
    function sell(uint256 food, bytes32 ref) external nonReentrant returns (uint256 sold, uint256 usdc) {
        if (msg.sender != keeper) revert Farm__NotKeeper(msg.sender, keeper);
        if (food == 0) revert Farm__ZeroAmount();
        uint256 held = FOOD.balanceOf(address(this));
        if (held < food) revert Farm__NotEnoughStock(food, held);

        FoodRouter currentRouter = router;
        FOOD.forceApprove(address(currentRouter), food);
        (sold, usdc) = currentRouter.sellFood(food, ref);
        FOOD.forceApprove(address(currentRouter), 0);

        if (usdc != 0) USDC.safeTransfer(treasury, usdc);
        // forge-lint: disable-next-line(reentrancy-events) nonReentrant guards the sale
        emit HarvestSold(ref, food, sold, usdc);
    }

    /// @notice Moves `food` FOOD from the caller (the admin) into the farm's stock.
    function restock(uint256 food) external onlyOwner {
        if (food == 0) revert Farm__ZeroAmount();
        FOOD.safeTransferFrom(msg.sender, address(this), food);
        emit Restocked(msg.sender, food);
    }

    /// @notice Replaces the keeper key. This is the off switch for selling.
    function setKeeper(address newKeeper) external onlyOwner {
        if (newKeeper == address(0)) revert Farm__ZeroAddress();
        address old = keeper;
        keeper = newKeeper;
        emit KeeperSet(old, newKeeper);
    }

    /// @notice Points the farm at a replacement FoodRouter (which must give it the Seller role).
    function setRouter(FoodRouter newRouter) external onlyOwner {
        if (address(newRouter) == address(0)) revert Farm__ZeroAddress();
        emit RouterSet(address(router), address(newRouter));
        router = newRouter;
    }

    /// @notice Always refuses. Without an admin, a leaked keeper key could never be replaced.
    function renounceOwnership() public pure override {
        revert Farm__AdminCantBeRemoved();
    }

    /// @notice FOOD the farm holds (base units).
    function stock() external view returns (uint256) {
        return FOOD.balanceOf(address(this));
    }
}
