// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TownWorld} from "../kit/TownWorld.sol";
import {TestRouter} from "../kit/TestRouter.sol";
import {FoodToken} from "../../src/food/FoodToken.sol";
import {FoodHook} from "../../src/food/FoodHook.sol";

/// @dev An outsider's contract that opens the PoolManager and asks it to hand FOOD to an outsider.
contract FoodTaker is IUnlockCallback {
    IPoolManager internal immutable manager;
    Currency internal immutable food;
    address internal immutable to;

    constructor(IPoolManager manager_, Currency food_, address to_) {
        manager = manager_;
        food = food_;
        to = to_;
    }

    function run() external {
        manager.unlock("");
    }

    function unlockCallback(bytes calldata) external returns (bytes memory) {
        manager.take(food, to, 1);
        return "";
    }
}

/// @notice The founder's rule: FOOD can never be bought, held or traded outside the game. Both sides of every
///         transfer must be on FOOD's allowlist, which is locked after deploy (TownWorld deploys it like Deploy.s.sol).
contract FoodLockdownTest is TownWorld {
    Currency internal foodC;

    function setUp() public override {
        super.setUp();
        foodC = Currency.wrap(address(foodToken));
    }

    // ---------------------------------------------------------------- the allowlist

    function test_allowlist_holdsExactlyTheGamesContracts() public view {
        assertTrue(foodToken.allowed(admin), "deploy holder");
        assertTrue(foodToken.allowed(address(manager)), "PoolManager");
        assertTrue(foodToken.allowed(address(router)), "FoodRouter");
        assertTrue(foodToken.allowed(address(mealCounter)), "MealCounter");
        assertTrue(foodToken.allowed(address(farm)), "Farm");
        assertFalse(foodToken.allowed(stranger), "nobody else");
        assertTrue(foodToken.allowlistLocked(), "locked after deploy");
    }

    function test_allowlist_isLockedForever() public {
        vm.startPrank(admin);
        vm.expectRevert(FoodToken.FoodToken__AllowlistLocked.selector);
        foodToken.setAllowed(stranger, true);
        vm.expectRevert(FoodToken.FoodToken__AllowlistLocked.selector);
        foodToken.lockAllowlist();
        vm.stopPrank();
    }

    function test_allowlist_onlyTheAllowlisterSetsIt() public {
        FoodToken fresh = new FoodToken(admin, ONE_FOOD);
        vm.expectRevert(abi.encodeWithSelector(FoodToken.FoodToken__NotAllowlister.selector, stranger));
        vm.prank(stranger);
        fresh.setAllowed(stranger, true);
        vm.expectRevert(abi.encodeWithSelector(FoodToken.FoodToken__NotAllowlister.selector, stranger));
        vm.prank(stranger);
        fresh.lockAllowlist();
    }

    // ---------------------------------------------------------------- nobody outside can receive, hold or send it

    function test_outsiderCantReceiveFood() public {
        vm.expectRevert(abi.encodeWithSelector(FoodToken.FoodToken__NotAllowed.selector, stranger));
        vm.prank(admin);
        foodToken.transfer(stranger, 1);
    }

    function test_transferFromToAnOutsiderReverts() public {
        vm.prank(admin);
        foodToken.approve(stranger, 1);
        vm.expectRevert(abi.encodeWithSelector(FoodToken.FoodToken__NotAllowed.selector, stranger));
        vm.prank(stranger);
        foodToken.transferFrom(admin, stranger, 1);
    }

    function test_foodThatSomehowReachedAnOutsiderIsStuck() public {
        deal(address(foodToken), stranger, ONE_FOOD); // only a test cheat can put it there
        vm.expectRevert(abi.encodeWithSelector(FoodToken.FoodToken__NotAllowed.selector, stranger));
        vm.prank(stranger);
        foodToken.transfer(admin, 1);
    }

    function test_poolManagerTakeToAnOutsiderReverts() public {
        FoodTaker taker = new FoodTaker(manager, foodC, stranger);
        // CurrencyLibrary wraps the token's refusal in WrappedError; the refusal itself must be the allowlist's.
        try taker.run() {
            fail();
        } catch (bytes memory reason) {
            bytes memory want = abi.encodeWithSelector(FoodToken.FoodToken__NotAllowed.selector, stranger);
            assertTrue(_contains(reason, want), "refused by FOOD's allowlist");
        }
        assertEq(foodToken.balanceOf(stranger), 0, "no FOOD left the pool");
    }

    function test_outsiderCantSwapInOurPool() public {
        TestRouter outsiderRouter = new TestRouter(manager);
        PoolKey memory ours = router.poolKey();
        usdc.mint(stranger, 10 * ONE_USDC);
        vm.startPrank(stranger);
        usdc.approve(address(outsiderRouter), type(uint256).max);
        bool zeroForOne = address(usdc) < address(foodToken);
        vm.expectRevert(); // FoodHook__NotRouter, wrapped by the PoolManager
        outsiderRouter.swap(
            ours,
            IPoolManager.SwapParams(
                zeroForOne, -int256(ONE_USDC), zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            )
        );
        vm.stopPrank();
    }

    function test_outsiderCantCallTheRouter() public {
        vm.expectRevert();
        vm.prank(stranger);
        router.buyFood(ONE_FOOD, ONE_USDC, _ref());
    }

    function test_outsiderCantSeedAnotherPool() public {
        // A second FOOD/USDC pool with no hook: initialising is open to anyone in v4, but stocking it needs FOOD
        // to move from the outsider to the PoolManager, and the outsider isn't allowed to send FOOD.
        (Currency c0, Currency c1) = address(foodToken) < address(usdc)
            ? (foodC, Currency.wrap(address(usdc)))
            : (Currency.wrap(address(usdc)), foodC);
        PoolKey memory rogue = PoolKey(c0, c1, 3000, 60, IHooks(address(0)));
        manager.initialize(rogue, TickMath.getSqrtPriceAtTick(0));

        deal(address(foodToken), stranger, 1000 * ONE_FOOD);
        usdc.mint(stranger, 1000 * ONE_USDC);
        TestRouter outsiderRouter = new TestRouter(manager);
        vm.startPrank(stranger);
        usdc.approve(address(outsiderRouter), type(uint256).max);
        foodToken.approve(address(outsiderRouter), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(FoodToken.FoodToken__NotAllowed.selector, stranger));
        outsiderRouter.modifyLiquidity(
            rogue,
            IPoolManager.ModifyLiquidityParams(
                TickMath.minUsableTick(60), TickMath.maxUsableTick(60), int256(uint256(ONE_FOOD)), 0
            )
        );
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- the game still works under the lock

    function test_harvestSaleStillWorks() public {
        vm.prank(keeper);
        (uint256 sold,) = farm.sell(10 * ONE_FOOD, _ref());
        assertGt(sold, 0, "the farm sold into the pool");
    }

    function test_hookStillOnlyAcceptsOurRouter() public view {
        assertEq(FoodHook(address(hook)).router(), address(router));
    }

    function _contains(bytes memory hay, bytes memory needle) internal pure returns (bool) {
        if (needle.length > hay.length) return false;
        for (uint256 i = 0; i <= hay.length - needle.length; ++i) {
            bool same = true;
            for (uint256 j = 0; j < needle.length && same; ++j) {
                same = hay[i + j] == needle[j];
            }
            if (same) return true;
        }
        return false;
    }
}
