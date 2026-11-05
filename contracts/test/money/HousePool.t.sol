// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TownWorld} from "../kit/TownWorld.sol";
import {HousePool} from "../../src/money/HousePool.sol";
import {MealCounter} from "../../src/food/MealCounter.sol";
import {PayoutVoucher} from "../../src/money/Vouchers.sol";

/// @notice HousePool: three buckets, 4% of each a day at most, a per-human daily cap, vouchers that work once.
contract HousePoolTest is TownWorld {
    uint8 internal constant FIXED = 0;
    uint8 internal constant SURPRISE = 1;
    uint8 internal constant SAFETY = 2;

    function setUp() public override {
        super.setUp();
        _fundBucket(FIXED, dollars(1000)); // budget $40 a day
        _fundBucket(SURPRISE, dollars(500)); // $20
        _fundBucket(SAFETY, dollars(100)); // $4
    }

    // ================================================================ money in

    function test_fund_addsToTheBucket() public {
        usdc.mint(sam, dollars(2));
        vm.startPrank(sam);
        usdc.approve(address(housePool), dollars(2));
        vm.expectEmit(address(housePool));
        emit HousePool.Funded(SURPRISE, sam, dollars(2));
        housePool.fund(SURPRISE, dollars(2));
        vm.expectRevert(abi.encodeWithSelector(HousePool.HousePool__BadSource.selector, 3));
        housePool.fund(3, 1);
        vm.expectRevert(HousePool.HousePool__ZeroAmount.selector);
        housePool.fund(FIXED, 0);
        vm.stopPrank();
        assertEq(housePool.bucketBalance(SURPRISE), dollars(502));
    }

    // ================================================================ paying a voucher

    function test_pay_paysThePlayer_andOpensTheDaysBudget() public {
        (PayoutVoucher memory v, bytes memory sig) = _payout(sam, SAM_HUMAN, FIXED, dollars(1));
        vm.expectEmit(address(housePool));
        emit HousePool.BudgetOpened(FIXED, block.timestamp / 1 days, dollars(40));
        vm.expectEmit(address(housePool));
        emit HousePool.Paid(FIXED, sam, SAM_HUMAN, dollars(1), v.ref);
        vm.prank(stranger); // anyone may submit
        housePool.pay(v, sig);
        assertEq(usdc.balanceOf(sam), dollars(1));
        assertEq(housePool.bucketBalance(FIXED), dollars(999));
        (uint256 budget, uint256 spent, uint256 left) = housePool.todayBudget(FIXED);
        assertEq(budget, dollars(40));
        assertEq(spent, dollars(1));
        assertEq(left, dollars(39));
        assertEq(housePool.humanPaidToday(SAM_HUMAN), dollars(1));
        assertTrue(housePool.refUsed(v.ref));
    }

    function test_budget_isFixedAtTheDaysFirstPayout_andRenewsNextDay() public {
        _payAs(sam, SAM_HUMAN, FIXED, dollars(1));
        _fundBucket(FIXED, dollars(1000)); // more money today doesn't raise today's budget
        (uint256 budget,,) = housePool.todayBudget(FIXED);
        assertEq(budget, dollars(40));

        vm.warp(block.timestamp + 1 days);
        (budget,,) = housePool.todayBudget(FIXED);
        assertEq(budget, dollars(1999) * 400 / 10_000, "4% of the new balance");
    }

    function test_pay_overDailyBudget() public {
        _payAs(sam, SAM_HUMAN, SAFETY, dollars(3)); // budget $4
        (PayoutVoucher memory v, bytes memory sig) = _payout(priya, PRIYA_HUMAN, SAFETY, dollars(2));
        vm.expectRevert(
            abi.encodeWithSelector(HousePool.HousePool__OverDailyBudget.selector, SAFETY, dollars(5), dollars(4))
        );
        housePool.pay(v, sig);
    }

    function test_pay_perHumanDailyCap() public {
        _payAs(sam, SAM_HUMAN, FIXED, dollars(4));
        (PayoutVoucher memory v, bytes memory sig) = _payout(sam, SAM_HUMAN, SURPRISE, dollars(2));
        vm.expectRevert(
            abi.encodeWithSelector(HousePool.HousePool__HumanCapReached.selector, SAM_HUMAN, dollars(6), dollars(5))
        );
        housePool.pay(v, sig);
        vm.warp(block.timestamp + 1 days);
        PayoutVoucher memory f = _fresh(v);
        housePool.pay(f, _signPayout(f, voucherSignerKey)); // a new day, a new cap
    }

    function test_pay_refusals() public {
        (PayoutVoucher memory v, bytes memory sig) = _payout(sam, SAM_HUMAN, 3, dollars(1));
        vm.expectRevert(abi.encodeWithSelector(HousePool.HousePool__BadSource.selector, 3));
        housePool.pay(v, sig);

        (v, sig) = _payout(sam, SAM_HUMAN, FIXED, 0);
        vm.expectRevert(HousePool.HousePool__ZeroAmount.selector);
        housePool.pay(v, sig);

        (v, sig) = _payout(sam, bytes32(0), FIXED, 1);
        vm.expectRevert(abi.encodeWithSelector(HousePool.HousePool__NotVerified.selector, sam));
        housePool.pay(v, sig);

        (v, sig) = _payout(sam, SAM_HUMAN, FIXED, 1);
        vm.warp(v.expiry + 1);
        vm.expectRevert(abi.encodeWithSelector(HousePool.HousePool__Expired.selector, v.expiry, v.expiry + 1));
        housePool.pay(v, sig);

        (v,) = _payout(sam, SAM_HUMAN, FIXED, 1);
        bytes memory forged = _signPayout(v, ticketSignerKey);
        vm.expectRevert(abi.encodeWithSelector(HousePool.HousePool__BadSignature.selector, ticketSigner, voucherSigner));
        housePool.pay(v, forged);

        (v, sig) = _payout(sam, SAM_HUMAN, FIXED, 1);
        housePool.pay(v, sig);
        vm.expectRevert(abi.encodeWithSelector(HousePool.HousePool__RefUsed.selector, v.ref));
        housePool.pay(v, sig);
    }

    // ================================================================ rescue meals and meal vouchers

    function test_payMeal_rescueMeal_paidFromSafety_unusedStaysInTheBucket() public {
        (PayoutVoucher memory v, bytes memory sig) = _payout(sam, SAM_HUMAN, SAFETY, 50_000); // up to $0.05
        uint256 supplyBefore = foodToken.totalSupply();
        vm.expectEmit(true, true, false, false, address(mealCounter));
        emit MealCounter.MealEaten(sam, v.ref, THALI, 0, 6 * ONE_FOOD, 0);
        vm.prank(sam);
        uint256 spent = housePool.payMeal(v, THALI, 6 * ONE_FOOD, sig);

        assertApproxEqRel(spent, 6 * BASE_PRICE, 0.01e18);
        assertEq(housePool.bucketBalance(SAFETY), dollars(100) - spent, "only the meal's cost left the bucket");
        (, uint256 spentToday,) = housePool.todayBudget(SAFETY);
        assertEq(spentToday, spent);
        assertEq(housePool.humanPaidToday(SAM_HUMAN), spent);
        assertEq(foodToken.totalSupply(), supplyBefore - 6 * ONE_FOOD);
        assertEq(usdc.balanceOf(sam), 0, "Sam got a meal, not cash");
        assertEq(usdc.balanceOf(address(mealCounter)), 0);
    }

    function test_payMeal_refusals() public {
        (PayoutVoucher memory v, bytes memory sig) = _payout(sam, SAM_HUMAN, SAFETY, 50_000);
        vm.expectRevert(abi.encodeWithSelector(HousePool.HousePool__NotPlayer.selector, stranger, sam));
        vm.prank(stranger);
        housePool.payMeal(v, THALI, 6 * ONE_FOOD, sig);

        (v, sig) = _payout(sam, SAM_HUMAN, FIXED, 50_000);
        vm.expectRevert(abi.encodeWithSelector(HousePool.HousePool__BadSource.selector, FIXED));
        vm.prank(sam);
        housePool.payMeal(v, THALI, 6 * ONE_FOOD, sig);

        vm.prank(admin);
        housePool.setMealCounter(address(0));
        (v, sig) = _payout(sam, SAM_HUMAN, SURPRISE, 50_000);
        vm.expectRevert(HousePool.HousePool__NoMealCounter.selector);
        vm.prank(sam);
        housePool.payMeal(v, THALI, 6 * ONE_FOOD, sig);
    }

    function test_payMeal_mealTooDear_revertsEverything() public {
        (PayoutVoucher memory v, bytes memory sig) = _payout(sam, SAM_HUMAN, SURPRISE, 1000); // $0.001: too little
        vm.expectPartialRevert(MealCounter.MealCounter__TooDear.selector);
        vm.prank(sam);
        housePool.payMeal(v, THALI, 6 * ONE_FOOD, sig);
        assertEq(housePool.bucketBalance(SURPRISE), dollars(500));
        assertFalse(housePool.refUsed(v.ref));
    }

    // ================================================================ the weekly draw

    function test_payDraw_onlyLuckyLedger_refOnce_withinBudget() public {
        vm.expectRevert(abi.encodeWithSelector(HousePool.HousePool__NotLuckyLedger.selector, stranger));
        vm.prank(stranger);
        housePool.payDraw(sam, 1, bytes32("r"));

        vm.startPrank(address(lucky));
        vm.expectEmit(address(housePool));
        emit HousePool.Paid(SURPRISE, sam, bytes32(0), dollars(10), bytes32("r"));
        housePool.payDraw(sam, dollars(10), bytes32("r"));
        vm.expectRevert(abi.encodeWithSelector(HousePool.HousePool__RefUsed.selector, bytes32("r")));
        housePool.payDraw(sam, dollars(1), bytes32("r"));
        vm.expectRevert(
            abi.encodeWithSelector(HousePool.HousePool__OverDailyBudget.selector, SURPRISE, dollars(21), dollars(20))
        );
        housePool.payDraw(sam, dollars(11), bytes32("s"));
        vm.expectRevert(HousePool.HousePool__ZeroAmount.selector);
        housePool.payDraw(sam, 0, bytes32("t"));
        vm.expectRevert(HousePool.HousePool__ZeroAddress.selector);
        housePool.payDraw(address(0), 1, bytes32("t"));
        vm.stopPrank();
    }

    // ================================================================ admin

    function test_admin() public {
        vm.startPrank(admin);
        vm.expectEmit(address(housePool));
        emit HousePool.VoucherSignerSet(voucherSigner, sam);
        housePool.setVoucherSigner(sam);
        vm.expectRevert(HousePool.HousePool__ZeroAddress.selector);
        housePool.setVoucherSigner(address(0));
        vm.expectEmit(address(housePool));
        emit HousePool.PerHumanDailyCapSet(PER_HUMAN_DAILY_CAP, 7);
        housePool.setPerHumanDailyCap(7);
        vm.expectRevert(abi.encodeWithSelector(HousePool.HousePool__BadSettings.selector, BUDGET_BPS, 0));
        housePool.setPerHumanDailyCap(0);
        vm.expectEmit(address(housePool));
        emit HousePool.LuckyLedgerSet(address(lucky), address(0));
        housePool.setLuckyLedger(address(0));
        vm.expectEmit(address(housePool));
        emit HousePool.MealCounterSet(address(mealCounter), address(0));
        housePool.setMealCounter(address(0));
        vm.expectRevert(HousePool.HousePool__AdminCantBeRemoved.selector);
        housePool.renounceOwnership();
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        housePool.setVoucherSigner(stranger);
        vm.expectRevert(abi.encodeWithSelector(HousePool.HousePool__BadSource.selector, 3));
        housePool.bucketBalance(3);
        vm.expectRevert(abi.encodeWithSelector(HousePool.HousePool__BadSource.selector, 3));
        housePool.todayBudget(3);
        assertEq(housePool.today(), block.timestamp / 1 days);
        assertEq(housePool.budgetBps(), BUDGET_BPS);
    }

    function test_constructor_refusesBadSettings() public {
        vm.expectRevert(abi.encodeWithSelector(HousePool.HousePool__BadSettings.selector, 0, 1));
        new HousePool(usdc, voucherSigner, 0, 1, admin);
        vm.expectRevert(abi.encodeWithSelector(HousePool.HousePool__BadSettings.selector, 10_001, 1));
        new HousePool(usdc, voucherSigner, 10_001, 1, admin);
        vm.expectRevert(HousePool.HousePool__ZeroAddress.selector);
        new HousePool(IERC20(address(0)), voucherSigner, 400, 1, admin);
    }

    // ================================================================ the money rule

    /// @notice However many payouts, from any bucket, to any humans: no bucket ever pays more in a day than its budget.
    function testFuzz_poolNeverExceedsDailyBudget(
        uint256[12] memory amounts,
        uint8[12] memory buckets,
        bool[12] memory waits
    ) public {
        vm.prank(admin);
        housePool.setPerHumanDailyCap(dollars(1_000_000));
        uint256[3] memory paidToday;
        uint256 day = block.timestamp / 1 days;
        for (uint256 i = 0; i < 12; ++i) {
            if (waits[i]) {
                vm.warp(block.timestamp + 1 days);
                day += 1;
                delete paidToday;
            }
            uint8 bucket = buckets[i] % 3;
            uint256 amount = bound(amounts[i], 1, dollars(30));
            (uint256 budgetBefore,,) = housePool.todayBudget(bucket);
            (PayoutVoucher memory v, bytes memory sig) = _payout(sam, keccak256(abi.encode("human", i)), bucket, amount);
            try housePool.pay(v, sig) {
                paidToday[bucket] += amount;
            } catch {}
            (uint256 budget, uint256 spent,) = housePool.todayBudget(bucket);
            assertEq(spent, paidToday[bucket], "spent is what was paid today");
            assertLe(spent, budget, "never over the day's budget");
            assertLe(budget, budgetBefore, "the budget never grows within a day");
        }
    }

    // ================================================================ helpers

    function _payAs(address player, bytes32 humanId, uint8 bucket, uint256 amount) internal {
        (PayoutVoucher memory v, bytes memory sig) = _payout(player, humanId, bucket, amount);
        housePool.pay(v, sig);
    }

    function _fresh(PayoutVoucher memory v) internal returns (PayoutVoucher memory f) {
        f = v;
        f.ref = _ref();
        f.expiry = uint64(block.timestamp + 10 minutes);
    }
}
