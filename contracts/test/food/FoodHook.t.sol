// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {CustomRevert} from "@uniswap/v4-core/src/libraries/CustomRevert.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {FoodWorld} from "../kit/FoodWorld.sol";
import {TestRouter} from "../kit/TestRouter.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";
import {FoodToken} from "../../src/food/FoodToken.sol";
import {FoodHook} from "../../src/food/FoodHook.sol";

/// @notice FoodHook's rules, tested on a real local Uniswap v4 pool.
///         The two contracts at the bottom run every test twice: FOOD sorting first in the pool, then second,
///         because the price maths flips between the two.
abstract contract FoodHookTest is FoodWorld {
    TestRouter internal router;

    function setUp() public override {
        super.setUp();
        _setUpWorld();
        router = new TestRouter(manager);
        vm.label(address(router), "router");

        hook = _deployHook(0x4444, address(router));
        key = _key(hook, Currency.wrap(foodAddress()), TICK_SPACING);

        vm.prank(admin);
        manager.initialize(key, _sqrtFor(START));

        // Stock the pool, and give the two traders money and permission to pay the router.
        usdc.mint(admin, 100 * ONE_USDC);
        _approveRouter(admin);
        vm.prank(admin);
        router.modifyLiquidity(key, _fullRange(int256(uint256(STARTING_LIQUIDITY))));

        usdc.mint(buyer, 1000 * ONE_USDC);
        _approveRouter(buyer);
        vm.prank(admin);
        assertTrue(foodToken.transfer(seller, food(1_000_000)));
        _approveRouter(seller);
    }

    // ================================================================ deploy

    function test_deploy_refusesBadSettings() public {
        vm.expectRevert(abi.encodeWithSelector(FoodHook.FoodHook__BadSettings.selector, 0, CEILING, BAND_BPS, DAY));
        new FoodHook(manager, admin, address(router), usdcC(), foodC(), 0, CEILING, BAND_BPS, DAY);

        vm.expectRevert(abi.encodeWithSelector(FoodHook.FoodHook__BadSettings.selector, CEILING, FLOOR, BAND_BPS, DAY));
        new FoodHook(manager, admin, address(router), usdcC(), foodC(), CEILING, FLOOR, BAND_BPS, DAY);

        vm.expectRevert(abi.encodeWithSelector(FoodHook.FoodHook__BadSettings.selector, FLOOR, CEILING, BAND_BPS, 0));
        new FoodHook(manager, admin, address(router), usdcC(), foodC(), FLOOR, CEILING, BAND_BPS, 0);

        vm.expectRevert(abi.encodeWithSelector(FoodHook.FoodHook__BadSettings.selector, FLOOR, CEILING, 0, DAY));
        new FoodHook(manager, admin, address(router), usdcC(), foodC(), FLOOR, CEILING, 0, DAY);

        vm.expectRevert(abi.encodeWithSelector(FoodHook.FoodHook__BadSettings.selector, FLOOR, CEILING, 10_000, DAY));
        new FoodHook(manager, admin, address(router), usdcC(), foodC(), FLOOR, CEILING, 10_000, DAY);
    }

    function test_deploy_refusesAnAddressThatDoesntCarryItsPermissions() public {
        address next = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, next));
        new FoodHook(manager, admin, address(router), usdcC(), foodC(), FLOOR, CEILING, BAND_BPS, DAY);
    }

    function test_deploy_settingsReadBack() public view {
        (address u, address f, uint256 lo, uint256 hi, uint256 bandBps, uint256 day,, bytes32 id) = hook.settings();
        assertEq(u, address(usdc));
        assertEq(bandBps, BAND_BPS);
        assertEq(hook.ceilingPrice(), CEILING);
        assertEq(f, foodAddress());
        assertEq(lo, FLOOR);
        assertEq(hi, CEILING);
        assertEq(day, DAY);
        assertEq(id, keccak256(abi.encode(key)), "pool id");
        assertEq(hook.router(), address(router));
        assertEq(address(hook.poolManager()), address(manager));
    }

    // ================================================================ creating the pool

    function test_init_onlyTheAdminCanCreateThePool() public {
        FoodHook fresh = _deployHook(0x5555, address(router));
        _expectWrapped(
            address(fresh),
            IHooks.beforeInitialize.selector,
            abi.encodeWithSelector(FoodHook.FoodHook__NotAdmin.selector, stranger)
        );
        vm.prank(stranger);
        manager.initialize(_key(fresh, foodC(), TICK_SPACING), _sqrtFor(START));
    }

    function test_init_onlyOnePool() public {
        _expectWrapped(
            address(hook),
            IHooks.beforeInitialize.selector,
            abi.encodeWithSelector(FoodHook.FoodHook__PoolExists.selector)
        );
        vm.prank(admin);
        manager.initialize(_key(hook, foodC(), 10), _sqrtFor(START));
    }

    function test_init_onlyFoodAgainstUsdc() public {
        FoodHook fresh = _deployHook(0x5555, address(router));
        MockUSDC other = new MockUSDC();
        PoolKey memory wrong = _key(fresh, Currency.wrap(address(other)), TICK_SPACING);
        _expectWrapped(
            address(fresh),
            IHooks.beforeInitialize.selector,
            abi.encodeWithSelector(
                FoodHook.FoodHook__WrongTokens.selector,
                Currency.unwrap(wrong.currency0),
                Currency.unwrap(wrong.currency1)
            )
        );
        vm.prank(admin);
        manager.initialize(wrong, _sqrtFor(START));
    }

    function test_init_startPriceMustBeInsideFloorAndCeiling() public {
        FoodHook fresh = _deployHook(0x5555, address(router));
        uint160 tooCheap = _sqrtFor(1900); // $0.0019: under the $0.002 floor
        _expectWrapped(
            address(fresh),
            IHooks.beforeInitialize.selector,
            abi.encodeWithSelector(
                FoodHook.FoodHook__StartOutsideBounds.selector, fresh.usdcPerFood(tooCheap), FLOOR, CEILING
            )
        );
        vm.prank(admin);
        manager.initialize(_key(fresh, foodC(), TICK_SPACING), tooCheap);
    }

    // ================================================================ only FoodRouter gets in

    function test_stock_onlyThroughTheRouter() public {
        TestRouter other = new TestRouter(manager);
        _approve(stranger, address(other));
        usdc.mint(stranger, ONE_USDC);
        _expectWrapped(
            address(hook),
            IHooks.beforeAddLiquidity.selector,
            abi.encodeWithSelector(FoodHook.FoodHook__NotRouter.selector, address(other))
        );
        vm.prank(stranger);
        other.modifyLiquidity(key, _fullRange(1000));
    }

    function test_trades_onlyThroughTheRouter() public {
        TestRouter other = new TestRouter(manager);
        _approve(buyer, address(other));
        _expectWrapped(
            address(hook),
            IHooks.beforeSwap.selector,
            abi.encodeWithSelector(FoodHook.FoodHook__NotRouter.selector, address(other))
        );
        vm.prank(buyer);
        other.swap(key, _buyParams(food(1), _noLimit(true)));
    }

    function test_hookFunctions_onlyForThePoolManager() public {
        IPoolManager.SwapParams memory params;
        vm.expectRevert(abi.encodeWithSelector(FoodHook.FoodHook__NotPoolManager.selector, stranger));
        vm.prank(stranger);
        hook.beforeSwap(stranger, key, params, "");
    }

    function test_unusedHooks_alwaysRefuse() public {
        vm.expectRevert(FoodHook.FoodHook__HookNotUsed.selector);
        hook.afterInitialize(address(0), key, 0, 0);
        vm.expectRevert(FoodHook.FoodHook__HookNotUsed.selector);
        hook.beforeDonate(address(0), key, 0, 0, "");
    }

    function test_permissions_matchTheAddress() public view {
        Hooks.Permissions memory p = hook.getHookPermissions();
        assertTrue(p.beforeInitialize && p.beforeAddLiquidity && p.beforeSwap && p.afterSwap);
        assertFalse(p.afterInitialize || p.beforeRemoveLiquidity || p.beforeDonate || p.beforeSwapReturnDelta);
    }

    // ================================================================ the day and its limit

    function test_firstTrade_opensTheDayAtTheCurrentPrice() public {
        uint256 before = _price();
        vm.expectEmit(address(hook));
        emit FoodHook.DayOpened(0, before);
        _buy(food(10));
        (uint256 open,,) = hook.dayTotals(0);
        assertEq(open, before);
    }

    function test_buy_stopsAtTodays15PercentLimit_insteadOfFailing() public {
        (uint256 got,) = _buy(food(1000)); // far more than 15% worth
        assertLt(got, food(1000), "only part of the order could be filled");
        assertGt(got, 0, "but some was");
        assertLe(_price(), START * 115 / 100, "never above +15%");
        assertGe(_price(), START * 114 / 100, "and it got close to the limit");
    }

    function test_sell_stopsAtTodays15PercentLimit_insteadOfFailing() public {
        _sell(food(1000));
        assertGe(_price(), START * 85 / 100, "never below -15%");
        assertLe(_price(), START * 86 / 100, "and it got close to the limit");
    }

    function test_priceBand_readsTodaysLimitsInUsdcPerFood() public {
        (uint256 low, uint256 high, uint256 live) = hook.priceBand();
        assertApproxEqAbs(live, START, 1, "live price");
        assertApproxEqAbs(low, START * 85 / 100, 2, "low = open - 15%");
        assertApproxEqAbs(high, START * 115 / 100, 2, "high = open + 15%");
        assertLe(high, START * 115 / 100, "rounded inward");
        assertGe(low, START * 85 / 100, "rounded inward");

        _buy(food(1000)); // to the top of today's band
        (, uint256 highAfter, uint256 liveAfter) = hook.priceBand();
        assertEq(highAfter, high, "the band is fixed by the day's opening price");
        assertApproxEqAbs(liveAfter, high, 1, "the price now sits at the top");
    }

    function test_buy_pastTheLimit_isRefusedByTheHook() public {
        bytes memory err = _tryBuyUnlimited(food(1000));
        _assertWrappedReason(err, address(hook), IHooks.afterSwap.selector, FoodHook.FoodHook__OutsideBand.selector);
    }

    function test_nextDay_allowsAnother15Percent() public {
        _buy(food(1000));
        uint256 dayOneClose = _price();
        assertEq(hook.today(), 0);

        vm.warp(block.timestamp + DAY);
        assertEq(hook.today(), 1);
        vm.expectEmit(address(hook));
        emit FoodHook.DayOpened(1, dayOneClose);
        _buy(food(1000));

        assertLe(_price(), dayOneClose * 115 / 100 + 1, "at most 15% above yesterday's close");
        assertGt(_price(), dayOneClose * 114 / 100, "and it got there");
    }

    function test_ceiling_holdsOverManyDays() public {
        for (uint256 d = 0; d < 40; ++d) {
            (uint160 low, uint160 high, uint160 live) = hook.band();
            if (live == (foodFirst ? high : low)) break; // pinned at the ceiling
            _buy(food(1000));
            vm.warp(block.timestamp + DAY);
        }
        assertLe(_price(), CEILING, "never above $0.008");
        assertGe(_price(), CEILING - 10, "and it reached it");
    }

    function test_floor_holdsOverManyDays() public {
        for (uint256 d = 0; d < 40; ++d) {
            (uint160 low, uint160 high, uint160 live) = hook.band();
            if (live == (foodFirst ? low : high)) break; // pinned at the floor
            _sell(food(10_000));
            vm.warp(block.timestamp + DAY);
        }
        assertGe(_price(), FLOOR, "never below $0.002");
        assertLe(_price(), FLOOR + 10, "and it reached it");
    }

    // ================================================================ the day's price

    function test_dayPrice_isTotalUsdcOverTotalFood() public {
        (uint256 food1, uint256 paid1) = _buy(food(40));
        (uint256 food2, uint256 got2) = _sellReturning(food(15));

        (, uint256 usdcTotal, uint256 foodTotal) = hook.dayTotals(0);
        assertEq(usdcTotal, paid1 + got2, "USDC total = everything paid and received");
        assertEq(foodTotal, food1 + food2, "FOOD total = everything bought and sold");
        assertEq(hook.dayPrice(0), Math.mulDiv(usdcTotal, ONE_FOOD, foodTotal), "rounded down to the base unit");
        assertApproxEqAbs(hook.dayPrice(0), START, 80, "about $0.004");
    }

    function test_dayPrice_isZeroForAQuietDay() public view {
        assertEq(hook.dayPrice(7), 0);
    }

    // ================================================================ replacing the router

    function test_setRouter_onlyTheAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        hook.setRouter(stranger);
    }

    function test_setRouter_newRouterWorks_oldOneIsLockedOut() public {
        TestRouter replacement = new TestRouter(manager);
        _approve(buyer, address(replacement));

        vm.expectEmit(address(hook));
        emit FoodHook.RouterSet(address(router), address(replacement));
        vm.prank(admin);
        hook.setRouter(address(replacement));

        IPoolManager.SwapParams memory params = _buyParams(food(5), _limit(true));
        vm.prank(buyer);
        replacement.swap(key, params);

        params = _buyParams(food(5), _limit(true));
        _expectWrapped(
            address(hook),
            IHooks.beforeSwap.selector,
            abi.encodeWithSelector(FoodHook.FoodHook__NotRouter.selector, address(router))
        );
        vm.prank(buyer);
        router.swap(key, params);
    }

    function test_admin_cantBeThrownAway() public {
        vm.expectRevert(FoodHook.FoodHook__AdminCantBeRemoved.selector);
        vm.prank(admin);
        hook.renounceOwnership();
    }

    function test_admin_handoverNeedsTheNewKeyToAccept() public {
        address newAdmin = makeAddr("new admin");
        vm.prank(admin);
        hook.transferOwnership(newAdmin);
        assertEq(hook.owner(), admin, "nothing changes until the new key accepts");
        assertEq(hook.pendingOwner(), newAdmin);

        vm.prank(newAdmin);
        hook.acceptOwnership();
        assertEq(hook.owner(), newAdmin);
    }

    // ================================================================ the property that matters most

    /// @notice Whatever anyone tries, in any order, across days: the price never leaves the floor and ceiling,
    ///         and never moves more than 15% from the day's opening price.
    function testFuzz_priceNeverLeavesItsBand(uint256[8] memory amounts, bool[8] memory buys, bool[8] memory waits)
        public
    {
        for (uint256 i = 0; i < 8; ++i) {
            if (waits[i]) vm.warp(block.timestamp + DAY);
            uint256 amount = bound(amounts[i], 1, food(5000));
            if (buys[i]) _tryBuyUnlimited(amount);
            else _trySellUnlimited(amount);

            uint256 price = _price();
            assertGe(price, FLOOR, "floor");
            assertLe(price, CEILING, "ceiling");
            (uint256 open,,) = hook.dayTotals(hook.today());
            if (open != 0) {
                assertLe(price, open * 115 / 100 + 1, "at most +15% today");
                assertGe(price + 1, open * 85 / 100, "at most -15% today");
            }
        }
    }

    // ================================================================ helpers

    /// @dev Buying FOOD pays USDC in. If USDC is token0 that's zeroForOne.
    function _buyParams(uint256 foodWanted, uint160 limit) internal view returns (IPoolManager.SwapParams memory) {
        return IPoolManager.SwapParams(!foodFirst, int256(foodWanted), limit);
    }

    function _sellParams(uint256 foodIn, uint160 limit) internal view returns (IPoolManager.SwapParams memory) {
        return IPoolManager.SwapParams(foodFirst, -int256(foodIn), limit);
    }

    /// @dev The limit FoodRouter will use: today's band edge in the direction of the trade.
    function _limit(bool buying) internal view returns (uint160) {
        (uint160 low, uint160 high,) = hook.band();
        bool zeroForOne = buying ? !foodFirst : foodFirst;
        return zeroForOne ? low : high;
    }

    function _noLimit(bool buying) internal view returns (uint160) {
        bool zeroForOne = buying ? !foodFirst : foodFirst;
        return zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
    }

    function _buy(uint256 foodWanted) internal returns (uint256 foodGot, uint256 usdcPaid) {
        uint256 f0 = foodToken.balanceOf(buyer);
        uint256 u0 = usdc.balanceOf(buyer);
        IPoolManager.SwapParams memory params = _buyParams(foodWanted, _limit(true)); // read the band first:
        vm.prank(buyer); // a prank applies to the very next call, so it must sit right before the trade
        router.swap(key, params);
        return (foodToken.balanceOf(buyer) - f0, u0 - usdc.balanceOf(buyer));
    }

    function _sell(uint256 foodIn) internal {
        _sellReturning(foodIn);
    }

    function _sellReturning(uint256 foodIn) internal returns (uint256 foodSold, uint256 usdcGot) {
        uint256 f0 = foodToken.balanceOf(seller);
        uint256 u0 = usdc.balanceOf(seller);
        IPoolManager.SwapParams memory params = _sellParams(foodIn, _limit(false));
        vm.prank(seller);
        router.swap(key, params);
        return (f0 - foodToken.balanceOf(seller), usdc.balanceOf(seller) - u0);
    }

    function _tryBuyUnlimited(uint256 foodWanted) internal returns (bytes memory err) {
        vm.prank(buyer);
        try router.swap(key, _buyParams(foodWanted, _noLimit(true))) {}
        catch (bytes memory reason) {
            err = reason;
        }
    }

    function _trySellUnlimited(uint256 foodIn) internal returns (bytes memory err) {
        vm.prank(seller);
        try router.swap(key, _sellParams(foodIn, _noLimit(false))) {}
        catch (bytes memory reason) {
            err = reason;
        }
    }

    function _approveRouter(address who) internal {
        _approve(who, address(router));
    }

    function _assertWrappedReason(bytes memory err, address target, bytes4 hookFn, bytes4 reasonSelector)
        internal
        pure
    {
        assertEq(bytes4(err), CustomRevert.WrappedError.selector, "Uniswap wrapped the refusal");
        (address t, bytes4 fn, bytes memory reason,) = abi.decode(_strip(err), (address, bytes4, bytes, bytes));
        assertEq(t, target, "refused by the hook");
        assertEq(fn, hookFn, "in this hook function");
        assertEq(bytes4(reason), reasonSelector, "for this reason");
    }

    function _strip(bytes memory err) internal pure returns (bytes memory body) {
        body = new bytes(err.length - 4);
        for (uint256 i = 0; i < body.length; ++i) {
            body[i] = err[i + 4];
        }
    }
}

contract FoodHookTest_FoodSortsFirst is FoodHookTest {
    function foodAddress() internal pure override returns (address) {
        return FOOD_SORTS_FIRST;
    }
}

contract FoodHookTest_FoodSortsSecond is FoodHookTest {
    function foodAddress() internal pure override returns (address) {
        return FOOD_SORTS_SECOND;
    }
}
