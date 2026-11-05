// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {FoodHook} from "../food/FoodHook.sol";
import {ICampaignBook, IFloatManager, IHousePool} from "./Links.sol";
import {AdvanceVoucher, CampaignClaim, Vouchers} from "./Vouchers.sol";

/// @notice What a sponsor sets when creating a campaign (build spec 2.6). Money in USDC base units, times in unix
///         seconds.
struct CampaignParams {
    bytes32 template; // keccak256 of the quest template name, e.g. keccak256("spice_run")
    bytes32 metaHash; // Swarm reference of the campaign's story/media JSON
    uint256 budget; // what the sponsor deposits, before the platform fee
    uint256 payoutPerClaim; // what one completed quest pays
    uint32 energyCost; // energy one attempt costs the player
    uint32 maxClaims; // the most completions the campaign pays for
    uint16 perHumanCap; // the most completions one human may be paid for
    uint64 start;
    uint64 end;
    uint8 kind; // 0 Sponsored, 1 Boosted
    address deliverTo; // where delivered quest tokens go (e.g. the sponsor)
    address questToken; // the token the quest uses (e.g. MANGO); zero for templates without one
}

/// @title CampaignEscrow
/// @notice Sponsor money and its rules. A sponsor creates a campaign and deposits its budget; 10% is the platform
///         fee (half to HousePool's SURPRISE bucket, half to the team) and the rest is the campaign's spendable
///         budget, held by FloatManager. Players are paid per completed quest through server-signed CampaignClaims,
///         within a daily cap that spreads the budget over the campaign's days. A short wallet can get one advance
///         ("cargo") per campaign, repaid first from its next claim. After the end (or a sponsor's cancel) the unspent
///         budget goes back to the sponsor.
/// @dev Invariant I1, the 25% rule, is enforced on create: the food for a quest's energy, at FoodHook's ceiling price,
///      costs at most a quarter of its payout. Escrow never holds USDC between calls.
///      Spec: docs/architecture/spec.json, contract "CampaignEscrow".
// forge-lint: disable-start(block-timestamp) expiries and days are hours long; a validator's few seconds don't matter
contract CampaignEscrow is ICampaignBook, EIP712, Ownable2Step, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    /// @notice Campaign kinds.
    uint8 public constant KIND_SPONSORED = 0;
    uint8 public constant KIND_BOOSTED = 1;
    /// @notice One FOOD is worth 10 energy in the game.
    uint256 public constant ENERGY_PER_FOOD = 10;
    /// @notice I1: a quest pays at least 4x the ceiling cost of its energy.
    uint256 public constant QUARTER_RULE_MULTIPLE = 4;
    /// @notice At most this many campaigns can be open (not yet refunded) at once, so every scan stays bounded.
    uint256 public constant MAX_OPEN_CAMPAIGNS = 100;
    /// @notice Templates whose quests trade or hold a token, so they must name their questToken.
    bytes32 public constant SPICE_RUN_TEMPLATE = keccak256("spice_run");
    bytes32 public constant HOLD_LINE_TEMPLATE = keccak256("hold_line");
    uint256 private constant BPS = 10_000;
    uint256 private constant DAY_SECONDS = 1 days;
    uint8 private constant SURPRISE_BUCKET = 1;

    IERC20 private immutable USDC;
    FoodHook private immutable HOOK;
    IHousePool private immutable HOUSE_POOL;
    IFloatManager private immutable FLOAT;
    /// @notice The platform fee taken at deposit, in basis points of the budget (launch 1,000 = 10%).
    uint256 public immutable feeBps;

    /// @notice Receives the team's half of the fee.
    address public team;
    /// @notice The server key whose EIP-712 signature makes a claim or advance valid.
    address public voucherSigner;
    /// @notice The smallest payout per claim a campaign may offer (launch 150,000 = $0.15).
    uint256 public minPayout;
    /// @notice The largest advance (launch 1,000,000 = $1).
    uint256 public maxAdvance;

    /// @notice One campaign's record.
    struct Campaign {
        address sponsor;
        CampaignParams params;
        uint256 net; // budget minus fee: what players can be paid
        uint256 spent; // paid to players so far, advances included
        uint256 advancesOut; // advances not yet repaid
        uint32 claims;
        bool paused;
        bool cancelled;
        bool refunded;
    }

    /// @dev Today's daily cap, fixed at the day's first payout. `dayPlusOne` is zero until a payout happens.
    struct CapDay {
        uint64 dayPlusOne;
        uint256 cap;
        uint256 spent;
    }

    uint256 public campaignCount;
    mapping(uint256 id => Campaign) private _campaigns;
    mapping(uint256 id => CapDay) private _capDays;
    mapping(uint256 id => mapping(bytes32 humanId => uint256)) private _humanClaims;
    mapping(uint256 id => mapping(bytes32 humanId => uint256)) private _openAdvance;
    mapping(bytes32 ref => bool) private _refUsed;
    uint256 private _liabilities;
    EnumerableSet.UintSet private _open;

    /// @notice A campaign was created and funded. net is its spendable budget; fee was split between HousePool's
    ///         SURPRISE bucket and the team.
    event CampaignCreated(
        uint256 indexed campaignId, address indexed sponsor, CampaignParams params, uint256 net, uint256 fee
    );
    /// @notice A completed quest was paid: the player received amount - advanceRepaid.
    event Claimed(
        uint256 indexed campaignId,
        address indexed player,
        bytes32 indexed humanId,
        uint256 amount,
        uint256 advanceRepaid,
        bytes32 ref
    );
    /// @notice A human was advanced USDC from the campaign, to be repaid from their next claim.
    event Advanced(
        uint256 indexed campaignId, address indexed player, bytes32 indexed humanId, uint256 amount, bytes32 ref
    );
    /// @notice The unspent budget went back to the sponsor. advancesUnpaid were never repaid and are lost.
    event Refunded(uint256 indexed campaignId, address indexed sponsor, uint256 amount, uint256 advancesUnpaid);
    /// @notice The sponsor ended the campaign early: no new claims or advances.
    event Cancelled(uint256 indexed campaignId);
    /// @notice The admin paused or unpaused a campaign (abuse).
    event PausedSet(uint256 indexed campaignId, bool paused);
    /// @notice The campaign's first payout of the day fixed that day's cap (USDC base units).
    event DailyCapOpened(uint256 indexed campaignId, uint256 indexed day, uint256 cap);
    event VoucherSignerSet(address indexed oldSigner, address indexed newSigner);
    event TeamSet(address indexed oldTeam, address indexed newTeam);
    event LimitsSet(uint256 minPayout, uint256 maxAdvance);

    /// @notice The payout per claim is under the minimum (USDC base units).
    error CampaignEscrow__PayoutTooSmall(uint256 payoutPerClaim, uint256 minPayout);
    /// @notice I1: the food for the quest's energy at the ceiling price, times 4, is more than the payout.
    error CampaignEscrow__BreaksQuarterRule(uint256 ceilingFoodCostX4, uint256 payoutPerClaim);
    /// @notice The campaign must start before it ends and end in the future (unix seconds).
    error CampaignEscrow__BadWindow(uint64 start, uint64 end, uint256 nowSeconds);
    /// @notice After the fee, the budget can't pay even one claim.
    error CampaignEscrow__BudgetTooSmall(uint256 net, uint256 payoutPerClaim);
    /// @notice maxClaims and perHumanCap must be above zero.
    error CampaignEscrow__BadLimits(uint32 maxClaims, uint16 perHumanCap);
    /// @notice This template (spice_run, hold_line) needs a quest token.
    error CampaignEscrow__QuestTokenMissing(bytes32 template);
    /// @notice Kind must be 0 (Sponsored) or 1 (Boosted).
    error CampaignEscrow__BadKind(uint8 kind);
    /// @notice Too many campaigns are open; refund ended ones first.
    error CampaignEscrow__TooManyOpen(uint256 open, uint256 max);
    /// @notice No campaign has this id.
    error CampaignEscrow__UnknownCampaign(uint256 campaignId);
    /// @notice The campaign isn't running now (unix seconds).
    error CampaignEscrow__NotLive(uint256 campaignId, uint64 start, uint64 end, uint256 nowSeconds);
    /// @notice The campaign is paused or cancelled.
    error CampaignEscrow__Closed(uint256 campaignId, bool paused, bool cancelled);
    /// @notice This ref was already used: the retry was blocked.
    error CampaignEscrow__RefUsed(bytes32 ref);
    /// @notice The voucher's expiry (unix seconds) has passed.
    error CampaignEscrow__Expired(uint64 expiry, uint256 nowSeconds);
    /// @notice The voucher wasn't signed by the voucher signer.
    error CampaignEscrow__BadSignature(address recovered, address expected);
    /// @notice Payouts go only to verified humans (humanId can't be zero) and real addresses.
    error CampaignEscrow__NotVerified(address player);
    /// @notice The claim is zero or more than the campaign's payout per claim.
    error CampaignEscrow__BadAmount(uint256 amount, uint256 max);
    /// @notice Every claim the campaign pays for has been made.
    error CampaignEscrow__SoldOut(uint256 campaignId, uint32 claims, uint32 maxClaims);
    /// @notice This human has been paid for this campaign as often as allowed.
    error CampaignEscrow__HumanCapReached(uint256 campaignId, bytes32 humanId, uint256 claims, uint16 cap);
    /// @notice Today's cap is reached; the server retries tomorrow (USDC base units).
    error CampaignEscrow__DailyCapReached(uint256 campaignId, uint256 wouldSpend, uint256 cap);
    /// @notice The payment is more than the campaign has left.
    error CampaignEscrow__OverRemaining(uint256 campaignId, uint256 amount, uint256 remaining);
    /// @notice This human already has an open advance on this campaign.
    error CampaignEscrow__AdvanceOpen(uint256 campaignId, bytes32 humanId, uint256 open);
    /// @notice Only the campaign's sponsor may cancel it.
    error CampaignEscrow__NotSponsor(address sender, address sponsor);
    /// @notice A refund needs the campaign to have ended or been cancelled.
    error CampaignEscrow__NotEnded(uint256 campaignId, uint64 end, uint256 nowSeconds);
    /// @notice The campaign was already refunded.
    error CampaignEscrow__AlreadyRefunded(uint256 campaignId);
    /// @notice The fee must be below 10,000 bps.
    error CampaignEscrow__BadFee(uint256 feeBps);
    /// @notice An address that must be set was zero.
    error CampaignEscrow__ZeroAddress();
    /// @notice The admin role can be handed over, but never thrown away.
    error CampaignEscrow__AdminCantBeRemoved();

    constructor(
        IERC20 usdc,
        FoodHook hook,
        IHousePool housePool,
        IFloatManager floatManager,
        address team_,
        address voucherSigner_,
        uint256 feeBps_,
        uint256 minPayout_,
        uint256 maxAdvance_,
        address admin
    ) EIP712(Vouchers.DOMAIN_NAME, Vouchers.DOMAIN_VERSION) Ownable(admin) {
        if (
            address(usdc) == address(0) || address(hook) == address(0) || address(housePool) == address(0)
                || address(floatManager) == address(0) || team_ == address(0) || voucherSigner_ == address(0)
        ) revert CampaignEscrow__ZeroAddress();
        if (feeBps_ >= BPS) revert CampaignEscrow__BadFee(feeBps_);
        USDC = usdc;
        HOOK = hook;
        HOUSE_POOL = housePool;
        FLOAT = floatManager;
        feeBps = feeBps_;
        team = team_;
        voucherSigner = voucherSigner_;
        minPayout = minPayout_;
        maxAdvance = maxAdvance_;
        emit TeamSet(address(0), team_);
        emit VoucherSignerSet(address(0), voucherSigner_);
        emit LimitsSet(minPayout_, maxAdvance_);
    }

    // ---------------------------------------------------------------- sponsors

    /// @notice Creates a campaign and pulls `p.budget` USDC from the sender (open sign-up). The fee is split at once;
    ///         the rest goes to FloatManager as the campaign's budget.
    /// @return campaignId The new campaign's id (ids start at 1).
    function createCampaign(CampaignParams calldata p) external nonReentrant returns (uint256 campaignId) {
        _checkParams(p);
        uint256 fee = p.budget * feeBps / BPS;
        uint256 net = p.budget - fee;
        if (net < p.payoutPerClaim) revert CampaignEscrow__BudgetTooSmall(net, p.payoutPerClaim);
        if (_open.length() >= MAX_OPEN_CAMPAIGNS) {
            revert CampaignEscrow__TooManyOpen(_open.length(), MAX_OPEN_CAMPAIGNS);
        }

        campaignId = ++campaignCount;
        Campaign storage c = _campaigns[campaignId];
        c.sponsor = msg.sender;
        c.params = p;
        c.net = net;
        _open.add(campaignId);
        _liabilities += net;

        uint256 surpriseFee = fee / 2;
        USDC.safeTransferFrom(msg.sender, address(this), p.budget);
        if (surpriseFee != 0) {
            USDC.forceApprove(address(HOUSE_POOL), surpriseFee);
            HOUSE_POOL.fund(SURPRISE_BUCKET, surpriseFee);
        }
        if (fee - surpriseFee != 0) USDC.safeTransfer(team, fee - surpriseFee);
        USDC.safeTransfer(address(FLOAT), net);
        // forge-lint: disable-next-line(reentrancy-events) nonReentrant guards the deposit
        emit CampaignCreated(campaignId, msg.sender, p, net, fee);
    }

    /// @notice The sponsor ends the campaign now: no new claims or advances. Refund it next.
    function cancel(uint256 campaignId) external {
        Campaign storage c = _campaign(campaignId);
        if (msg.sender != c.sponsor) revert CampaignEscrow__NotSponsor(msg.sender, c.sponsor);
        if (c.refunded) revert CampaignEscrow__AlreadyRefunded(campaignId);
        c.cancelled = true;
        emit Cancelled(campaignId);
    }

    /// @notice Sends the unspent budget back to the sponsor, once the campaign has ended or was cancelled. Anyone may
    ///         call it. Outstanding advances were already counted as spent.
    function refund(uint256 campaignId) external nonReentrant returns (uint256 amount) {
        Campaign storage c = _campaign(campaignId);
        if (c.refunded) revert CampaignEscrow__AlreadyRefunded(campaignId);
        if (!c.cancelled && block.timestamp <= c.params.end) {
            revert CampaignEscrow__NotEnded(campaignId, c.params.end, block.timestamp);
        }
        amount = c.net - c.spent;
        c.refunded = true;
        _open.remove(campaignId);
        _liabilities -= amount;
        if (amount != 0) FLOAT.release(c.sponsor, amount);
        // forge-lint: disable-next-line(reentrancy-events) nonReentrant guards the refund
        emit Refunded(campaignId, c.sponsor, amount, c.advancesOut);
    }

    // ---------------------------------------------------------------- players (server-signed, anyone submits)

    /// @notice Pays a completed quest. Repays the human's open advance first; the rest goes to the player.
    function claim(CampaignClaim calldata v, bytes calldata sig) external nonReentrant {
        _checkSigned(_hashTypedDataV4(Vouchers.hash(v)), sig, v.ref, v.expiry, v.humanId, v.player);
        uint256 id = v.campaignId;
        Campaign storage c = _live(id);
        if (v.amount == 0 || v.amount > c.params.payoutPerClaim) {
            revert CampaignEscrow__BadAmount(v.amount, c.params.payoutPerClaim);
        }
        _checkSlots(id, c, v.humanId);

        uint256 repaid = Math.min(_openAdvance[id][v.humanId], v.amount);
        uint256 fresh = v.amount - repaid;
        _checkRemaining(id, c, fresh);
        CapDay storage d = _capDay(id, c);
        if (d.spent + fresh > d.cap) revert CampaignEscrow__DailyCapReached(id, d.spent + fresh, d.cap);

        // Change.
        _refUsed[v.ref] = true;
        c.claims += 1;
        _humanClaims[id][v.humanId] += 1;
        if (repaid != 0) {
            _openAdvance[id][v.humanId] -= repaid;
            c.advancesOut -= repaid;
        }
        c.spent += fresh;
        d.spent += fresh;
        _liabilities -= fresh;
        // Pay.
        if (fresh != 0) FLOAT.pay(v.player, fresh);
        // forge-lint: disable-next-line(reentrancy-events) nonReentrant guards the claim
        emit Claimed(id, v.player, v.humanId, v.amount, repaid, v.ref);
    }

    /// @notice Advances USDC to a short wallet (the Spice Run's cargo): one open advance per human per campaign,
    ///         at most maxAdvance, paid from the campaign's budget and repaid first from the human's next claim.
    function advance(AdvanceVoucher calldata v, bytes calldata sig) external nonReentrant {
        _checkSigned(_hashTypedDataV4(Vouchers.hash(v)), sig, v.ref, v.expiry, v.humanId, v.player);
        uint256 id = v.campaignId;
        Campaign storage c = _live(id);
        if (v.amount == 0 || v.amount > maxAdvance) revert CampaignEscrow__BadAmount(v.amount, maxAdvance);
        uint256 open = _openAdvance[id][v.humanId];
        if (open != 0) revert CampaignEscrow__AdvanceOpen(id, v.humanId, open);
        _checkSlots(id, c, v.humanId);
        _checkRemaining(id, c, v.amount);
        CapDay storage d = _capDay(id, c);
        if (d.spent + v.amount > d.cap) revert CampaignEscrow__DailyCapReached(id, d.spent + v.amount, d.cap);

        _refUsed[v.ref] = true;
        _openAdvance[id][v.humanId] = v.amount;
        c.advancesOut += v.amount;
        c.spent += v.amount;
        d.spent += v.amount;
        _liabilities -= v.amount;
        FLOAT.pay(v.player, v.amount);
        // forge-lint: disable-next-line(reentrancy-events) nonReentrant guards the advance
        emit Advanced(id, v.player, v.humanId, v.amount, v.ref);
    }

    // ---------------------------------------------------------------- admin

    /// @notice Pauses (or unpauses) a campaign for abuse. A paused campaign pays nothing; it can still be refunded
    ///         after its end.
    function setPaused(uint256 campaignId, bool paused) external onlyOwner {
        _campaign(campaignId).paused = paused;
        emit PausedSet(campaignId, paused);
    }

    /// @notice Replaces the server key that signs claims and advances.
    function setVoucherSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert CampaignEscrow__ZeroAddress();
        address old = voucherSigner;
        voucherSigner = newSigner;
        emit VoucherSignerSet(old, newSigner);
    }

    /// @notice Changes where the team's half of the fee goes.
    function setTeam(address newTeam) external onlyOwner {
        if (newTeam == address(0)) revert CampaignEscrow__ZeroAddress();
        address old = team;
        team = newTeam;
        emit TeamSet(old, newTeam);
    }

    /// @notice Changes the minimum payout per claim (for new campaigns) and the maximum advance.
    function setLimits(uint256 minPayout_, uint256 maxAdvance_) external onlyOwner {
        minPayout = minPayout_;
        maxAdvance = maxAdvance_;
        emit LimitsSet(minPayout_, maxAdvance_);
    }

    /// @notice Always refuses.
    function renounceOwnership() public pure override {
        revert CampaignEscrow__AdminCantBeRemoved();
    }

    // ---------------------------------------------------------------- reads (never blocked)

    /// @notice A campaign's whole record.
    function campaign(uint256 campaignId) external view returns (Campaign memory) {
        return _campaigns[campaignId];
    }

    /// @notice What a campaign can still pay (USDC base units). Zero once refunded.
    function remaining(uint256 campaignId) public view returns (uint256) {
        Campaign storage c = _campaigns[campaignId];
        if (c.refunded) return 0;
        return c.net - c.spent;
    }

    /// @notice Today's payout cap: remaining ÷ days left (at least one payout a day), fixed at the day's first
    ///         payout. Before then, what the first payout would fix right now.
    function dailyCap(uint256 campaignId) public view returns (uint256) {
        Campaign storage c = _campaigns[campaignId];
        CapDay storage d = _capDays[campaignId];
        if (d.dayPlusOne == _today() + 1) return d.cap;
        return _computeCap(campaignId, c);
    }

    /// @notice What can still be paid today under the daily cap.
    function dailyCapLeft(uint256 campaignId) external view returns (uint256) {
        CapDay storage d = _capDays[campaignId];
        uint256 cap = dailyCap(campaignId);
        uint256 spentToday = d.dayPlusOne == _today() + 1 ? d.spent : 0;
        return cap > spentToday ? cap - spentToday : 0;
    }

    /// @notice Everything owed to sponsors: the sum of every unrefunded campaign's unspent budget.
    function totalLiabilities() external view returns (uint256) {
        return _liabilities;
    }

    /// @notice The sum of today's caps over campaigns that can still pay (not ended, not cancelled). FloatManager
    ///         sizes its cash buffer from this.
    function liveDailyCapSum() external view returns (uint256 sum) {
        uint256 n = _open.length();
        for (uint256 i = 0; i < n; ++i) {
            uint256 id = _open.at(i);
            Campaign storage c = _campaigns[id];
            if (!c.cancelled && block.timestamp <= c.params.end) sum += dailyCap(id);
        }
    }

    /// @notice Unspent budgets of campaigns that ended or were cancelled but aren't refunded yet.
    function pendingRefunds() external view returns (uint256 sum) {
        uint256 n = _open.length();
        for (uint256 i = 0; i < n; ++i) {
            uint256 id = _open.at(i);
            Campaign storage c = _campaigns[id];
            if (c.cancelled || block.timestamp > c.params.end) sum += c.net - c.spent;
        }
    }

    /// @notice Ids of campaigns not yet refunded.
    function openCampaigns() external view returns (uint256[] memory) {
        return _open.values();
    }

    /// @notice Whether a campaign pays right now (started, not ended, not paused or cancelled, not refunded).
    function isLive(uint256 campaignId) public view returns (bool) {
        Campaign storage c = _campaigns[campaignId];
        return c.sponsor != address(0) && !c.paused && !c.cancelled && !c.refunded && block.timestamp >= c.params.start
            && block.timestamp <= c.params.end;
    }

    /// @notice Where SpiceMerchant forwards this campaign's delivered tokens. Zero for an unknown campaign.
    function deliverTo(uint256 campaignId) external view returns (address) {
        return _campaigns[campaignId].params.deliverTo;
    }

    /// @notice The token a campaign's quest uses (zero if none, or for an unknown campaign).
    function questToken(uint256 campaignId) external view returns (address) {
        return _campaigns[campaignId].params.questToken;
    }

    /// @notice How many times a human has been paid by a campaign, and their open advance.
    function humanState(uint256 campaignId, bytes32 humanId) external view returns (uint256 claims, uint256 advance_) {
        return (_humanClaims[campaignId][humanId], _openAdvance[campaignId][humanId]);
    }

    /// @notice The smallest payout per claim that passes I1 and the minimum, for a quest costing `energyCost`.
    function minPayoutFor(uint32 energyCost) external view returns (uint256) {
        return Math.max(minPayout, _ceilingFoodCostX4(energyCost));
    }

    /// @notice Whether a claim or advance ref has been used.
    function refUsed(bytes32 ref) external view returns (bool) {
        return _refUsed[ref];
    }

    // ---------------------------------------------------------------- internals

    function _checkParams(CampaignParams calldata p) private view {
        if (p.deliverTo == address(0)) revert CampaignEscrow__ZeroAddress();
        if (p.kind > KIND_BOOSTED) revert CampaignEscrow__BadKind(p.kind);
        if ((p.template == SPICE_RUN_TEMPLATE || p.template == HOLD_LINE_TEMPLATE) && p.questToken == address(0)) {
            revert CampaignEscrow__QuestTokenMissing(p.template);
        }
        if (p.maxClaims == 0 || p.perHumanCap == 0) revert CampaignEscrow__BadLimits(p.maxClaims, p.perHumanCap);
        if (p.start >= p.end || p.end <= block.timestamp) {
            revert CampaignEscrow__BadWindow(p.start, p.end, block.timestamp);
        }
        if (p.payoutPerClaim < minPayout) revert CampaignEscrow__PayoutTooSmall(p.payoutPerClaim, minPayout);
        uint256 costX4 = _ceilingFoodCostX4(p.energyCost);
        if (costX4 > p.payoutPerClaim) revert CampaignEscrow__BreaksQuarterRule(costX4, p.payoutPerClaim);
    }

    /// @dev energyCost × (ceiling ÷ ENERGY_PER_FOOD) × 4, in USDC base units, rounded up (so I1 is never loosened).
    function _ceilingFoodCostX4(uint32 energyCost) private view returns (uint256) {
        return Math.mulDiv(
            uint256(energyCost) * QUARTER_RULE_MULTIPLE, HOOK.ceilingPrice(), ENERGY_PER_FOOD, Math.Rounding.Ceil
        );
    }

    function _checkSigned(
        bytes32 digest,
        bytes calldata sig,
        bytes32 ref,
        uint64 expiry,
        bytes32 humanId,
        address player
    ) private view {
        if (humanId == bytes32(0) || player == address(0)) revert CampaignEscrow__NotVerified(player);
        if (_refUsed[ref]) revert CampaignEscrow__RefUsed(ref);
        if (block.timestamp > expiry) revert CampaignEscrow__Expired(expiry, block.timestamp);
        (address recovered,,) = ECDSA.tryRecover(digest, sig);
        if (recovered != voucherSigner || recovered == address(0)) {
            revert CampaignEscrow__BadSignature(recovered, voucherSigner);
        }
    }

    function _campaign(uint256 campaignId) private view returns (Campaign storage c) {
        c = _campaigns[campaignId];
        if (c.sponsor == address(0)) revert CampaignEscrow__UnknownCampaign(campaignId);
    }

    function _live(uint256 campaignId) private view returns (Campaign storage c) {
        c = _campaign(campaignId);
        if (c.paused || c.cancelled || c.refunded) revert CampaignEscrow__Closed(campaignId, c.paused, c.cancelled);
        if (block.timestamp < c.params.start || block.timestamp > c.params.end) {
            revert CampaignEscrow__NotLive(campaignId, c.params.start, c.params.end, block.timestamp);
        }
    }

    function _checkSlots(uint256 id, Campaign storage c, bytes32 humanId) private view {
        if (c.claims >= c.params.maxClaims) revert CampaignEscrow__SoldOut(id, c.claims, c.params.maxClaims);
        uint256 humanClaims = _humanClaims[id][humanId];
        if (humanClaims >= c.params.perHumanCap) {
            revert CampaignEscrow__HumanCapReached(id, humanId, humanClaims, c.params.perHumanCap);
        }
    }

    function _checkRemaining(uint256 id, Campaign storage c, uint256 amount) private view {
        uint256 left = c.net - c.spent;
        if (amount > left) revert CampaignEscrow__OverRemaining(id, amount, left);
    }

    /// @dev Today's cap record, opened (and its cap fixed) on the day's first payout.
    function _capDay(uint256 id, Campaign storage c) private returns (CapDay storage d) {
        d = _capDays[id];
        uint256 day = _today();
        if (d.dayPlusOne != day + 1) {
            uint256 cap = _computeCap(id, c);
            d.dayPlusOne = SafeCast.toUint64(day + 1);
            d.cap = cap;
            d.spent = 0;
            emit DailyCapOpened(id, day, cap);
        }
    }

    /// @dev remaining ÷ max(1, days left, rounded up), but at least one payout (and never more than what's left).
    function _computeCap(uint256 id, Campaign storage c) private view returns (uint256) {
        uint256 left = remaining(id);
        uint256 secondsLeft = c.params.end > block.timestamp ? c.params.end - block.timestamp : 0;
        uint256 daysLeft = Math.max(1, Math.ceilDiv(secondsLeft, DAY_SECONDS));
        uint256 cap = Math.max(left / daysLeft, c.params.payoutPerClaim);
        return Math.min(cap, left);
    }

    function _today() private view returns (uint256) {
        return block.timestamp / DAY_SECONDS;
    }
}
// forge-lint: disable-end(block-timestamp)
