// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IHousePool} from "./Links.sol";

/// @title Treasury
/// @notice Collects food revenue (every Farm sale, every ration-shop meal) and splits it. Anyone may call split(),
///         which sends the whole balance out: 60% to HousePool's FIXED bucket, 10% to its SAFETY bucket, 20% to ops
///         (gas, servers) and 10% to the team (launch shares; fixed at deploy, summing to 10,000 bps).
/// @dev Spec: docs/architecture/spec.json, contract "Treasury".
contract Treasury is Ownable2Step, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    uint256 private constant BPS = 10_000;
    uint8 private constant FIXED_BUCKET = 0;
    uint8 private constant SAFETY_BUCKET = 2;

    IERC20 private immutable USDC;
    IHousePool private immutable HOUSE_POOL;
    uint256 public immutable fixedBps;
    uint256 public immutable safetyBps;
    uint256 public immutable opsBps;
    uint256 public immutable teamBps;

    /// @notice Receives the ops share (paymaster gas, servers).
    address public ops;
    /// @notice Receives the team share.
    address public team;

    /// @notice The balance was split. All amounts in USDC base units; total = fixed + safety + ops + team.
    event Split(uint256 total, uint256 fixedShare, uint256 safety, uint256 ops, uint256 team);
    event PayeesSet(address indexed ops, address indexed team);

    /// @notice There's no USDC to split.
    error Treasury__NothingToSplit();
    /// @notice The four shares must add up to exactly 10,000 basis points.
    error Treasury__BadShares(uint256 fixedBps, uint256 safetyBps, uint256 opsBps, uint256 teamBps);
    /// @notice An address that must be set was zero.
    error Treasury__ZeroAddress();
    /// @notice The admin role can be handed over, but never thrown away.
    error Treasury__AdminCantBeRemoved();

    constructor(
        IERC20 usdc,
        IHousePool housePool_,
        address ops_,
        address team_,
        uint256 fixedBps_,
        uint256 safetyBps_,
        uint256 opsBps_,
        uint256 teamBps_,
        address admin
    ) Ownable(admin) {
        if (address(usdc) == address(0) || address(housePool_) == address(0)) {
            revert Treasury__ZeroAddress();
        }
        if (fixedBps_ + safetyBps_ + opsBps_ + teamBps_ != BPS) {
            revert Treasury__BadShares(fixedBps_, safetyBps_, opsBps_, teamBps_);
        }
        USDC = usdc;
        HOUSE_POOL = housePool_;
        fixedBps = fixedBps_;
        safetyBps = safetyBps_;
        opsBps = opsBps_;
        teamBps = teamBps_;
        _setPayees(ops_, team_);
    }

    /// @notice Sends the whole USDC balance out in the four shares. Rounding dust goes to the team share, so nothing
    ///         is ever left behind.
    function split() external nonReentrant returns (uint256 total) {
        total = USDC.balanceOf(address(this));
        if (total == 0) revert Treasury__NothingToSplit();
        uint256 fixedShare = total * fixedBps / BPS;
        uint256 safetyShare = total * safetyBps / BPS;
        uint256 opsShare = total * opsBps / BPS;
        uint256 teamShare = total - fixedShare - safetyShare - opsShare;

        USDC.forceApprove(address(HOUSE_POOL), fixedShare + safetyShare);
        if (fixedShare != 0) HOUSE_POOL.fund(FIXED_BUCKET, fixedShare);
        if (safetyShare != 0) HOUSE_POOL.fund(SAFETY_BUCKET, safetyShare);
        if (opsShare != 0) USDC.safeTransfer(ops, opsShare);
        if (teamShare != 0) USDC.safeTransfer(team, teamShare);
        // forge-lint: disable-next-line(reentrancy-events) nonReentrant guards the split
        emit Split(total, fixedShare, safetyShare, opsShare, teamShare);
    }

    /// @notice Changes where the ops and team shares go.
    function setPayees(address ops_, address team_) external onlyOwner {
        _setPayees(ops_, team_);
    }

    /// @notice Always refuses.
    function renounceOwnership() public pure override {
        revert Treasury__AdminCantBeRemoved();
    }

    /// @notice HousePool, which receives the FIXED and SAFETY shares.
    function housePool() external view returns (address) {
        return address(HOUSE_POOL);
    }

    function _setPayees(address ops_, address team_) private {
        if (ops_ == address(0) || team_ == address(0)) revert Treasury__ZeroAddress();
        ops = ops_;
        team = team_;
        emit PayeesSet(ops_, team_);
    }
}
