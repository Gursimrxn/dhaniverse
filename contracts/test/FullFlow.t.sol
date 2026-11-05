// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {TownWorld} from "./kit/TownWorld.sol";
import {MealTicket, PayoutVoucher, CampaignClaim, AdvanceVoucher} from "../src/money/Vouchers.sol";

/// @notice One whole Tallyport story, every contract in order, with the books checked at each step:
///         a sponsor creates the Spice Run → Sam eats a thali → the farm sells a harvest → Treasury splits → the house
///         pays Sam's streak → Priya (broke) takes the cargo advance → swaps USDC for MANGO on a plain v4 pool and
///         delivers it → claims (advance repaid first) → the sponsor cancels and is refunded → the float's yield is
///         harvested → the weekly draw pays its winner. (The real Universal Router swap is in test/uniswap.)
contract FullFlowTest is TownWorld {
    PoolSwapTest internal swapRouter;
    PoolKey internal mangoKey;
    uint256 internal id;
    uint256 internal samUsdc;

    function setUp() public override {
        super.setUp();
        // The demo sponsor's MANGO/USDC pool: plain v4, fee 0.3%, no hook, ~1 MANGO = $0.05.
        swapRouter = new PoolSwapTest(manager);
        PoolModifyLiquidityTest lp = new PoolModifyLiquidityTest(manager);
        (Currency c0, Currency c1) = address(mango) < address(usdc)
            ? (Currency.wrap(address(mango)), Currency.wrap(address(usdc)))
            : (Currency.wrap(address(usdc)), Currency.wrap(address(mango)));
        mangoKey = PoolKey(c0, c1, 3000, 60, IHooks(address(0)));
        // price = token1 per token0 in base units; MANGO has 18 decimals, USDC 6.
        uint160 sqrtPrice = address(mango) < address(usdc)
            ? uint160(_sqrt(uint256(5e4) * (1 << 192) / 1e18))
            : uint160(_sqrt(uint256(1e18 / 5e4) * (1 << 192)));
        manager.initialize(mangoKey, sqrtPrice);
        vm.startPrank(admin);
        mango.mint(admin, 1_000_000 ether);
        mango.approve(address(lp), type(uint256).max);
        usdc.approve(address(lp), type(uint256).max);
        lp.modifyLiquidity(
            mangoKey,
            IPoolManager.ModifyLiquidityParams(
                TickMath.minUsableTick(60), TickMath.maxUsableTick(60), int256(uint256(1e15)), 0
            ),
            ""
        );
        vm.stopPrank();
    }

    function test_theWholeStory() public {
        _sponsorCreatesTheSpiceRun();
        _samEatsAThali();
        _farmSellsAndTreasurySplits();
        _housePaysSamsStreak();
        _priyaRunsTheSpiceRun();
        _floatEarnsAndSponsorIsRefunded();
        _weeklyDrawPaysItsWinner();

        // The pass-throughs kept nothing along the way.
        assertEq(usdc.balanceOf(address(escrow)), 0);
        assertEq(usdc.balanceOf(address(mealCounter)), 0);
        assertEq(usdc.balanceOf(address(farm)), 0);
        assertEq(usdc.balanceOf(address(treasury)), 0);
    }

    /// @dev 1. A sponsor creates the Spice Run: $100, 10% fee.
    function _sponsorCreatesTheSpiceRun() internal {
        id = _createCampaign(_spiceRunParams());
        assertEq(housePool.bucketBalance(1), dollars(5), "fee: half to SURPRISE");
        assertEq(usdc.balanceOf(address(floatManager)), dollars(90));
    }

    /// @dev 2. Sam eats a thali with a server ticket.
    function _samEatsAThali() internal {
        _giveUsdc(sam, dollars(1), address(mealCounter));
        (MealTicket memory t, bytes memory tsig) = _ticket(sam, THALI, 6 * ONE_FOOD, 6 * BASE_PRICE * 102 / 100);
        vm.prank(sam);
        (uint256 mealCost,) = mealCounter.buyMeal(t, tsig);
        samUsdc = dollars(1) - mealCost;
        assertEq(usdc.balanceOf(sam), samUsdc);
    }

    /// @dev 3. The farm sells a harvest tranche; 4. Treasury splits the revenue.
    function _farmSellsAndTreasurySplits() internal {
        vm.prank(keeper);
        (, uint256 harvestUsdc) = farm.sell(2500 * ONE_FOOD, _ref());
        treasury.split();
        assertEq(housePool.bucketBalance(0), harvestUsdc * 6000 / 10_000, "60% FIXED");
        assertEq(housePool.bucketBalance(2), harvestUsdc * 1000 / 10_000, "10% SAFETY");
    }

    /// @dev 5. The house pays Sam's streak bonus from FIXED (within 4% of the bucket).
    function _housePaysSamsStreak() internal {
        uint256 streak = housePool.bucketBalance(0) * 400 / 10_000;
        (PayoutVoucher memory pv, bytes memory psig) = _payout(sam, SAM_HUMAN, 0, streak);
        housePool.pay(pv, psig);
        samUsdc += streak;
        assertEq(usdc.balanceOf(sam), samUsdc);
    }

    /// @dev 6-8. Priya (broke) takes the cargo advance, swaps it for MANGO, delivers, and claims.
    function _priyaRunsTheSpiceRun() internal {
        (AdvanceVoucher memory a, bytes memory asig) = _advance(id, priya, PRIYA_HUMAN, 500_000);
        escrow.advance(a, asig);
        assertEq(usdc.balanceOf(priya), 500_000);

        vm.startPrank(priya);
        usdc.approve(address(swapRouter), 500_000);
        bool usdcIsToken0 = address(usdc) < address(mango);
        swapRouter.swap(
            mangoKey,
            IPoolManager.SwapParams(
                usdcIsToken0, -int256(500_000), usdcIsToken0 ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            ),
            PoolSwapTest.TestSettings(false, false),
            ""
        );
        uint256 got = mango.balanceOf(priya);
        assertApproxEqRel(got, 10 ether, 0.01e18, "about 10 MANGO for $0.50, less the 0.3% fee");
        mango.approve(address(spice), got);
        spice.deliver(id, address(mango), got, _ref());
        vm.stopPrank();
        assertEq(mango.balanceOf(sponsor), got, "the sponsor got the cargo");

        (CampaignClaim memory c, bytes memory csig) = _claim(id, priya, PRIYA_HUMAN, dollars(1));
        escrow.claim(c, csig);
        assertEq(usdc.balanceOf(priya), 500_000, "cargo repaid, reward kept");
        assertEq(escrow.remaining(id), dollars(89));
    }

    /// @dev 9-11. The float invests and earns (simulated) yield; the campaign ends and is refunded; yield harvested.
    function _floatEarnsAndSponsorIsRefunded() internal {
        usdc.mint(admin, dollars(10));
        vm.startPrank(admin);
        usdc.approve(address(vault), dollars(10));
        vault.fundDrip(dollars(10));
        vm.stopPrank();
        vm.prank(keeper);
        floatManager.rebalance();
        vm.warp(block.timestamp + 30 days);

        assertEq(escrow.refund(id), dollars(89));
        assertEq(usdc.balanceOf(sponsor), dollars(89));
        assertEq(escrow.totalLiabilities(), 0);

        uint256 surpriseBefore = housePool.bucketBalance(1);
        (uint256 toPool,) = floatManager.harvestYield();
        assertGt(toPool, 0);
        assertEq(housePool.bucketBalance(1), surpriseBefore + toPool);
    }

    /// @dev 12. The weekly draw: Sam holds every ticket this week.
    function _weeklyDrawPaysItsWinner() internal {
        bytes32 seed = keccak256("week 45");
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(sam, uint256(0), uint256(3)))));
        vm.prank(keeper);
        lucky.commit(45, keccak256(abi.encode(seed)), leaf, 3, 100_000);
        vm.roll(block.number + REVEAL_DELAY_BLOCKS);
        lucky.reveal(45, seed);
        lucky.claim(45, sam, 0, 3, new bytes32[](0));
        assertEq(usdc.balanceOf(sam), samUsdc + 100_000, "Sam won $0.10 from SURPRISE");
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        y = x;
        uint256 z = (x + 1) / 2;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
