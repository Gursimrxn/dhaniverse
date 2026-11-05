// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TownWorld} from "../kit/TownWorld.sol";
import {Treasury} from "../../src/money/Treasury.sol";
import {IHousePool} from "../../src/money/Links.sol";

/// @notice Treasury: food revenue split 60/10/20/10, nothing left behind.
contract TreasuryTest is TownWorld {
    function test_split_sendsEverything_60_10_20_10() public {
        usdc.mint(address(treasury), dollars(10));
        vm.expectEmit(address(treasury));
        emit Treasury.Split(dollars(10), dollars(6), dollars(1), dollars(2), dollars(1));
        vm.prank(stranger); // anyone may split
        treasury.split();
        assertEq(housePool.bucketBalance(housePool.FIXED()), dollars(6));
        assertEq(housePool.bucketBalance(housePool.SAFETY()), dollars(1));
        assertEq(usdc.balanceOf(ops), dollars(2));
        assertEq(usdc.balanceOf(team), dollars(1));
        assertEq(usdc.balanceOf(address(treasury)), 0);
    }

    function test_split_nothingToSplit() public {
        vm.expectRevert(Treasury.Treasury__NothingToSplit.selector);
        treasury.split();
    }

    function testFuzz_split_neverLeavesDust_andNeverPaysMoreThanItHad(uint256 amount) public {
        amount = bound(amount, 1, dollars(1_000_000));
        usdc.mint(address(treasury), amount);
        uint256 opsBefore = usdc.balanceOf(ops);
        uint256 teamBefore = usdc.balanceOf(team);
        treasury.split();
        uint256 out = housePool.bucketBalance(0) + housePool.bucketBalance(2) + usdc.balanceOf(ops) - opsBefore
            + usdc.balanceOf(team) - teamBefore;
        assertEq(out, amount, "exactly the balance, split");
        assertEq(usdc.balanceOf(address(treasury)), 0);
        assertLe(housePool.bucketBalance(0), amount * 6000 / 10_000);
    }

    function test_constructor_andPayees() public {
        vm.expectRevert(abi.encodeWithSelector(Treasury.Treasury__BadShares.selector, 6000, 1000, 2000, 999));
        new Treasury(usdc, IHousePool(address(housePool)), ops, team, 6000, 1000, 2000, 999, admin);
        vm.expectRevert(Treasury.Treasury__ZeroAddress.selector);
        new Treasury(usdc, IHousePool(address(0)), ops, team, 6000, 1000, 2000, 1000, admin);

        vm.expectEmit(address(treasury));
        emit Treasury.PayeesSet(priya, sam);
        vm.prank(admin);
        treasury.setPayees(priya, sam);
        assertEq(treasury.ops(), priya);
        assertEq(treasury.team(), sam);
        assertEq(treasury.housePool(), address(housePool));
        assertEq(treasury.fixedBps() + treasury.safetyBps() + treasury.opsBps() + treasury.teamBps(), 10_000);

        vm.expectRevert(Treasury.Treasury__ZeroAddress.selector);
        vm.prank(admin);
        treasury.setPayees(address(0), sam);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        treasury.setPayees(stranger, stranger);
        vm.expectRevert(Treasury.Treasury__AdminCantBeRemoved.selector);
        vm.prank(admin);
        treasury.renounceOwnership();
    }
}
