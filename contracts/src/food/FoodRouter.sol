// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {FoodHook} from "./FoodHook.sol";
import {FoodToken} from "./FoodToken.sol";

/// @title FoodRouter
/// @notice The only way to trade FOOD. Two of our contracts use it:
///         - MealCounter (Buyer) buys the FOOD in each meal a player pays for, and the FOOD is burned;
///         - Farm (Seller) sells the harvest into the pool through the day.
///         At today's price limit a trade stops part-way instead of failing, and reports how much it filled.
///         Every trade carries a ref that works once, so a retry can never buy or sell twice.
/// @dev Replaceable: if this contract breaks, the admin deploys a fixed one and points FoodHook at it. The pool,
///      its money and its price history stay put. Spec: docs/architecture/spec.json, contract "FoodRouter".
contract FoodRouter is IUnlockCallback, Ownable2Step, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    /// @notice What a key may do here. None is also the off switch.
    enum Role {
        None,
        Buyer,
        Seller
    }

    /// @dev The four things this router asks Uniswap to do inside a callback.
    enum Action {
        Buy,
        Sell,
        AddStock,
        RemoveStock
    }

    // ---------------------------------------------------------------- fixed at deploy

    IPoolManager private immutable MANAGER;
    FoodHook private immutable HOOK;
    FoodToken private immutable FOOD_TOKEN;
    Currency private immutable USDC;
    Currency private immutable FOOD;
    bool private immutable FOOD_IS_TOKEN0;
    /// @dev The pool has no trading fee (founder, 28 Oct): only our own keys trade.
    uint24 private constant POOL_FEE = 0;
    int24 private immutable TICK_SPACING;
    /// @dev "No USDC limit" for the actions where the admin or the seller pays nothing in, or is the payer by choice.
    uint256 private constant NO_USDC_LIMIT = type(uint256).max;

    // ---------------------------------------------------------------- state

    mapping(address key => Role) private _roles;
    mapping(bytes32 ref => bool) private _refUsed;

    // ---------------------------------------------------------------- events

    /// @notice A batch of eaten food was bought and burned. bought below wanted means today's limit was reached.
    event FoodBought(
        uint256 indexed day, address indexed buyer, uint256 wanted, uint256 bought, uint256 usdcPaid, bytes32 ref
    );
    /// @notice The supplier sold food. sold below offered means today's limit was reached.
    event FoodSold(
        uint256 indexed day, address indexed seller, uint256 offered, uint256 sold, uint256 usdcGot, bytes32 ref
    );
    /// @notice The pool's stock changed. usdc and food are the amounts that went in (or out, when removing).
    event LiquidityChanged(address indexed by, int256 liquidityDelta, uint256 usdc, uint256 food);
    /// @notice A key got or lost a role.
    event RoleSet(address indexed key, Role role);

    // ---------------------------------------------------------------- errors

    /// @notice This key doesn't have the role for this function, or it was switched off.
    error FoodRouter__NotAllowed(address caller, Role has, Role needs);
    /// @notice This action already went through. The retry was blocked.
    error FoodRouter__RefUsed(bytes32 ref);
    /// @notice Asked to trade or move nothing.
    error FoodRouter__ZeroAmount();
    /// @notice The FOOD would cost more USDC than the buyer allowed. Nothing was bought.
    error FoodRouter__TooDear(uint256 usdcNeeded, uint256 maxUsdc);
    /// @notice Only Uniswap's PoolManager may call the settlement plumbing.
    error FoodRouter__OnlyPoolManager(address caller);
    /// @notice The admin role can be handed over, but never thrown away.
    error FoodRouter__AdminCantBeRemoved();

    // ---------------------------------------------------------------- setup

    /// @param manager Uniswap's PoolManager.
    /// @param hook FoodHook, which holds the price rules. Its pool is FOOD against USDC.
    /// @param admin The admin key: gives out roles and manages the pool's stock.
    /// @param tickSpacing The pool's tick spacing (part of the pool's identity in Uniswap).
    constructor(IPoolManager manager, FoodHook hook, address admin, int24 tickSpacing) Ownable(admin) {
        // forge-lint: disable-next-line(unused-return)
        (address usdc, address food,,,,,,) = hook.settings(); // only the two token addresses are needed here
        MANAGER = manager;
        HOOK = hook;
        FOOD_TOKEN = FoodToken(food);
        USDC = Currency.wrap(usdc);
        FOOD = Currency.wrap(food);
        FOOD_IS_TOKEN0 = food < usdc;
        TICK_SPACING = tickSpacing;
    }

    // ---------------------------------------------------------------- trading (server keys)

    /// @notice Buys up to `foodWanted` FOOD with the caller's USDC, stopping at today's limit, then burns it:
    ///         this is food a player has already eaten. The caller must have approved this router for USDC.
    ///         Refuses (FoodRouter__TooDear) if what fits would cost more than `maxUsdc`.
    /// @return foodBought How much was bought (less than wanted if today's limit was reached; 0 if already there).
    /// @return usdcPaid What it cost, in USDC base units.
    function buyFood(uint256 foodWanted, uint256 maxUsdc, bytes32 ref)
        external
        nonReentrant
        returns (uint256 foodBought, uint256 usdcPaid)
    {
        _checkRole(Role.Buyer);
        _useRef(ref, foodWanted);

        if (!_atLimit(true)) {
            (foodBought, usdcPaid) = _unlock(Action.Buy, msg.sender, foodWanted, maxUsdc);
            if (foodBought != 0) FOOD_TOKEN.burn(foodBought);
        }
        // forge-lint: disable-next-line(reentrancy-events) reports what the trade filled; nonReentrant guards it
        emit FoodBought(HOOK.today(), msg.sender, foodWanted, foodBought, usdcPaid, ref);
    }

    /// @notice Sells up to `foodOffered` of the caller's FOOD for USDC, stopping at today's limit.
    ///         Only the FOOD actually sold leaves the caller. The caller must have approved this router for FOOD.
    /// @return foodSold How much was sold (less than offered if today's limit was reached; 0 if already there).
    /// @return usdcGot What it fetched, in USDC base units, paid to the caller.
    function sellFood(uint256 foodOffered, bytes32 ref)
        external
        nonReentrant
        returns (uint256 foodSold, uint256 usdcGot)
    {
        _checkRole(Role.Seller);
        _useRef(ref, foodOffered);

        if (!_atLimit(false)) (foodSold, usdcGot) = _unlock(Action.Sell, msg.sender, foodOffered, NO_USDC_LIMIT);
        // forge-lint: disable-next-line(reentrancy-events) reports what the trade filled; nonReentrant guards it
        emit FoodSold(HOOK.today(), msg.sender, foodOffered, foodSold, usdcGot, ref);
    }

    // ---------------------------------------------------------------- stock (admin)

    /// @notice Puts FOOD and USDC into the pool across the full price range, paid by the admin key.
    ///         The admin must have approved this router for both tokens.
    function addLiquidity(uint128 liquidity) external nonReentrant onlyOwner returns (uint256 usdcIn, uint256 foodIn) {
        if (liquidity == 0) revert FoodRouter__ZeroAmount();
        (usdcIn, foodIn) = _unlock(Action.AddStock, msg.sender, liquidity, NO_USDC_LIMIT);
        // forge-lint: disable-next-line(reentrancy-events) reports what the trade filled; nonReentrant guards it
        emit LiquidityChanged(msg.sender, SafeCast.toInt256(uint256(liquidity)), usdcIn, foodIn);
    }

    /// @notice Takes stock back out of the pool to the admin key: for moving to a new router, or recycling a
    ///         test world.
    function removeLiquidity(uint128 liquidity)
        external
        nonReentrant
        onlyOwner
        returns (uint256 usdcOut, uint256 foodOut)
    {
        if (liquidity == 0) revert FoodRouter__ZeroAmount();
        (usdcOut, foodOut) = _unlock(Action.RemoveStock, msg.sender, liquidity, NO_USDC_LIMIT);
        // forge-lint: disable-next-line(reentrancy-events) reports what the trade filled; nonReentrant guards it
        emit LiquidityChanged(msg.sender, -SafeCast.toInt256(uint256(liquidity)), usdcOut, foodOut);
    }

    // ---------------------------------------------------------------- roles (admin)

    /// @notice Gives a key the Buyer or Seller role, or takes it away (None). This is the off switch.
    function setRole(address key, Role role) external onlyOwner {
        _roles[key] = role;
        emit RoleSet(key, role);
    }

    /// @notice Always refuses. Without an admin, nobody could ever switch a leaked key off.
    function renounceOwnership() public pure override {
        revert FoodRouter__AdminCantBeRemoved();
    }

    // ---------------------------------------------------------------- reads (never blocked)

    /// @notice A key's role.
    function roleOf(address key) external view returns (Role) {
        return _roles[key];
    }

    /// @notice Whether a ref has been used.
    function refUsed(bytes32 ref) external view returns (bool) {
        return _refUsed[ref];
    }

    /// @notice The pool this router trades, as Uniswap identifies it.
    function poolKey() public view returns (PoolKey memory) {
        (Currency token0, Currency token1) = FOOD_IS_TOKEN0 ? (FOOD, USDC) : (USDC, FOOD);
        return PoolKey({
            currency0: token0, currency1: token1, fee: POOL_FEE, tickSpacing: TICK_SPACING, hooks: IHooks(address(HOOK))
        });
    }

    // ---------------------------------------------------------------- Uniswap's settlement plumbing

    /// @notice Called by Uniswap's PoolManager in the middle of our own trades. Nobody else may call it.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(MANAGER)) revert FoodRouter__OnlyPoolManager(msg.sender);
        (Action action, address payer, uint256 amount, uint256 maxUsdc) =
            abi.decode(data, (Action, address, uint256, uint256));
        PoolKey memory key = poolKey();

        BalanceDelta delta;
        if (action == Action.Buy || action == Action.Sell) {
            delta = MANAGER.swap(key, _swapParams(action == Action.Buy, amount), "");
        } else {
            int256 change = SafeCast.toInt256(amount);
            // forge-lint: disable-next-line(unused-return) fees are already inside delta in v4, and the fee is 0
            (delta,) = MANAGER.modifyLiquidity(key, _fullRange(action == Action.AddStock ? change : -change), "");
        }

        (int128 usdcDelta, int128 foodDelta) =
            FOOD_IS_TOKEN0 ? (delta.amount1(), delta.amount0()) : (delta.amount0(), delta.amount1());
        // Bought FOOD comes to this router, to be burned. Everything else goes to, or comes from, the payer.
        if (usdcDelta < 0) {
            uint256 usdcOwed = SafeCast.toUint256(-int256(usdcDelta));
            if (usdcOwed > maxUsdc) revert FoodRouter__TooDear(usdcOwed, maxUsdc);
        }
        uint256 usdcMoved = _settle(USDC, usdcDelta, payer, payer);
        uint256 foodMoved = _settle(FOOD, foodDelta, payer, action == Action.Buy ? address(this) : payer);
        return abi.encode(foodMoved, usdcMoved);
    }

    // ---------------------------------------------------------------- internals

    function _checkRole(Role needed) private view {
        Role has = _roles[msg.sender];
        if (has != needed) revert FoodRouter__NotAllowed(msg.sender, has, needed);
    }

    function _useRef(bytes32 ref, uint256 amount) private {
        if (amount == 0) revert FoodRouter__ZeroAmount();
        if (_refUsed[ref]) revert FoodRouter__RefUsed(ref);
        _refUsed[ref] = true;
    }

    /// @dev Runs one action inside Uniswap's unlock. Returns (FOOD moved, USDC moved), or for stock (USDC, FOOD).
    function _unlock(Action action, address payer, uint256 amount, uint256 maxUsdc)
        private
        returns (uint256 a, uint256 b)
    {
        (uint256 foodMoved, uint256 usdcMoved) =
            abi.decode(MANAGER.unlock(abi.encode(action, payer, amount, maxUsdc)), (uint256, uint256));
        return (action == Action.Buy || action == Action.Sell) ? (foodMoved, usdcMoved) : (usdcMoved, foodMoved);
    }

    /// @dev Buying FOOD pays USDC in. Uniswap's sign rule: positive amount = exact output, negative = exact input.
    ///      The price limit is today's band edge in the direction of the trade, so the trade stops there.
    function _swapParams(bool buying, uint256 amount) private view returns (IPoolManager.SwapParams memory) {
        bool zeroForOne = buying ? !FOOD_IS_TOKEN0 : FOOD_IS_TOKEN0;
        int256 signed = SafeCast.toInt256(amount);
        return IPoolManager.SwapParams(zeroForOne, buying ? signed : -signed, _limitFor(zeroForOne));
    }

    function _limitFor(bool zeroForOne) private view returns (uint160) {
        // forge-lint: disable-next-line(unused-return) the live price isn't needed for the limit
        (uint160 low, uint160 high,) = HOOK.band();
        return zeroForOne ? low : high;
    }

    /// @dev True if the price already sits at today's edge in this direction, so nothing more can trade today.
    function _atLimit(bool buying) private view returns (bool) {
        bool zeroForOne = buying ? !FOOD_IS_TOKEN0 : FOOD_IS_TOKEN0;
        (uint160 low, uint160 high, uint160 live) = HOOK.band();
        return zeroForOne ? live <= low : live >= high;
    }

    function _fullRange(int256 liquidityDelta) private view returns (IPoolManager.ModifyLiquidityParams memory) {
        return IPoolManager.ModifyLiquidityParams(
            TickMath.minUsableTick(TICK_SPACING), TickMath.maxUsableTick(TICK_SPACING), liquidityDelta, 0
        );
    }

    /// @dev Negative delta: we owe the pool, paid by `payer`. Positive: the pool owes us, sent to `receiver`.
    ///      Returns the amount moved either way.
    function _settle(Currency currency, int128 delta, address payer, address receiver) private returns (uint256) {
        if (delta < 0) {
            uint256 owed = SafeCast.toUint256(-int256(delta));
            MANAGER.sync(currency);
            // `payer` is always the msg.sender of our own buyFood/sellFood/addLiquidity: the PoolManager only ever
            // calls back the contract that called unlock (this one), with the data this contract gave it.
            // forge-lint: disable-next-line(arbitrary-send-erc20)
            IERC20(Currency.unwrap(currency)).safeTransferFrom(payer, address(MANAGER), owed);
            // forge-lint: disable-next-line(unused-return) settle returns the amount, which we already know
            MANAGER.settle();
            return owed;
        }
        if (delta > 0) {
            uint256 due = SafeCast.toUint256(int256(delta));
            MANAGER.take(currency, receiver, due);
            return due;
        }
        return 0;
    }
}
