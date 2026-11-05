// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPermit2, IPositionManager, V4Periphery} from "../../src/uniswap/UniswapPeriphery.sol";

/// @notice The plain Uniswap v4 quest-token pool (e.g. MANGO/USDC, no hook) and the Spice Run swap, encoded exactly as
///         the server must encode them. Used by script/Deploy.s.sol, script/QuestSwap.s.sol and test/uniswap.
abstract contract QuestPool {
    /// @notice The quest pool for `token` against `usdc`.
    function questPoolKey(address token, address usdc, uint24 fee, int24 tickSpacing)
        internal
        pure
        returns (PoolKey memory)
    {
        (address a, address b) = token < usdc ? (token, usdc) : (usdc, token);
        return PoolKey(Currency.wrap(a), Currency.wrap(b), fee, tickSpacing, IHooks(address(0)));
    }

    /// @notice sqrtPriceX96 for a price of `usdcPerToken` USDC base units per 1 whole token (10**tokenDecimals units).
    function questSqrtPrice(address token, address usdc, uint256 usdcPerToken, uint8 tokenDecimals)
        internal
        pure
        returns (uint160)
    {
        uint256 unit = 10 ** tokenDecimals;
        // Uniswap's price is token1 base units per token0 base unit, as a Q192 fraction.
        uint256 priceX192 =
            token < usdc ? Math.mulDiv(usdcPerToken, 1 << 192, unit) : Math.mulDiv(unit, 1 << 192, usdcPerToken);
        return uint160(Math.sqrt(priceX192));
    }

    /// @notice Creates the pool through PositionManager and adds a full-range position holding about `tokenAmount`
    ///         and `usdcAmount`, owned by `owner`. The sender pays through Permit2 (approvals are set here).
    function seedQuestPool(
        IPositionManager positionManager,
        IPermit2 permit2,
        PoolKey memory key,
        uint160 sqrtPriceX96,
        address token,
        uint256 tokenAmount,
        uint256 usdcAmount,
        address owner
    ) internal returns (uint256 tokenId) {
        address usdc = Currency.unwrap(key.currency0) == token
            ? Currency.unwrap(key.currency1)
            : Currency.unwrap(key.currency0);
        IERC20(token).approve(address(permit2), type(uint256).max);
        IERC20(usdc).approve(address(permit2), type(uint256).max);
        permit2.approve(token, address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(usdc, address(positionManager), type(uint160).max, type(uint48).max);
        positionManager.initializePool(key, sqrtPriceX96);

        (uint256 amount0, uint256 amount1) = token < usdc ? (tokenAmount, usdcAmount) : (usdcAmount, tokenAmount);
        // Full range: L = sqrt(amount0 × amount1) needs just under both amounts at this price.
        uint256 liquidity = Math.sqrt(amount0 * amount1);
        bytes memory actions = abi.encodePacked(V4Periphery.MINT_POSITION, V4Periphery.SETTLE_PAIR);
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            key,
            TickMath.minUsableTick(key.tickSpacing),
            TickMath.maxUsableTick(key.tickSpacing),
            liquidity,
            uint128(amount0 * 101 / 100),
            uint128(amount1 * 101 / 100),
            owner,
            bytes("")
        );
        params[1] = abi.encode(key.currency0, key.currency1);
        tokenId = positionManager.nextTokenId();
        positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp + 1 hours);
    }

    /// @notice The Universal Router call for "swap exactly `usdcIn` USDC for at least `minOut` of the quest token":
    ///         one V4_SWAP command with SWAP_EXACT_IN_SINGLE, SETTLE_ALL (USDC in) and TAKE_ALL (token out).
    ///         The player must have approved Permit2 for USDC and Permit2 must allow the router.
    function encodeQuestSwap(PoolKey memory key, address usdc, uint128 usdcIn, uint128 minOut)
        internal
        pure
        returns (bytes memory commands, bytes[] memory inputs)
    {
        bool zeroForOne = Currency.unwrap(key.currency0) == usdc;
        (Currency currencyIn, Currency currencyOut) =
            zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);
        bytes memory actions =
            abi.encodePacked(V4Periphery.SWAP_EXACT_IN_SINGLE, V4Periphery.SETTLE_ALL, V4Periphery.TAKE_ALL);
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(V4Periphery.ExactInputSingleParams(key, zeroForOne, usdcIn, minOut, bytes("")));
        params[1] = abi.encode(currencyIn, uint256(usdcIn));
        params[2] = abi.encode(currencyOut, uint256(minOut));
        commands = abi.encodePacked(V4Periphery.V4_SWAP);
        inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
    }
}
