// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

// The few Uniswap v4 periphery calls Tallyport makes (seeding the MANGO pool, the player's Spice Run swap, quotes),
// as minimal interfaces instead of a v4-periphery/universal-router dependency. They match the contracts deployed on
// Sepolia (docs.uniswap.org/contracts/v4/deployments): PositionManager 0x429b…09b4, UniversalRouter 0x3A9D…F98b,
// Permit2 0x0000…8BA3, V4Quoter 0x68aF…8244, StateView 0xe1dd…7e4c. Checked by test/uniswap/QuestPool.t.sol against
// those contracts' own bytecode.

/// @notice Uniswap's Permit2: the allowance hub PositionManager and UniversalRouter pull tokens through.
interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
    function allowance(address user, address token, address spender)
        external
        view
        returns (uint160 amount, uint48 expiration, uint48 nonce);
}

/// @notice Uniswap v4's PositionManager (liquidity positions as NFTs).
interface IPositionManager {
    function initializePool(PoolKey calldata key, uint160 sqrtPriceX96) external payable returns (int24);
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;
    function nextTokenId() external view returns (uint256);
    function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity);
}

/// @notice Uniswap's Universal Router: the router players swap through.
interface IUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

/// @notice Uniswap v4's quoter (simulates a swap and reverts with the result; call it with eth_call).
interface IV4Quoter {
    struct QuoteExactSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 exactAmount;
        bytes hookData;
    }

    function quoteExactInputSingle(QuoteExactSingleParams memory params)
        external
        returns (uint256 amountOut, uint256 gasEstimate);
}

/// @notice The v4-periphery structs and command/action numbers we encode.
library V4Periphery {
    /// @notice v4-periphery IV4Router.ExactInputSingleParams as deployed on Sepolia (5 fields).
    struct ExactInputSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountIn;
        uint128 amountOutMinimum;
        bytes hookData;
    }

    // Universal Router commands (universal-router Commands.sol).
    uint8 internal constant V4_SWAP = 0x10;

    // v4-periphery Actions.sol.
    uint8 internal constant MINT_POSITION = 0x02;
    uint8 internal constant SWAP_EXACT_IN_SINGLE = 0x06;
    uint8 internal constant SETTLE_ALL = 0x0c;
    uint8 internal constant SETTLE_PAIR = 0x0d;
    uint8 internal constant TAKE_ALL = 0x0f;
}
