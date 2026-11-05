// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IRegistry, IPermissionedResolver} from "../../src/names/ENSv2.sol";
import {NameKit} from "../../src/names/NameKit.sol";
import {CityNames, Ens, City} from "../../script/names/CityNames.sol";

/// @notice The whole name setup, run against a copy of live Sepolia with ENS's real ENSv2 contracts.
///         Every check reads names the way any ENS app does: through ENS's Universal Resolver.
///         Needs SEPOLIA_RPC_URL; without it these tests are skipped (CI runs them only when it has one).
contract CityNamesForkTest is Test, CityNames {
    /// @dev ENSv2's "you don't have that role" error (IEnhancedAccessControl).
    bytes4 internal constant EAC_UNAUTHORIZED =
        bytes4(keccak256("EACUnauthorizedAccountRoles(uint256,uint256,address)"));

    Ens internal e;
    City internal c;
    bool internal forked;

    address internal admin = makeAddr("ens admin key");
    address internal namesKey = makeAddr("names key");
    address internal sam = makeAddr("sam");
    address internal priya = makeAddr("priya");
    address internal stranger = makeAddr("stranger");
    address internal market = makeAddr("FoodRouter");
    address internal merchant = makeAddr("SpiceMerchant");

    function setUp() public {
        string memory rpc = vm.envOr("SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        forked = true;
        e = loadEns();
        checkEns(e);

        // ENSv2 on Sepolia takes the .eth fee in a test stablecoin that anyone can mint.
        vm.prank(admin);
        (bool ok,) = e.paymentToken.call(abi.encodeWithSignature("mint(address,uint256)", admin, 100e6));
        require(ok, "mint failed");

        vm.startPrank(admin);
        c = deployCity(e, admin, namesKey, NameKit.PARENT_LABEL);
        commitParent(e, c, admin, keccak256("test secret"));
        vm.stopPrank();

        vm.warp(block.timestamp + e.registrar.MIN_COMMITMENT_AGE() + 1);
        vm.startPrank(admin);
        registerParent(e, c, admin, keccak256("test secret"));
        nameContract(c, "market", market, admin);
        nameContract(c, "spice-merchant", merchant, admin);
        vm.stopPrank();
    }

    function _registerSam(string memory avatar) internal returns (IPermissionedResolver resolver) {
        vm.startPrank(namesKey);
        resolver = registerPlayer(e, c, admin, namesKey, "sam", sam, avatar);
        vm.stopPrank();
    }

    modifier onFork() {
        if (!forked) vm.skip(true);
        _;
    }

    // ================================================================ the town's name

    function test_tallyportEth_pointsAtOurRegistryAndDirectory() public onFork {
        IRegistry eth = IRegistry(e.registrar.ETH_REGISTRY());
        assertEq(eth.getSubregistry(NameKit.PARENT_LABEL), address(c.registry), "our registry");
        assertEq(eth.getResolver(NameKit.PARENT_LABEL), address(c.directory), "our directory resolver");
    }

    function test_ourCopiesLandWhereAnyoneCanPredict() public onFork {
        City memory predicted = predictCity(e, admin, NameKit.PARENT_LABEL);
        assertEq(address(predicted.registry), address(c.registry));
        assertEq(address(predicted.directory), address(c.directory));
        IPermissionedResolver resolver = _registerSam("");
        assertEq(address(predictPlayerResolver(e, c, namesKey, "sam")), address(resolver));
    }

    // ================================================================ a player's name

    function test_player_getsANameThatAnyAppCanRead() public onFork {
        _registerSam("https://tallyport.example/avatars/sam.png");

        assertEq(resolveAddress(e, "sam.tallyport.eth", NameKit.ETH_COIN_TYPE), sam, "ETH address (coin type 60)");
        assertEq(resolveAddress(e, "sam.tallyport.eth", NameKit.DEFAULT_EVM_COIN_TYPE), sam, "default EVM address");
        assertEq(resolveText(e, "sam.tallyport.eth", NameKit.AVATAR_KEY), "https://tallyport.example/avatars/sam.png");
        assertEq(resolveText(e, "sam.tallyport.eth", NameKit.HUMAN_KEY), "verified");
        assertEq(c.registry.ownerOf(c.registry.findTokenId("sam")), sam, "Sam's wallet owns the name");
    }

    function test_player_paintsTheirOwnShopSign() public onFork {
        _registerSam("");
        vm.startPrank(sam);
        paintSign(c, "sam", "Sam's Spice Stall - best mangoes in Tallyport");
        vm.stopPrank();
        assertEq(
            resolveText(e, "sam.tallyport.eth", NameKit.DESCRIPTION_KEY),
            "Sam's Spice Stall - best mangoes in Tallyport"
        );
    }

    function test_player_cantPaintSomeoneElsesSign_orFakeTheirStamps() public onFork {
        _registerSam("");
        vm.startPrank(namesKey);
        registerPlayer(e, c, admin, namesKey, "priya", priya, "");
        vm.stopPrank();

        IPermissionedResolver samResolver = IPermissionedResolver(c.registry.getResolver("sam"));
        bytes memory samName = NameKit.dnsEncode("sam.tallyport.eth");
        vm.expectPartialRevert(EAC_UNAUTHORIZED);
        vm.prank(priya); // Priya's description role is on her own resolver only
        samResolver.setText(samName, NameKit.DESCRIPTION_KEY, "hacked");

        vm.expectPartialRevert(EAC_UNAUTHORIZED);
        vm.prank(sam);
        samResolver.setText(samName, NameKit.STAMPS_KEY, "every,stamp");
    }

    function test_namesKey_writesTitleAndStamps() public onFork {
        _registerSam("");
        vm.startPrank(namesKey);
        setPlayerRecords(c, "sam", "Spice Runner", "town_pass,spice_run");
        vm.stopPrank();
        assertEq(resolveText(e, "sam.tallyport.eth", NameKit.TITLE_KEY), "Spice Runner");
        assertEq(resolveText(e, "sam.tallyport.eth", NameKit.STAMPS_KEY), "town_pass,spice_run");
    }

    function test_player_nameCantBeSoldOrTaken() public onFork {
        _registerSam("");
        uint256 tokenId = c.registry.findTokenId("sam");
        vm.expectRevert(); // no transfer role was given, so ENSv2 refuses any transfer
        vm.prank(sam);
        c.registry.safeTransferFrom(sam, stranger, tokenId, 1, "");
        assertEq(c.registry.ownerOf(tokenId), sam);
    }

    function test_onlyTheNamesKey_canGiveOutNames() public onFork {
        vm.expectPartialRevert(EAC_UNAUTHORIZED);
        vm.prank(stranger);
        c.registry.register("fake", stranger, address(0), address(c.directory), 0, uint64(block.timestamp + 1 days));
    }

    // ================================================================ the town's directory

    function test_directory_theServerFindsContractsAndNpcsByName() public onFork {
        assertEq(resolveAddress(e, "market.tallyport.eth", NameKit.ETH_COIN_TYPE), market);
        assertEq(resolveAddress(e, "spice-merchant.tallyport.eth", NameKit.ETH_COIN_TYPE), merchant);
    }

    function test_directory_aLeakedNamesKeyCantRedirectTheMarket() public onFork {
        bytes memory name = NameKit.dnsEncode("market.tallyport.eth");
        vm.expectPartialRevert(EAC_UNAUTHORIZED);
        vm.prank(namesKey);
        c.directory.setAddress(name, NameKit.ETH_COIN_TYPE, abi.encodePacked(stranger));
        assertEq(resolveAddress(e, "market.tallyport.eth", NameKit.ETH_COIN_TYPE), market, "still the market");
    }

    // ================================================================ primary names

    function test_primaryName_appsShowTheNameInsteadOfTheAddress() public onFork {
        _registerSam("");
        vm.prank(sam);
        e.reverseAdapter.setName(sam, "sam.tallyport.eth");
        (string memory name,,) = e.universalResolver.reverse(abi.encodePacked(sam), NameKit.ETH_COIN_TYPE);
        assertEq(name, "sam.tallyport.eth", "Sam's address shows Sam's name");
    }
}
