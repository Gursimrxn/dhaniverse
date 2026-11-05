// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TownWorld} from "../kit/TownWorld.sol";
import {CampaignEscrow, CampaignParams} from "../../src/money/CampaignEscrow.sol";
import {IHousePool, IFloatManager} from "../../src/money/Links.sol";
import {CampaignClaim, AdvanceVoucher} from "../../src/money/Vouchers.sol";

/// @notice CampaignEscrow: sponsor money and its rules (fee, I1, daily cap, claims, advances, refunds, pause).
contract CampaignEscrowTest is TownWorld {
    uint256 internal id;

    function setUp() public override {
        super.setUp();
        id = _createCampaign(_spiceRunParams());
    }

    // ================================================================ creating a campaign

    function test_create_splitsTheFee_andParksTheBudgetInTheFloat() public view {
        assertEq(usdc.balanceOf(address(floatManager)), dollars(90), "90% to the float");
        assertEq(housePool.bucketBalance(1), dollars(5), "half the 10% fee to SURPRISE");
        assertEq(usdc.balanceOf(team), dollars(5), "half to the team");
        assertEq(usdc.balanceOf(address(escrow)), 0, "escrow holds nothing");
        assertEq(escrow.totalLiabilities(), dollars(90));
        assertEq(escrow.remaining(id), dollars(90));
        CampaignEscrow.Campaign memory c = escrow.campaign(id);
        assertEq(c.sponsor, sponsor);
        assertEq(c.net, dollars(90));
        assertEq(c.params.questToken, address(mango));
        assertEq(escrow.questToken(id), address(mango));
        assertEq(escrow.deliverTo(id), sponsor);
        assertTrue(escrow.isLive(id));
        assertEq(escrow.openCampaigns().length, 1);
        assertEq(escrow.campaignCount(), 1);
    }

    function test_create_emitsTheWholeParams() public {
        CampaignParams memory p = _spiceRunParams();
        usdc.mint(sponsor, p.budget);
        vm.startPrank(sponsor);
        usdc.approve(address(escrow), p.budget);
        vm.expectEmit(address(escrow));
        emit CampaignEscrow.CampaignCreated(2, sponsor, p, dollars(90), dollars(10));
        escrow.createCampaign(p);
        vm.stopPrank();
    }

    function test_create_quarterRule_I1() public {
        CampaignParams memory p = _spiceRunParams();
        p.energyCost = 50;
        p.payoutPerClaim = 150_000; // 50 energy = 5 FOOD; at the $0.008 ceiling that's $0.04; x4 = $0.16 > $0.15
        _expectCreateRevert(
            p, abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__BreaksQuarterRule.selector, 160_000, 150_000)
        );
        p.payoutPerClaim = 160_000; // exactly 4x passes
        _createCampaign(p);
        assertEq(escrow.minPayoutFor(50), 160_000);
        assertEq(escrow.minPayoutFor(10), MIN_PAYOUT, "the minimum payout applies below that");
    }

    function test_create_refusals() public {
        CampaignParams memory p = _spiceRunParams();
        p.payoutPerClaim = 149_999;
        _expectCreateRevert(
            p, abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__PayoutTooSmall.selector, 149_999, MIN_PAYOUT)
        );

        p = _spiceRunParams();
        p.end = p.start;
        _expectCreateRevert(
            p,
            abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__BadWindow.selector, p.start, p.end, block.timestamp)
        );

        p = _spiceRunParams();
        p.budget = dollars(1); // net $0.90 < $1
        _expectCreateRevert(
            p, abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__BudgetTooSmall.selector, 900_000, dollars(1))
        );

        p = _spiceRunParams();
        p.maxClaims = 0;
        _expectCreateRevert(p, abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__BadLimits.selector, 0, 1));

        p = _spiceRunParams();
        p.kind = 2;
        _expectCreateRevert(p, abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__BadKind.selector, 2));

        p = _spiceRunParams();
        p.deliverTo = address(0);
        _expectCreateRevert(p, abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__ZeroAddress.selector));

        p = _spiceRunParams();
        p.questToken = address(0);
        _expectCreateRevert(
            p, abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__QuestTokenMissing.selector, SPICE_RUN)
        );
        p.template = keccak256("paint_sign"); // a template without a token is fine without one
        _createCampaign(p);
    }

    function test_create_tooManyOpen() public {
        CampaignParams memory p = _spiceRunParams();
        p.budget = 200_000;
        p.payoutPerClaim = MIN_PAYOUT;
        p.energyCost = 10;
        for (uint256 i = 1; i < escrow.MAX_OPEN_CAMPAIGNS(); ++i) {
            _createCampaign(p);
        }
        _expectCreateRevert(p, abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__TooManyOpen.selector, 100, 100));
    }

    // ================================================================ claims

    function test_claim_paysThePlayer() public {
        (CampaignClaim memory c, bytes memory sig) = _claim(id, sam, SAM_HUMAN, dollars(1));
        vm.expectEmit(address(escrow));
        emit CampaignEscrow.Claimed(id, sam, SAM_HUMAN, dollars(1), 0, c.ref);
        vm.prank(stranger);
        escrow.claim(c, sig);
        assertEq(usdc.balanceOf(sam), dollars(1));
        assertEq(escrow.remaining(id), dollars(89));
        assertEq(escrow.totalLiabilities(), dollars(89));
        assertEq(usdc.balanceOf(address(floatManager)), dollars(89));
        (uint256 claims,) = escrow.humanState(id, SAM_HUMAN);
        assertEq(claims, 1);
        assertTrue(escrow.refUsed(c.ref));
    }

    function test_claim_signatureAndRefRefusals() public {
        (CampaignClaim memory c, bytes memory sig) = _claim(id, sam, SAM_HUMAN, dollars(1));
        bytes memory forged = _signClaim(c, ticketSignerKey);
        vm.expectRevert(
            abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__BadSignature.selector, ticketSigner, voucherSigner)
        );
        escrow.claim(c, forged);

        CampaignClaim memory tampered = c;
        tampered.campaignId = 99; // the campaign id is signed: a voucher can't be moved to another campaign
        vm.expectPartialRevert(CampaignEscrow.CampaignEscrow__BadSignature.selector);
        escrow.claim(tampered, sig);
        c.campaignId = id; // (tampered points at the same memory as c)

        escrow.claim(c, sig);
        vm.expectRevert(abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__RefUsed.selector, c.ref));
        escrow.claim(c, sig);

        (c, sig) = _claim(id, priya, PRIYA_HUMAN, dollars(1));
        vm.warp(c.expiry + 1);
        vm.expectRevert(abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__Expired.selector, c.expiry, c.expiry + 1));
        escrow.claim(c, sig);

        (c, sig) = _claim(id, priya, bytes32(0), dollars(1));
        vm.expectRevert(abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__NotVerified.selector, priya));
        escrow.claim(c, sig);
    }

    function test_claim_amountAndSlotRefusals() public {
        (CampaignClaim memory c, bytes memory sig) = _claim(id, sam, SAM_HUMAN, dollars(1) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__BadAmount.selector, dollars(1) + 1, dollars(1))
        );
        escrow.claim(c, sig);
        (c, sig) = _claim(id, sam, SAM_HUMAN, 0);
        vm.expectRevert(abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__BadAmount.selector, 0, dollars(1)));
        escrow.claim(c, sig);

        _claimOk(id, sam, SAM_HUMAN, dollars(1));
        (c, sig) = _claim(id, sam, SAM_HUMAN, dollars(1));
        vm.expectRevert(
            abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__HumanCapReached.selector, id, SAM_HUMAN, 1, 1)
        );
        escrow.claim(c, sig);

        (c, sig) = _claim(99, sam, SAM_HUMAN, dollars(1));
        vm.expectRevert(abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__UnknownCampaign.selector, 99));
        escrow.claim(c, sig);
    }

    function test_claim_soldOut() public {
        CampaignParams memory p = _spiceRunParams();
        p.maxClaims = 2;
        uint256 small = _createCampaign(p);
        _claimOk(small, sam, SAM_HUMAN, dollars(1));
        _claimOk(small, priya, PRIYA_HUMAN, dollars(1));
        (CampaignClaim memory c, bytes memory sig) = _claim(small, stranger, keccak256("third"), dollars(1));
        vm.expectRevert(abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__SoldOut.selector, small, 2, 2));
        escrow.claim(c, sig);
    }

    function test_dailyCap_spreadsTheBudget_andTheServerRetriesTomorrow() public {
        uint256 cap = dollars(90) / 7; // 12.857142 USDC a day
        assertEq(escrow.dailyCap(id), cap);
        for (uint256 i = 0; i < 12; ++i) {
            _claimOk(id, sam, keccak256(abi.encode("human", i)), dollars(1));
        }
        assertEq(escrow.dailyCapLeft(id), cap - dollars(12));
        (CampaignClaim memory c, bytes memory sig) = _claim(id, sam, keccak256("13th"), dollars(1));
        vm.expectRevert(
            abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__DailyCapReached.selector, id, dollars(13), cap)
        );
        escrow.claim(c, sig);

        vm.warp(block.timestamp + 1 days);
        assertEq(escrow.dailyCap(id), dollars(78) / 6, "tomorrow: what's left over the days left");
        c.expiry = uint64(block.timestamp + 1 hours);
        escrow.claim(c, _signClaim(c, voucherSignerKey));
    }

    function test_dailyCap_atLeastOnePayoutADay() public {
        CampaignParams memory p = _spiceRunParams();
        p.budget = dollars(5); // net $4.50 over 30 days: $0.15 a day, but a claim is $1
        p.end = uint64(block.timestamp + 30 days);
        uint256 thin = _createCampaign(p);
        assertEq(escrow.dailyCap(thin), dollars(1));
        _claimOk(thin, sam, SAM_HUMAN, dollars(1));
    }

    function test_claim_overRemaining() public {
        CampaignParams memory p = _spiceRunParams();
        p.budget = 2_500_000; // net $2.25, one day
        p.end = uint64(block.timestamp + 1 days);
        uint256 small = _createCampaign(p);
        _claimOk(small, sam, SAM_HUMAN, dollars(1));
        _claimOk(small, priya, PRIYA_HUMAN, dollars(1));
        (CampaignClaim memory c, bytes memory sig) = _claim(small, stranger, keccak256("third"), dollars(1));
        vm.expectRevert(
            abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__OverRemaining.selector, small, dollars(1), 250_000)
        );
        escrow.claim(c, sig);
    }

    function test_claim_notLiveBeforeStartAndAfterEnd() public {
        CampaignParams memory p = _spiceRunParams();
        p.start = uint64(block.timestamp + 1 days);
        p.end = uint64(block.timestamp + 2 days);
        uint256 later = _createCampaign(p);
        assertFalse(escrow.isLive(later));
        (CampaignClaim memory c, bytes memory sig) = _claim(later, sam, SAM_HUMAN, dollars(1));
        vm.expectRevert(
            abi.encodeWithSelector(
                CampaignEscrow.CampaignEscrow__NotLive.selector, later, p.start, p.end, block.timestamp
            )
        );
        escrow.claim(c, sig);

        vm.warp(p.end + 1);
        c.expiry = uint64(block.timestamp + 1 hours);
        sig = _signClaim(c, voucherSignerKey);
        vm.expectRevert(
            abi.encodeWithSelector(
                CampaignEscrow.CampaignEscrow__NotLive.selector, later, p.start, p.end, block.timestamp
            )
        );
        escrow.claim(c, sig);
    }

    // ================================================================ advances

    function test_advance_thenClaim_repaysTheAdvanceFirst() public {
        (AdvanceVoucher memory a, bytes memory sig) = _advance(id, sam, SAM_HUMAN, 500_000);
        vm.expectEmit(address(escrow));
        emit CampaignEscrow.Advanced(id, sam, SAM_HUMAN, 500_000, a.ref);
        escrow.advance(a, sig);
        assertEq(usdc.balanceOf(sam), 500_000, "the cargo money");
        (, uint256 open) = escrow.humanState(id, SAM_HUMAN);
        assertEq(open, 500_000);
        assertEq(escrow.remaining(id), dollars(90) - 500_000);

        (CampaignClaim memory c, bytes memory csig) = _claim(id, sam, SAM_HUMAN, dollars(1));
        vm.expectEmit(address(escrow));
        emit CampaignEscrow.Claimed(id, sam, SAM_HUMAN, dollars(1), 500_000, c.ref);
        escrow.claim(c, csig);
        assertEq(usdc.balanceOf(sam), dollars(1), "advance + rest = one payout in total");
        (, open) = escrow.humanState(id, SAM_HUMAN);
        assertEq(open, 0);
        assertEq(escrow.remaining(id), dollars(89), "the campaign spent exactly one payout");
        assertEq(escrow.campaign(id).advancesOut, 0);
    }

    function test_advance_refusals() public {
        (AdvanceVoucher memory a, bytes memory sig) = _advance(id, sam, SAM_HUMAN, MAX_ADVANCE + 1);
        vm.expectRevert(
            abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__BadAmount.selector, MAX_ADVANCE + 1, MAX_ADVANCE)
        );
        escrow.advance(a, sig);

        (a, sig) = _advance(id, sam, SAM_HUMAN, 500_000);
        escrow.advance(a, sig);
        (a, sig) = _advance(id, sam, SAM_HUMAN, 100_000);
        vm.expectRevert(
            abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__AdvanceOpen.selector, id, SAM_HUMAN, 500_000)
        );
        escrow.advance(a, sig);

        // A human who already used up their claims can't take an advance they could never repay.
        _claimOk(id, priya, PRIYA_HUMAN, dollars(1));
        (a, sig) = _advance(id, priya, PRIYA_HUMAN, 100_000);
        vm.expectRevert(
            abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__HumanCapReached.selector, id, PRIYA_HUMAN, 1, 1)
        );
        escrow.advance(a, sig);
    }

    // ================================================================ cancel, refund, pause

    function test_cancel_stopsClaims_andRefundReturnsTheUnspentBudget() public {
        _claimOk(id, sam, SAM_HUMAN, dollars(1));
        (AdvanceVoucher memory a, bytes memory asig) = _advance(id, priya, PRIYA_HUMAN, 500_000);
        escrow.advance(a, asig); // never repaid

        vm.expectRevert(abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__NotSponsor.selector, stranger, sponsor));
        vm.prank(stranger);
        escrow.cancel(id);
        vm.expectRevert(
            abi.encodeWithSelector(
                CampaignEscrow.CampaignEscrow__NotEnded.selector, id, _spiceRunParams().end, block.timestamp
            )
        );
        escrow.refund(id);

        vm.expectEmit(address(escrow));
        emit CampaignEscrow.Cancelled(id);
        vm.prank(sponsor);
        escrow.cancel(id);
        assertFalse(escrow.isLive(id));
        assertEq(escrow.pendingRefunds(), dollars(90) - dollars(1) - 500_000);
        assertEq(escrow.liveDailyCapSum(), 0);

        (CampaignClaim memory c, bytes memory sig) = _claim(id, stranger, keccak256("late"), dollars(1));
        vm.expectRevert(abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__Closed.selector, id, false, true));
        escrow.claim(c, sig);

        uint256 expected = dollars(88) + 500_000;
        vm.expectEmit(address(escrow));
        emit CampaignEscrow.Refunded(id, sponsor, expected, 500_000);
        vm.prank(stranger); // anyone may trigger it; the money goes to the sponsor
        assertEq(escrow.refund(id), expected);
        assertEq(usdc.balanceOf(sponsor), expected);
        assertEq(escrow.totalLiabilities(), 0);
        assertEq(escrow.remaining(id), 0);
        assertEq(escrow.openCampaigns().length, 0);

        vm.expectRevert(abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__AlreadyRefunded.selector, id));
        escrow.refund(id);
        vm.expectRevert(abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__AlreadyRefunded.selector, id));
        vm.prank(sponsor);
        escrow.cancel(id);
    }

    function test_refund_afterTheEnd() public {
        vm.warp(_spiceRunParams().end + 1);
        assertEq(escrow.pendingRefunds(), dollars(90));
        escrow.refund(id);
        assertEq(usdc.balanceOf(sponsor), dollars(90));
    }

    function test_pause_onlyAdmin_stopsPayouts() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, sponsor));
        vm.prank(sponsor);
        escrow.setPaused(id, true);

        vm.expectEmit(address(escrow));
        emit CampaignEscrow.PausedSet(id, true);
        vm.prank(admin);
        escrow.setPaused(id, true);
        (CampaignClaim memory c, bytes memory sig) = _claim(id, sam, SAM_HUMAN, dollars(1));
        vm.expectRevert(abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__Closed.selector, id, true, false));
        escrow.claim(c, sig);

        vm.prank(admin);
        escrow.setPaused(id, false);
        escrow.claim(c, sig);

        vm.expectRevert(abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__UnknownCampaign.selector, 42));
        vm.prank(admin);
        escrow.setPaused(42, true);
    }

    // ================================================================ views for FloatManager and admin

    function test_liveDailyCapSum_coversLiveCampaigns() public {
        uint256 second = _createCampaign(_spiceRunParams());
        assertEq(escrow.liveDailyCapSum(), escrow.dailyCap(id) + escrow.dailyCap(second));
        assertEq(escrow.pendingRefunds(), 0);
    }

    function test_admin() public {
        vm.startPrank(admin);
        vm.expectEmit(address(escrow));
        emit CampaignEscrow.VoucherSignerSet(voucherSigner, sam);
        escrow.setVoucherSigner(sam);
        vm.expectRevert(CampaignEscrow.CampaignEscrow__ZeroAddress.selector);
        escrow.setVoucherSigner(address(0));
        vm.expectEmit(address(escrow));
        emit CampaignEscrow.TeamSet(team, priya);
        escrow.setTeam(priya);
        vm.expectRevert(CampaignEscrow.CampaignEscrow__ZeroAddress.selector);
        escrow.setTeam(address(0));
        vm.expectEmit(address(escrow));
        emit CampaignEscrow.LimitsSet(1, 2);
        escrow.setLimits(1, 2);
        vm.expectRevert(CampaignEscrow.CampaignEscrow__AdminCantBeRemoved.selector);
        escrow.renounceOwnership();
        vm.stopPrank();
        assertEq(escrow.minPayout(), 1);
        assertEq(escrow.maxAdvance(), 2);
        assertEq(escrow.feeBps(), FEE_BPS);
    }

    function test_constructor_refusals() public {
        vm.expectRevert(abi.encodeWithSelector(CampaignEscrow.CampaignEscrow__BadFee.selector, 10_000));
        new CampaignEscrow(
            usdc,
            hook,
            IHousePool(address(housePool)),
            IFloatManager(address(floatManager)),
            team,
            voucherSigner,
            10_000,
            1,
            1,
            admin
        );
        vm.expectRevert(CampaignEscrow.CampaignEscrow__ZeroAddress.selector);
        new CampaignEscrow(
            IERC20(address(0)),
            hook,
            IHousePool(address(housePool)),
            IFloatManager(address(floatManager)),
            team,
            voucherSigner,
            1000,
            1,
            1,
            admin
        );
    }

    // ================================================================ the money rule

    /// @notice Any mix of claims, advances and days, then a refund: players + sponsor together never get more than
    ///         the budget minus the fee, and the float keeps exactly what's still owed.
    function testFuzz_escrowNeverPaysMoreThanDepositedMinusFee(uint8[16] memory actions, uint256[16] memory amounts)
        public
    {
        uint256 paidOut;
        uint256 sponsorBefore = usdc.balanceOf(sponsor);
        for (uint256 i = 0; i < 16; ++i) {
            bytes32 human = keccak256(abi.encode("h", actions[i] % 5));
            address player = address(uint160(0xBEEF0000 + (actions[i] % 5)));
            uint256 before = usdc.balanceOf(player);
            uint8 kind = actions[i] % 3;
            if (kind == 0) {
                (CampaignClaim memory c, bytes memory sig) = _claim(id, player, human, bound(amounts[i], 1, dollars(1)));
                try escrow.claim(c, sig) {} catch {}
            } else if (kind == 1) {
                (AdvanceVoucher memory a, bytes memory sig) =
                    _advance(id, player, human, bound(amounts[i], 1, MAX_ADVANCE));
                try escrow.advance(a, sig) {} catch {}
            } else {
                vm.warp(block.timestamp + 1 days);
            }
            paidOut += usdc.balanceOf(player) - before;
            assertEq(usdc.balanceOf(address(floatManager)), escrow.totalLiabilities(), "the float holds what's owed");
            assertLe(paidOut, dollars(90));
        }
        vm.warp(block.timestamp + 8 days);
        escrow.refund(id);
        uint256 refunded = usdc.balanceOf(sponsor) - sponsorBefore;
        assertEq(paidOut + refunded, dollars(90), "players + refund = budget - fee, exactly");
        assertEq(usdc.balanceOf(address(floatManager)), 0);
    }

    // ================================================================ helpers

    function _claimOk(uint256 campaignId, address player, bytes32 human, uint256 amount) internal {
        (CampaignClaim memory c, bytes memory sig) = _claim(campaignId, player, human, amount);
        escrow.claim(c, sig);
    }

    function _expectCreateRevert(CampaignParams memory p, bytes memory err) internal {
        usdc.mint(sponsor, p.budget);
        vm.startPrank(sponsor);
        usdc.approve(address(escrow), p.budget);
        vm.expectRevert(err);
        escrow.createCampaign(p);
        vm.stopPrank();
    }
}
