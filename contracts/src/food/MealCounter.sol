// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {FoodHook} from "./FoodHook.sol";
import {FoodRouter} from "./FoodRouter.sol";
import {FoodToken} from "./FoodToken.sol";
import {IMealCounter} from "../money/Links.sol";
import {MealTicket, Vouchers} from "../money/Vouchers.sol";

/// @title MealCounter
/// @notice The only way a player buys food. The player's wallet sends a server-signed MealTicket and USDC; the counter
///         buys the meal's FOOD through FoodRouter (which burns it), and if the pool can't fill it today (the price is
///         at the top of today's band) the rest comes from the ration reserve at the band-high price, also burned.
///         Players never hold FOOD: they get energy in the game when the server sees MealEaten.
/// @dev Holds FoodRouter's Buyer role and the ration reserve (its whole FOOD balance). Holds no USDC between calls:
///      ration revenue goes straight to Treasury and unused USDC straight back to the payer.
///      Spec: docs/architecture/spec.json, contract "MealCounter".
contract MealCounter is IMealCounter, EIP712, Ownable2Step, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    /// @notice FOOD has 6 decimals: prices are USDC base units per 1,000,000 FOOD base units.
    uint256 private constant FOOD_UNIT = 1e6;

    IERC20 private immutable USDC;
    FoodToken private immutable FOOD;
    FoodHook private immutable HOOK;
    /// @notice Where ration-shop revenue goes.
    address public immutable treasury;

    /// @notice FoodRouter (replaceable: the admin points the counter at a fixed router).
    FoodRouter public router;
    /// @notice The server key whose EIP-712 signature makes a MealTicket valid.
    address public ticketSigner;
    /// @notice The only caller allowed into buyMealFor (rescue meals and meal vouchers).
    address public housePool;

    mapping(bytes32 ref => bool) private _refUsed;

    /// @notice A meal was bought and its FOOD burned. usdcPaid is the total (pool + ration); fromRation is the part of
    ///         foodBurned that came from the ration reserve. The server credits the player's energy from foodBurned.
    event MealEaten(
        address indexed player,
        bytes32 indexed ref,
        bytes32 item,
        uint256 usdcPaid,
        uint256 foodBurned,
        uint256 fromRation
    );
    /// @notice FOOD was added to the ration reserve.
    event RationRestocked(address indexed from, uint256 food);
    event TicketSignerSet(address indexed oldSigner, address indexed newSigner);
    event HousePoolSet(address indexed oldPool, address indexed newPool);
    event RouterSet(address indexed oldRouter, address indexed newRouter);

    /// @notice A ticket can only be used by the player it names.
    error MealCounter__NotPlayer(address sender, address player);
    /// @notice Only HousePool may buy a meal on a player's behalf.
    error MealCounter__NotHousePool(address sender);
    /// @notice This ref was already used: the retry was blocked.
    error MealCounter__RefUsed(bytes32 ref);
    /// @notice The ticket's expiry (unix seconds) has passed.
    error MealCounter__Expired(uint64 expiry, uint256 nowSeconds);
    /// @notice The ticket wasn't signed by the ticket signer.
    error MealCounter__BadSignature(address recovered, address expected);
    /// @notice A meal must contain some FOOD.
    error MealCounter__ZeroFood();
    /// @notice The meal would cost more than maxUsdc (USDC base units). Nothing moved.
    error MealCounter__TooDear(uint256 cost, uint256 maxUsdc);
    /// @notice The pool couldn't fill the meal and the ration reserve is too small (FOOD base units).
    error MealCounter__RationEmpty(uint256 needed, uint256 reserve);
    /// @notice An address that must be set was zero.
    error MealCounter__ZeroAddress();
    /// @notice The admin role can be handed over, but never thrown away.
    error MealCounter__AdminCantBeRemoved();

    /// @param router_ FoodRouter; the admin must give this counter the Buyer role there.
    /// @param treasury_ Treasury, which receives ration revenue.
    /// @param ticketSigner_ The server key that signs MealTickets.
    /// @param admin The admin key.
    constructor(FoodRouter router_, FoodHook hook, address treasury_, address ticketSigner_, address admin)
        EIP712(Vouchers.DOMAIN_NAME, Vouchers.DOMAIN_VERSION)
        Ownable(admin)
    {
        if (address(router_) == address(0) || treasury_ == address(0) || ticketSigner_ == address(0)) {
            revert MealCounter__ZeroAddress();
        }
        // forge-lint: disable-next-line(unused-return) only the two token addresses are needed here
        (address usdc, address foodToken,,,,,,) = hook.settings();
        USDC = IERC20(usdc);
        FOOD = FoodToken(foodToken);
        HOOK = hook;
        treasury = treasury_;
        router = router_;
        ticketSigner = ticketSigner_;
        emit RouterSet(address(0), address(router_));
        emit TicketSignerSet(address(0), ticketSigner_);
    }

    // ---------------------------------------------------------------- buying

    /// @notice The player buys one meal with a server-signed ticket. Pulls `t.maxUsdc` USDC from the player (who must
    ///         have approved this contract), buys what the pool can fill, takes the rest from the ration reserve at the
    ///         band-high price, sends ration revenue to Treasury and refunds the unused USDC.
    /// @return usdcPaid What the meal cost in total, USDC base units.
    /// @return fromRation How much of the meal's FOOD came from the ration reserve.
    function buyMeal(MealTicket calldata t, bytes calldata sig)
        external
        nonReentrant
        returns (uint256 usdcPaid, uint256 fromRation)
    {
        if (msg.sender != t.player) revert MealCounter__NotPlayer(msg.sender, t.player);
        // forge-lint: disable-next-line(block-timestamp) a ticket lives for minutes; seconds of drift don't matter
        if (block.timestamp > t.expiry) revert MealCounter__Expired(t.expiry, block.timestamp);
        (address recovered,,) = ECDSA.tryRecover(_hashTypedDataV4(Vouchers.hash(t)), sig);
        if (recovered != ticketSigner || recovered == address(0)) {
            revert MealCounter__BadSignature(recovered, ticketSigner);
        }
        return _serve(msg.sender, t.player, t.item, t.food, t.maxUsdc, t.ref);
    }

    /// @notice HousePool buys a meal for a player (a rescue meal or a meal voucher), paid from the pool. Same rules as
    ///         buyMeal; the pool is the payer and gets the unused USDC back, the player gets the energy.
    function buyMealFor(address player, bytes32 item, uint256 food, uint256 maxUsdc, bytes32 ref)
        external
        nonReentrant
        returns (uint256 usdcPaid, uint256 fromRation)
    {
        if (msg.sender != housePool || msg.sender == address(0)) {
            revert MealCounter__NotHousePool(msg.sender);
        }
        return _serve(msg.sender, player, item, food, maxUsdc, ref);
    }

    // ---------------------------------------------------------------- admin

    /// @notice Adds FOOD to the ration reserve, pulled from the caller (the admin holds FOOD's fixed supply).
    function restockRation(uint256 food) external onlyOwner {
        if (food == 0) revert MealCounter__ZeroFood();
        IERC20(address(FOOD)).safeTransferFrom(msg.sender, address(this), food);
        emit RationRestocked(msg.sender, food);
    }

    /// @notice Replaces the server key that signs MealTickets (e.g. after a leak). Old tickets stop working.
    function setTicketSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert MealCounter__ZeroAddress();
        address old = ticketSigner;
        ticketSigner = newSigner;
        emit TicketSignerSet(old, newSigner);
    }

    /// @notice Sets HousePool, the only caller of buyMealFor. Zero switches buyMealFor off.
    // forge-lint: disable-next-line(missing-zero-check)
    function setHousePool(address newPool) external onlyOwner {
        address old = housePool;
        housePool = newPool; // zero on purpose means "no meals on anyone's behalf"
        emit HousePoolSet(old, newPool);
    }

    /// @notice Points the counter at a replacement FoodRouter (which must give it the Buyer role).
    function setRouter(FoodRouter newRouter) external onlyOwner {
        if (address(newRouter) == address(0)) revert MealCounter__ZeroAddress();
        address old = address(router);
        router = newRouter;
        emit RouterSet(old, address(newRouter));
    }

    /// @notice Always refuses. Without an admin, a leaked ticket signer could never be replaced.
    function renounceOwnership() public pure override {
        revert MealCounter__AdminCantBeRemoved();
    }

    // ---------------------------------------------------------------- reads

    /// @notice FOOD in the ration reserve (base units).
    function rationReserve() external view returns (uint256) {
        return FOOD.balanceOf(address(this));
    }

    /// @notice Whether a meal ref has been used.
    function refUsed(bytes32 ref) external view returns (bool) {
        return _refUsed[ref];
    }

    // ---------------------------------------------------------------- internals

    function _serve(address payer, address player, bytes32 item, uint256 food, uint256 maxUsdc, bytes32 ref)
        private
        returns (uint256 usdcPaid, uint256 fromRation)
    {
        // Check.
        if (food == 0) revert MealCounter__ZeroFood();
        if (_refUsed[ref]) revert MealCounter__RefUsed(ref);
        // Change.
        _refUsed[ref] = true;

        // Take the most the payer allowed, buy what the pool can fill, burned by the router.
        USDC.safeTransferFrom(payer, address(this), maxUsdc);
        FoodRouter currentRouter = router;
        USDC.forceApprove(address(currentRouter), maxUsdc);
        uint256 bought = 0;
        uint256 poolUsdc = 0;
        try currentRouter.buyFood(food, maxUsdc, ref) returns (uint256 b, uint256 p) {
            (bought, poolUsdc) = (b, p);
        } catch (bytes memory reason) {
            // forge-lint: disable-next-line(unsafe-typecast) reading the 4-byte selector off the revert data
            if (bytes4(reason) == FoodRouter.FoodRouter__TooDear.selector) {
                uint256 needed;
                assembly ("memory-safe") {
                    needed := mload(add(reason, 36)) // after the length word and the 4-byte selector
                }
                revert MealCounter__TooDear(needed, maxUsdc);
            }
            assembly ("memory-safe") {
                revert(add(reason, 32), mload(reason))
            }
        }
        USDC.forceApprove(address(currentRouter), 0);

        // The shortfall comes from the ration reserve at today's band-high price, and is burned too.
        fromRation = food - bought;
        uint256 rationUsdc = 0;
        if (fromRation != 0) {
            uint256 reserve = FOOD.balanceOf(address(this));
            if (reserve < fromRation) revert MealCounter__RationEmpty(fromRation, reserve);
            // forge-lint: disable-next-line(unused-return) only today's high end is needed
            (, uint256 highUsdcPerFood,) = HOOK.priceBand();
            rationUsdc = Math.mulDiv(fromRation, highUsdcPerFood, FOOD_UNIT, Math.Rounding.Ceil);
        }
        usdcPaid = poolUsdc + rationUsdc;
        if (usdcPaid > maxUsdc) revert MealCounter__TooDear(usdcPaid, maxUsdc);
        if (fromRation != 0) FOOD.burn(fromRation);

        // Pay.
        if (rationUsdc != 0) USDC.safeTransfer(treasury, rationUsdc);
        if (maxUsdc > usdcPaid) USDC.safeTransfer(payer, maxUsdc - usdcPaid);
        // forge-lint: disable-next-line(reentrancy-events) nonReentrant guards the whole meal
        emit MealEaten(player, ref, item, usdcPaid, food, fromRation);
    }
}
