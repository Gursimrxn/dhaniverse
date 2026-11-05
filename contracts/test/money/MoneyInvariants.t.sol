// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {TownWorld} from "../kit/TownWorld.sol";
import {CampaignEscrow, CampaignParams} from "../../src/money/CampaignEscrow.sol";
import {FloatManager} from "../../src/money/FloatManager.sol";
import {CampaignClaim, AdvanceVoucher, PayoutVoucher} from "../../src/money/Vouchers.sol";

/// @notice Drives the money contracts with random sponsors, claims, advances, replays, refunds, rebalances, harvests
///         and house payouts, and keeps the books an outside auditor would keep.
contract MoneyHandler is Test {
    MoneyInvariantsTest internal immutable WORLD;
    CampaignEscrow internal immutable ESCROW;

    uint256[] public ids;
    mapping(uint256 id => uint256) public paidToPlayers; // USDC that left the float for this campaign's players
    mapping(uint256 id => uint256) public refunded;
    uint256 public replaysThatWorked;
    uint256 public housePaidToday;
    uint256 public houseDay;

    CampaignClaim internal _lastClaim;
    bytes internal _lastClaimSig;

    constructor(MoneyInvariantsTest world) {
        WORLD = world;
        ESCROW = world.escrowForHandler();
    }

    function create(uint256 budgetSeed, uint256 daysSeed) external {
        if (ids.length >= 6) return;
        uint256 budget = bound(budgetSeed, 2e6, 200e6);
        uint256 id = WORLD.createFor(budget, bound(daysSeed, 1, 10));
        ids.push(id);
    }

    function claim(uint256 idSeed, uint256 humanSeed, uint256 amountSeed) external {
        if (ids.length == 0) return;
        uint256 id = ids[idSeed % ids.length];
        address player = address(uint160(0xA11CE + (humanSeed % 7)));
        bytes32 human = keccak256(abi.encode("human", humanSeed % 7));
        (CampaignClaim memory c, bytes memory sig) = WORLD.claimVoucher(id, player, human, bound(amountSeed, 1, 1e6));
        uint256 before = WORLD.usdcOf(player);
        try ESCROW.claim(c, sig) {
            paidToPlayers[id] += WORLD.usdcOf(player) - before;
            _lastClaim = c;
            _lastClaimSig = sig;
        } catch {}
    }

    function advance(uint256 idSeed, uint256 humanSeed, uint256 amountSeed) external {
        if (ids.length == 0) return;
        uint256 id = ids[idSeed % ids.length];
        address player = address(uint160(0xA11CE + (humanSeed % 7)));
        bytes32 human = keccak256(abi.encode("human", humanSeed % 7));
        (AdvanceVoucher memory a, bytes memory sig) = WORLD.advanceVoucher(id, player, human, bound(amountSeed, 1, 1e6));
        uint256 before = WORLD.usdcOf(player);
        try ESCROW.advance(a, sig) {
            paidToPlayers[id] += WORLD.usdcOf(player) - before;
        } catch {}
    }

    function replayLastClaim() external {
        if (_lastClaim.ref == bytes32(0)) return;
        try ESCROW.claim(_lastClaim, _lastClaimSig) {
            ++replaysThatWorked;
        } catch {}
    }

    function cancelAndRefund(uint256 idSeed) external {
        if (ids.length == 0) return;
        uint256 id = ids[idSeed % ids.length];
        address sponsor = ESCROW.campaign(id).sponsor;
        uint256 before = WORLD.usdcOf(sponsor);
        vm.prank(sponsor);
        try ESCROW.cancel(id) {} catch {}
        try ESCROW.refund(id) {
            refunded[id] += WORLD.usdcOf(sponsor) - before;
        } catch {}
    }

    function wait(uint256 hoursSeed) external {
        vm.warp(block.timestamp + bound(hoursSeed, 1, 72) * 1 hours);
    }

    function rebalance() external {
        WORLD.rebalanceAsKeeper();
    }

    function harvest() external {
        try WORLD.floatForHandler().harvestYield() {} catch {}
    }

    function housePay(uint256 bucketSeed, uint256 amountSeed, uint256 humanSeed) external {
        WORLD.housePay(uint8(bucketSeed % 3), bound(amountSeed, 1, 10e6), keccak256(abi.encode("h", humanSeed)));
    }

    function idCount() external view returns (uint256) {
        return ids.length;
    }
}

contract MoneyInvariantsTest is TownWorld {
    MoneyHandler internal handler;

    function setUp() public override {
        super.setUp();
        _fundBucket(0, dollars(1000));
        _fundBucket(1, dollars(1000));
        _fundBucket(2, dollars(1000));
        usdc.mint(admin, dollars(100));
        vm.startPrank(admin);
        usdc.approve(address(vault), dollars(100));
        vault.fundDrip(dollars(100));
        housePool.setPerHumanDailyCap(dollars(1_000_000));
        vm.stopPrank();
        handler = new MoneyHandler(this);
        targetContract(address(handler));
    }

    // ---------------------------------------------------------------- the invariants

    /// @notice A campaign never pays players + its sponsor more than its budget minus the fee.
    function invariant_escrowNeverPaysMoreThanDepositedMinusFee() public view {
        for (uint256 i = 0; i < handler.idCount(); ++i) {
            uint256 id = handler.ids(i);
            CampaignEscrow.Campaign memory c = escrow.campaign(id);
            assertLe(handler.paidToPlayers(id) + handler.refunded(id), c.net, "out <= budget - fee");
            assertEq(c.net, c.params.budget - c.params.budget * FEE_BPS / 10_000, "net is budget - fee");
            assertLe(c.spent, c.net);
            assertEq(handler.paidToPlayers(id), c.spent, "every spent USDC reached a player");
        }
    }

    /// @notice The float always covers what sponsors are owed plus the loss reserve: harvests never touch principal.
    function invariant_floatCoversLiabilities() public view {
        assertGe(floatManager.totalAssets(), escrow.totalLiabilities() + floatManager.lossReserve());
    }

    /// @notice No bucket ever spends more in a day than that day's budget.
    function invariant_poolsNeverExceedDailyBudget() public view {
        for (uint8 b = 0; b < 3; ++b) {
            (uint256 budget, uint256 spent,) = housePool.todayBudget(b);
            assertLe(spent, budget);
        }
    }

    /// @notice A ref works once: a replayed claim never pays.
    function invariant_refsWorkOnce() public view {
        assertEq(handler.replaysThatWorked(), 0);
    }

    /// @notice The pass-through contracts never keep USDC.
    function invariant_passThroughsHoldNothing() public view {
        assertEq(usdc.balanceOf(address(escrow)), 0);
        assertEq(usdc.balanceOf(address(mealCounter)), 0);
    }

    // ---------------------------------------------------------------- what the handler needs from the world

    function escrowForHandler() external view returns (CampaignEscrow) {
        return escrow;
    }

    function floatForHandler() external view returns (FloatManager) {
        return floatManager;
    }

    function usdcOf(address who) external view returns (uint256) {
        return usdc.balanceOf(who);
    }

    function createFor(uint256 budget, uint256 lengthDays) external returns (uint256) {
        CampaignParams memory p = _spiceRunParams();
        p.budget = budget;
        p.end = uint64(block.timestamp + lengthDays * 1 days);
        p.perHumanCap = 3;
        return _createCampaign(p);
    }

    function claimVoucher(uint256 id, address player, bytes32 human, uint256 amount)
        external
        returns (CampaignClaim memory, bytes memory)
    {
        return _claim(id, player, human, amount);
    }

    function advanceVoucher(uint256 id, address player, bytes32 human, uint256 amount)
        external
        returns (AdvanceVoucher memory, bytes memory)
    {
        return _advance(id, player, human, amount);
    }

    function rebalanceAsKeeper() external {
        vm.prank(keeper);
        floatManager.rebalance();
    }

    function housePay(uint8 bucket, uint256 amount, bytes32 human) external {
        (PayoutVoucher memory v, bytes memory sig) = _payout(sam, human, bucket, amount);
        try housePool.pay(v, sig) {} catch {}
    }
}
