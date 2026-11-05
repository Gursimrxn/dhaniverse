// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {CityNames, Ens, City} from "./CityNames.sol";
import {NameKit} from "../../src/names/NameKit.sol";

/// @notice Sets up tallyport.eth on ENSv2 (Sepolia) and gives players their names. Run in order:
///
///   1. forge script script/names/CityNames.s.sol --sig "setUpCity()" --rpc-url sepolia --broadcast
///      Deploys our registry and the directory resolver, gives each key its one job, commits to tallyport.eth.
///   2. (wait at least a minute)
///      forge script script/names/CityNames.s.sol --sig "registerCity()" --rpc-url sepolia --broadcast
///      Registers tallyport.eth and names every contract in deployments/sepolia.json (market, mealcounter,
///      campaigns, housepool, treasury, farm, luckyledger, spice-merchant, food, foodhook, float, mango).
///   3. forge script script/names/CityNames.s.sol --sig "registerPlayer(string,address,string)" sam 0x... "" ...
///      Gives one verified player their name. In the game, the server's names key does this instead.
///
/// Keys come from the environment, never from files: ENS_ADMIN_KEY, NAMES_KEY (private keys); NAMES_SECRET (any 32
/// random bytes, kept until step 2). TALLYPORT_ENS_LABEL overrides the parent label (default "tallyport").
contract CityNamesScript is Script, CityNames {
    function setUpCity() external {
        Ens memory e = loadEns();
        checkEns(e);
        uint256 adminKey = vm.envUint("ENS_ADMIN_KEY");
        address admin = vm.addr(adminKey);
        address namesKey = vm.addr(vm.envUint("NAMES_KEY"));

        vm.startBroadcast(adminKey);
        City memory c = deployCity(e, admin, namesKey, _parent());
        commitParent(e, c, admin, vm.envBytes32("NAMES_SECRET"));
        vm.stopBroadcast();

        console.log("registry  ", address(c.registry));
        console.log("directory ", address(c.directory));
        console.log("Committed to", NameKit.parentName(c.parent), "- run registerCity() after a minute.");
    }

    function registerCity() external {
        Ens memory e = loadEns();
        checkEns(e);
        uint256 adminKey = vm.envUint("ENS_ADMIN_KEY");
        address admin = vm.addr(adminKey);
        City memory c = predictCity(e, admin, _parent());
        string memory deployments = vm.readFile(string.concat(vm.projectRoot(), "/deployments/sepolia.json"));

        vm.startBroadcast(adminKey);
        registerParent(e, c, admin, vm.envBytes32("NAMES_SECRET"));
        string[12] memory labels = [
            "market",
            "mealcounter",
            "campaigns",
            "housepool",
            "treasury",
            "farm",
            "luckyledger",
            "spice-merchant",
            "food",
            "foodhook",
            "float",
            "mango"
        ];
        string[12] memory keys = [
            "FoodRouter",
            "MealCounter",
            "CampaignEscrow",
            "HousePool",
            "Treasury",
            "Farm",
            "LuckyLedger",
            "SpiceMerchant",
            "FoodToken",
            "FoodHook",
            "FloatManager",
            "QuestToken"
        ];
        for (uint256 i = 0; i < labels.length; ++i) {
            string memory path = string.concat(".contracts.", keys[i]);
            if (vm.keyExistsJson(deployments, path)) {
                nameContract(c, labels[i], vm.parseJsonAddress(deployments, path), admin);
            }
        }
        vm.stopBroadcast();
        console.log(NameKit.parentName(c.parent), "is registered.");
    }

    function registerPlayer(string calldata label, address player, string calldata avatar) external {
        Ens memory e = loadEns();
        address admin = vm.addr(vm.envUint("ENS_ADMIN_KEY"));
        City memory c = predictCity(e, admin, _parent());
        uint256 namesKey = vm.envUint("NAMES_KEY");
        vm.startBroadcast(namesKey);
        registerPlayer(e, c, admin, vm.addr(namesKey), label, player, avatar);
        vm.stopBroadcast();
    }

    function _parent() private view returns (string memory) {
        return vm.envOr("TALLYPORT_ENS_LABEL", string(NameKit.PARENT_LABEL));
    }
}
