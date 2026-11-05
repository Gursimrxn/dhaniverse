// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

/// @title FoodHook
/// @notice The rules that run inside every trade in Tallyport's FOOD/USDC pool on Uniswap v4:
///         1. Only FoodRouter may trade or add stock.
///         2. In one market day, the price moves at most `bandBps` either way from that day's opening price
///            (launch: 1,500 = 15%).
///         3. The price always stays between the floor and the ceiling (launch: 2,000 and 8,000 USDC base units
///            per FOOD, i.e. $0.002 and $0.008).
///         4. Each day's trades are added up, so anyone can read that day's average price.
/// @dev Prices for people are "USDC per FOOD": USDC base units for one whole FOOD (4,000 = $0.004).
///      Inside, prices are Uniswap's sqrtPriceX96, in the pool's own token order. This hook can't be upgraded or
///      paused, as Uniswap expects; to stop trading, take FoodRouter's keys away. Spec: docs/architecture/spec.json.
contract FoodHook is IHooks, Ownable2Step {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    // ---------------------------------------------------------------- constants

    /// @notice FOOD has 6 decimals, so one whole FOOD is 1,000,000 base units.
    uint256 private constant FOOD_UNIT = 1e6;
    /// @notice Fixed-point one for the factors below.
    uint256 private constant ONE = 1e18;

    /// @notice Basis points in one whole (100%).
    uint256 private constant BPS = 10_000;

    // ---------------------------------------------------------------- fixed at deploy

    /// @notice Uniswap's PoolManager: the only caller allowed into the hook functions.
    IPoolManager public immutable poolManager;

    Currency private immutable USDC;
    Currency private immutable FOOD;
    /// @dev True if FOOD sorts first in the pool. Then a higher sqrtPrice means FOOD costs more.
    bool private immutable FOOD_IS_TOKEN0;
    uint256 private immutable FLOOR_USDC_PER_FOOD;
    uint256 private immutable CEILING_USDC_PER_FOOD;
    uint256 private immutable BAND_BPS;
    // The day limit as factors on sqrtPriceX96 (a price moves by the square of its sqrt-price factor), 1e18 = 1.
    // Each is rounded inward, so the allowed band is never wider than `bandBps`.
    /// @dev sqrt(1 + band), rounded down.
    uint256 private immutable SQRT_UP;
    /// @dev sqrt(1 - band), rounded up.
    uint256 private immutable SQRT_DOWN;
    /// @dev 1 / sqrt(1 + band), rounded up.
    uint256 private immutable INV_SQRT_UP;
    /// @dev 1 / sqrt(1 - band), rounded down.
    uint256 private immutable INV_SQRT_DOWN;
    /// @dev The floor and ceiling as sqrt prices in the pool's token order: always MIN_SQRT <= MAX_SQRT.
    uint160 private immutable MIN_SQRT_PRICE;
    uint160 private immutable MAX_SQRT_PRICE;
    uint256 private immutable DAY_LENGTH_SECONDS;
    uint256 private immutable FIRST_DAY_START;

    // ---------------------------------------------------------------- state

    /// @notice The only address allowed to trade and add stock. The admin can replace it.
    address public router;
    /// @dev The one pool this hook serves. Zero until the admin creates it.
    PoolId private _poolId;

    /// @dev One market day's record. Prices are sqrt prices; totals are base units.
    struct Day {
        uint160 openSqrtPriceX96;
        uint128 usdcTotal;
        uint128 foodTotal;
    }

    mapping(uint256 day => Day) private _days;

    // ---------------------------------------------------------------- events

    /// @notice The first trade of a new day. Today's limit is set around this price (USDC per FOOD).
    event DayOpened(uint256 indexed day, uint256 openPrice);
    /// @notice A trade counted toward today's price. usdc and food are base units; priceAfter is USDC per FOOD.
    event TradeCounted(uint256 indexed day, uint256 usdc, uint256 food, uint256 priceAfter);
    /// @notice FoodRouter was replaced.
    event RouterSet(address indexed oldRouter, address indexed newRouter);

    // ---------------------------------------------------------------- errors

    /// @notice Hook functions can only be called by Uniswap's PoolManager.
    error FoodHook__NotPoolManager(address caller);
    /// @notice This hook function is switched off for our pool, so nobody should call it.
    error FoodHook__HookNotUsed();
    /// @notice The deploy settings don't make sense: the floor must be above zero and below the ceiling,
    ///         the band must be above 0 and below 10,000 basis points, and a day must last at least a second.
    error FoodHook__BadSettings(uint256 floor, uint256 ceiling, uint256 bandBps, uint256 dayLength);
    /// @notice Only the admin key can create the pool.
    error FoodHook__NotAdmin(address sender);
    /// @notice This hook serves one pool, and it already exists.
    error FoodHook__PoolExists();
    /// @notice The pool must be FOOD against USDC.
    error FoodHook__WrongTokens(address currency0, address currency1);
    /// @notice The starting price (USDC per FOOD) must be between the floor and the ceiling.
    error FoodHook__StartOutsideBounds(uint256 price, uint256 floor, uint256 ceiling);
    /// @notice The admin role can be handed to another key, but never thrown away: without an admin, a broken
    ///         router could never be replaced.
    error FoodHook__AdminCantBeRemoved();
    /// @notice Trades and new stock must come through FoodRouter.
    error FoodHook__NotRouter(address sender);
    /// @notice The trade would move the price (USDC per FOOD) past today's limit, the floor or the ceiling.
    error FoodHook__OutsideBand(uint256 price, uint256 low, uint256 high);

    // ---------------------------------------------------------------- setup

    /// @param manager Uniswap's PoolManager.
    /// @param admin The admin key: creates the pool and can replace the router.
    /// @param initialRouter FoodRouter's address. Zero is allowed: nobody can trade until setRouter is called.
    /// @param usdc USDC's address.
    /// @param food FoodToken's address.
    /// @param floorUsdcPerFood The lowest price ever allowed, in USDC base units per FOOD (launch 2,000 = $0.002).
    /// @param ceilingUsdcPerFood The highest price ever allowed, in USDC base units per FOOD (launch 8,000).
    /// @param bandBps How far the price may move in one day from the day's opening price (launch 1,500 = 15%).
    /// @param dayLengthSeconds How long a market day lasts (3,600 = one real hour).
    constructor(
        IPoolManager manager,
        address admin,
        // forge-lint: disable-next-line(missing-zero-check)
        address initialRouter,
        Currency usdc,
        Currency food,
        uint256 floorUsdcPerFood,
        uint256 ceilingUsdcPerFood,
        uint256 bandBps,
        uint256 dayLengthSeconds
    ) Ownable(admin) {
        if (
            floorUsdcPerFood == 0 || floorUsdcPerFood >= ceilingUsdcPerFood || bandBps == 0 || bandBps >= BPS
                || dayLengthSeconds == 0
        ) {
            revert FoodHook__BadSettings(floorUsdcPerFood, ceilingUsdcPerFood, bandBps, dayLengthSeconds);
        }
        // Uniswap reads a hook's permissions from its address. Refuse to exist at an address that says otherwise.
        Hooks.validateHookPermissions(this, _permissions());

        poolManager = manager;
        router = initialRouter; // zero on purpose means "no trading yet"
        USDC = usdc;
        FOOD = food;
        FOOD_IS_TOKEN0 = food < usdc;
        FLOOR_USDC_PER_FOOD = floorUsdcPerFood;
        CEILING_USDC_PER_FOOD = ceilingUsdcPerFood;
        BAND_BPS = bandBps;
        SQRT_UP = Math.sqrt(Math.mulDiv(BPS + bandBps, ONE * ONE, BPS), Math.Rounding.Floor);
        SQRT_DOWN = Math.sqrt(Math.mulDiv(BPS - bandBps, ONE * ONE, BPS, Math.Rounding.Ceil), Math.Rounding.Ceil);
        INV_SQRT_UP = Math.sqrt(Math.mulDiv(BPS, ONE * ONE, BPS + bandBps, Math.Rounding.Ceil), Math.Rounding.Ceil);
        INV_SQRT_DOWN = Math.sqrt(Math.mulDiv(BPS, ONE * ONE, BPS - bandBps), Math.Rounding.Floor);
        uint160 floorSqrt = _sqrtPriceOf(floorUsdcPerFood, FOOD_IS_TOKEN0, true);
        uint160 ceilingSqrt = _sqrtPriceOf(ceilingUsdcPerFood, FOOD_IS_TOKEN0, false);
        (MIN_SQRT_PRICE, MAX_SQRT_PRICE) = FOOD_IS_TOKEN0 ? (floorSqrt, ceilingSqrt) : (ceilingSqrt, floorSqrt);
        DAY_LENGTH_SECONDS = dayLengthSeconds;
        FIRST_DAY_START = block.timestamp;
        emit RouterSet(address(0), initialRouter);
    }

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert FoodHook__NotPoolManager(msg.sender);
        _;
    }

    // ---------------------------------------------------------------- admin

    /// @notice Points the hook at a new FoodRouter. The pool, its money and its history stay where they are.
    ///         Setting it to zero stops all trading and new stock.
    // forge-lint: disable-next-line(missing-zero-check)
    function setRouter(address newRouter) external onlyOwner {
        emit RouterSet(router, newRouter);
        router = newRouter; // zero on purpose means "trading off"
    }

    /// @notice Always refuses. See FoodHook__AdminCantBeRemoved.
    function renounceOwnership() public pure override {
        revert FoodHook__AdminCantBeRemoved();
    }

    // ---------------------------------------------------------------- hooks we use

    /// @notice Allows only our FOOD/USDC pool, only once, only from the admin key, and only at a starting price
    ///         between the floor and the ceiling.
    function beforeInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96)
        external
        onlyPoolManager
        returns (bytes4)
    {
        if (sender != owner()) revert FoodHook__NotAdmin(sender);
        if (PoolId.unwrap(_poolId) != bytes32(0)) revert FoodHook__PoolExists();
        (Currency token0, Currency token1) = FOOD_IS_TOKEN0 ? (FOOD, USDC) : (USDC, FOOD);
        if (!(key.currency0 == token0 && key.currency1 == token1)) {
            revert FoodHook__WrongTokens(Currency.unwrap(key.currency0), Currency.unwrap(key.currency1));
        }
        if (sqrtPriceX96 < MIN_SQRT_PRICE || sqrtPriceX96 > MAX_SQRT_PRICE) {
            revert FoodHook__StartOutsideBounds(usdcPerFood(sqrtPriceX96), FLOOR_USDC_PER_FOOD, CEILING_USDC_PER_FOOD);
        }
        _poolId = key.toId();
        return IHooks.beforeInitialize.selector;
    }

    /// @notice Allows new stock only through FoodRouter, so nobody else can change how fast prices move.
    function beforeAddLiquidity(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external view onlyPoolManager returns (bytes4) {
        if (sender != router) revert FoodHook__NotRouter(sender);
        return IHooks.beforeAddLiquidity.selector;
    }

    /// @notice Allows only FoodRouter. On the day's first trade, notes the opening price.
    function beforeSwap(address sender, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata)
        external
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (sender != router) revert FoodHook__NotRouter(sender);
        uint256 day = today();
        if (_days[day].openSqrtPriceX96 == 0) {
            uint160 open = _livePrice();
            _days[day].openSqrtPriceX96 = open;
            emit DayOpened(day, usdcPerFood(open));
        }
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /// @notice Refuses a trade that leaves the price outside today's limit (`bandBps` either way from the opening
    ///         price, and inside the floor and ceiling). Adds the trade to today's totals.
    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta delta,
        bytes calldata
    ) external onlyPoolManager returns (bytes4, int128) {
        uint256 day = today();
        Day storage record = _days[day];
        uint160 price = _livePrice();
        (uint160 low, uint160 high) = _band(record.openSqrtPriceX96);
        if (price < low || price > high) {
            (uint256 lowUsdc, uint256 highUsdc) = _usdcRange(low, high);
            revert FoodHook__OutsideBand(usdcPerFood(price), lowUsdc, highUsdc);
        }

        (uint256 usdcMoved, uint256 foodMoved) = _amounts(key, delta);
        record.usdcTotal += SafeCast.toUint128(usdcMoved);
        record.foodTotal += SafeCast.toUint128(foodMoved);
        emit TradeCounted(day, usdcMoved, foodMoved, usdcPerFood(price));
        return (IHooks.afterSwap.selector, 0);
    }

    // ---------------------------------------------------------------- hooks we don't use

    /// @dev Switched off by this hook's address; refuses if called anyway. Same for the five below.
    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure returns (bytes4) {
        revert FoodHook__HookNotUsed();
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        revert FoodHook__HookNotUsed();
    }

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        revert FoodHook__HookNotUsed();
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        revert FoodHook__HookNotUsed();
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        revert FoodHook__HookNotUsed();
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        revert FoodHook__HookNotUsed();
    }

    // ---------------------------------------------------------------- reads (never blocked)

    /// @notice Today's day number, counted from the block clock since deploy.
    function today() public view returns (uint256) {
        return (block.timestamp - FIRST_DAY_START) / DAY_LENGTH_SECONDS;
    }

    /// @notice Today's lowest and highest allowed sqrt price, and the live one, in the pool's token order.
    ///         FoodRouter uses low and high as the price limit for its trades. Before today's first trade, the
    ///         live price is what the day will open at.
    function band() external view returns (uint160 low, uint160 high, uint160 live) {
        live = _livePrice();
        uint160 open = _days[today()].openSqrtPriceX96;
        (low, high) = _band(open == 0 ? live : open);
    }

    /// @notice Today's lowest and highest allowed price and the live price, in USDC base units per FOOD. The high
    ///         end is what MealCounter's ration shop charges when the pool can't fill a meal.
    function priceBand()
        external
        view
        returns (uint256 lowUsdcPerFood, uint256 highUsdcPerFood, uint256 liveUsdcPerFood)
    {
        uint160 live = _livePrice();
        uint160 open = _days[today()].openSqrtPriceX96;
        (uint160 low, uint160 high) = _band(open == 0 ? live : open);
        (lowUsdcPerFood, highUsdcPerFood) = _usdcRange(low, high);
        liveUsdcPerFood = usdcPerFood(live);
    }

    /// @notice The highest price ever allowed, in USDC base units per FOOD. CampaignEscrow prices the 25% rule on it.
    function ceilingPrice() external view returns (uint256) {
        return CEILING_USDC_PER_FOOD;
    }

    /// @notice That day's price in USDC per FOOD: total USDC ÷ total FOOD, rounded down. Zero if nothing traded.
    function dayPrice(uint256 day) external view returns (uint256) {
        Day storage record = _days[day];
        if (record.foodTotal == 0) return 0;
        return FullMath.mulDiv(record.usdcTotal, FOOD_UNIT, record.foodTotal);
    }

    /// @notice That day's opening price (USDC per FOOD), USDC total and FOOD total, so anyone can check dayPrice.
    function dayTotals(uint256 day) external view returns (uint256 openPrice, uint256 usdcTotal, uint256 foodTotal) {
        Day storage record = _days[day];
        openPrice = record.openSqrtPriceX96 == 0 ? 0 : usdcPerFood(record.openSqrtPriceX96);
        return (openPrice, record.usdcTotal, record.foodTotal);
    }

    /// @notice Everything fixed at deploy, in one read.
    function settings()
        external
        view
        returns (
            address usdc,
            address food,
            uint256 floorUsdcPerFood,
            uint256 ceilingUsdcPerFood,
            uint256 bandBps,
            uint256 dayLengthSeconds,
            uint256 firstDayStart,
            bytes32 poolId
        )
    {
        return (
            Currency.unwrap(USDC),
            Currency.unwrap(FOOD),
            FLOOR_USDC_PER_FOOD,
            CEILING_USDC_PER_FOOD,
            BAND_BPS,
            DAY_LENGTH_SECONDS,
            FIRST_DAY_START,
            PoolId.unwrap(_poolId)
        );
    }

    /// @notice Turns one of Uniswap's sqrt prices for our pool into USDC base units per FOOD, rounded down.
    function usdcPerFood(uint160 sqrtPriceX96) public view returns (uint256) {
        // Uniswap's price is token1 per token0 = sqrtPrice^2 / 2^192.
        return FOOD_IS_TOKEN0
            ? FullMath.mulDiv(sqrtPriceX96, uint256(sqrtPriceX96) * FOOD_UNIT, 1 << 192)  // USDC per FOOD
            : FullMath.mulDiv(FullMath.mulDiv(FOOD_UNIT, 1 << 192, sqrtPriceX96), 1, sqrtPriceX96); // inverse
    }

    /// @notice The four hook functions this contract uses. Uniswap reads the same list from its address.
    function getHookPermissions() external pure returns (Hooks.Permissions memory) {
        return _permissions();
    }

    // ---------------------------------------------------------------- internals

    function _permissions() private pure returns (Hooks.Permissions memory p) {
        p.beforeInitialize = true;
        p.beforeAddLiquidity = true;
        p.beforeSwap = true;
        p.afterSwap = true;
    }

    function _livePrice() private view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96,,,) = poolManager.getSlot0(_poolId);
    }

    /// @dev Today's allowed sqrt-price range around `open`, cut to the floor and ceiling. Rounded inward.
    function _band(uint160 open) private view returns (uint160 low, uint160 high) {
        (uint256 lowFactor, uint256 highFactor) = FOOD_IS_TOKEN0
            ? (SQRT_DOWN, SQRT_UP)  // FOOD first: price follows sqrt price
            : (INV_SQRT_UP, INV_SQRT_DOWN); // FOOD second: price moves against sqrt price
        uint256 lowWide = FullMath.mulDivRoundingUp(open, lowFactor, ONE);
        uint256 highWide = FullMath.mulDiv(open, highFactor, ONE);
        // Clamp first, so both values fit in uint160 before they are narrowed.
        low = lowWide < MIN_SQRT_PRICE ? MIN_SQRT_PRICE : SafeCast.toUint160(lowWide);
        high = highWide > MAX_SQRT_PRICE ? MAX_SQRT_PRICE : SafeCast.toUint160(highWide);
    }

    /// @dev A sqrt-price range as (cheapest, dearest) in USDC per FOOD, whatever the token order.
    function _usdcRange(uint160 low, uint160 high) private view returns (uint256, uint256) {
        (uint256 a, uint256 b) = (usdcPerFood(low), usdcPerFood(high));
        return a < b ? (a, b) : (b, a);
    }

    /// @dev How much USDC and FOOD changed hands in a swap, as positive base units.
    function _amounts(PoolKey calldata key, BalanceDelta delta) private view returns (uint256 usdc, uint256 food) {
        uint256 amount0 = _abs(delta.amount0());
        uint256 amount1 = _abs(delta.amount1());
        return key.currency0 == USDC ? (amount0, amount1) : (amount1, amount0);
    }

    function _abs(int128 x) private pure returns (uint256) {
        int256 wide = x; // widening int128 -> int256 is always safe, and so is negating it
        return SafeCast.toUint256(wide < 0 ? -wide : wide);
    }

    /// @dev USDC per FOOD -> sqrtPriceX96 in the pool's token order.
    ///      Both tokens have 6 decimals, so one base unit of FOOD costs (price / 1e6) base units of USDC.
    ///      Rounds inward, so the floor and ceiling are never crossed by rounding: the floor's sqrt price lands
    ///      on the dearer side of the true value, and the ceiling's on the cheaper side.
    function _sqrtPriceOf(uint256 price, bool foodIsToken0, bool isFloor) private pure returns (uint160) {
        // With FOOD first, a higher sqrt price means dearer FOOD; with FOOD second, cheaper.
        Math.Rounding rounding = (isFloor == foodIsToken0) ? Math.Rounding.Ceil : Math.Rounding.Floor;
        uint256 priceX192 = foodIsToken0
            ? Math.mulDiv(price, 1 << 192, FOOD_UNIT, rounding)  // USDC per FOOD
            : Math.mulDiv(FOOD_UNIT, 1 << 192, price, rounding); // FOOD per USDC
        return SafeCast.toUint160(Math.sqrt(priceX192, rounding));
    }
}
