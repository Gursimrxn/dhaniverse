// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TownWorld} from "../kit/TownWorld.sol";
import {Farm} from "../../src/food/Farm.sol";
import {FoodRouter} from "../../src/food/FoodRouter.sol";

/// @notice Farm: the keeper sells the harvest, and every USDC goes straight to Treasury.
contract FarmTest is TownWorld {
    function test_sell_sendsTheProceedsToTreasury() public {
        bytes32 ref = _ref();
        uint256 stockBefore = farm.stock();
        vm.expectEmit(true, false, false, false, address(farm));
        emit Farm.HarvestSold(ref, 0, 0, 0);
        vm.prank(keeper);
        (uint256 sold, uint256 got) = farm.sell(500 * ONE_FOOD, ref);
        assertEq(sold, 500 * ONE_FOOD);
        assertApproxEqRel(got, 500 * BASE_PRICE, 0.02e18, "about $2");
        assertEq(usdc.balanceOf(address(treasury)), got, "straight to Treasury");
        assertEq(usdc.balanceOf(address(farm)), 0, "the farm keeps no USDC");
        assertEq(farm.stock(), stockBefore - sold);
        assertEq(foodToken.allowance(address(farm), address(router)), 0, "no allowance left behind");
    }

    function test_sell_stopsAtTodaysLimit_unsoldStaysOnTheFarm() public {
        uint256 stockBefore = farm.stock();
        vm.prank(keeper);
        (uint256 sold,) = farm.sell(50_000 * ONE_FOOD, _ref());
        assertLt(sold, 50_000 * ONE_FOOD);
        assertEq(farm.stock(), stockBefore - sold);
    }

    function test_sell_refusals() public {
        vm.expectRevert(abi.encodeWithSelector(Farm.Farm__NotKeeper.selector, stranger, keeper));
        vm.prank(stranger);
        farm.sell(ONE_FOOD, _ref());

        vm.expectRevert(Farm.Farm__ZeroAmount.selector);
        vm.prank(keeper);
        farm.sell(0, _ref());

        uint256 stock = farm.stock();
        vm.expectRevert(abi.encodeWithSelector(Farm.Farm__NotEnoughStock.selector, stock + 1, stock));
        vm.prank(keeper);
        farm.sell(stock + 1, _ref());

        bytes32 ref = _ref();
        vm.prank(keeper);
        farm.sell(ONE_FOOD, ref);
        vm.expectRevert(abi.encodeWithSelector(FoodRouter.FoodRouter__RefUsed.selector, ref));
        vm.prank(keeper);
        farm.sell(ONE_FOOD, ref);
    }

    function test_restock_andAdmin() public {
        vm.startPrank(admin);
        foodToken.approve(address(farm), 10 * ONE_FOOD);
        vm.expectEmit(address(farm));
        emit Farm.Restocked(admin, 10 * ONE_FOOD);
        farm.restock(10 * ONE_FOOD);
        vm.expectRevert(Farm.Farm__ZeroAmount.selector);
        farm.restock(0);

        vm.expectEmit(address(farm));
        emit Farm.KeeperSet(keeper, stranger);
        farm.setKeeper(stranger);
        vm.expectRevert(Farm.Farm__ZeroAddress.selector);
        farm.setKeeper(address(0));
        vm.expectRevert(Farm.Farm__ZeroAddress.selector);
        farm.setRouter(FoodRouter(address(0)));
        vm.expectEmit(address(farm));
        emit Farm.RouterSet(address(router), address(1));
        farm.setRouter(FoodRouter(address(1)));
        vm.expectRevert(Farm.Farm__AdminCantBeRemoved.selector);
        farm.renounceOwnership();
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        farm.restock(1);
        assertEq(farm.treasury(), address(treasury));
    }

    function test_constructor_refusesZeroAddresses() public {
        vm.expectRevert(Farm.Farm__ZeroAddress.selector);
        new Farm(router, usdc, IERC20(address(0)), address(treasury), keeper, admin);
    }
}
