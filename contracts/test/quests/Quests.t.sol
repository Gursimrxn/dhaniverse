// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TownWorld} from "../kit/TownWorld.sol";
import {SpiceMerchant} from "../../src/quests/SpiceMerchant.sol";
import {QuestToken} from "../../src/quests/QuestToken.sol";
import {LuckyLedger} from "../../src/quests/LuckyLedger.sol";
import {ICampaignBook, IHousePool} from "../../src/money/Links.sol";

/// @notice SpiceMerchant (deliveries), QuestToken (MANGO) and LuckyLedger (the weekly draw).
contract QuestsTest is TownWorld {
    uint256 internal id;

    function setUp() public override {
        super.setUp();
        id = _createCampaign(_spiceRunParams());
        vm.prank(admin);
        mango.mint(sam, 100 ether);
        vm.prank(sam);
        mango.approve(address(spice), type(uint256).max);
    }

    // ================================================================ SpiceMerchant

    function test_deliver_forwardsTheTokenToTheCampaignsDeliverTo() public {
        bytes32 questRef = _ref();
        vm.expectEmit(address(spice));
        emit SpiceMerchant.Delivered(id, sam, address(mango), 12 ether, questRef);
        vm.prank(sam);
        spice.deliver(id, address(mango), 12 ether, questRef);
        assertEq(mango.balanceOf(sponsor), 12 ether);
        assertEq(mango.balanceOf(address(spice)), 0, "the merchant keeps nothing");
        assertTrue(spice.refUsed(questRef));
        assertEq(address(spice.escrow()), address(escrow));
    }

    function test_deliver_refusals() public {
        bytes32 questRef = _ref();
        vm.startPrank(sam);
        vm.expectRevert(SpiceMerchant.SpiceMerchant__ZeroAddress.selector);
        spice.deliver(id, address(0), 1, questRef);
        vm.expectRevert(SpiceMerchant.SpiceMerchant__ZeroAmount.selector);
        spice.deliver(id, address(mango), 0, questRef);
        vm.expectRevert(abi.encodeWithSelector(SpiceMerchant.SpiceMerchant__CampaignNotLive.selector, 99));
        spice.deliver(99, address(mango), 1, questRef);
        vm.expectRevert(
            abi.encodeWithSelector(SpiceMerchant.SpiceMerchant__WrongToken.selector, address(usdc), address(mango))
        );
        spice.deliver(id, address(usdc), 1, questRef);
        spice.deliver(id, address(mango), 1, questRef);
        vm.expectRevert(abi.encodeWithSelector(SpiceMerchant.SpiceMerchant__RefUsed.selector, questRef));
        spice.deliver(id, address(mango), 1, questRef);
        vm.stopPrank();

        vm.prank(sponsor);
        escrow.cancel(id);
        vm.expectRevert(abi.encodeWithSelector(SpiceMerchant.SpiceMerchant__CampaignNotLive.selector, id));
        vm.prank(sam);
        spice.deliver(id, address(mango), 1, _ref());

        vm.expectRevert(SpiceMerchant.SpiceMerchant__ZeroAddress.selector);
        new SpiceMerchant(ICampaignBook(address(0)));
    }

    // ================================================================ QuestToken

    function test_questToken_mintOnlyAdmin_permit_noRenounce() public {
        assertEq(mango.symbol(), "MANGO");
        assertEq(mango.decimals(), 18);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        mango.mint(stranger, 1);
        vm.startPrank(admin);
        vm.expectRevert(QuestToken.QuestToken__ZeroAmount.selector);
        mango.mint(sam, 0);
        vm.expectRevert(QuestToken.QuestToken__AdminCantBeRemoved.selector);
        mango.renounceOwnership();
        vm.stopPrank();
        assertGt(uint256(mango.DOMAIN_SEPARATOR()), 0);
        assertEq(mango.nonces(sam), 0);
    }

    // ================================================================ LuckyLedger

    bytes32 internal constant SEED = keccak256("week 45 secret seed");

    function test_draw_commitRevealClaim_paysTheWinnerFromSurprise() public {
        _fundBucket(1, dollars(500)); // SURPRISE: $505 incl. the campaign fee; budget ~$20 today
        (bytes32 root, bytes32 leafSam, bytes32 leafPriya) = _tree();

        vm.expectEmit(address(lucky));
        emit LuckyLedger.Committed(45, keccak256(abi.encode(SEED)), root, 30, dollars(5), block.number);
        vm.prank(keeper);
        lucky.commit(45, keccak256(abi.encode(SEED)), root, 30, dollars(5));

        vm.expectRevert(
            abi.encodeWithSelector(LuckyLedger.LuckyLedger__TooEarly.selector, block.number, block.number + 5)
        );
        lucky.reveal(45, SEED);
        vm.roll(block.number + 5);
        uint256 winner = lucky.reveal(45, SEED);
        LuckyLedger.Draw memory d = lucky.draw(45);
        assertTrue(d.revealed);
        assertEq(
            winner, uint256(keccak256(abi.encode(SEED, blockhash(d.commitBlock + 1)))) % 30, "the published formula"
        );

        (address who, uint256 from, uint256 to, bytes32 sibling) =
            winner < 10 ? (sam, uint256(0), uint256(10), leafPriya) : (priya, uint256(10), uint256(30), leafSam);
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = sibling;
        (address loser, uint256 lfrom, uint256 lto) =
            winner < 10 ? (priya, uint256(10), uint256(30)) : (sam, uint256(0), uint256(10));
        bytes32[] memory loserProof = new bytes32[](1);
        loserProof[0] = winner < 10 ? leafSam : leafPriya;
        vm.expectRevert(abi.encodeWithSelector(LuckyLedger.LuckyLedger__NotTheWinner.selector, winner, lfrom, lto));
        lucky.claim(45, loser, lfrom, lto, loserProof);
        vm.expectRevert(LuckyLedger.LuckyLedger__BadProof.selector);
        lucky.claim(45, stranger, from, to, proof); // right range, wrong player

        vm.expectEmit(address(lucky));
        emit LuckyLedger.DrawClaimed(45, who, dollars(5));
        lucky.claim(45, who, from, to, proof);
        assertEq(usdc.balanceOf(who), dollars(5));
        vm.expectRevert(abi.encodeWithSelector(LuckyLedger.LuckyLedger__AlreadyClaimed.selector, 45));
        lucky.claim(45, who, from, to, proof);
    }

    function test_draw_refusals() public {
        (bytes32 root,,) = _tree();
        vm.expectRevert(abi.encodeWithSelector(LuckyLedger.LuckyLedger__NotKeeper.selector, stranger, keeper));
        vm.prank(stranger);
        lucky.commit(1, bytes32("h"), root, 30, 1);

        vm.startPrank(keeper);
        vm.expectRevert(abi.encodeWithSelector(LuckyLedger.LuckyLedger__BadDraw.selector, 0, 1));
        lucky.commit(1, bytes32("h"), root, 0, 1);
        lucky.commit(1, keccak256(abi.encode(SEED)), root, 30, 1);
        vm.expectRevert(abi.encodeWithSelector(LuckyLedger.LuckyLedger__AlreadyCommitted.selector, 1));
        lucky.commit(1, keccak256(abi.encode(SEED)), root, 30, 1);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(LuckyLedger.LuckyLedger__NotCommitted.selector, 2));
        lucky.reveal(2, SEED);
        vm.roll(block.number + 5);
        bytes32 wrong = keccak256("wrong");
        vm.expectRevert(
            abi.encodeWithSelector(
                LuckyLedger.LuckyLedger__BadSeed.selector, keccak256(abi.encode(wrong)), keccak256(abi.encode(SEED))
            )
        );
        lucky.reveal(1, wrong);
        vm.expectRevert(abi.encodeWithSelector(LuckyLedger.LuckyLedger__NotRevealed.selector, 1));
        lucky.claim(1, sam, 0, 10, new bytes32[](0));
        lucky.reveal(1, SEED);
        vm.expectRevert(abi.encodeWithSelector(LuckyLedger.LuckyLedger__AlreadyRevealed.selector, 1));
        lucky.reveal(1, SEED);
        vm.expectRevert(abi.encodeWithSelector(LuckyLedger.LuckyLedger__AlreadyRevealed.selector, 1));
        vm.prank(admin);
        lucky.voidDraw(1);
    }

    function test_draw_missedWindow_canBeVoidedAndRecommitted() public {
        (bytes32 root,,) = _tree();
        vm.prank(keeper);
        lucky.commit(7, keccak256(abi.encode(SEED)), root, 30, 1);
        uint256 commitBlock = block.number;
        vm.roll(block.number + 300);
        vm.expectRevert(
            abi.encodeWithSelector(LuckyLedger.LuckyLedger__RevealWindowMissed.selector, commitBlock, block.number)
        );
        lucky.reveal(7, SEED);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, keeper));
        vm.prank(keeper);
        lucky.voidDraw(7);
        vm.expectEmit(address(lucky));
        emit LuckyLedger.DrawVoided(7);
        vm.prank(admin);
        lucky.voidDraw(7);
        vm.prank(keeper);
        lucky.commit(7, keccak256(abi.encode(SEED)), root, 30, 1);
        vm.expectRevert(abi.encodeWithSelector(LuckyLedger.LuckyLedger__NotCommitted.selector, 8));
        vm.prank(admin);
        lucky.voidDraw(8);
    }

    function test_draw_admin() public {
        vm.startPrank(admin);
        vm.expectEmit(address(lucky));
        emit LuckyLedger.KeeperSet(keeper, sam);
        lucky.setKeeper(sam);
        vm.expectRevert(LuckyLedger.LuckyLedger__BadSettings.selector);
        lucky.setKeeper(address(0));
        vm.expectRevert(LuckyLedger.LuckyLedger__AdminCantBeRemoved.selector);
        lucky.renounceOwnership();
        vm.stopPrank();
        vm.expectRevert(LuckyLedger.LuckyLedger__BadSettings.selector);
        new LuckyLedger(IHousePool(address(housePool)), keeper, 0, admin);
        vm.expectRevert(LuckyLedger.LuckyLedger__BadSettings.selector);
        new LuckyLedger(IHousePool(address(housePool)), keeper, 256, admin);
        assertEq(lucky.revealDelayBlocks(), REVEAL_DELAY_BLOCKS);
        assertEq(lucky.drawRef(3), keccak256(abi.encode("tallyport.draw", uint256(3))));
        assertEq(lucky.revealFromBlock(99), REVEAL_DELAY_BLOCKS);
        assertEq(lucky.BLOCKHASH_WINDOW(), 256);
    }

    // ---------------------------------------------------------------- a two-leaf ticket tree

    function _tree() internal view returns (bytes32 root, bytes32 leafSam, bytes32 leafPriya) {
        leafSam = keccak256(bytes.concat(keccak256(abi.encode(sam, uint256(0), uint256(10)))));
        leafPriya = keccak256(bytes.concat(keccak256(abi.encode(priya, uint256(10), uint256(30)))));
        root = leafSam < leafPriya
            ? keccak256(abi.encodePacked(leafSam, leafPriya))
            : keccak256(abi.encodePacked(leafPriya, leafSam));
    }
}
