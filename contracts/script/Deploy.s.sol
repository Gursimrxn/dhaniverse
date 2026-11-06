// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {FoodToken} from "../src/food/FoodToken.sol";
import {FoodHook} from "../src/food/FoodHook.sol";
import {FoodRouter} from "../src/food/FoodRouter.sol";
import {MealCounter} from "../src/food/MealCounter.sol";
import {Farm} from "../src/food/Farm.sol";
import {Treasury} from "../src/money/Treasury.sol";
import {HousePool} from "../src/money/HousePool.sol";
import {CampaignEscrow, CampaignParams} from "../src/money/CampaignEscrow.sol";
import {FloatManager} from "../src/money/FloatManager.sol";
import {IHousePool, IFloatManager} from "../src/money/Links.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockYieldVault} from "../src/mocks/MockYieldVault.sol";
import {SpiceMerchant} from "../src/quests/SpiceMerchant.sol";
import {QuestToken} from "../src/quests/QuestToken.sol";
import {LuckyLedger} from "../src/quests/LuckyLedger.sol";
import {IPermit2, IPositionManager} from "../src/uniswap/UniswapPeriphery.sol";
import {NameKit} from "../src/names/NameKit.sol";
import {QuestPool} from "./uniswap/QuestPool.sol";
import {CityNames, Ens, City} from "./names/CityNames.sol";

/// @notice Deploys all of Tallyport in dependency order, wires every role, seeds the FOOD/USDC pool through FoodRouter
///         and the plain MANGO/USDC v4 pool through Uniswap's PositionManager, stocks the ration reserve and the farm,
///         seeds the house buckets and the mock vault's drip, creates the demo "Tallyport Launch" Spice Run, and
///         writes deployments/<network>.json for the server.
///
///   anvil:   script/dev_chain.sh   (starts anvil, places Uniswap, runs this)
///   sepolia: forge script script/Deploy.s.sol --rpc-url sepolia --broadcast
///
/// Settings come from deployments/<network>.config.json; keys from the environment only: DEPLOYER_KEY (private key),
/// KEEPER_ADDRESS, TICKET_SIGNER_ADDRESS, VOUCHER_SIGNER_ADDRESS, OPS_ADDRESS, TEAM_ADDRESS. The deployer is the admin
/// of every contract (hand it to a multisig with transferOwnership + acceptOwnership afterwards).
contract Deploy is Script, QuestPool, CityNames {
    using PoolIdLibrary for PoolKey;

    /// @dev Foundry's deterministic CREATE2 deployer (present on anvil and Sepolia), used to mine FoodHook's address.
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    uint160 internal constant HOOK_FLAGS =
        Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG;
    uint160 internal constant ALL_HOOK_FLAGS_MASK = (1 << 14) - 1;
    uint256 internal constant MAX_HOOK_SALT_TRIES = 2_000_000;
    uint256 internal constant ONE_FOOD = 1e6;
    uint8 internal constant MANGO_DECIMALS = 18;
    uint256 internal constant SEPOLIA_CHAIN_ID = 11_155_111;

    struct Keys {
        uint256 deployerKey;
        address admin;
        address keeper;
        address ticketSigner;
        address voucherSigner;
        address ops;
        address team;
    }

    struct Uni {
        address poolManager;
        address positionManager;
        address universalRouter;
        address permit2;
        address stateView;
        address quoter;
    }

    struct Town {
        address usdc;
        bool usdcIsMock;
        FoodToken food;
        FoodHook hook;
        FoodRouter router;
        HousePool housePool;
        Treasury treasury;
        MealCounter mealCounter;
        Farm farm;
        FloatManager floatManager;
        CampaignEscrow escrow;
        MockYieldVault vault;
        SpiceMerchant spice;
        QuestToken mango;
        LuckyLedger lucky;
        bytes32 foodPoolId;
        PoolKey questKey;
        uint256 questPositionId;
        uint256 demoCampaignId;
        uint256 startBlock;
    }

    string internal network;
    string internal config;
    Keys internal keys;
    Uni internal uni;
    Town internal town;

    function run() external {
        _load();
        town.startBlock = block.number;
        vm.startBroadcast(keys.deployerKey);
        _deployUsdc();
        _deployFoodMarket();
        _deployMoney();
        _deployQuests();
        _wire();
        _seedQuestPool();
        _seedHouseAndVault();
        _createDemoCampaign();
        vm.stopBroadcast();
        _write();
    }

    // ---------------------------------------------------------------- steps

    function _load() internal {
        network = vm.envOr("NETWORK", block.chainid == 11_155_111 ? string("sepolia") : string("anvil"));
        config = vm.readFile(string.concat(vm.projectRoot(), "/deployments/", network, ".config.json"));
        require(vm.parseJsonUint(config, ".chainId") == block.chainid, "Deploy: config chainId != this chain");
        keys.deployerKey = vm.envUint("DEPLOYER_KEY");
        keys.admin = vm.addr(keys.deployerKey);
        keys.keeper = vm.envAddress("KEEPER_ADDRESS");
        keys.ticketSigner = vm.envAddress("TICKET_SIGNER_ADDRESS");
        keys.voucherSigner = vm.envAddress("VOUCHER_SIGNER_ADDRESS");
        keys.ops = vm.envAddress("OPS_ADDRESS");
        keys.team = vm.envAddress("TEAM_ADDRESS");
        uni.poolManager = vm.parseJsonAddress(config, ".uniswap.poolManager");
        uni.positionManager = vm.parseJsonAddress(config, ".uniswap.positionManager");
        uni.universalRouter = vm.parseJsonAddress(config, ".uniswap.universalRouter");
        uni.permit2 = vm.parseJsonAddress(config, ".uniswap.permit2");
        uni.stateView = vm.parseJsonAddress(config, ".uniswap.stateView");
        uni.quoter = vm.parseJsonAddress(config, ".uniswap.quoter");
        require(
            uni.poolManager.code.length != 0 && uni.positionManager.code.length != 0
                && uni.universalRouter.code.length != 0 && uni.permit2.code.length != 0,
            "Deploy: Uniswap v4 isn't on this chain (on anvil, run script/dev_chain.sh, which places it)"
        );
    }

    function _deployUsdc() internal {
        town.usdc = vm.parseJsonAddress(config, ".usdc");
        if (town.usdc == address(0)) {
            town.usdc = address(new MockUSDC());
            town.usdcIsMock = true;
            MockUSDC(town.usdc).mint(keys.admin, _uint(".deployerUsdc"));
        }
    }

    function _deployFoodMarket() internal {
        town.food = new FoodToken(keys.admin, _uint(".market.foodSupply"));
        bytes memory args = abi.encode(
            IPoolManager(uni.poolManager),
            keys.admin,
            address(0),
            Currency.wrap(town.usdc),
            Currency.wrap(address(town.food)),
            _uint(".market.floorUsdcPerFood"),
            _uint(".market.ceilingUsdcPerFood"),
            _uint(".market.bandBps"),
            _uint(".market.dayLengthSeconds")
        );
        bytes32 salt = _mineHookSalt(keccak256(abi.encodePacked(type(FoodHook).creationCode, args)));
        town.hook = new FoodHook{salt: salt}(
            IPoolManager(uni.poolManager),
            keys.admin,
            address(0),
            Currency.wrap(town.usdc),
            Currency.wrap(address(town.food)),
            _uint(".market.floorUsdcPerFood"),
            _uint(".market.ceilingUsdcPerFood"),
            _uint(".market.bandBps"),
            _uint(".market.dayLengthSeconds")
        );
        int24 tickSpacing = int24(int256(_uint(".market.tickSpacing")));
        town.router = new FoodRouter(IPoolManager(uni.poolManager), town.hook, keys.admin, tickSpacing);
        town.hook.setRouter(address(town.router));
        // FOOD moves only between the game's own contracts (the admin, as holder, is on the list from the start).
        // MealCounter and Farm join in _wire, which then locks the list for good.
        town.food.setAllowed(uni.poolManager, true);
        town.food.setAllowed(address(town.router), true);

        PoolKey memory key = town.router.poolKey();
        IPoolManager(uni.poolManager).initialize(key, _foodSqrtPrice(_uint(".market.baseUsdcPerFood")));
        town.foodPoolId = PoolId.unwrap(key.toId());
        uint256 poolFood = _uint(".market.poolFood");
        uint256 poolUsdc = poolFood * _uint(".market.baseUsdcPerFood") / ONE_FOOD;
        IERC20(town.usdc).approve(address(town.router), poolUsdc * 101 / 100);
        town.food.approve(address(town.router), poolFood * 101 / 100);
        town.router.addLiquidity(uint128(Math.sqrt(poolFood * poolUsdc)));
        IERC20(town.usdc).approve(address(town.router), 0);
        town.food.approve(address(town.router), 0);
    }

    function _deployMoney() internal {
        town.housePool = new HousePool(
            IERC20(town.usdc),
            keys.voucherSigner,
            _uint(".house.budgetBps"),
            _uint(".house.perHumanDailyCap"),
            keys.admin
        );
        town.treasury = new Treasury(
            IERC20(town.usdc),
            IHousePool(address(town.housePool)),
            keys.ops,
            keys.team,
            _uint(".treasury.fixedBps"),
            _uint(".treasury.safetyBps"),
            _uint(".treasury.opsBps"),
            _uint(".treasury.teamBps"),
            keys.admin
        );
        town.mealCounter =
            new MealCounter(town.router, town.hook, address(town.treasury), keys.ticketSigner, keys.admin);
        town.farm = new Farm(
            town.router, IERC20(town.usdc), IERC20(address(town.food)), address(town.treasury), keys.keeper, keys.admin
        );
        town.floatManager =
            new FloatManager(IERC20(town.usdc), IHousePool(address(town.housePool)), keys.keeper, keys.admin);
        town.escrow = new CampaignEscrow(
            IERC20(town.usdc),
            town.hook,
            IHousePool(address(town.housePool)),
            IFloatManager(address(town.floatManager)),
            keys.team,
            keys.voucherSigner,
            _uint(".escrow.feeBps"),
            _uint(".escrow.minPayout"),
            _uint(".escrow.maxAdvance"),
            keys.admin
        );
        town.vault = new MockYieldVault(IERC20(town.usdc), _uint(".vault.aprBps"), keys.admin);
    }

    function _deployQuests() internal {
        town.spice = new SpiceMerchant(town.escrow);
        town.mango = new QuestToken(
            vm.parseJsonString(config, ".mango.name"), vm.parseJsonString(config, ".mango.symbol"), keys.admin
        );
        town.lucky = new LuckyLedger(
            IHousePool(address(town.housePool)), keys.keeper, _uint(".lucky.revealDelayBlocks"), keys.admin
        );
    }

    function _wire() internal {
        town.router.setRole(address(town.mealCounter), FoodRouter.Role.Buyer);
        town.router.setRole(address(town.farm), FoodRouter.Role.Seller);
        town.housePool.setMealCounter(address(town.mealCounter));
        town.housePool.setLuckyLedger(address(town.lucky));
        town.mealCounter.setHousePool(address(town.housePool));
        town.floatManager.setEscrow(town.escrow);
        town.floatManager.setVenue(0, town.vault);

        town.food.setAllowed(address(town.mealCounter), true);
        town.food.setAllowed(address(town.farm), true);
        town.food.lockAllowlist();

        uint256 ration = _uint(".market.rationFood");
        town.food.approve(address(town.mealCounter), ration);
        town.mealCounter.restockRation(ration);
        uint256 farmFood = _uint(".market.farmFood");
        town.food.approve(address(town.farm), farmFood);
        town.farm.restock(farmFood);
    }

    function _seedQuestPool() internal {
        uint256 poolMango = _uint(".mango.poolMango");
        town.mango.mint(keys.admin, poolMango);
        town.questKey = questPoolKey(
            address(town.mango), town.usdc, uint24(_uint(".mango.fee")), int24(int256(_uint(".mango.tickSpacing")))
        );
        town.questPositionId = seedQuestPool(
            IPositionManager(uni.positionManager),
            IPermit2(uni.permit2),
            town.questKey,
            questSqrtPrice(address(town.mango), town.usdc, _uint(".mango.usdcPerMango"), MANGO_DECIMALS),
            address(town.mango),
            poolMango,
            _uint(".mango.poolUsdc"),
            keys.admin
        );
    }

    function _seedHouseAndVault() internal {
        uint256 seedTotal = _uint(".house.seedFixed") + _uint(".house.seedSurprise") + _uint(".house.seedSafety");
        IERC20(town.usdc).approve(address(town.housePool), seedTotal);
        if (_uint(".house.seedFixed") != 0) town.housePool.fund(0, _uint(".house.seedFixed"));
        if (_uint(".house.seedSurprise") != 0) town.housePool.fund(1, _uint(".house.seedSurprise"));
        if (_uint(".house.seedSafety") != 0) town.housePool.fund(2, _uint(".house.seedSafety"));
        uint256 drip = _uint(".vault.drip");
        if (drip != 0) {
            IERC20(town.usdc).approve(address(town.vault), drip);
            town.vault.fundDrip(drip);
        }
    }

    function _createDemoCampaign() internal {
        uint256 budget = _uint(".demoCampaign.budget");
        CampaignParams memory p = CampaignParams({
            template: keccak256(bytes(vm.parseJsonString(config, ".demoCampaign.template"))),
            metaHash: vm.parseJsonBytes32(config, ".demoCampaign.metaHash"),
            budget: budget,
            payoutPerClaim: _uint(".demoCampaign.payoutPerClaim"),
            energyCost: uint32(_uint(".demoCampaign.energyCost")),
            maxClaims: uint32(_uint(".demoCampaign.maxClaims")),
            perHumanCap: uint16(_uint(".demoCampaign.perHumanCap")),
            start: uint64(block.timestamp),
            end: uint64(block.timestamp + _uint(".demoCampaign.days") * 1 days),
            kind: 0,
            deliverTo: keys.team,
            questToken: address(town.mango)
        });
        IERC20(town.usdc).approve(address(town.escrow), budget);
        town.demoCampaignId = town.escrow.createCampaign(p);
    }

    // ---------------------------------------------------------------- deployments/<network>.json

    function _write() internal {
        string memory root = "tallyport.root";
        vm.serializeUint(root, "chainId", block.chainid);
        vm.serializeString(root, "network", network);
        vm.serializeAddress(root, "usdc", town.usdc);
        vm.serializeBool(root, "usdcIsMock", town.usdcIsMock);
        vm.serializeString(root, "contracts", _contractsJson());
        vm.serializeString(root, "uniswap", _uniswapJson());
        if (block.chainid == SEPOLIA_CHAIN_ID) vm.serializeString(root, "ens", _ensJson());
        vm.serializeString(root, "keys", _keysJson());
        vm.serializeUint(root, "demoCampaignId", town.demoCampaignId);
        string memory out = vm.serializeUint(root, "startBlock", town.startBlock);
        string memory path = string.concat(vm.projectRoot(), "/deployments/", network, ".json");
        vm.writeJson(out, path);
        console.log("Wrote", path);
    }

    function _contractsJson() internal returns (string memory) {
        string memory c = "tallyport.contracts";
        vm.serializeAddress(c, "FoodToken", address(town.food));
        vm.serializeAddress(c, "FoodHook", address(town.hook));
        vm.serializeAddress(c, "FoodRouter", address(town.router));
        vm.serializeAddress(c, "MealCounter", address(town.mealCounter));
        vm.serializeAddress(c, "Farm", address(town.farm));
        vm.serializeAddress(c, "Treasury", address(town.treasury));
        vm.serializeAddress(c, "HousePool", address(town.housePool));
        vm.serializeAddress(c, "CampaignEscrow", address(town.escrow));
        vm.serializeAddress(c, "FloatManager", address(town.floatManager));
        vm.serializeAddress(c, "MockYieldVault", address(town.vault));
        vm.serializeAddress(c, "SpiceMerchant", address(town.spice));
        vm.serializeAddress(c, "QuestToken", address(town.mango));
        string memory contractsJson = vm.serializeAddress(c, "LuckyLedger", address(town.lucky));
        return contractsJson;
    }

    function _uniswapJson() internal returns (string memory) {
        string memory q = "tallyport.questPool";
        vm.serializeAddress(q, "currency0", Currency.unwrap(town.questKey.currency0));
        vm.serializeAddress(q, "currency1", Currency.unwrap(town.questKey.currency1));
        vm.serializeUint(q, "fee", town.questKey.fee);
        vm.serializeInt(q, "tickSpacing", town.questKey.tickSpacing);
        vm.serializeAddress(q, "hooks", address(0));
        vm.serializeBytes32(q, "poolId", PoolId.unwrap(town.questKey.toId()));
        string memory questJson = vm.serializeUint(q, "positionId", town.questPositionId);

        string memory f = "tallyport.foodPool";
        PoolKey memory foodKey = town.router.poolKey();
        vm.serializeAddress(f, "currency0", Currency.unwrap(foodKey.currency0));
        vm.serializeAddress(f, "currency1", Currency.unwrap(foodKey.currency1));
        vm.serializeUint(f, "fee", foodKey.fee);
        vm.serializeInt(f, "tickSpacing", foodKey.tickSpacing);
        vm.serializeAddress(f, "hooks", address(town.hook));
        string memory foodJson = vm.serializeBytes32(f, "poolId", town.foodPoolId);

        string memory u = "tallyport.uniswap";
        vm.serializeAddress(u, "poolManager", uni.poolManager);
        vm.serializeAddress(u, "positionManager", uni.positionManager);
        vm.serializeAddress(u, "universalRouter", uni.universalRouter);
        vm.serializeAddress(u, "permit2", uni.permit2);
        vm.serializeAddress(u, "stateView", uni.stateView);
        vm.serializeAddress(u, "quoter", uni.quoter);
        vm.serializeString(u, "foodPool", foodJson);
        string memory uniJson = vm.serializeString(u, "questPool", questJson);
        return uniJson;
    }

    /// @dev ENSv2 exists only on Sepolia: anvil's deployments file has no "ens" key. The registry and directory are
    ///      where script/names/CityNames.s.sol (run by ENS_ADMIN_ADDRESS, default the deployer) puts them. Players have
    ///      no shared resolver: each player's name gets its own, deployed by the names key through `factory` from
    ///      `resolverImpl` with salt uint256(keccak256(abi.encode("tallyport.names.player.v1", parentLabel, label))).
    function _ensJson() internal returns (string memory) {
        string memory parent = vm.envOr("TALLYPORT_ENS_LABEL", string(NameKit.PARENT_LABEL));
        Ens memory ens = loadEns();
        City memory city = predictCity(ens, vm.envOr("ENS_ADMIN_ADDRESS", keys.admin), parent);
        string memory e = "tallyport.ens";
        vm.serializeString(e, "parent", NameKit.parentName(parent));
        vm.serializeString(e, "parentLabel", parent);
        vm.serializeUint(e, "coinType", NameKit.ETH_COIN_TYPE);
        vm.serializeAddress(e, "registry", address(city.registry));
        vm.serializeAddress(e, "directory", address(city.directory));
        vm.serializeAddress(e, "factory", address(ens.factory));
        vm.serializeAddress(e, "resolverImpl", ens.resolverImpl);
        vm.serializeAddress(e, "reverseAdapter", address(ens.reverseAdapter));
        vm.serializeString(e, "players", "per-player resolver: see playerResolverSalt");
        vm.serializeString(
            e, "playerResolverSalt", "uint256(keccak256(abi.encode(\"tallyport.names.player.v1\", parentLabel, label)))"
        );
        return vm.serializeAddress(e, "universalResolver", address(ens.universalResolver));
    }

    function _keysJson() internal returns (string memory) {
        string memory k = "tallyport.keys";
        vm.serializeAddress(k, "admin", keys.admin);
        vm.serializeAddress(k, "keeper", keys.keeper);
        vm.serializeAddress(k, "ticketSigner", keys.ticketSigner);
        vm.serializeAddress(k, "voucherSigner", keys.voucherSigner);
        vm.serializeAddress(k, "ops", keys.ops);
        string memory keysJson = vm.serializeAddress(k, "team", keys.team);
        return keysJson;
    }

    // ---------------------------------------------------------------- helpers

    function _uint(string memory key) internal view returns (uint256) {
        return vm.parseJsonUint(config, key);
    }

    /// @dev FoodHook must sit at an address whose low 14 bits are exactly its four hook flags.
    function _mineHookSalt(bytes32 initCodeHash) internal view returns (bytes32) {
        uint256 base = uint256(keccak256(abi.encode(keys.admin, block.chainid, block.number)));
        for (uint256 i = 0; i < MAX_HOOK_SALT_TRIES; ++i) {
            bytes32 salt = bytes32(base + i);
            address at = vm.computeCreate2Address(salt, initCodeHash, CREATE2_DEPLOYER);
            if (uint160(at) & ALL_HOOK_FLAGS_MASK == HOOK_FLAGS && at.code.length == 0) return salt;
        }
        revert("Deploy: no hook salt found");
    }

    /// @dev USDC per FOOD → sqrtPriceX96 in the pool's token order (both tokens have 6 decimals).
    function _foodSqrtPrice(uint256 usdcPerFood) internal view returns (uint160) {
        bool foodFirst = address(town.food) < town.usdc;
        uint256 x192 =
            foodFirst ? Math.mulDiv(usdcPerFood, 1 << 192, ONE_FOOD) : Math.mulDiv(ONE_FOOD, 1 << 192, usdcPerFood);
        return uint160(Math.sqrt(x192));
    }
}
