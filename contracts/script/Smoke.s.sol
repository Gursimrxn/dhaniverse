// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {MealCounter} from "../src/food/MealCounter.sol";
import {FoodHook} from "../src/food/FoodHook.sol";
import {SpiceMerchant} from "../src/quests/SpiceMerchant.sol";
import {MealTicket, Vouchers} from "../src/money/Vouchers.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {IPermit2, IUniversalRouter} from "../src/uniswap/UniswapPeriphery.sol";
import {QuestPool} from "./uniswap/QuestPool.sol";

/// @notice A smoke test of a deployed LOCAL chain (anvil), the way the server will drive it: a player buys a thali
///         with a server-signed MealTicket, swaps $0.50 of USDC for MANGO through Uniswap's Universal Router, and
///         delivers it to the Spice Merchant for the demo campaign.
///
///   PLAYER_KEY=<any funded anvil key> TICKET_SIGNER_KEY=<from dev_chain.sh> \
///     forge script script/Smoke.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
contract Smoke is Script, QuestPool {
    uint256 internal constant THALI_FOOD = 6e6;
    uint128 internal constant CARGO_USDC = 500_000;

    string internal d;
    uint256 internal playerKey;
    address internal player;

    function run() external {
        d = vm.readFile(string.concat(vm.projectRoot(), "/deployments/anvil.json"));
        require(vm.parseJsonBool(d, ".usdcIsMock"), "Smoke: local chains only (it mints MockUSDC)");
        playerKey = vm.envUint("PLAYER_KEY");
        player = vm.addr(playerKey);
        uint256 paid = _eatThali();
        uint256 got = _swapForMango();
        _deliver(got);
        console.log("thali cost (USDC base units):", paid);
        console.log("MANGO from a $0.50 swap (wei):", got);
    }

    /// @dev The server's ticket: one thali, 2% headroom over the live price.
    function _eatThali() internal returns (uint256 paid) {
        address usdc = vm.parseJsonAddress(d, ".usdc");
        MealCounter counter = MealCounter(vm.parseJsonAddress(d, ".contracts.MealCounter"));
        (,, uint256 live) = FoodHook(vm.parseJsonAddress(d, ".contracts.FoodHook")).priceBand();
        MealTicket memory t = MealTicket(
            player,
            keccak256("thali"),
            THALI_FOOD,
            THALI_FOOD * live / 1e6 * 102 / 100,
            keccak256(abi.encode("smoke meal", block.timestamp)),
            uint64(block.timestamp + 10 minutes)
        );
        bytes memory sig = _signTicket(t, address(counter), vm.envUint("TICKET_SIGNER_KEY"));
        vm.startBroadcast(playerKey);
        MockUSDC(usdc).mint(player, 2e6);
        IERC20(usdc).approve(address(counter), type(uint256).max);
        (paid,) = counter.buyMeal(t, sig);
        vm.stopBroadcast();
    }

    function _swapForMango() internal returns (uint256 got) {
        address usdc = vm.parseJsonAddress(d, ".usdc");
        address permit2 = vm.parseJsonAddress(d, ".uniswap.permit2");
        address router = vm.parseJsonAddress(d, ".uniswap.universalRouter");
        address mango = vm.parseJsonAddress(d, ".contracts.QuestToken");
        PoolKey memory key = PoolKey(
            Currency.wrap(vm.parseJsonAddress(d, ".uniswap.questPool.currency0")),
            Currency.wrap(vm.parseJsonAddress(d, ".uniswap.questPool.currency1")),
            uint24(vm.parseJsonUint(d, ".uniswap.questPool.fee")),
            int24(vm.parseJsonInt(d, ".uniswap.questPool.tickSpacing")),
            IHooks(address(0))
        );
        (bytes memory commands, bytes[] memory inputs) = encodeQuestSwap(key, usdc, CARGO_USDC, 1);
        uint256 before = IERC20(mango).balanceOf(player);
        vm.startBroadcast(playerKey);
        IERC20(usdc).approve(permit2, type(uint256).max);
        IPermit2(permit2).approve(usdc, router, type(uint160).max, uint48(block.timestamp + 1 days));
        IUniversalRouter(router).execute(commands, inputs, block.timestamp + 5 minutes);
        vm.stopBroadcast();
        got = IERC20(mango).balanceOf(player) - before;
    }

    function _deliver(uint256 got) internal {
        address mango = vm.parseJsonAddress(d, ".contracts.QuestToken");
        SpiceMerchant spice = SpiceMerchant(vm.parseJsonAddress(d, ".contracts.SpiceMerchant"));
        uint256 campaignId = vm.parseJsonUint(d, ".demoCampaignId");
        vm.startBroadcast(playerKey);
        IERC20(mango).approve(address(spice), got);
        spice.deliver(campaignId, mango, got, keccak256(abi.encode("smoke run", block.timestamp)));
        vm.stopBroadcast();
    }

    function _signTicket(MealTicket memory t, address counter, uint256 key) internal view returns (bytes memory) {
        bytes32 domain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(Vouchers.DOMAIN_NAME)),
                keccak256(bytes(Vouchers.DOMAIN_VERSION)),
                block.chainid,
                counter
            )
        );
        bytes32 structHash =
            keccak256(abi.encode(Vouchers.MEAL_TICKET_TYPEHASH, t.player, t.item, t.food, t.maxUsdc, t.ref, t.expiry));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, keccak256(abi.encodePacked("\x19\x01", domain, structHash)));
        return abi.encodePacked(r, s, v);
    }
}
