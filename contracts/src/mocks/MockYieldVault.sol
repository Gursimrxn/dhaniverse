// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title MockYieldVault
/// @notice SIMULATED YIELD, for anvil and Sepolia demos only. An ERC-4626 vault over USDC that pays a stated APR to its
///         depositors out of a "drip pot" the admin funds in advance. The interest is real USDC moving, but nobody
///         earns it from lending: it's paid by whoever funded the pot. The UI labels it "simulated".
/// @dev Production venues are Aave v3 / Morpho ERC-4626 vaults (not available on Sepolia with Circle's USDC).
///      Interest accrues linearly on the depositors' assets and stops when the pot is empty.
///      Spec: docs/architecture/spec.json, contract "MockYieldVault".
contract MockYieldVault is ERC4626, Ownable2Step {
    using SafeERC20 for IERC20;

    uint256 private constant BPS = 10_000;
    uint256 private constant YEAR_SECONDS = 365 days;
    /// @dev Extra share decimals, so a first deposit can't be front-run into rounding to nothing.
    uint8 private constant SHARE_DECIMALS_OFFSET = 6;
    /// @notice The highest APR the admin may set (50%), so a typo can't drain the pot in a day.
    uint256 public constant MAX_APR_BPS = 5000;

    /// @notice The stated yearly rate paid to depositors, in basis points (400 = 4%).
    uint256 public aprBps;
    /// @notice USDC set aside to pay interest, not yet paid out (base units).
    uint256 public dripPot;
    /// @notice When interest was last moved from the pot to depositors (unix seconds).
    uint256 public lastAccrual;

    /// @notice USDC was added to the drip pot.
    event DripFunded(address indexed from, uint256 amount);
    /// @notice Interest moved from the pot to depositors (base units).
    event Accrued(uint256 interest, uint256 potLeft);
    event AprSet(uint256 oldAprBps, uint256 newAprBps);

    /// @notice The APR is above MAX_APR_BPS.
    error MockYieldVault__AprTooHigh(uint256 aprBps, uint256 max);
    /// @notice Asked to fund nothing.
    error MockYieldVault__ZeroAmount();
    /// @notice The admin role can be handed over, but never thrown away.
    error MockYieldVault__AdminCantBeRemoved();

    constructor(IERC20 usdc, uint256 aprBps_, address admin)
        ERC20("Mock Yield USDC (simulated)", "mockyUSDC")
        ERC4626(usdc)
        Ownable(admin)
    {
        if (aprBps_ > MAX_APR_BPS) {
            revert MockYieldVault__AprTooHigh(aprBps_, MAX_APR_BPS);
        }
        aprBps = aprBps_;
        lastAccrual = block.timestamp;
        emit AprSet(0, aprBps_);
    }

    /// @notice Adds `amount` USDC from the caller to the drip pot that pays the interest.
    function fundDrip(uint256 amount) external {
        if (amount == 0) revert MockYieldVault__ZeroAmount();
        _accrue();
        dripPot += amount;
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
        emit DripFunded(msg.sender, amount);
    }

    /// @notice Changes the stated APR from now on (interest so far is settled at the old rate first).
    function setApr(uint256 newAprBps) external onlyOwner {
        if (newAprBps > MAX_APR_BPS) revert MockYieldVault__AprTooHigh(newAprBps, MAX_APR_BPS);
        _accrue();
        uint256 old = aprBps;
        aprBps = newAprBps;
        emit AprSet(old, newAprBps);
    }

    /// @notice Settles interest so far (anyone; also done on every deposit and withdrawal).
    function accrue() external {
        _accrue();
    }

    /// @notice Always refuses.
    function renounceOwnership() public pure override {
        revert MockYieldVault__AdminCantBeRemoved();
    }

    /// @notice Depositors' assets including interest earned but not yet settled: balance − pot + pending interest.
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) - dripPot + _pending();
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        _accrue();
        super._deposit(caller, receiver, assets, shares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        _accrue();
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function _decimalsOffset() internal pure override returns (uint8) {
        return SHARE_DECIMALS_OFFSET;
    }

    function _accrue() private {
        uint256 interest = _pending();
        lastAccrual = block.timestamp;
        if (interest != 0) {
            dripPot -= interest;
            emit Accrued(interest, dripPot);
        }
    }

    /// @dev Linear interest on the depositors' assets since the last accrual, capped by the pot.
    function _pending() private view returns (uint256) {
        uint256 principal = IERC20(asset()).balanceOf(address(this)) - dripPot;
        uint256 owed = Math.mulDiv(principal, aprBps * (block.timestamp - lastAccrual), BPS * YEAR_SECONDS);
        return Math.min(owed, dripPot);
    }
}
