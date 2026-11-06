// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestKit} from "../kit/TestKit.sol";
import {FoodToken} from "../../src/food/FoodToken.sol";

/// @notice FoodToken: all FOOD is made once, nobody can make more, and eaten FOOD is burned.
contract FoodTokenTest is TestKit {
    /// @notice Starting supply for these tests: 100 million servings.
    uint256 internal constant SUPPLY = 100_000_000 * ONE_FOOD;

    FoodToken internal token;

    function setUp() public override {
        super.setUp();
        token = new FoodToken(admin, SUPPLY);
    }

    // ---------------------------------------------------------------- made once

    function test_deploy_givesTheWholeSupplyToTheHolder() public view {
        assertEq(token.totalSupply(), SUPPLY, "total supply");
        assertEq(token.balanceOf(admin), SUPPLY, "holder has it all");
    }

    function test_deploy_looksLikeUsdc() public view {
        assertEq(token.decimals(), 6, "6 decimals, like USDC");
        assertEq(token.symbol(), "FOOD");
        assertEq(token.name(), "Dhaniverse Food");
    }

    function test_deploy_refusesZeroSupply() public {
        vm.expectRevert(FoodToken.FoodToken__ZeroSupply.selector);
        new FoodToken(admin, 0);
    }

    function test_deploy_refusesNoHolder() public {
        vm.expectRevert(FoodToken.FoodToken__ZeroHolder.selector);
        new FoodToken(address(0), SUPPLY);
    }

    // ---------------------------------------------------------------- eaten FOOD is burned

    function test_burn_shrinksTheBalanceAndTheSupply() public {
        vm.prank(admin);
        token.burn(food(140));

        assertEq(token.balanceOf(admin), SUPPLY - food(140), "holder balance");
        assertEq(token.totalSupply(), SUPPLY - food(140), "supply really shrinks");
    }

    function test_burn_isATransferToNobody() public {
        vm.expectEmit(address(token));
        emit IERC20.Transfer(admin, address(0), food(1));
        vm.prank(admin);
        token.burn(food(1));
    }

    function test_burn_refusesMoreThanYouHave_withTheNumbers() public {
        vm.startPrank(admin);
        token.setAllowed(keeper, true);
        assertTrue(token.transfer(keeper, food(10)));
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, keeper, food(10), food(11))
        );
        vm.prank(keeper);
        token.burn(food(11));
    }

    function test_burn_onlyBurnsYourOwn() public {
        // A stranger with no FOOD can't burn anyone else's: burn always takes from the caller.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, stranger, 0, 1));
        vm.prank(stranger);
        token.burn(1);
        assertEq(token.balanceOf(admin), SUPPLY, "admin untouched");
    }

    /// @notice Whatever is burned, supply goes down by exactly that much, and never below zero.
    function testFuzz_burn_supplyDropsByExactlyTheAmount(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(admin);
        token.burn(amount);
        assertEq(token.totalSupply(), SUPPLY - amount);
    }
}
