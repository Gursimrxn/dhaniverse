// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {CustomRevert} from "@uniswap/v4-core/src/libraries/CustomRevert.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TestKit} from "./TestKit.sol";
import {FoodToken} from "../../src/food/FoodToken.sol";
import {FoodHook} from "../../src/food/FoodHook.sol";

/// @notice The food market's world for tests: a local PoolManager, FOOD, and helpers to deploy FoodHook and read
///         prices. FoodHook's and FoodRouter's tests both build on it, so they set up the same world the same way.
///         Each test file runs twice, with FOOD sorting first and then second in the pool (see foodAddress).
abstract contract FoodWorld is TestKit {
    // Launch settings (build spec 2.1), in USDC base units per whole FOOD.
    uint256 internal constant FLOOR = 2000; // $0.002 per FOOD
    uint256 internal constant CEILING = 8000; // $0.008
    uint256 internal constant START = 4000; // $0.004: the base price
    uint256 internal constant BAND_BPS = 1500; // 15% a day either way
    uint256 internal constant DAY = 1 hours; // founder, 28 Oct
    uint24 internal constant NO_FEE = 0; // founder, 28 Oct
    int24 internal constant TICK_SPACING = 60;
    uint160 internal constant HOOK_FLAGS =
        Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG;
    uint256 internal constant FOOD_SUPPLY = 100_000_000 * ONE_FOOD;

    // The pool starts with about 5,000 FOOD and 20 USDC: full range, at $0.004 per FOOD.
    uint128 internal constant STARTING_LIQUIDITY = 316_227_766;

    // Where FoodToken is deployed decides the pool's token order. MockUSDC lands at an ordinary CREATE address,
    // which sorts between these two (checked in _setUpWorld).
    address internal constant FOOD_SORTS_FIRST = address(uint160(0x1000) << 144);
    address internal constant FOOD_SORTS_SECOND = address(uint160(0xF000) << 144);

    /// @dev The two keys that trade in these tests: the Buyer and Seller roles (MealCounter and Farm in production).
    address internal buyer;
    address internal seller;

    PoolManager internal manager;
    FoodToken internal foodToken;
    FoodHook internal hook;
    PoolKey internal key;
    bool internal foodFirst;

    function foodAddress() internal pure virtual returns (address);

    /// @dev A PoolManager and FOOD (all of it held by the admin key). No hook or pool yet.
    function _setUpWorld() internal {
        buyer = makeAddr("buyer key");
        seller = makeAddr("seller key");
        manager = deployPoolManager();
        deployCodeTo("FoodToken.sol:FoodToken", abi.encode(admin, FOOD_SUPPLY), foodAddress());
        foodToken = FoodToken(foodAddress());
        vm.label(foodAddress(), "FOOD");
        // These market tests trade straight from the two keys, so they're on FOOD's allowlist (left unlocked).
        vm.startPrank(admin);
        foodToken.setAllowed(address(manager), true);
        foodToken.setAllowed(buyer, true);
        foodToken.setAllowed(seller, true);
        vm.stopPrank();
        foodFirst = foodAddress() < address(usdc);
        require(FOOD_SORTS_FIRST < address(usdc) && address(usdc) < FOOD_SORTS_SECOND, "USDC must sort in between");
    }

    function usdcC() internal view returns (Currency) {
        return Currency.wrap(address(usdc));
    }

    function foodC() internal view returns (Currency) {
        return Currency.wrap(foodAddress());
    }

    /// @dev Deploys FoodHook at an address carrying its four permission bits. `tag` makes each address different.
    function _deployHook(uint160 tag, address hookRouter) internal returns (FoodHook deployed) {
        address at = address(HOOK_FLAGS | (tag << 144));
        bytes memory args = abi.encode(manager, admin, hookRouter, usdcC(), foodC(), FLOOR, CEILING, BAND_BPS, DAY);
        deployCodeTo("FoodHook.sol:FoodHook", args, at);
        deployed = FoodHook(at);
        vm.label(at, "FoodHook");
    }

    function _key(FoodHook forHook, Currency other, int24 spacing) internal view returns (PoolKey memory) {
        (Currency c0, Currency c1) = other < usdcC() ? (other, usdcC()) : (usdcC(), other);
        return PoolKey(c0, c1, NO_FEE, spacing, IHooks(address(forHook)));
    }

    /// @dev USDC per FOOD -> sqrtPriceX96 in this pool's token order (same maths as the hook).
    function _sqrtFor(uint256 price) internal view returns (uint160) {
        uint256 x192 = foodFirst ? Math.mulDiv(price, 1 << 192, ONE_FOOD) : Math.mulDiv(ONE_FOOD, 1 << 192, price);
        return uint160(Math.sqrt(x192));
    }

    /// @dev The live price, in USDC base units per FOOD.
    function _price() internal view returns (uint256) {
        (,, uint160 live) = hook.band();
        return hook.usdcPerFood(live);
    }

    function _fullRange(int256 liquidity) internal pure returns (IPoolManager.ModifyLiquidityParams memory) {
        return IPoolManager.ModifyLiquidityParams(
            TickMath.minUsableTick(TICK_SPACING), TickMath.maxUsableTick(TICK_SPACING), liquidity, 0
        );
    }

    function _approve(address who, address spender) internal {
        vm.startPrank(who);
        usdc.approve(spender, type(uint256).max);
        foodToken.approve(spender, type(uint256).max);
        vm.stopPrank();
    }

    /// @dev Uniswap wraps a hook's refusal: WrappedError(hook, hook function, our error, HookCallFailed).
    function _expectWrapped(address target, bytes4 hookFn, bytes memory reason) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                target,
                hookFn,
                reason,
                abi.encodePacked(Hooks.HookCallFailed.selector)
            )
        );
    }
}
