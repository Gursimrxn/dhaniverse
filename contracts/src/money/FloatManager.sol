// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {ICampaignBook, IFloatManager, IHousePool} from "./Links.sol";

/// @title FloatManager
/// @notice Holds every sponsor's USDC and earns yield on the idle part, with no lock-ins. A cash buffer sized from the
///         campaigns' daily caps stays liquid; up to 80% of the float may sit in at most two ERC-4626 venues with
///         instant withdrawal. Only CampaignEscrow can move principal out (claims, advances, refunds), and it is
///         pulled back from the venues automatically when cash runs short. Yield above what sponsors are owed goes to
///         HousePool's SURPRISE bucket, after topping up a loss reserve.
/// @dev buffer = 1.5 × 3 days × Σ live daily caps + pending refunds; invest = min(80% float, float − buffer).
///      Spec: docs/architecture/spec.json, contract "FloatManager".
contract FloatManager is IFloatManager, Ownable2Step, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    /// @notice At most two venues.
    uint256 public constant MAX_VENUES = 2;
    uint256 private constant BPS = 10_000;
    /// @notice The buffer covers this many days of the maximum possible payouts...
    uint256 public constant BUFFER_DAYS = 3;
    /// @notice ...times 1.5.
    uint256 public constant BUFFER_FACTOR_BPS = 15_000;
    /// @notice At most 80% of the float is ever invested.
    uint256 public constant MAX_INVESTED_BPS = 8000;
    /// @notice Withdraw back up to the buffer when cash falls under half of it...
    uint256 public constant LOW_WATER_BPS = 5000;
    /// @notice ...and invest the excess when cash is over 1.5x of it.
    uint256 public constant HIGH_WATER_BPS = 15_000;
    /// @notice 80% of harvested yield goes to HousePool's SURPRISE bucket while the loss reserve fills...
    uint256 public constant POOL_SHARE_BPS = 8000;
    /// @notice ...until the reserve reaches 2% of what's invested; then 100% goes to the pool.
    uint256 public constant RESERVE_TARGET_BPS = 200;
    uint8 private constant SURPRISE_BUCKET = 1;

    IERC20 private immutable USDC;
    IHousePool private immutable HOUSE_POOL;

    /// @notice CampaignEscrow: the only caller of pay and release. Set once.
    ICampaignBook public escrow;
    /// @notice The key that runs rebalance (hourly).
    address public keeper;
    /// @notice The part of the float held back against venue losses (USDC base units). It never leaves as yield.
    uint256 public lossReserve;
    /// @notice All yield ever sent to HousePool (USDC base units).
    uint256 public yieldEarned;

    IERC4626[MAX_VENUES] private _venues;

    /// @notice Principal paid to a player (a claim or an advance).
    event PaidOut(address indexed to, uint256 amount);
    /// @notice Principal returned to a sponsor (a refund).
    event Released(address indexed to, uint256 amount);
    /// @notice The keeper rebalanced cash and venues (USDC base units).
    event Rebalanced(uint256 buffer, uint256 liquidBefore, uint256 deposited, uint256 withdrawn);
    /// @notice Yield above liabilities was harvested: toPool went to SURPRISE, toReserve to the loss reserve.
    event YieldHarvested(uint256 surplus, uint256 toPool, uint256 toReserve);
    event VenueSet(uint256 indexed index, address indexed oldVenue, address indexed newVenue, uint256 assetsMoved);
    event EscrowSet(address indexed escrow);
    event KeeperSet(address indexed oldKeeper, address indexed newKeeper);

    /// @notice Only CampaignEscrow may move principal.
    error FloatManager__NotEscrow(address sender);
    /// @notice Only the keeper key may rebalance.
    error FloatManager__NotKeeper(address sender, address keeper);
    /// @notice CampaignEscrow can be set only once.
    error FloatManager__EscrowAlreadySet(address escrow);
    /// @notice Not enough cash even after withdrawing everything the venues allow (USDC base units).
    error FloatManager__Illiquid(uint256 needed, uint256 available);
    /// @notice There's nothing above liabilities and the loss reserve to harvest.
    error FloatManager__NoYield(uint256 totalAssets, uint256 owed);
    /// @notice Venues are numbered 0 and 1.
    error FloatManager__BadVenueIndex(uint256 index);
    /// @notice A venue must be an ERC-4626 vault over USDC.
    error FloatManager__WrongAsset(address venue, address asset);
    /// @notice Asked to move nothing.
    error FloatManager__ZeroAmount();
    /// @notice An address that must be set was zero.
    error FloatManager__ZeroAddress();
    /// @notice The admin role can be handed over, but never thrown away.
    error FloatManager__AdminCantBeRemoved();

    constructor(IERC20 usdc, IHousePool housePool, address keeper_, address admin) Ownable(admin) {
        if (address(usdc) == address(0) || address(housePool) == address(0) || keeper_ == address(0)) {
            revert FloatManager__ZeroAddress();
        }
        USDC = usdc;
        HOUSE_POOL = housePool;
        keeper = keeper_;
        emit KeeperSet(address(0), keeper_);
    }

    modifier onlyEscrow() {
        if (msg.sender != address(escrow) || msg.sender == address(0)) revert FloatManager__NotEscrow(msg.sender);
        _;
    }

    // ---------------------------------------------------------------- principal (CampaignEscrow only)

    /// @notice Pays a player for a claim or an advance, withdrawing from the venues if cash is short.
    function pay(address to, uint256 amount) external nonReentrant onlyEscrow {
        _send(to, amount);
        // forge-lint: disable-next-line(reentrancy-events) nonReentrant guards the payment
        emit PaidOut(to, amount);
    }

    /// @notice Returns a refund to a sponsor, withdrawing from the venues if cash is short.
    function release(address to, uint256 amount) external nonReentrant onlyEscrow {
        _send(to, amount);
        // forge-lint: disable-next-line(reentrancy-events) nonReentrant guards the refund
        emit Released(to, amount);
    }

    // ---------------------------------------------------------------- keeper and anyone

    /// @notice Moves money between cash and the venues: withdraws back up to the buffer when cash is under half of
    ///         it, invests the excess when cash is over 1.5x of it, never investing more than min(80% of the float,
    ///         float − buffer).
    function rebalance() external nonReentrant returns (uint256 deposited, uint256 withdrawn) {
        if (msg.sender != keeper) revert FloatManager__NotKeeper(msg.sender, keeper);
        uint256 target = buffer();
        uint256 liquidBefore = USDC.balanceOf(address(this));
        if (liquidBefore * BPS < target * LOW_WATER_BPS) {
            withdrawn = _withdrawUpTo(target - liquidBefore);
        } else if (liquidBefore * BPS > target * HIGH_WATER_BPS) {
            uint256 room = investCap();
            uint256 investedNow = invested();
            room = room > investedNow ? room - investedNow : 0;
            deposited = _deposit(Math.min(liquidBefore - target, room));
        }
        // forge-lint: disable-next-line(reentrancy-events) nonReentrant guards the rebalance
        emit Rebalanced(target, liquidBefore, deposited, withdrawn);
    }

    /// @notice Sends yield to HousePool's SURPRISE bucket: surplus = total assets − what sponsors are owed − the loss
    ///         reserve. 20% of it tops up the loss reserve until that reaches 2% of what's invested; the rest goes to
    ///         the pool. Never touches principal. Anyone may call it.
    function harvestYield() external nonReentrant returns (uint256 toPool, uint256 toReserve) {
        uint256 owed = escrow.totalLiabilities() + lossReserve;
        uint256 total = totalAssets();
        if (total <= owed) revert FloatManager__NoYield(total, owed);
        // Make the surplus liquid first, then measure again: a venue may round a withdrawal against us.
        // forge-lint: disable-next-line(reentrancy-no-eth) nonReentrant guards the harvest; the venues are admin-set
        _ensureLiquid(total - owed);
        total = totalAssets();
        if (total <= owed) revert FloatManager__NoYield(total, owed);
        uint256 extra = total - owed;

        uint256 reserveTarget = invested() * RESERVE_TARGET_BPS / BPS;
        if (lossReserve < reserveTarget) {
            toReserve = Math.min(extra * (BPS - POOL_SHARE_BPS) / BPS, reserveTarget - lossReserve);
        }
        toPool = extra - toReserve;
        lossReserve += toReserve;
        yieldEarned += toPool;

        if (toPool != 0) {
            USDC.forceApprove(address(HOUSE_POOL), toPool);
            HOUSE_POOL.fund(SURPRISE_BUCKET, toPool);
        }
        // forge-lint: disable-next-line(reentrancy-events) nonReentrant guards the harvest
        emit YieldHarvested(extra, toPool, toReserve);
    }

    // ---------------------------------------------------------------- admin

    /// @notice Sets CampaignEscrow, once (it's deployed after this contract).
    function setEscrow(ICampaignBook escrow_) external onlyOwner {
        if (address(escrow) != address(0)) revert FloatManager__EscrowAlreadySet(address(escrow));
        if (address(escrow_) == address(0)) revert FloatManager__ZeroAddress();
        escrow = escrow_;
        emit EscrowSet(address(escrow_));
    }

    /// @notice Sets (or clears, with zero) venue `index`. Everything in the old venue is withdrawn first.
    function setVenue(uint256 index, IERC4626 newVenue) external nonReentrant onlyOwner {
        if (index >= MAX_VENUES) revert FloatManager__BadVenueIndex(index);
        if (address(newVenue) != address(0) && newVenue.asset() != address(USDC)) {
            revert FloatManager__WrongAsset(address(newVenue), newVenue.asset());
        }
        IERC4626 old = _venues[index];
        _venues[index] = newVenue;
        uint256 moved = 0;
        if (address(old) != address(0)) {
            uint256 shares = old.balanceOf(address(this));
            if (shares != 0) moved = old.redeem(shares, address(this), address(this));
        }
        // forge-lint: disable-next-line(reentrancy-events) nonReentrant guards the change
        emit VenueSet(index, address(old), address(newVenue), moved);
    }

    /// @notice Replaces the keeper key.
    function setKeeper(address newKeeper) external onlyOwner {
        if (newKeeper == address(0)) revert FloatManager__ZeroAddress();
        address old = keeper;
        keeper = newKeeper;
        emit KeeperSet(old, newKeeper);
    }

    /// @notice Always refuses.
    function renounceOwnership() public pure override {
        revert FloatManager__AdminCantBeRemoved();
    }

    // ---------------------------------------------------------------- reads (never blocked)

    /// @notice Cash plus what the venues would pay out now (USDC base units).
    function totalAssets() public view returns (uint256) {
        return USDC.balanceOf(address(this)) + invested();
    }

    /// @notice Cash on hand (USDC base units).
    function liquid() external view returns (uint256) {
        return USDC.balanceOf(address(this));
    }

    /// @notice What the venues would pay out now (USDC base units).
    function invested() public view returns (uint256 sum) {
        for (uint256 i = 0; i < MAX_VENUES; ++i) {
            IERC4626 v = _venues[i];
            // forge-lint: disable-next-line(calls-loop) at most two admin-set venues
            if (address(v) != address(0)) sum += v.previewRedeem(v.balanceOf(address(this)));
        }
    }

    /// @notice The cash buffer: 1.5 × 3 days × Σ live campaigns' daily caps + pending refunds.
    function buffer() public view returns (uint256) {
        ICampaignBook book = escrow;
        if (address(book) == address(0)) return 0;
        return book.liveDailyCapSum() * BUFFER_DAYS * BUFFER_FACTOR_BPS / BPS + book.pendingRefunds();
    }

    /// @notice The most that may be invested now: min(80% of the float, float − buffer).
    function investCap() public view returns (uint256) {
        uint256 total = totalAssets();
        uint256 target = buffer();
        uint256 aboveBuffer = total > target ? total - target : 0;
        return Math.min(total * MAX_INVESTED_BPS / BPS, aboveBuffer);
    }

    /// @notice What harvestYield would split right now (0 if nothing).
    function surplus() external view returns (uint256) {
        ICampaignBook book = escrow;
        uint256 owed = (address(book) == address(0) ? 0 : book.totalLiabilities()) + lossReserve;
        uint256 total = totalAssets();
        return total > owed ? total - owed : 0;
    }

    /// @notice Both venues (zero where unset).
    function venues() external view returns (IERC4626[MAX_VENUES] memory) {
        return _venues;
    }

    /// @notice Venue `index` (zero if unset).
    function venue(uint256 index) external view returns (IERC4626) {
        if (index >= MAX_VENUES) revert FloatManager__BadVenueIndex(index);
        return _venues[index];
    }

    // ---------------------------------------------------------------- internals

    function _send(address to, uint256 amount) private {
        if (to == address(0)) revert FloatManager__ZeroAddress();
        if (amount == 0) revert FloatManager__ZeroAmount();
        _ensureLiquid(amount);
        USDC.safeTransfer(to, amount);
    }

    function _ensureLiquid(uint256 amount) private {
        uint256 cash = USDC.balanceOf(address(this));
        if (cash >= amount) return;
        _withdrawUpTo(amount - cash);
        cash = USDC.balanceOf(address(this));
        if (cash < amount) revert FloatManager__Illiquid(amount, cash);
    }

    /// @dev Withdraws up to `want` from the venues, in order, as far as each allows right now.
    function _withdrawUpTo(uint256 want) private returns (uint256 got) {
        got = 0;
        for (uint256 i = 0; i < MAX_VENUES && got < want; ++i) {
            IERC4626 v = _venues[i];
            if (address(v) == address(0)) continue;
            // forge-lint: disable-next-line(calls-loop) at most two admin-set venues
            uint256 take = Math.min(want - got, v.maxWithdraw(address(this)));
            if (take == 0) continue;
            got += take;
            // forge-lint: disable-next-line(unused-return,calls-loop,reentrancy-no-eth) two admin-set venues; callers are nonReentrant
            v.withdraw(take, address(this), address(this));
        }
    }

    /// @dev Deposits `amount`, split evenly between the venues that are set.
    function _deposit(uint256 amount) private returns (uint256 deposited) {
        if (amount == 0) return 0;
        deposited = 0;
        uint256 count = 0;
        for (uint256 i = 0; i < MAX_VENUES; ++i) {
            if (address(_venues[i]) != address(0)) ++count;
        }
        if (count == 0) return 0;
        uint256 share = amount / count;
        for (uint256 i = 0; i < MAX_VENUES; ++i) {
            IERC4626 v = _venues[i];
            if (address(v) == address(0)) continue;
            uint256 put = --count == 0 ? amount - deposited : share; // the last venue takes the rounding dust
            if (put == 0) continue;
            USDC.forceApprove(address(v), put);
            // forge-lint: disable-next-line(unused-return,calls-loop) two admin-set venues; shares read via balanceOf
            v.deposit(put, address(this));
            deposited += put;
        }
    }
}
