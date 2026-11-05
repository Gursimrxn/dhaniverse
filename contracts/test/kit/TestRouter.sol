// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

/// @notice Test-only router: lets a test trade and add stock on a local pool before FoodRouter exists (Phase 2).
///         It has no rules of its own (no roles, no refs). The caller pays and receives directly.
contract TestRouter is IUnlockCallback {
    using SafeERC20 for IERC20;

    IPoolManager public immutable manager;

    struct Job {
        bool isSwap;
        address payer;
        PoolKey key;
        IPoolManager.SwapParams swap;
        IPoolManager.ModifyLiquidityParams liquidity;
    }

    constructor(IPoolManager poolManager) {
        manager = poolManager;
    }

    function swap(PoolKey memory key, IPoolManager.SwapParams memory params) external returns (BalanceDelta) {
        IPoolManager.ModifyLiquidityParams memory none;
        return abi.decode(manager.unlock(abi.encode(Job(true, msg.sender, key, params, none))), (BalanceDelta));
    }

    function modifyLiquidity(PoolKey memory key, IPoolManager.ModifyLiquidityParams memory params)
        external
        returns (BalanceDelta)
    {
        IPoolManager.SwapParams memory none;
        return abi.decode(manager.unlock(abi.encode(Job(false, msg.sender, key, none, params))), (BalanceDelta));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "TestRouter: only the PoolManager");
        Job memory job = abi.decode(data, (Job));
        BalanceDelta delta;
        if (job.isSwap) {
            delta = manager.swap(job.key, job.swap, "");
        } else {
            (delta,) = manager.modifyLiquidity(job.key, job.liquidity, "");
        }
        _settle(job.key.currency0, job.payer, delta.amount0());
        _settle(job.key.currency1, job.payer, delta.amount1());
        return abi.encode(delta);
    }

    /// @dev Negative: the payer owes the pool. Positive: the pool owes the payer.
    function _settle(Currency currency, address payer, int128 amount) private {
        if (amount < 0) {
            manager.sync(currency);
            IERC20(Currency.unwrap(currency)).safeTransferFrom(payer, address(manager), uint256(int256(-amount)));
            manager.settle();
        } else if (amount > 0) {
            manager.take(currency, payer, uint256(int256(amount)));
        }
    }
}
