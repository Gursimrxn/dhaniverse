// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";

/// @notice The shared starting point for every Tallyport test.
///         It gives each test the same named keys, a freshly deployed MockUSDC, and helpers for money units, so a test
///         reads like the game: "Sam pays 0.024 USDC for a thali", not "0x2f9a sends 24000".
abstract contract TestKit is Test {
    // ---------------------------------------------------------------- money units

    /// @notice USDC and FOOD both use 6 decimals.
    uint256 internal constant ONE_USDC = 1e6;
    uint256 internal constant ONE_FOOD = 1e6;

    // ---------------------------------------------------------------- named keys

    // Server keys, each with one job.
    address internal admin;
    address internal keeper;
    address internal ops;
    address internal team;

    // Players, sponsors and outsiders.
    address internal sam;
    address internal priya;
    address internal sponsor;
    address internal stranger;

    MockUSDC internal usdc;

    function setUp() public virtual {
        admin = makeAddr("admin");
        keeper = makeAddr("keeper key");
        ops = makeAddr("ops wallet");
        team = makeAddr("team wallet");
        sam = makeAddr("sam");
        priya = makeAddr("priya");
        sponsor = makeAddr("sponsor");
        stranger = makeAddr("stranger");

        usdc = new MockUSDC();
        vm.label(address(usdc), "USDC");
    }

    // ---------------------------------------------------------------- helpers

    /// @notice USDC base units from a whole-dollar amount and millionths: usdcOf(0, 24_000) = $0.024.
    function usdcOf(uint256 wholeUsdc, uint256 baseUnits) internal pure returns (uint256) {
        return wholeUsdc * ONE_USDC + baseUnits;
    }

    /// @notice Whole USDC to base units: dollars(5) = 5,000,000.
    function dollars(uint256 amount) internal pure returns (uint256) {
        return amount * ONE_USDC;
    }

    /// @notice Whole FOOD to base units.
    function food(uint256 amount) internal pure returns (uint256) {
        return amount * ONE_FOOD;
    }

    /// @notice A fresh local Uniswap v4 PoolManager (v4-core v4.0.0).
    function deployPoolManager() internal returns (PoolManager manager) {
        manager = new PoolManager(admin);
        vm.label(address(manager), "PoolManager");
    }
}
