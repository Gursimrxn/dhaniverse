// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";
import {QuestToken} from "../../src/quests/QuestToken.sol";
import {IPermit2, IPositionManager, IUniversalRouter} from "../../src/uniswap/UniswapPeriphery.sol";
import {QuestPool} from "../../script/uniswap/QuestPool.sol";
import {UniswapOnAnvil} from "../../script/anvil/UniswapOnAnvil.sol";

/// @notice The anvil Uniswap setup, end to end: Uniswap's own Sepolia bytecode (PoolManager, PositionManager,
///         Permit2, UniversalRouter) placed at its Sepolia addresses, the MANGO/USDC pool seeded through
///         PositionManager, and a player's Spice Run swap through the real Universal Router, encoded the way the
///         server encodes it.
contract QuestPoolTest is Test, QuestPool, UniswapOnAnvil {
    MockUSDC internal usdc;
    QuestToken internal mango;
    address internal admin = makeAddr("admin");
    address internal player = makeAddr("player");

    function setUp() public {
        etchUniswap();
        usdc = new MockUSDC();
        mango = new QuestToken("Mango", "MANGO", admin);
    }

    function test_seedThroughPositionManager_thenSwapThroughTheUniversalRouter() public {
        PoolKey memory key = questPoolKey(address(mango), address(usdc), 3000, 60);
        uint160 sqrtPrice = questSqrtPrice(address(mango), address(usdc), 50_000, 18); // $0.05 per MANGO

        vm.startPrank(admin);
        mango.mint(admin, 200_000 ether);
        usdc.mint(admin, 10_000e6);
        uint256 tokenId = seedQuestPool(
            IPositionManager(POSITION_MANAGER),
            IPermit2(PERMIT2),
            key,
            sqrtPrice,
            address(mango),
            200_000 ether,
            10_000e6,
            admin
        );
        vm.stopPrank();
        assertGt(IPositionManager(POSITION_MANAGER).getPositionLiquidity(tokenId), 0, "a real v4 position");

        // The player swaps $0.50 for MANGO through the Universal Router.
        usdc.mint(player, 500_000);
        vm.startPrank(player);
        usdc.approve(PERMIT2, type(uint256).max);
        IPermit2(PERMIT2).approve(address(usdc), UNIVERSAL_ROUTER, type(uint160).max, uint48(block.timestamp + 1 days));
        (bytes memory commands, bytes[] memory inputs) = encodeQuestSwap(key, address(usdc), 500_000, 9.8 ether);
        IUniversalRouter(UNIVERSAL_ROUTER).execute(commands, inputs, block.timestamp + 60);
        vm.stopPrank();

        assertEq(usdc.balanceOf(player), 0, "all the cargo money went in");
        assertApproxEqRel(mango.balanceOf(player), 9.97 ether, 0.002e18, "~10 MANGO less the 0.3% fee");
    }

    function test_minOut_protectsThePlayer() public {
        PoolKey memory key = questPoolKey(address(mango), address(usdc), 3000, 60);
        vm.startPrank(admin);
        mango.mint(admin, 200_000 ether);
        usdc.mint(admin, 10_000e6);
        seedQuestPool(
            IPositionManager(POSITION_MANAGER),
            IPermit2(PERMIT2),
            key,
            questSqrtPrice(address(mango), address(usdc), 50_000, 18),
            address(mango),
            200_000 ether,
            10_000e6,
            admin
        );
        vm.stopPrank();
        usdc.mint(player, 500_000);
        vm.startPrank(player);
        usdc.approve(PERMIT2, type(uint256).max);
        IPermit2(PERMIT2).approve(address(usdc), UNIVERSAL_ROUTER, type(uint160).max, uint48(block.timestamp + 1 days));
        (bytes memory commands, bytes[] memory inputs) = encodeQuestSwap(key, address(usdc), 500_000, 11 ether);
        vm.expectRevert(); // V4TooLittleReceived, wrapped by the router
        IUniversalRouter(UNIVERSAL_ROUTER).execute(commands, inputs, block.timestamp + 60);
        vm.stopPrank();
    }
}
