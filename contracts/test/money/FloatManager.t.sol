// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {TownWorld} from "../kit/TownWorld.sol";
import {FloatManager} from "../../src/money/FloatManager.sol";
import {ICampaignBook, IHousePool} from "../../src/money/Links.sol";
import {MockYieldVault} from "../../src/mocks/MockYieldVault.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";
import {CampaignClaim} from "../../src/money/Vouchers.sol";

/// @notice FloatManager (custody, buffer, yield) and MockYieldVault (simulated yield).
contract FloatManagerTest is TownWorld {
    uint256 internal id;
    uint256 internal cap;

    function setUp() public override {
        super.setUp();
        id = _createCampaign(_spiceRunParams()); // $90 in the float, cap $12.857142 a day
        cap = escrow.dailyCap(id);
        usdc.mint(admin, dollars(1000));
        vm.startPrank(admin);
        usdc.approve(address(vault), type(uint256).max);
        vault.fundDrip(dollars(100));
        vm.stopPrank();
    }

    // ================================================================ principal

    function test_payAndRelease_onlyEscrow() public {
        vm.expectRevert(abi.encodeWithSelector(FloatManager.FloatManager__NotEscrow.selector, stranger));
        vm.prank(stranger);
        floatManager.pay(stranger, 1);
        vm.expectRevert(abi.encodeWithSelector(FloatManager.FloatManager__NotEscrow.selector, stranger));
        vm.prank(stranger);
        floatManager.release(stranger, 1);

        vm.startPrank(address(escrow));
        vm.expectRevert(FloatManager.FloatManager__ZeroAmount.selector);
        floatManager.pay(sam, 0);
        vm.expectRevert(FloatManager.FloatManager__ZeroAddress.selector);
        floatManager.pay(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(FloatManager.FloatManager__Illiquid.selector, dollars(91), dollars(90)));
        floatManager.pay(sam, dollars(91));
        vm.expectEmit(address(floatManager));
        emit FloatManager.Released(sponsor, 5);
        floatManager.release(sponsor, 5);
        vm.stopPrank();
    }

    // ================================================================ the buffer

    function test_rebalance_investsTheExcessAboveTheBuffer() public {
        uint256 buffer = cap * 3 * 15_000 / 10_000;
        assertEq(floatManager.buffer(), buffer, "1.5 x 3 days x daily caps");
        vm.expectEmit(address(floatManager));
        emit FloatManager.Rebalanced(buffer, dollars(90), dollars(90) - buffer, 0);
        vm.prank(keeper);
        (uint256 deposited, uint256 withdrawn) = floatManager.rebalance();
        assertEq(deposited, dollars(90) - buffer);
        assertEq(withdrawn, 0);
        assertEq(floatManager.liquid(), buffer);
        assertApproxEqAbs(floatManager.invested(), dollars(90) - buffer, 1);
        assertLe(floatManager.invested(), floatManager.totalAssets() * 8000 / 10_000, "never over 80%");
    }

    function test_rebalance_neverInvestsMoreThan80Percent() public {
        vm.prank(sponsor);
        escrow.cancel(id); // no live caps: buffer is just the pending refund...
        vm.warp(block.timestamp + 1); // (a pending refund keeps it all liquid)
        vm.prank(keeper);
        (uint256 deposited,) = floatManager.rebalance();
        assertEq(deposited, 0, "a pending refund is buffer");

        escrow.refund(id);
        // A float with no campaigns at all: buffer 0, so at most 80% goes in.
        usdc.mint(address(floatManager), dollars(100));
        vm.prank(keeper);
        (deposited,) = floatManager.rebalance();
        assertEq(deposited, dollars(80));
    }

    function test_rebalance_withdrawsBackToTheBuffer_whenCashFallsUnderHalf() public {
        vm.prank(keeper);
        floatManager.rebalance();
        uint256 buffer = floatManager.buffer();
        // Three days of twelve claims drain the cash to well under half the buffer.
        for (uint256 d = 0; d < 3; ++d) {
            for (uint256 i = 0; i < 12; ++i) {
                (CampaignClaim memory c, bytes memory sig) = _claim(id, sam, keccak256(abi.encode(d, i)), dollars(1));
                escrow.claim(c, sig);
            }
            vm.warp(block.timestamp + 1 days);
        }
        buffer = floatManager.buffer();
        uint256 cash = floatManager.liquid();
        assertLt(cash * 2, buffer, "cash under half the buffer");
        uint256 investedBefore = vault.maxWithdraw(address(floatManager));
        vm.prank(keeper);
        (, uint256 withdrawn) = floatManager.rebalance();
        // Back up to the buffer, or everything the venue holds if that's less.
        assertEq(withdrawn, investedBefore < buffer - cash ? investedBefore : buffer - cash);
        assertEq(floatManager.liquid(), cash + withdrawn);
    }

    function test_pay_pullsFromTheVenues_whenCashIsShort() public {
        vm.prank(keeper);
        floatManager.rebalance();
        vm.prank(sponsor);
        escrow.cancel(id);
        uint256 refunded = escrow.refund(id); // more than the cash on hand
        assertEq(refunded, dollars(90));
        assertEq(usdc.balanceOf(sponsor), dollars(90), "the sponsor got everything back at once");
    }

    function test_rebalance_onlyKeeper() public {
        vm.expectRevert(abi.encodeWithSelector(FloatManager.FloatManager__NotKeeper.selector, stranger, keeper));
        vm.prank(stranger);
        floatManager.rebalance();
    }

    // ================================================================ yield

    function test_harvestYield_sendsInterestToTheHousePool_andFillsTheReserve() public {
        vm.prank(keeper);
        floatManager.rebalance();
        uint256 invested = floatManager.invested();
        vm.warp(block.timestamp + 365 days);
        uint256 extra = floatManager.surplus();
        assertApproxEqRel(extra, invested * 400 / 10_000, 0.001e18, "4% a year on what's invested");

        uint256 surpriseBefore = housePool.bucketBalance(1);
        vm.prank(stranger); // anyone may harvest
        (uint256 toPool, uint256 toReserve) = floatManager.harvestYield();
        assertEq(toPool + toReserve, extra);
        assertLe(toReserve, extra * 2000 / 10_000, "at most 20% to the reserve");
        assertLe(floatManager.lossReserve(), floatManager.invested() * 200 / 10_000 + 1, "reserve stops at 2%");
        assertEq(housePool.bucketBalance(1) - surpriseBefore, toPool);
        assertEq(floatManager.yieldEarned(), toPool);
        assertGe(floatManager.totalAssets(), escrow.totalLiabilities() + floatManager.lossReserve(), "principal safe");

        vm.expectPartialRevert(FloatManager.FloatManager__NoYield.selector);
        floatManager.harvestYield();
    }

    function test_harvestYield_onceTheReserveIsFull_allGoesToThePool() public {
        vm.prank(keeper);
        floatManager.rebalance();
        vm.warp(block.timestamp + 365 days);
        floatManager.harvestYield(); // reserve reaches its 2% target
        vm.warp(block.timestamp + 30 days);
        uint256 reserveBefore = floatManager.lossReserve();
        (uint256 toPool, uint256 toReserve) = floatManager.harvestYield();
        assertEq(toReserve + floatManager.lossReserve() - reserveBefore, 2 * toReserve);
        assertGt(toPool, 0);
    }

    function test_harvestYield_nothingToHarvest() public {
        vm.expectRevert(abi.encodeWithSelector(FloatManager.FloatManager__NoYield.selector, dollars(90), dollars(90)));
        floatManager.harvestYield();
    }

    /// @notice Yield harvest never pays out principal, whatever happens to claims, time and the drip.
    function testFuzz_harvestNeverTouchesPrincipal(uint256 waitDays, uint256 claims, uint256 donation) public {
        waitDays = bound(waitDays, 0, 400);
        claims = bound(claims, 0, 12);
        donation = bound(donation, 0, dollars(5));
        vm.prank(keeper);
        floatManager.rebalance();
        for (uint256 i = 0; i < claims; ++i) {
            (CampaignClaim memory c, bytes memory sig) = _claim(id, sam, keccak256(abi.encode(i)), dollars(1));
            escrow.claim(c, sig);
        }
        usdc.mint(address(floatManager), donation);
        vm.warp(block.timestamp + waitDays * 1 days);
        try floatManager.harvestYield() {} catch {}
        assertGe(floatManager.totalAssets(), escrow.totalLiabilities() + floatManager.lossReserve(), "principal safe");
        // And every sponsor can still be paid in full.
        vm.warp(block.timestamp + 30 days);
        escrow.refund(id);
        assertEq(escrow.totalLiabilities(), 0);
    }

    // ================================================================ admin

    function test_venues_andAdmin() public {
        assertEq(address(floatManager.venue(0)), address(vault));
        assertEq(address(floatManager.venues()[1]), address(0));
        vm.expectRevert(abi.encodeWithSelector(FloatManager.FloatManager__BadVenueIndex.selector, 2));
        floatManager.venue(2);

        vm.prank(keeper);
        floatManager.rebalance();
        uint256 invested = floatManager.invested();
        MockYieldVault second = new MockYieldVault(usdc, 300, admin);

        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(FloatManager.FloatManager__BadVenueIndex.selector, 2));
        floatManager.setVenue(2, second);
        MockUSDC other = new MockUSDC();
        MockYieldVault wrong = new MockYieldVault(other, 300, admin);
        vm.expectRevert(
            abi.encodeWithSelector(FloatManager.FloatManager__WrongAsset.selector, address(wrong), address(other))
        );
        floatManager.setVenue(1, wrong);
        vm.expectEmit(address(floatManager));
        emit FloatManager.VenueSet(0, address(vault), address(second), invested);
        floatManager.setVenue(0, second); // everything comes out of the old venue first
        vm.expectRevert(abi.encodeWithSelector(FloatManager.FloatManager__EscrowAlreadySet.selector, address(escrow)));
        floatManager.setEscrow(ICampaignBook(address(1)));
        vm.expectEmit(address(floatManager));
        emit FloatManager.KeeperSet(keeper, sam);
        floatManager.setKeeper(sam);
        vm.expectRevert(FloatManager.FloatManager__ZeroAddress.selector);
        floatManager.setKeeper(address(0));
        vm.expectRevert(FloatManager.FloatManager__AdminCantBeRemoved.selector);
        floatManager.renounceOwnership();
        vm.stopPrank();
        assertEq(floatManager.invested(), 0);
        assertEq(floatManager.liquid(), dollars(90));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        floatManager.setVenue(1, IERC4626(address(0)));
    }

    function test_twoVenues_splitDeposits() public {
        MockYieldVault second = new MockYieldVault(usdc, 300, admin);
        vm.prank(admin);
        floatManager.setVenue(1, second);
        vm.prank(keeper);
        (uint256 deposited,) = floatManager.rebalance();
        assertApproxEqAbs(vault.totalAssets(), deposited / 2, 1);
        assertApproxEqAbs(second.totalAssets(), deposited - deposited / 2, 1);
    }

    function test_constructor_andEscrowOnce() public {
        vm.expectRevert(FloatManager.FloatManager__ZeroAddress.selector);
        new FloatManager(usdc, IHousePool(address(0)), keeper, admin);
        FloatManager fresh = new FloatManager(usdc, IHousePool(address(housePool)), keeper, admin);
        assertEq(fresh.buffer(), 0);
        assertEq(fresh.surplus(), 0);
        vm.expectRevert(FloatManager.FloatManager__ZeroAddress.selector);
        vm.prank(admin);
        fresh.setEscrow(ICampaignBook(address(0)));
        vm.expectEmit(address(fresh));
        emit FloatManager.EscrowSet(address(escrow));
        vm.prank(admin);
        fresh.setEscrow(escrow);
    }

    // ================================================================ MockYieldVault

    function test_mockVault_paysTheStatedApr_fromItsPot_andStopsWhenEmpty() public {
        usdc.mint(sam, dollars(1000));
        vm.startPrank(sam);
        usdc.approve(address(vault), dollars(1000));
        vault.deposit(dollars(1000), sam);
        vm.stopPrank();
        vm.warp(block.timestamp + 365 days);
        assertApproxEqAbs(vault.totalAssets(), dollars(1040), 1, "4% a year");
        vault.accrue();
        assertApproxEqAbs(vault.dripPot(), dollars(60), 1);

        vm.warp(block.timestamp + 10 * 365 days); // far more interest than the pot holds
        assertEq(vault.totalAssets(), dollars(1100), "capped by the pot");
        uint256 shares = vault.balanceOf(sam);
        vm.prank(sam);
        vault.redeem(shares, sam, sam);
        assertApproxEqAbs(usdc.balanceOf(sam), dollars(1100), 1);
    }

    function test_mockVault_admin() public {
        vm.startPrank(admin);
        vm.expectEmit(address(vault));
        emit MockYieldVault.AprSet(VAULT_APR_BPS, 800);
        vault.setApr(800);
        vm.expectRevert(abi.encodeWithSelector(MockYieldVault.MockYieldVault__AprTooHigh.selector, 5001, 5000));
        vault.setApr(5001);
        vm.expectRevert(MockYieldVault.MockYieldVault__ZeroAmount.selector);
        vault.fundDrip(0);
        vm.expectRevert(MockYieldVault.MockYieldVault__AdminCantBeRemoved.selector);
        vault.renounceOwnership();
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(MockYieldVault.MockYieldVault__AprTooHigh.selector, 6000, 5000));
        new MockYieldVault(usdc, 6000, admin);
        assertEq(vault.symbol(), "mockyUSDC");
        assertEq(vault.aprBps(), 800);
        assertGt(vault.lastAccrual(), 0);
        assertEq(IERC20(vault.asset()).balanceOf(address(vault)), dollars(100));
    }
}
