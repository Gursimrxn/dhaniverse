// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TestKit} from "./TestKit.sol";
import {FoodToken} from "../../src/food/FoodToken.sol";
import {FoodHook} from "../../src/food/FoodHook.sol";
import {FoodRouter} from "../../src/food/FoodRouter.sol";
import {MealCounter} from "../../src/food/MealCounter.sol";
import {Farm} from "../../src/food/Farm.sol";
import {Treasury} from "../../src/money/Treasury.sol";
import {HousePool} from "../../src/money/HousePool.sol";
import {CampaignEscrow, CampaignParams} from "../../src/money/CampaignEscrow.sol";
import {FloatManager} from "../../src/money/FloatManager.sol";
import {IHousePool, IFloatManager} from "../../src/money/Links.sol";
import {MealTicket, PayoutVoucher, CampaignClaim, AdvanceVoucher} from "../../src/money/Vouchers.sol";
import {MockYieldVault} from "../../src/mocks/MockYieldVault.sol";
import {SpiceMerchant} from "../../src/quests/SpiceMerchant.sol";
import {QuestToken} from "../../src/quests/QuestToken.sol";
import {LuckyLedger} from "../../src/quests/LuckyLedger.sol";

/// @notice The whole of Tallyport on a local chain: the food market, the money contracts and the quest contracts,
///         wired exactly like script/Deploy.s.sol wires them, with launch numbers. Signing helpers make the server's
///         EIP-712 tickets and vouchers.
abstract contract TownWorld is TestKit {
    // Launch numbers (build spec 2.1-2.7).
    uint256 internal constant FLOOR = 2000;
    uint256 internal constant CEILING = 8000;
    uint256 internal constant BASE_PRICE = 4000;
    uint256 internal constant BAND_BPS = 1500;
    uint256 internal constant DAY = 1 hours;
    int24 internal constant TICK_SPACING = 60;
    uint256 internal constant FOOD_SUPPLY = 100_000_000 * ONE_FOOD;
    /// @dev About 100,000 FOOD and 400 USDC, full range, at $0.004 per FOOD.
    uint128 internal constant POOL_LIQUIDITY = 6_324_555_320;
    uint256 internal constant BUDGET_BPS = 400;
    uint256 internal constant PER_HUMAN_DAILY_CAP = 5_000_000; // $5
    uint256 internal constant FEE_BPS = 1000;
    uint256 internal constant MIN_PAYOUT = 150_000; // $0.15
    uint256 internal constant MAX_ADVANCE = 1_000_000; // $1
    uint256 internal constant VAULT_APR_BPS = 400;
    uint256 internal constant REVEAL_DELAY_BLOCKS = 5;
    uint256 internal constant RATION_STOCK = 10_000 * ONE_FOOD;
    uint256 internal constant FARM_STOCK = 1_000_000 * ONE_FOOD;
    uint160 internal constant HOOK_FLAGS =
        Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG;

    bytes32 internal constant THALI = keccak256("thali");
    bytes32 internal constant CHAI = keccak256("chai");
    bytes32 internal constant SPICE_RUN = keccak256("spice_run");
    bytes32 internal constant SAM_HUMAN = keccak256("sam's World ID nullifier");
    bytes32 internal constant PRIYA_HUMAN = keccak256("priya's World ID nullifier");

    address internal ticketSigner;
    uint256 internal ticketSignerKey;
    address internal voucherSigner;
    uint256 internal voucherSignerKey;

    PoolManager internal manager;
    FoodToken internal foodToken;
    FoodHook internal hook;
    FoodRouter internal router;
    HousePool internal housePool;
    Treasury internal treasury;
    MealCounter internal mealCounter;
    Farm internal farm;
    FloatManager internal floatManager;
    CampaignEscrow internal escrow;
    MockYieldVault internal vault;
    SpiceMerchant internal spice;
    QuestToken internal mango;
    LuckyLedger internal lucky;

    uint256 private _refCount;

    function setUp() public virtual override {
        super.setUp();
        (ticketSigner, ticketSignerKey) = makeAddrAndKey("ticket signer");
        (voucherSigner, voucherSignerKey) = makeAddrAndKey("voucher signer");
        vm.warp(1_762_400_000); // 6 Nov 2025-ish: a real clock, mid UTC day

        manager = deployPoolManager();
        foodToken = new FoodToken(admin, FOOD_SUPPLY);
        address hookAt = address(HOOK_FLAGS | (uint160(0x7777) << 144));
        deployCodeTo(
            "FoodHook.sol:FoodHook",
            abi.encode(
                manager,
                admin,
                address(0),
                Currency.wrap(address(usdc)),
                Currency.wrap(address(foodToken)),
                FLOOR,
                CEILING,
                BAND_BPS,
                DAY
            ),
            hookAt
        );
        hook = FoodHook(hookAt);
        router = new FoodRouter(manager, hook, admin, TICK_SPACING);

        housePool = new HousePool(usdc, voucherSigner, BUDGET_BPS, PER_HUMAN_DAILY_CAP, admin);
        treasury = new Treasury(usdc, IHousePool(address(housePool)), ops, team, 6000, 1000, 2000, 1000, admin);
        mealCounter = new MealCounter(router, hook, address(treasury), ticketSigner, admin);
        farm = new Farm(router, usdc, foodToken, address(treasury), keeper, admin);
        floatManager = new FloatManager(usdc, IHousePool(address(housePool)), keeper, admin);
        escrow = new CampaignEscrow(
            usdc,
            hook,
            IHousePool(address(housePool)),
            IFloatManager(address(floatManager)),
            team,
            voucherSigner,
            FEE_BPS,
            MIN_PAYOUT,
            MAX_ADVANCE,
            admin
        );
        vault = new MockYieldVault(usdc, VAULT_APR_BPS, admin);
        spice = new SpiceMerchant(escrow);
        mango = new QuestToken("Mango", "MANGO", admin);
        lucky = new LuckyLedger(IHousePool(address(housePool)), keeper, REVEAL_DELAY_BLOCKS, admin);

        usdc.mint(admin, dollars(10_000));
        vm.startPrank(admin);
        hook.setRouter(address(router));
        // FOOD moves only between the game's own contracts, set once and locked, as script/Deploy.s.sol does.
        foodToken.setAllowed(address(manager), true);
        foodToken.setAllowed(address(router), true);
        foodToken.setAllowed(address(mealCounter), true);
        foodToken.setAllowed(address(farm), true);
        foodToken.lockAllowlist();
        manager.initialize(router.poolKey(), _sqrtFor(BASE_PRICE));
        usdc.approve(address(router), type(uint256).max);
        foodToken.approve(address(router), type(uint256).max);
        router.addLiquidity(POOL_LIQUIDITY);
        router.setRole(address(mealCounter), FoodRouter.Role.Buyer);
        router.setRole(address(farm), FoodRouter.Role.Seller);
        housePool.setMealCounter(address(mealCounter));
        housePool.setLuckyLedger(address(lucky));
        mealCounter.setHousePool(address(housePool));
        foodToken.approve(address(mealCounter), RATION_STOCK);
        mealCounter.restockRation(RATION_STOCK);
        foodToken.approve(address(farm), FARM_STOCK);
        farm.restock(FARM_STOCK);
        floatManager.setEscrow(escrow);
        floatManager.setVenue(0, vault);
        vm.stopPrank();

        vm.label(address(hook), "FoodHook");
        vm.label(address(router), "FoodRouter");
        vm.label(address(foodToken), "FOOD");
        vm.label(address(housePool), "HousePool");
        vm.label(address(treasury), "Treasury");
        vm.label(address(mealCounter), "MealCounter");
        vm.label(address(farm), "Farm");
        vm.label(address(floatManager), "FloatManager");
        vm.label(address(escrow), "CampaignEscrow");
        vm.label(address(vault), "MockYieldVault");
        vm.label(address(spice), "SpiceMerchant");
        vm.label(address(mango), "MANGO");
        vm.label(address(lucky), "LuckyLedger");
    }

    // ---------------------------------------------------------------- refs and prices

    function _ref() internal returns (bytes32) {
        return keccak256(abi.encode("test ref", ++_refCount));
    }

    function _sqrtFor(uint256 price) internal view returns (uint160) {
        bool foodFirst = address(foodToken) < address(usdc);
        uint256 x192 = foodFirst ? Math.mulDiv(price, 1 << 192, ONE_FOOD) : Math.mulDiv(ONE_FOOD, 1 << 192, price);
        return uint160(Math.sqrt(x192));
    }

    function _livePrice() internal view returns (uint256 live) {
        (,, live) = hook.priceBand();
    }

    // ---------------------------------------------------------------- signing (the server's keys)

    function _digest(address verifying, bytes32 structHash) internal view returns (bytes32) {
        bytes32 domain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("Tallyport"),
                keccak256("1"),
                block.chainid,
                verifying
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domain, structHash));
    }

    function _sign(uint256 key, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _ticket(address player, bytes32 item, uint256 foodAmount, uint256 maxUsdc)
        internal
        returns (MealTicket memory t, bytes memory sig)
    {
        t = MealTicket(player, item, foodAmount, maxUsdc, _ref(), uint64(block.timestamp + 10 minutes));
        sig = _signTicket(t, ticketSignerKey);
    }

    function _signTicket(MealTicket memory t, uint256 key) internal view returns (bytes memory) {
        bytes32 h = keccak256(
            abi.encode(
                keccak256(
                    "MealTicket(address player,bytes32 item,uint256 food,uint256 maxUsdc,bytes32 ref,uint64 expiry)"
                ),
                t.player,
                t.item,
                t.food,
                t.maxUsdc,
                t.ref,
                t.expiry
            )
        );
        return _sign(key, _digest(address(mealCounter), h));
    }

    function _payout(address player, bytes32 humanId, uint8 source, uint256 amount)
        internal
        returns (PayoutVoucher memory v, bytes memory sig)
    {
        v = PayoutVoucher(player, humanId, source, amount, _ref(), uint64(block.timestamp + 10 minutes));
        sig = _signPayout(v, voucherSignerKey);
    }

    function _signPayout(PayoutVoucher memory v, uint256 key) internal view returns (bytes memory) {
        bytes32 h = keccak256(
            abi.encode(
                keccak256(
                    "PayoutVoucher(address player,bytes32 humanId,uint8 source,uint256 amount,bytes32 ref,uint64 expiry)"
                ),
                v.player,
                v.humanId,
                v.source,
                v.amount,
                v.ref,
                v.expiry
            )
        );
        return _sign(key, _digest(address(housePool), h));
    }

    function _claim(uint256 id, address player, bytes32 humanId, uint256 amount)
        internal
        returns (CampaignClaim memory c, bytes memory sig)
    {
        c = CampaignClaim(id, player, humanId, amount, _ref(), uint64(block.timestamp + 10 minutes));
        sig = _signClaim(c, voucherSignerKey);
    }

    function _signClaim(CampaignClaim memory c, uint256 key) internal view returns (bytes memory) {
        bytes32 h = keccak256(
            abi.encode(
                keccak256(
                    "CampaignClaim(uint256 campaignId,address player,bytes32 humanId,uint256 amount,bytes32 ref,uint64 expiry)"
                ),
                c.campaignId,
                c.player,
                c.humanId,
                c.amount,
                c.ref,
                c.expiry
            )
        );
        return _sign(key, _digest(address(escrow), h));
    }

    function _advance(uint256 id, address player, bytes32 humanId, uint256 amount)
        internal
        returns (AdvanceVoucher memory a, bytes memory sig)
    {
        a = AdvanceVoucher(id, player, humanId, amount, _ref(), uint64(block.timestamp + 10 minutes));
        sig = _signAdvance(a, voucherSignerKey);
    }

    function _signAdvance(AdvanceVoucher memory a, uint256 key) internal view returns (bytes memory) {
        bytes32 h = keccak256(
            abi.encode(
                keccak256(
                    "AdvanceVoucher(uint256 campaignId,address player,bytes32 humanId,uint256 amount,bytes32 ref,uint64 expiry)"
                ),
                a.campaignId,
                a.player,
                a.humanId,
                a.amount,
                a.ref,
                a.expiry
            )
        );
        return _sign(key, _digest(address(escrow), h));
    }

    // ---------------------------------------------------------------- common setups

    /// @dev The demo "Tallyport Launch" Spice Run: $100 budget, $1 a claim, 30 energy, 7 days.
    function _spiceRunParams() internal view returns (CampaignParams memory p) {
        p = CampaignParams({
            template: SPICE_RUN,
            metaHash: keccak256("swarm: tallyport launch story"),
            budget: dollars(100),
            payoutPerClaim: dollars(1),
            energyCost: 30,
            maxClaims: 80,
            perHumanCap: 1,
            start: uint64(block.timestamp),
            end: uint64(block.timestamp + 7 days),
            kind: 0,
            deliverTo: sponsor,
            questToken: address(mango)
        });
    }

    function _createCampaign(CampaignParams memory p) internal returns (uint256 id) {
        usdc.mint(sponsor, p.budget);
        vm.startPrank(sponsor);
        usdc.approve(address(escrow), p.budget);
        id = escrow.createCampaign(p);
        vm.stopPrank();
    }

    /// @dev Funds a HousePool bucket from a fresh donor.
    function _fundBucket(uint8 bucket, uint256 amount) internal {
        address donor = makeAddr("donor");
        usdc.mint(donor, amount);
        vm.startPrank(donor);
        usdc.approve(address(housePool), amount);
        housePool.fund(bucket, amount);
        vm.stopPrank();
    }

    function _giveUsdc(address who, uint256 amount, address spender) internal {
        usdc.mint(who, amount);
        vm.prank(who);
        usdc.approve(spender, type(uint256).max);
    }
}
