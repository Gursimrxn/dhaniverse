// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {TownWorld} from "../kit/TownWorld.sol";
import {MealCounter} from "../../src/food/MealCounter.sol";
import {FoodRouter} from "../../src/food/FoodRouter.sol";
import {MealTicket} from "../../src/money/Vouchers.sol";

/// @notice MealCounter: the only way a player buys food. Tickets are server-signed, a ref works once, the meal never
///         costs more than maxUsdc, and when the pool is at today's top the ration reserve fills the meal.
contract MealCounterTest is TownWorld {
    uint256 internal constant THALI_FOOD = 6 * ONE_FOOD;

    function setUp() public override {
        super.setUp();
        _giveUsdc(sam, dollars(50), address(mealCounter));
    }

    // ================================================================ a normal meal

    function test_buyMeal_buysAndBurnsThroughThePool_andRefundsTheRest() public {
        uint256 maxUsdc = 6 * BASE_PRICE * 102 / 100; // the server's 2% headroom
        (MealTicket memory t, bytes memory sig) = _ticket(sam, THALI, THALI_FOOD, maxUsdc);
        uint256 supplyBefore = foodToken.totalSupply();
        uint256 samBefore = usdc.balanceOf(sam);
        (,, uint160 sqrtBefore) = hook.band();

        vm.expectEmit(true, true, false, false, address(mealCounter));
        emit MealCounter.MealEaten(sam, t.ref, THALI, 0, THALI_FOOD, 0);
        vm.prank(sam);
        (uint256 paid, uint256 fromRation) = mealCounter.buyMeal(t, sig);

        assertEq(fromRation, 0, "the pool filled it");
        assertApproxEqRel(paid, 6 * BASE_PRICE, 0.01e18, "about $0.024");
        assertLe(paid, maxUsdc);
        assertEq(samBefore - usdc.balanceOf(sam), paid, "Sam paid exactly the meal's cost");
        assertEq(foodToken.totalSupply(), supplyBefore - THALI_FOOD, "6 FOOD burned");
        (,, uint160 sqrtAfter) = hook.band();
        assertTrue(sqrtAfter != sqrtBefore, "the meal moved the pool price");
        assertEq(usdc.balanceOf(address(mealCounter)), 0, "the counter keeps no USDC");
        assertEq(usdc.balanceOf(address(treasury)), 0, "no ration revenue");
        assertEq(foodToken.balanceOf(sam), 0, "players never hold FOOD");
        assertTrue(mealCounter.refUsed(t.ref));
    }

    // ================================================================ the ration shop

    function test_rationShop_fillsWhatThePoolCant_atTheBandHighPrice() public {
        uint256 bigMeal = 9000 * ONE_FOOD; // more than ~6,700 FOOD that moves the price 15%
        (MealTicket memory t, bytes memory sig) = _ticket(sam, THALI, bigMeal, dollars(40));
        uint256 reserveBefore = mealCounter.rationReserve();
        uint256 supplyBefore = foodToken.totalSupply();

        vm.prank(sam);
        (uint256 paid, uint256 fromRation) = mealCounter.buyMeal(t, sig);

        (, uint256 high,) = hook.priceBand();
        assertGt(fromRation, 0, "the pool hit today's top");
        uint256 rationUsdc = Math.mulDiv(fromRation, high, ONE_FOOD, Math.Rounding.Ceil);
        assertEq(usdc.balanceOf(address(treasury)), rationUsdc, "ration revenue went to Treasury");
        assertEq(mealCounter.rationReserve(), reserveBefore - fromRation, "taken from the reserve");
        assertEq(foodToken.totalSupply(), supplyBefore - bigMeal, "every FOOD in the meal burned");
        assertLe(paid, dollars(40));
        assertEq(usdc.balanceOf(address(mealCounter)), 0);
    }

    function test_rationShop_atTheTop_theWholeMealIsRationAtBandHigh() public {
        _pushToTop();
        (, uint256 high,) = hook.priceBand();
        uint256 expected = Math.mulDiv(THALI_FOOD, high, ONE_FOOD, Math.Rounding.Ceil);
        (MealTicket memory t, bytes memory sig) = _ticket(sam, THALI, THALI_FOOD, expected);
        vm.prank(sam);
        (uint256 paid, uint256 fromRation) = mealCounter.buyMeal(t, sig);
        assertEq(fromRation, THALI_FOOD);
        assertEq(paid, expected, "6 FOOD at today's band-high price");
    }

    function test_rationShop_tooDear_whenMaxIsBelowTheRationPrice() public {
        _pushToTop();
        (, uint256 high,) = hook.priceBand();
        uint256 cost = Math.mulDiv(THALI_FOOD, high, ONE_FOOD, Math.Rounding.Ceil);
        (MealTicket memory t, bytes memory sig) = _ticket(sam, THALI, THALI_FOOD, cost - 1);
        vm.expectRevert(abi.encodeWithSelector(MealCounter.MealCounter__TooDear.selector, cost, cost - 1));
        vm.prank(sam);
        mealCounter.buyMeal(t, sig);
    }

    function test_rationShop_empty_refuses() public {
        _pushToTop();
        uint256 reserve = mealCounter.rationReserve();
        (MealTicket memory t, bytes memory sig) = _ticket(sam, THALI, reserve + ONE_FOOD, dollars(50));
        vm.expectRevert(
            abi.encodeWithSelector(MealCounter.MealCounter__RationEmpty.selector, reserve + ONE_FOOD, reserve)
        );
        vm.prank(sam);
        mealCounter.buyMeal(t, sig);
    }

    // ================================================================ refusals

    function test_tooDear_whenThePoolCostsMoreThanMax_nothingMoves() public {
        (MealTicket memory t, bytes memory sig) = _ticket(sam, THALI, THALI_FOOD, 6 * BASE_PRICE / 2);
        uint256 samBefore = usdc.balanceOf(sam);
        vm.expectPartialRevert(MealCounter.MealCounter__TooDear.selector);
        vm.prank(sam);
        mealCounter.buyMeal(t, sig);
        assertEq(usdc.balanceOf(sam), samBefore);
        assertFalse(mealCounter.refUsed(t.ref));
    }

    function test_onlyTheTicketsPlayer() public {
        (MealTicket memory t, bytes memory sig) = _ticket(sam, THALI, THALI_FOOD, dollars(1));
        vm.expectRevert(abi.encodeWithSelector(MealCounter.MealCounter__NotPlayer.selector, stranger, sam));
        vm.prank(stranger);
        mealCounter.buyMeal(t, sig);
    }

    function test_expiredTicket() public {
        (MealTicket memory t, bytes memory sig) = _ticket(sam, THALI, THALI_FOOD, dollars(1));
        vm.warp(t.expiry + 1);
        vm.expectRevert(abi.encodeWithSelector(MealCounter.MealCounter__Expired.selector, t.expiry, t.expiry + 1));
        vm.prank(sam);
        mealCounter.buyMeal(t, sig);
    }

    function test_wrongSigner() public {
        (MealTicket memory t,) = _ticket(sam, THALI, THALI_FOOD, dollars(1));
        bytes memory forged = _signTicket(t, voucherSignerKey);
        vm.expectRevert(
            abi.encodeWithSelector(MealCounter.MealCounter__BadSignature.selector, voucherSigner, ticketSigner)
        );
        vm.prank(sam);
        mealCounter.buyMeal(t, forged);
    }

    function test_tamperedTicket_isRefused() public {
        (MealTicket memory t, bytes memory sig) = _ticket(sam, THALI, THALI_FOOD, dollars(1));
        t.food = 60 * ONE_FOOD; // ten thalis on a one-thali ticket
        vm.expectPartialRevert(MealCounter.MealCounter__BadSignature.selector);
        vm.prank(sam);
        mealCounter.buyMeal(t, sig);
    }

    function test_ref_worksOnce() public {
        (MealTicket memory t, bytes memory sig) = _ticket(sam, THALI, THALI_FOOD, dollars(1));
        vm.prank(sam);
        mealCounter.buyMeal(t, sig);
        vm.expectRevert(abi.encodeWithSelector(MealCounter.MealCounter__RefUsed.selector, t.ref));
        vm.prank(sam);
        mealCounter.buyMeal(t, sig);
    }

    function test_zeroFood_isRefused() public {
        (MealTicket memory t, bytes memory sig) = _ticket(sam, THALI, 0, dollars(1));
        vm.expectRevert(MealCounter.MealCounter__ZeroFood.selector);
        vm.prank(sam);
        mealCounter.buyMeal(t, sig);
    }

    function test_buyMealFor_onlyHousePool() public {
        vm.expectRevert(abi.encodeWithSelector(MealCounter.MealCounter__NotHousePool.selector, stranger));
        vm.prank(stranger);
        mealCounter.buyMealFor(sam, THALI, THALI_FOOD, dollars(1), _ref());
    }

    function test_buyMealFor_payerIsThePool_energyGoesToThePlayer() public {
        _giveUsdc(address(housePool), dollars(1), address(mealCounter));
        bytes32 ref = _ref();
        vm.expectEmit(true, true, false, false, address(mealCounter));
        emit MealCounter.MealEaten(sam, ref, THALI, 0, THALI_FOOD, 0);
        vm.prank(address(housePool));
        (uint256 paid,) = mealCounter.buyMealFor(sam, THALI, THALI_FOOD, dollars(1), ref);
        assertEq(usdc.balanceOf(address(housePool)), dollars(1) - paid, "the pool paid and got the rest back");
    }

    function test_routerWithoutBuyerRole_bubblesTheRoutersError() public {
        vm.prank(admin);
        router.setRole(address(mealCounter), FoodRouter.Role.None);
        (MealTicket memory t, bytes memory sig) = _ticket(sam, THALI, THALI_FOOD, dollars(1));
        vm.expectRevert(
            abi.encodeWithSelector(
                FoodRouter.FoodRouter__NotAllowed.selector,
                address(mealCounter),
                FoodRouter.Role.None,
                FoodRouter.Role.Buyer
            )
        );
        vm.prank(sam);
        mealCounter.buyMeal(t, sig);
    }

    // ================================================================ admin

    function test_admin_setters_emitAndRefuseStrangers() public {
        (address newSigner, uint256 newKey) = makeAddrAndKey("new ticket signer");
        (MealTicket memory t, bytes memory oldSig) = _ticket(sam, THALI, THALI_FOOD, dollars(1));

        vm.expectEmit(address(mealCounter));
        emit MealCounter.TicketSignerSet(ticketSigner, newSigner);
        vm.prank(admin);
        mealCounter.setTicketSigner(newSigner);

        vm.expectPartialRevert(MealCounter.MealCounter__BadSignature.selector);
        vm.prank(sam);
        mealCounter.buyMeal(t, oldSig); // old tickets stop working
        vm.prank(sam);
        mealCounter.buyMeal(t, _signTicket(t, newKey));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        mealCounter.setTicketSigner(stranger);

        vm.startPrank(admin);
        vm.expectRevert(MealCounter.MealCounter__ZeroAddress.selector);
        mealCounter.setTicketSigner(address(0));
        vm.expectRevert(MealCounter.MealCounter__ZeroAddress.selector);
        mealCounter.setRouter(FoodRouter(address(0)));
        vm.expectEmit(address(mealCounter));
        emit MealCounter.HousePoolSet(address(housePool), address(0));
        mealCounter.setHousePool(address(0));
        vm.expectEmit(address(mealCounter));
        emit MealCounter.RouterSet(address(router), address(1));
        mealCounter.setRouter(FoodRouter(address(1)));
        vm.expectRevert(MealCounter.MealCounter__AdminCantBeRemoved.selector);
        mealCounter.renounceOwnership();
        vm.expectRevert(MealCounter.MealCounter__ZeroFood.selector);
        mealCounter.restockRation(0);
        vm.stopPrank();
    }

    function test_restockRation_addsToTheReserve() public {
        uint256 before = mealCounter.rationReserve();
        vm.startPrank(admin);
        foodToken.approve(address(mealCounter), 5 * ONE_FOOD);
        vm.expectEmit(address(mealCounter));
        emit MealCounter.RationRestocked(admin, 5 * ONE_FOOD);
        mealCounter.restockRation(5 * ONE_FOOD);
        vm.stopPrank();
        assertEq(mealCounter.rationReserve(), before + 5 * ONE_FOOD);
    }

    function test_constructor_refusesZeroAddresses() public {
        vm.expectRevert(MealCounter.MealCounter__ZeroAddress.selector);
        new MealCounter(router, hook, address(0), ticketSigner, admin);
    }

    // ================================================================ the money rule

    /// @notice Whatever the meal and the limit: a meal never charges above maxUsdc, the player pays exactly what the
    ///         event says, and the counter never keeps USDC.
    function testFuzz_mealNeverChargesAboveMax(uint256 foodAmount, uint256 maxUsdc, bool pushFirst) public {
        foodAmount = bound(foodAmount, 1, 12_000 * ONE_FOOD);
        maxUsdc = bound(maxUsdc, 0, dollars(50));
        if (pushFirst) _pushToTop();
        (MealTicket memory t, bytes memory sig) = _ticket(sam, CHAI, foodAmount, maxUsdc);
        uint256 samBefore = usdc.balanceOf(sam);
        vm.prank(sam);
        try mealCounter.buyMeal(t, sig) returns (uint256 paid, uint256) {
            assertLe(paid, maxUsdc, "never above maxUsdc");
            assertEq(samBefore - usdc.balanceOf(sam), paid, "charged exactly the cost");
        } catch {
            assertEq(usdc.balanceOf(sam), samBefore, "a refused meal moves nothing");
        }
        assertEq(usdc.balanceOf(address(mealCounter)), 0, "the counter keeps no USDC");
    }

    // ================================================================ helpers

    /// @dev Another player eats enough to push the price to the top of today's band.
    function _pushToTop() internal {
        _giveUsdc(priya, dollars(100), address(mealCounter));
        (MealTicket memory t, bytes memory sig) = _ticket(priya, THALI, 8000 * ONE_FOOD, dollars(100));
        vm.prank(priya);
        mealCounter.buyMeal(t, sig);
    }
}
