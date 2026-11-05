// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    Grant,
    IUniversalResolver,
    IRegistry,
    IETHRegistrar,
    IVerifiableFactory,
    IPermissionedResolver,
    IUserRegistryInit,
    IDefaultReverseAdapter,
    IRecordReader
} from "../../src/names/ENSv2.sol";
import {Vm} from "forge-std/Vm.sol";
import {NameKit} from "../../src/names/NameKit.sol";

/// @notice ENS's contracts on Sepolia that Tallyport uses. Only the Universal Resolver is ENS's permanent entry point;
///         the rest come from script/names/sepolia.json and are checked against what the root of the name tree says.
struct Ens {
    IUniversalResolver universalResolver;
    IETHRegistrar registrar;
    IVerifiableFactory factory;
    address userRegistryImpl;
    address resolverImpl;
    address paymentToken; // the stablecoin ENSv2 takes the .eth fee in
    IDefaultReverseAdapter reverseAdapter;
}

/// @notice The town's own copies of ENS's contracts, and its parent label ("tallyport" → tallyport.eth).
struct City {
    string parent;
    IRegistry registry; // every name under tallyport.eth
    IPermissionedResolver directory; // NPC and contract names (market, campaigns...): only the admin writes here
}

/// @notice The town's name setup, step by step. The deploy scripts and the tests use these same steps, so what is
///         tested is exactly what runs. Each step says which key must be the sender.
///
///         Players: each player's name gets its OWN Permissioned Resolver (deployed by the names key through ENS's
///         factory), so the player's wallet can hold the text-record role for `description` and `avatar` on its own
///         name only (ENSv2 roles are per resolver and per record key, not per name). The names key writes the
///         address records and tallyport.title / tallyport.stamps / tallyport.human.
abstract contract CityNames {
    /// @dev Fixed salts, so our copies land at addresses anyone can predict and check.
    uint256 internal constant REGISTRY_SALT = uint256(keccak256("tallyport.names.registry.v1"));
    uint256 internal constant DIRECTORY_SALT = uint256(keccak256("tallyport.names.directory.v1"));
    /// @dev tallyport.eth is registered for a year at a time.
    uint64 internal constant PARENT_DURATION = 365 days;
    /// @dev Player and contract names last a year and are renewed by the names key.
    uint64 internal constant NAME_DURATION = 365 days;

    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error CityNames__RegistrarMismatch(address registrarSays, address rootSays);
    error CityNames__ParentTaken(string label);

    // ---------------------------------------------------------------- checks

    /// @notice ENS's contracts on Sepolia, from script/names/sepolia.json.
    function loadEns() internal view returns (Ens memory e) {
        string memory json = VM.readFile(string.concat(VM.projectRoot(), "/script/names/sepolia.json"));
        e.universalResolver = IUniversalResolver(VM.parseJsonAddress(json, ".universalResolver"));
        e.registrar = IETHRegistrar(VM.parseJsonAddress(json, ".registrar"));
        e.factory = IVerifiableFactory(VM.parseJsonAddress(json, ".factory"));
        e.userRegistryImpl = VM.parseJsonAddress(json, ".userRegistryImpl");
        e.resolverImpl = VM.parseJsonAddress(json, ".resolverImpl");
        e.paymentToken = VM.parseJsonAddress(json, ".paymentToken");
        e.reverseAdapter = IDefaultReverseAdapter(VM.parseJsonAddress(json, ".reverseAdapter"));
    }

    /// @notice Refuses to run against a registrar that isn't the one the root of the name tree points to.
    function checkEns(Ens memory e) internal view returns (address ethRegistry) {
        ethRegistry = IRegistry(e.universalResolver.ROOT_REGISTRY()).getSubregistry("eth");
        address registrarSays = e.registrar.ETH_REGISTRY();
        if (registrarSays != ethRegistry) revert CityNames__RegistrarMismatch(registrarSays, ethRegistry);
    }

    /// @notice Where the town's copies will be, before (or after) they're deployed by `admin`.
    function predictCity(Ens memory e, address admin, string memory parent) internal view returns (City memory c) {
        c.parent = parent;
        c.registry = IRegistry(e.factory.predictProxyAddress(admin, _salt(REGISTRY_SALT, parent)));
        c.directory = IPermissionedResolver(e.factory.predictProxyAddress(admin, _salt(DIRECTORY_SALT, parent)));
    }

    /// @notice Where a player's own resolver will be (deployed by the names key).
    function predictPlayerResolver(Ens memory e, City memory c, address namesKey, string memory label)
        internal
        view
        returns (IPermissionedResolver)
    {
        return IPermissionedResolver(e.factory.predictProxyAddress(namesKey, _playerSalt(c, label)));
    }

    // ---------------------------------------------------------------- step 1 (sender: admin key)

    /// @notice Deploys our registry and the directory resolver through ENS's factory. The admin holds every role; the
    ///         names key may only register and renew names.
    function deployCity(Ens memory e, address admin, address namesKey, string memory parent)
        internal
        returns (City memory c)
    {
        c.parent = parent;
        uint256 registryRoles = NameKit.ROLE_REGISTRAR | NameKit.ROLE_SET_PARENT | NameKit.ROLE_UNREGISTER
            | NameKit.ROLE_RENEW | NameKit.ROLE_SET_SUBREGISTRY | NameKit.ROLE_SET_RESOLVER | NameKit.ROLE_UPGRADE;
        Grant[] memory registryGrants = new Grant[](2);
        registryGrants[0] = Grant(admin, registryRoles | NameKit.admin(registryRoles));
        registryGrants[1] = Grant(namesKey, NameKit.ROLE_REGISTRAR | NameKit.ROLE_RENEW);
        c.registry = IRegistry(
            e.factory
                .deployProxy(
                    e.userRegistryImpl,
                    _salt(REGISTRY_SALT, parent),
                    abi.encodeCall(IUserRegistryInit.initialize, (registryGrants))
                )
        );

        uint256 recordRoles = NameKit.ROLE_SET_ADDRESS | NameKit.ROLE_SET_TEXT | NameKit.ROLE_UPGRADE;
        Grant[] memory resolverGrants = new Grant[](1);
        resolverGrants[0] = Grant(admin, recordRoles | NameKit.admin(recordRoles));
        bytes memory init = abi.encodeCall(IPermissionedResolver.initialize, (resolverGrants, new bytes[](0)));
        c.directory = IPermissionedResolver(e.factory.deployProxy(e.resolverImpl, _salt(DIRECTORY_SALT, parent), init));
    }

    /// @notice Step one of registering tallyport.eth: publish a sealed commitment. Register after a minute.
    function commitParent(Ens memory e, City memory c, address admin, bytes32 secret) internal {
        if (!e.registrar.isAvailable(c.parent)) revert CityNames__ParentTaken(c.parent);
        e.registrar.commit(_commitment(e, c, admin, secret));
    }

    // ---------------------------------------------------------------- step 2 (sender: admin key, a minute later)

    /// @notice Registers tallyport.eth to the admin key, pointing at our registry and the directory resolver, and
    ///         links our registry back to its parent. The admin must hold enough of the payment stablecoin.
    function registerParent(Ens memory e, City memory c, address admin, bytes32 secret) internal {
        (uint256 base, uint256 premium) = e.registrar.getRegisterPrice(c.parent, PARENT_DURATION, e.paymentToken);
        _approve(e.paymentToken, address(e.registrar), base + premium);
        e.registrar
            .register(
                c.parent,
                admin,
                secret,
                address(c.registry),
                address(c.directory),
                PARENT_DURATION,
                e.paymentToken,
                bytes32(0)
            );
        c.registry.setParent(e.registrar.ETH_REGISTRY(), c.parent);
    }

    /// @notice Names one of the town's contracts or NPCs (market, campaigns, spice-merchant...) and points it at the
    ///         contract's address (coin type 60 and the default EVM record). The server finds our contracts by these
    ///         names, so a replaced contract is one record change. `admin` must be the sender; it owns the name.
    function nameContract(City memory c, string memory label, address target, address admin) internal {
        c.registry.register(label, admin, address(0), address(c.directory), 0, _expiry());
        bytes memory name = NameKit.dnsEncode(NameKit.fullName(label, c.parent));
        c.directory.setAddress(name, NameKit.ETH_COIN_TYPE, abi.encodePacked(target));
        c.directory.setAddress(name, NameKit.DEFAULT_EVM_COIN_TYPE, abi.encodePacked(target));
    }

    // ---------------------------------------------------------------- players (sender: names key)

    /// @notice Gives a verified player their name (label.tallyport.eth), owned by their wallet, with no transfer role.
    ///         Deploys the name's own resolver with its first records (ETH address, default EVM address, avatar,
    ///         tallyport.human = "verified"), then grants the player's wallet the text role for `description` and
    ///         `avatar` on that resolver, so painting the shop sign is the player's own transaction.
    /// @param admin The ENS admin key: holds the upgrade role on the player's resolver.
    function registerPlayer(
        Ens memory e,
        City memory c,
        address admin,
        address namesKey,
        string memory label,
        address player,
        string memory avatar
    ) internal returns (IPermissionedResolver resolver) {
        bytes memory name = NameKit.dnsEncode(NameKit.fullName(label, c.parent));
        uint256 writerRoles = NameKit.ROLE_SET_ADDRESS | NameKit.ROLE_SET_TEXT;
        Grant[] memory grants = new Grant[](2);
        grants[0] = Grant(namesKey, writerRoles | NameKit.admin(NameKit.ROLE_SET_TEXT));
        grants[1] = Grant(admin, NameKit.ROLE_UPGRADE | NameKit.admin(NameKit.ROLE_UPGRADE));
        bytes[] memory calls = new bytes[](4);
        calls[0] =
            abi.encodeCall(IPermissionedResolver.setAddress, (name, NameKit.ETH_COIN_TYPE, abi.encodePacked(player)));
        calls[1] = abi.encodeCall(
            IPermissionedResolver.setAddress, (name, NameKit.DEFAULT_EVM_COIN_TYPE, abi.encodePacked(player))
        );
        calls[2] = abi.encodeCall(IPermissionedResolver.setText, (name, NameKit.AVATAR_KEY, avatar));
        calls[3] = abi.encodeCall(IPermissionedResolver.setText, (name, NameKit.HUMAN_KEY, NameKit.HUMAN_VERIFIED));
        resolver = IPermissionedResolver(
            e.factory
                .deployProxy(
                    e.resolverImpl,
                    _playerSalt(c, label),
                    abi.encodeCall(IPermissionedResolver.initialize, (grants, calls))
                )
        );
        _grantText(resolver, NameKit.DESCRIPTION_KEY, player);
        _grantText(resolver, NameKit.AVATAR_KEY, player);
        c.registry.register(label, player, address(0), address(resolver), 0, _expiry());
    }

    /// @notice (Sender: names key.) Writes the player's title and stamps.
    function setPlayerRecords(City memory c, string memory label, string memory title, string memory stamps) internal {
        IPermissionedResolver resolver = IPermissionedResolver(c.registry.getResolver(label));
        bytes memory name = NameKit.dnsEncode(NameKit.fullName(label, c.parent));
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(IPermissionedResolver.setText, (name, NameKit.TITLE_KEY, title));
        calls[1] = abi.encodeCall(IPermissionedResolver.setText, (name, NameKit.STAMPS_KEY, stamps));
        resolver.multicall(calls);
    }

    /// @notice (Sender: the player's own wallet.) "Paint your shop sign": sets the name's description record.
    function paintSign(City memory c, string memory label, string memory text) internal {
        IPermissionedResolver resolver = IPermissionedResolver(c.registry.getResolver(label));
        resolver.setText(NameKit.dnsEncode(NameKit.fullName(label, c.parent)), NameKit.DESCRIPTION_KEY, text);
    }

    // ---------------------------------------------------------------- reading (anyone)

    /// @notice A name's address for a coin type, read the way every app reads it: through ENS's Universal Resolver.
    function resolveAddress(Ens memory e, string memory name, uint256 coinType) internal view returns (address) {
        bytes memory call = abi.encodeCall(IRecordReader.addr, (NameKit.namehash(name), coinType));
        (bytes memory result,) = e.universalResolver.resolve(NameKit.dnsEncode(name), call);
        bytes memory raw = abi.decode(result, (bytes));
        return raw.length == 20 ? address(bytes20(raw)) : address(0);
    }

    /// @notice A name's text record, read through the Universal Resolver.
    function resolveText(Ens memory e, string memory name, string memory key) internal view returns (string memory) {
        bytes memory call = abi.encodeCall(IRecordReader.text, (NameKit.namehash(name), key));
        (bytes memory result,) = e.universalResolver.resolve(NameKit.dnsEncode(name), call);
        return abi.decode(result, (string));
    }

    // ---------------------------------------------------------------- internals

    function _commitment(Ens memory e, City memory c, address admin, bytes32 secret) internal view returns (bytes32) {
        return e.registrar
            .makeCommitment(
                c.parent, admin, secret, address(c.registry), address(c.directory), PARENT_DURATION, bytes32(0)
            );
    }

    function _salt(uint256 base, string memory parent) private pure returns (uint256) {
        return uint256(keccak256(abi.encode(base, parent)));
    }

    function _playerSalt(City memory c, string memory label) private pure returns (uint256) {
        return uint256(keccak256(abi.encode("tallyport.names.player.v1", c.parent, label)));
    }

    function _grantText(IPermissionedResolver r, string memory key, address to) private {
        r.grantSetterRoles(abi.encodeCall(IPermissionedResolver.setText, ("", key, "")), to);
    }

    function _approve(address token, address spender, uint256 amount) private {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSignature("approve(address,uint256)", spender, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "CityNames: approve failed");
    }

    function _expiry() private view returns (uint64) {
        return uint64(block.timestamp) + NAME_DURATION;
    }
}
