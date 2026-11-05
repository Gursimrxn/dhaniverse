// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// The few ENSv2 functions Dhaniverse calls, copied from ENS's own deployment on Sepolia
// (github.com/ensdomains/contracts-v2, tag v2-mainnet-deployment-1, deployed 1 Oct 2026; checked on chain 29 Oct).
// These are ENS's contracts, not ours: we only call them. Spec: docs/architecture/spec.json, layer "Names (Sepolia)".

/// @notice One role grant: `account` gets `roleBitmap` (ENSv2's Enhanced Access Control).
struct Grant {
    address account;
    uint256 roleBitmap;
}

/// @notice ENS's single entry point for reading any name. The address is permanent; libraries like alloy know it.
interface IUniversalResolver {
    /// @notice The root of the name tree, where every lookup starts.
    function ROOT_REGISTRY() external view returns (address);
    /// @notice Runs one record lookup (`data` is an addr/text call) on `name` (DNS-encoded).
    function resolve(bytes calldata name, bytes calldata data) external view returns (bytes memory, address);
    /// @notice An address's primary name, checked forward so a fake name can't appear.
    function reverse(bytes calldata lookupAddress, uint256 coinType)
        external
        view
        returns (string memory name, address resolver, address reverseResolver);
}

/// @notice An ENSv2 registry: who owns each name below it, and where its records live.
interface IRegistry {
    function getSubregistry(string calldata label) external view returns (address);
    function getResolver(string calldata label) external view returns (address);
    function register(
        string calldata label,
        address owner,
        address registry,
        address resolver,
        uint256 roleBitmap,
        uint64 expiry
    ) external returns (uint256 tokenId);
    function setParent(address parent, string calldata label) external;
    function findTokenId(string calldata label) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;
    function grantRootRoles(uint256 roleBitmap, address account) external returns (bool);
}

/// @notice ENS's registrar for .eth names. Registration is commit, wait a minute, then register, paid in a stablecoin.
interface IETHRegistrar {
    function ETH_REGISTRY() external view returns (address);
    function MIN_COMMITMENT_AGE() external view returns (uint64);
    function isAvailable(string calldata label) external view returns (bool);
    function makeCommitment(
        string calldata label,
        address owner,
        bytes32 secret,
        address subregistry,
        address resolver,
        uint64 duration,
        bytes32 referrer
    ) external pure returns (bytes32);
    function commit(bytes32 commitment) external;
    function getRegisterPrice(string calldata label, uint64 duration, address paymentToken)
        external
        view
        returns (uint256 base, uint256 premium);
    function register(
        string calldata label,
        address owner,
        bytes32 secret,
        address subregistry,
        address resolver,
        uint64 duration,
        address paymentToken,
        bytes32 referrer
    ) external returns (uint256 tokenId);
}

/// @notice ENS's factory: deploys our own copy of an ENS contract at a predictable address.
interface IVerifiableFactory {
    function deployProxy(address implementation, uint256 salt, bytes calldata data) external returns (address);
    function predictProxyAddress(address deployer, uint256 salt) external view returns (address);
}

/// @notice ENSv2's Permissioned Resolver: a name's records, where each record type can have its own writer.
interface IPermissionedResolver {
    function initialize(Grant[] calldata grants, bytes[] calldata calls) external;
    function setAddress(bytes calldata name, uint256 coinType, bytes calldata addressBytes) external;
    function setText(bytes calldata name, string calldata key, string calldata value) external;
    function multicall(bytes[] calldata calls) external returns (bytes[] memory);
    function grantSetterRoles(bytes calldata setter, address account) external returns (bool);
}

/// @notice The ENSv2 registry's own setup call (used when our copy is deployed).
interface IUserRegistryInit {
    function initialize(Grant[] calldata grants) external;
}

/// @notice ENS's adapter for setting an address's default primary name (the name it shows on every EVM chain).
interface IDefaultReverseAdapter {
    function setName(address account, string calldata name) external;
}

/// @notice The record lookups we ask the Universal Resolver to run.
interface IRecordReader {
    function addr(bytes32 node, uint256 coinType) external view returns (bytes memory);
    function text(bytes32 node, string calldata key) external view returns (string memory);
}

/// @notice ENSv2's errors that the city can run into, so `dhv why` can explain them in plain words.
///         Nothing implements this interface; it only puts the errors into our compiled ABIs.
interface IENSv2Errors {
    error EACUnauthorizedAccountRoles(uint256 resource, uint256 roleBitmap, address account);
    error LabelAlreadyRegistered(string label);
    error LabelExpired(uint256 tokenId);
    error TransferDisallowed(uint256 tokenId, address from);
    error UnauthorizedNamer(address namer);
    error NameNotAvailable(string label);
    error CommitmentTooNew(bytes32 commitment, uint64 validFrom, uint64 blockTimestamp);
    error CommitmentTooOld(bytes32 commitment, uint64 validTo, uint64 blockTimestamp);
    error DurationTooShort(uint64 duration, uint64 minDuration);
    error PaymentTokenNotSupported(address paymentToken);
}
