// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IHousePool, IMealCounter} from "./Links.sol";
import {PayoutVoucher, Vouchers} from "./Vouchers.sol";

/// @title HousePool
/// @notice Pays for Tallyport's own fun, in USDC, from three buckets:
///         FIXED (Rush pot, streak bonus, errands; funded by food revenue), SURPRISE (chests, golden USDC drops, mystery
///         quests, events, the weekly draw; funded by sponsor fees and yield) and SAFETY (rescue meals only).
///         Each bucket may spend at most `budgetBps` (launch 4%) of its balance a day, fixed at the day's first payout,
///         so the pool can never run dry. Each human may receive at most `perHumanDailyCap` a day.
/// @dev Payouts are server-signed PayoutVouchers that anyone may submit; a ref works once. Days are UTC days.
///      Spec: docs/architecture/spec.json, contract "HousePool".
contract HousePool is IHousePool, EIP712, Ownable2Step, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    /// @notice Bucket numbers (PayoutVoucher.source). 3 (CAMPAIGN) is only valid in CampaignEscrow.
    uint8 public constant FIXED = 0;
    uint8 public constant SURPRISE = 1;
    uint8 public constant SAFETY = 2;
    uint8 private constant BUCKET_COUNT = 3;
    uint256 private constant BPS = 10_000;
    uint256 private constant DAY_SECONDS = 1 days;

    IERC20 private immutable USDC;
    /// @notice Each bucket's daily budget, as basis points of its balance at the day's first payout (launch 400 = 4%).
    uint256 public immutable budgetBps;

    /// @notice The server key whose EIP-712 signature makes a PayoutVoucher valid.
    address public voucherSigner;
    /// @notice The most one human may receive in one UTC day, across all buckets (USDC base units).
    uint256 public perHumanDailyCap;
    /// @notice MealCounter, used for rescue meals and meal vouchers.
    address public mealCounter;
    /// @notice LuckyLedger, the only caller of payDraw.
    address public luckyLedger;

    uint256[BUCKET_COUNT] private _balances;

    struct DayBudget {
        uint128 budget;
        uint120 spent;
        bool opened;
    }

    mapping(uint256 day => mapping(uint8 bucket => DayBudget)) private _days;
    mapping(bytes32 humanId => mapping(uint256 day => uint256)) private _humanPaid;
    mapping(bytes32 ref => bool) private _refUsed;

    /// @notice USDC came into a bucket.
    event Funded(uint8 indexed bucket, address indexed from, uint256 amount);
    /// @notice A bucket paid USDC to a player (humanId is zero for a draw prize).
    event Paid(uint8 indexed source, address indexed player, bytes32 indexed humanId, uint256 amount, bytes32 ref);
    /// @notice A bucket bought a meal for a player through MealCounter (usdcSpent is what the meal really cost).
    event MealPaid(
        uint8 indexed source, address indexed player, bytes32 indexed humanId, uint256 usdcSpent, bytes32 ref
    );
    /// @notice A bucket's first payout of the day fixed that day's budget (USDC base units).
    event BudgetOpened(uint8 indexed bucket, uint256 indexed day, uint256 budget);
    event VoucherSignerSet(address indexed oldSigner, address indexed newSigner);
    event PerHumanDailyCapSet(uint256 oldCap, uint256 newCap);
    event MealCounterSet(address indexed oldCounter, address indexed newCounter);
    event LuckyLedgerSet(address indexed oldLedger, address indexed newLedger);

    /// @notice No such bucket (valid: 0 FIXED, 1 SURPRISE, 2 SAFETY; meals: SURPRISE or SAFETY).
    error HousePool__BadSource(uint8 source);
    /// @notice Asked to fund or pay nothing.
    error HousePool__ZeroAmount();
    /// @notice This ref was already used: the retry was blocked.
    error HousePool__RefUsed(bytes32 ref);
    /// @notice The voucher's expiry (unix seconds) has passed.
    error HousePool__Expired(uint64 expiry, uint256 nowSeconds);
    /// @notice The voucher wasn't signed by the voucher signer.
    error HousePool__BadSignature(address recovered, address expected);
    /// @notice Payouts go only to verified humans (humanId can't be zero) and real addresses.
    error HousePool__NotVerified(address player);
    /// @notice The payout would take the bucket past today's budget (USDC base units).
    error HousePool__OverDailyBudget(uint8 bucket, uint256 wouldSpend, uint256 budget);
    /// @notice The bucket holds less than the payout.
    error HousePool__InsufficientBalance(uint8 bucket, uint256 amount, uint256 balance);
    /// @notice The payout would take this human past today's cap.
    error HousePool__HumanCapReached(bytes32 humanId, uint256 wouldReceive, uint256 cap);
    /// @notice A meal voucher must be sent by the player it feeds (so nobody else picks the meal).
    error HousePool__NotPlayer(address sender, address player);
    /// @notice Only LuckyLedger may pay a draw prize.
    error HousePool__NotLuckyLedger(address sender);
    /// @notice MealCounter isn't set, so meals can't be bought from the pool.
    error HousePool__NoMealCounter();
    /// @notice The settings don't make sense: the budget must be 1..10,000 bps, the cap above zero.
    error HousePool__BadSettings(uint256 budgetBps, uint256 perHumanDailyCap);
    /// @notice An address that must be set was zero.
    error HousePool__ZeroAddress();
    /// @notice The admin role can be handed over, but never thrown away.
    error HousePool__AdminCantBeRemoved();

    constructor(IERC20 usdc, address voucherSigner_, uint256 budgetBps_, uint256 perHumanDailyCap_, address admin)
        EIP712(Vouchers.DOMAIN_NAME, Vouchers.DOMAIN_VERSION)
        Ownable(admin)
    {
        if (address(usdc) == address(0) || voucherSigner_ == address(0)) revert HousePool__ZeroAddress();
        if (budgetBps_ == 0 || budgetBps_ > BPS || perHumanDailyCap_ == 0) {
            revert HousePool__BadSettings(budgetBps_, perHumanDailyCap_);
        }
        USDC = usdc;
        budgetBps = budgetBps_;
        voucherSigner = voucherSigner_;
        perHumanDailyCap = perHumanDailyCap_;
        emit VoucherSignerSet(address(0), voucherSigner_);
        emit PerHumanDailyCapSet(0, perHumanDailyCap_);
    }

    // ---------------------------------------------------------------- money in

    /// @notice Pulls `amount` USDC from the caller into a bucket. Anyone may fund (Treasury, CampaignEscrow's fee,
    ///         FloatManager's yield, a sponsor's drop).
    function fund(uint8 bucket, uint256 amount) external nonReentrant {
        if (bucket >= BUCKET_COUNT) revert HousePool__BadSource(bucket);
        if (amount == 0) revert HousePool__ZeroAmount();
        _balances[bucket] += amount;
        USDC.safeTransferFrom(msg.sender, address(this), amount);
        emit Funded(bucket, msg.sender, amount);
    }

    // ---------------------------------------------------------------- money out

    /// @notice Pays a server-signed voucher: USDC from `v.source`'s bucket to `v.player`. Anyone may submit it.
    function pay(PayoutVoucher calldata v, bytes calldata sig) external nonReentrant {
        _checkVoucher(v, sig);
        // Change.
        _refUsed[v.ref] = true;
        _spend(v.source, v.amount);
        _countHuman(v.humanId, v.amount);
        // Pay.
        USDC.safeTransfer(v.player, v.amount);
        emit Paid(v.source, v.player, v.humanId, v.amount, v.ref);
    }

    /// @notice Pays a rescue meal (SAFETY) or a meal voucher (SURPRISE) straight into MealCounter: the pool pays at
    ///         most `v.amount`, the player gets the meal's energy. Sent by the player's own wallet, which picks the
    ///         menu item; the server checks MealEaten.
    /// @return usdcSpent What the meal really cost; the rest of `v.amount` stays in the bucket.
    function payMeal(PayoutVoucher calldata v, bytes32 item, uint256 food, bytes calldata sig)
        external
        nonReentrant
        returns (uint256 usdcSpent)
    {
        if (msg.sender != v.player) revert HousePool__NotPlayer(msg.sender, v.player);
        if (v.source != SAFETY && v.source != SURPRISE) revert HousePool__BadSource(v.source);
        address counter = mealCounter;
        if (counter == address(0)) revert HousePool__NoMealCounter();
        _checkVoucher(v, sig);

        // Change: reserve the whole voucher, then hand back whatever the meal didn't cost.
        _refUsed[v.ref] = true;
        _spend(v.source, v.amount);
        _countHuman(v.humanId, v.amount);

        USDC.forceApprove(counter, v.amount);
        // forge-lint: disable-next-line(unused-return,reentrancy-no-eth) nonReentrant; reconciled just below
        (usdcSpent,) = IMealCounter(counter).buyMealFor(v.player, item, food, v.amount, v.ref);
        USDC.forceApprove(counter, 0);

        uint256 unused = v.amount - usdcSpent;
        if (unused != 0) {
            _balances[v.source] += unused;
            _days[_today()][v.source].spent -= SafeCast.toUint120(unused);
            _humanPaid[v.humanId][_today()] -= unused;
        }
        // forge-lint: disable-next-line(reentrancy-events) nonReentrant guards the meal
        emit MealPaid(v.source, v.player, v.humanId, usdcSpent, v.ref);
    }

    /// @notice Pays the weekly draw's prize from SURPRISE. Only LuckyLedger, after it checked the winner's proof.
    function payDraw(address winner, uint256 amount, bytes32 ref) external nonReentrant {
        if (msg.sender != luckyLedger || msg.sender == address(0)) revert HousePool__NotLuckyLedger(msg.sender);
        if (winner == address(0)) revert HousePool__ZeroAddress();
        if (amount == 0) revert HousePool__ZeroAmount();
        if (_refUsed[ref]) revert HousePool__RefUsed(ref);
        _refUsed[ref] = true;
        _spend(SURPRISE, amount);
        USDC.safeTransfer(winner, amount);
        emit Paid(SURPRISE, winner, bytes32(0), amount, ref);
    }

    // ---------------------------------------------------------------- admin

    /// @notice Replaces the server key that signs vouchers. Unspent old vouchers stop working.
    function setVoucherSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert HousePool__ZeroAddress();
        address old = voucherSigner;
        voucherSigner = newSigner;
        emit VoucherSignerSet(old, newSigner);
    }

    /// @notice Changes the per-human daily cap (USDC base units).
    function setPerHumanDailyCap(uint256 newCap) external onlyOwner {
        if (newCap == 0) revert HousePool__BadSettings(budgetBps, newCap);
        uint256 old = perHumanDailyCap;
        perHumanDailyCap = newCap;
        emit PerHumanDailyCapSet(old, newCap);
    }

    /// @notice Sets MealCounter. Zero switches meal payouts off.
    // forge-lint: disable-next-line(missing-zero-check)
    function setMealCounter(address newCounter) external onlyOwner {
        address old = mealCounter;
        mealCounter = newCounter; // zero on purpose means "no meals"
        emit MealCounterSet(old, newCounter);
    }

    /// @notice Sets LuckyLedger. Zero switches draw payouts off.
    // forge-lint: disable-next-line(missing-zero-check)
    function setLuckyLedger(address newLedger) external onlyOwner {
        address old = luckyLedger;
        luckyLedger = newLedger; // zero on purpose means "no draw payouts"
        emit LuckyLedgerSet(old, newLedger);
    }

    /// @notice Always refuses. Without an admin, a leaked voucher signer could never be replaced.
    function renounceOwnership() public pure override {
        revert HousePool__AdminCantBeRemoved();
    }

    // ---------------------------------------------------------------- reads (never blocked)

    /// @notice A bucket's USDC balance (base units).
    function bucketBalance(uint8 bucket) external view returns (uint256) {
        if (bucket >= BUCKET_COUNT) revert HousePool__BadSource(bucket);
        return _balances[bucket];
    }

    /// @notice Today's budget for a bucket and what it has spent. Before today's first payout, `budget` is what the
    ///         first payout would fix right now.
    function todayBudget(uint8 bucket) external view returns (uint256 budget, uint256 spent, uint256 left) {
        if (bucket >= BUCKET_COUNT) revert HousePool__BadSource(bucket);
        DayBudget storage d = _days[_today()][bucket];
        budget = d.opened ? d.budget : _balances[bucket] * budgetBps / BPS;
        spent = d.spent;
        left = budget > spent ? budget - spent : 0;
        if (left > _balances[bucket]) left = _balances[bucket];
    }

    /// @notice What a human has received today (USDC base units).
    function humanPaidToday(bytes32 humanId) external view returns (uint256) {
        return _humanPaid[humanId][_today()];
    }

    /// @notice Whether a voucher ref has been used.
    function refUsed(bytes32 ref) external view returns (bool) {
        return _refUsed[ref];
    }

    /// @notice Today's UTC day number (unix seconds ÷ 86,400).
    function today() external view returns (uint256) {
        return _today();
    }

    // ---------------------------------------------------------------- internals

    function _checkVoucher(PayoutVoucher calldata v, bytes calldata sig) private view {
        if (v.source >= BUCKET_COUNT) revert HousePool__BadSource(v.source);
        if (v.amount == 0) revert HousePool__ZeroAmount();
        if (v.humanId == bytes32(0) || v.player == address(0)) revert HousePool__NotVerified(v.player);
        if (_refUsed[v.ref]) revert HousePool__RefUsed(v.ref);
        // forge-lint: disable-next-line(block-timestamp) a voucher lives for minutes; seconds of drift don't matter
        if (block.timestamp > v.expiry) revert HousePool__Expired(v.expiry, block.timestamp);
        (address recovered,,) = ECDSA.tryRecover(_hashTypedDataV4(Vouchers.hash(v)), sig);
        if (recovered != voucherSigner || recovered == address(0)) {
            revert HousePool__BadSignature(recovered, voucherSigner);
        }
    }

    /// @dev Opens today's budget on the bucket's first payout, then refuses anything past it or past the balance.
    function _spend(uint8 bucket, uint256 amount) private {
        uint256 day = _today();
        DayBudget storage d = _days[day][bucket];
        if (!d.opened) {
            uint256 budget = _balances[bucket] * budgetBps / BPS;
            d.opened = true;
            d.budget = SafeCast.toUint128(budget);
            emit BudgetOpened(bucket, day, budget);
        }
        uint256 wouldSpend = d.spent + amount;
        if (wouldSpend > d.budget) revert HousePool__OverDailyBudget(bucket, wouldSpend, d.budget);
        if (amount > _balances[bucket]) revert HousePool__InsufficientBalance(bucket, amount, _balances[bucket]);
        d.spent = SafeCast.toUint120(wouldSpend);
        _balances[bucket] -= amount;
    }

    function _countHuman(bytes32 humanId, uint256 amount) private {
        uint256 day = _today();
        uint256 wouldReceive = _humanPaid[humanId][day] + amount;
        if (wouldReceive > perHumanDailyCap) {
            revert HousePool__HumanCapReached(humanId, wouldReceive, perHumanDailyCap);
        }
        _humanPaid[humanId][day] = wouldReceive;
    }

    function _today() private view returns (uint256) {
        return block.timestamp / DAY_SECONDS;
    }
}
