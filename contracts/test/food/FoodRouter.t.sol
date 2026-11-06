// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {FoodWorld} from "../kit/FoodWorld.sol";
import {FoodHook} from "../../src/food/FoodHook.sol";
import {FoodRouter} from "../../src/food/FoodRouter.sol";

/// @notice FoodRouter: the only door into the food pool. Two roles use it, a ref works once, eaten FOOD is
///         burned, and at today's limit a trade fills what fits instead of failing.
abstract contract FoodRouterTest is FoodWorld {
    FoodRouter internal router;
    uint256 private _refCounter;
    uint256 internal constant NO_LIMIT = type(uint256).max;

    function setUp() public override {
        super.setUp();
        _setUpWorld();
        hook = _deployHook(0x4444, address(0));
        router = _deployRouter();
        vm.prank(admin);
        hook.setRouter(address(router));

        key = router.poolKey();
        vm.prank(admin);
        manager.initialize(key, _sqrtFor(START));

        // The admin stocks the pool through the router.
        usdc.mint(admin, 100 * ONE_USDC);
        _approve(admin, address(router));
        vm.prank(admin);
        router.addLiquidity(STARTING_LIQUIDITY);

        // Two server keys, one job each.
        vm.startPrank(admin);
        router.setRole(buyer, FoodRouter.Role.Buyer);
        router.setRole(seller, FoodRouter.Role.Seller);
        assertTrue(foodToken.transfer(seller, food(1_000_000)));
        vm.stopPrank();
        usdc.mint(buyer, 1000 * ONE_USDC);
        _approve(buyer, address(router));
        _approve(seller, address(router));
    }

    // ================================================================ buying what the city ate

    function test_poolKey_isTheHooksPool() public view {
        PoolKey memory expected = _key(hook, foodC(), TICK_SPACING);
        assertEq(keccak256(abi.encode(router.poolKey())), keccak256(abi.encode(expected)));
        assertEq(address(router.poolKey().hooks), address(hook));
    }

    function test_buy_burnsWhatTheCityAte() public {
        uint256 supplyBefore = foodToken.totalSupply();
        uint256 usdcBefore = usdc.balanceOf(buyer);

        vm.expectEmit(true, true, false, false, address(router));
        emit FoodRouter.FoodBought(0, buyer, 0, 0, 0, 0);
        // With the test pool's ~5,000 FOOD, ~330 FOOD moves the price 15%, so this meal stays well under.
        (uint256 bought, uint256 paid) = _buy(food(50));

        assertEq(bought, food(50), "all 50 bought");
        assertEq(foodToken.totalSupply(), supplyBefore - food(50), "and burned: the food supply really shrank");
        assertEq(usdcBefore - usdc.balanceOf(buyer), paid, "paid from the food court key");
        assertApproxEqRel(paid, usdcOf(0, 200_000), 0.05e18, "about $0.004 each");
        _assertRouterHoldsNothing();
    }

    function test_buy_stopsAtTheLimit_andSaysHowMuch() public {
        (uint256 bought,) = _buy(food(1000));
        assertGt(bought, 0);
        assertLt(bought, food(1000), "only part filled: today's limit");
        assertLe(_price(), START * 115 / 100, "price at most +15%");

        // Already at the edge: nothing more can be bought today, and the call still succeeds.
        (uint256 again, uint256 paid) = _buy(food(10));
        assertEq(again, 0);
        assertEq(paid, 0);
        _assertRouterHoldsNothing();
    }

    function test_buy_refusesWhenItWouldCostMoreThanMaxUsdc() public {
        uint256 usdcBefore = usdc.balanceOf(buyer);
        uint256 supplyBefore = foodToken.totalSupply();
        bytes32 ref = _ref();
        vm.expectPartialRevert(FoodRouter.FoodRouter__TooDear.selector);
        vm.prank(buyer);
        router.buyFood(food(50), usdcOf(0, 100_000), ref); // 50 FOOD cost ~$0.20; allowed only $0.10
        assertEq(usdc.balanceOf(buyer), usdcBefore, "nothing paid");
        assertEq(foodToken.totalSupply(), supplyBefore, "nothing burned");
        assertFalse(router.refUsed(ref), "the ref is still free");

        vm.prank(buyer);
        (uint256 bought, uint256 paid) = router.buyFood(food(50), usdcOf(0, 250_000), ref);
        assertEq(bought, food(50));
        assertLe(paid, usdcOf(0, 250_000));
    }

    // ================================================================ the seller selling

    function test_sell_paysTheSupplier() public {
        uint256 foodBefore = foodToken.balanceOf(seller);
        uint256 usdcBefore = usdc.balanceOf(seller);

        (uint256 sold, uint256 got) = _sell(food(50));

        assertEq(sold, food(50));
        assertEq(foodBefore - foodToken.balanceOf(seller), food(50), "exactly 50 FOOD left the seller");
        assertEq(usdc.balanceOf(seller) - usdcBefore, got, "and the USDC arrived");
        assertApproxEqRel(got, usdcOf(0, 200_000), 0.05e18, "about $0.004 each");
        _assertRouterHoldsNothing();
    }

    function test_sell_stopsAtTheLimit_unsoldStaysWithTheSupplier() public {
        uint256 foodBefore = foodToken.balanceOf(seller);
        (uint256 sold,) = _sell(food(10_000));

        assertLt(sold, food(10_000), "only part sold: today's limit");
        assertEq(foodBefore - foodToken.balanceOf(seller), sold, "only what sold left the seller");
        assertGe(_price(), START * 85 / 100, "price at most -15%");
        _assertRouterHoldsNothing();
    }

    // ================================================================ refs work once

    function test_ref_worksOnce() public {
        bytes32 ref = keccak256("meal 2026-11-06 #0412");
        vm.prank(buyer);
        router.buyFood(food(10), NO_LIMIT, ref);
        assertTrue(router.refUsed(ref));

        vm.expectRevert(abi.encodeWithSelector(FoodRouter.FoodRouter__RefUsed.selector, ref));
        vm.prank(buyer);
        router.buyFood(food(10), NO_LIMIT, ref);
    }

    function test_ref_isSharedBetweenBuyingAndSelling() public {
        bytes32 ref = keccak256("one ref");
        vm.prank(buyer);
        router.buyFood(food(10), NO_LIMIT, ref);

        vm.expectRevert(abi.encodeWithSelector(FoodRouter.FoodRouter__RefUsed.selector, ref));
        vm.prank(seller);
        router.sellFood(food(10), ref);
    }

    // ================================================================ roles

    function test_roles_eachKeyDoesOnlyItsJob() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                FoodRouter.FoodRouter__NotAllowed.selector, stranger, FoodRouter.Role.None, FoodRouter.Role.Buyer
            )
        );
        vm.prank(stranger);
        router.buyFood(food(1), NO_LIMIT, _ref());

        vm.expectRevert(
            abi.encodeWithSelector(
                FoodRouter.FoodRouter__NotAllowed.selector, seller, FoodRouter.Role.Seller, FoodRouter.Role.Buyer
            )
        );
        vm.prank(seller);
        router.buyFood(food(1), NO_LIMIT, _ref());

        vm.expectRevert(
            abi.encodeWithSelector(
                FoodRouter.FoodRouter__NotAllowed.selector, buyer, FoodRouter.Role.Buyer, FoodRouter.Role.Seller
            )
        );
        vm.prank(buyer);
        router.sellFood(food(1), _ref());
    }

    function test_offSwitch_takingARoleAwayStopsThatKey() public {
        vm.expectEmit(address(router));
        emit FoodRouter.RoleSet(buyer, FoodRouter.Role.None);
        vm.prank(admin);
        router.setRole(buyer, FoodRouter.Role.None);
        assertEq(uint8(router.roleOf(buyer)), uint8(FoodRouter.Role.None));

        vm.expectRevert(
            abi.encodeWithSelector(
                FoodRouter.FoodRouter__NotAllowed.selector, buyer, FoodRouter.Role.None, FoodRouter.Role.Buyer
            )
        );
        vm.prank(buyer);
        router.buyFood(food(1), NO_LIMIT, _ref());

        // The seller is untouched.
        _sell(food(1));
    }

    function test_setRole_onlyTheAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        router.setRole(stranger, FoodRouter.Role.Buyer);
    }

    function test_zeroAmounts_areRefused() public {
        vm.expectRevert(FoodRouter.FoodRouter__ZeroAmount.selector);
        vm.prank(buyer);
        router.buyFood(0, NO_LIMIT, _ref());

        vm.expectRevert(FoodRouter.FoodRouter__ZeroAmount.selector);
        vm.prank(admin);
        router.addLiquidity(0);
    }

    // ================================================================ safety of the plumbing

    /// @notice Nobody can call the settlement plumbing directly and make someone else pay.
    function test_unlockCallback_onlyForThePoolManager() public {
        bytes memory fake = abi.encode(uint8(0), buyer, food(1)); // "buy, paid by the buyer"
        vm.expectRevert(abi.encodeWithSelector(FoodRouter.FoodRouter__OnlyPoolManager.selector, stranger));
        vm.prank(stranger);
        router.unlockCallback(fake);
    }

    // ================================================================ stock

    function test_stock_onlyTheAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        router.addLiquidity(1000);
    }

    function test_stock_removeReturnsItToTheAdmin() public {
        uint256 usdcBefore = usdc.balanceOf(admin);
        uint256 foodBefore = foodToken.balanceOf(admin);

        vm.prank(admin);
        (uint256 usdcOut, uint256 foodOut) = router.removeLiquidity(STARTING_LIQUIDITY / 2);

        assertApproxEqRel(usdcOut, 10_000_000, 0.01e18, "about half of the 20 USDC");
        assertApproxEqRel(foodOut, food(2500), 0.01e18, "about half of the 5,000 FOOD");
        assertEq(usdc.balanceOf(admin) - usdcBefore, usdcOut);
        assertEq(foodToken.balanceOf(admin) - foodBefore, foodOut);
        _assertRouterHoldsNothing();
    }

    // ================================================================ replacing a broken router

    function test_replacedRouter_takesOverWithoutMovingThePool() public {
        _buy(food(30));
        uint256 priceBefore = _price();

        // 1. Deploy the fixed router and point the hook at it.
        FoodRouter fixedRouter = _deployRouter();
        vm.prank(admin);
        hook.setRouter(address(fixedRouter));

        // 2. Move the stock across: out through the old router, in through the new one.
        vm.startPrank(admin);
        router.removeLiquidity(STARTING_LIQUIDITY);
        usdc.approve(address(fixedRouter), type(uint256).max);
        foodToken.approve(address(fixedRouter), type(uint256).max);
        fixedRouter.addLiquidity(STARTING_LIQUIDITY);
        fixedRouter.setRole(buyer, FoodRouter.Role.Buyer);
        vm.stopPrank();
        _approve(buyer, address(fixedRouter));

        // Same pool, same price, same history.
        assertEq(keccak256(abi.encode(fixedRouter.poolKey())), keccak256(abi.encode(key)), "same pool");
        assertEq(_price(), priceBefore, "same price");
        (, uint256 usdcTotal,) = hook.dayTotals(0);
        assertGt(usdcTotal, 0, "today's history kept");

        // The new router trades; the old one is locked out by the hook.
        vm.prank(buyer);
        (uint256 bought,) = fixedRouter.buyFood(food(5), NO_LIMIT, _ref());
        assertEq(bought, food(5));

        bytes32 ref = _ref();
        _expectWrapped(
            address(hook),
            IHooks.beforeSwap.selector,
            abi.encodeWithSelector(FoodHook.FoodHook__NotRouter.selector, address(router))
        );
        vm.prank(buyer);
        router.buyFood(food(5), NO_LIMIT, ref);
    }

    // ================================================================ admin

    function test_admin_cantBeThrownAway() public {
        vm.expectRevert(FoodRouter.FoodRouter__AdminCantBeRemoved.selector);
        vm.prank(admin);
        router.renounceOwnership();
    }

    function test_admin_handoverNeedsTheNewKeyToAccept() public {
        address newAdmin = makeAddr("new admin");
        vm.prank(admin);
        router.transferOwnership(newAdmin);
        assertEq(router.owner(), admin);
        vm.prank(newAdmin);
        router.acceptOwnership();
        assertEq(router.owner(), newAdmin);
    }

    // ================================================================ the properties that matter most

    /// @notice Any mix of buys and sells, over any days: the router never keeps a single token, every eaten FOOD
    ///         is burned, and the price stays inside the floor and ceiling. No in-role call ever fails.
    function testFuzz_aCityDayOfTrades(uint256[10] memory amounts, bool[10] memory buys, bool[10] memory waits) public {
        uint256 burned;
        for (uint256 i = 0; i < 10; ++i) {
            if (waits[i]) vm.warp(block.timestamp + DAY);
            uint256 amount = bound(amounts[i], 1, food(3000));
            if (buys[i]) {
                (uint256 bought,) = _buy(amount);
                burned += bought;
            } else {
                _sell(amount);
            }
            _assertRouterHoldsNothing();
            assertEq(foodToken.totalSupply(), FOOD_SUPPLY - burned, "every eaten FOOD burned, nothing else");
            assertGe(_price(), FLOOR);
            assertLe(_price(), CEILING);
        }
    }

    // ================================================================ helpers

    function _deployRouter() internal returns (FoodRouter deployed) {
        deployed = new FoodRouter(manager, hook, admin, TICK_SPACING);
        vm.label(address(deployed), "FoodRouter");
        vm.prank(admin);
        foodToken.setAllowed(address(deployed), true);
    }

    function _ref() internal returns (bytes32) {
        return keccak256(abi.encode("test ref", ++_refCounter));
    }

    function _buy(uint256 foodWanted) internal returns (uint256 bought, uint256 paid) {
        bytes32 ref = _ref();
        vm.prank(buyer);
        return router.buyFood(foodWanted, NO_LIMIT, ref);
    }

    function _sell(uint256 foodOffered) internal returns (uint256 sold, uint256 got) {
        bytes32 ref = _ref();
        vm.prank(seller);
        return router.sellFood(foodOffered, ref);
    }

    function _assertRouterHoldsNothing() internal view {
        assertEq(usdc.balanceOf(address(router)), 0, "router holds no USDC");
        assertEq(foodToken.balanceOf(address(router)), 0, "router holds no FOOD");
    }
}

contract FoodRouterTest_FoodSortsFirst is FoodRouterTest {
    function foodAddress() internal pure override returns (address) {
        return FOOD_SORTS_FIRST;
    }
}

contract FoodRouterTest_FoodSortsSecond is FoodRouterTest {
    function foodAddress() internal pure override returns (address) {
        return FOOD_SORTS_SECOND;
    }
}
