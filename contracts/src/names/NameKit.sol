// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title NameKit
/// @notice The fixed facts and small helpers every Tallyport name needs: how ENS writes a name in bytes, which coin
///         type means Ethereum, the record keys we use, and ENSv2's role bits.
/// @dev Role values are copied from ENSv2's RegistryRolesLib and PermissionedResolverLib (tag v2-mainnet-deployment-1).
library NameKit {
    /// @notice A name with an empty part, like "sam..eth" or ".eth".
    error NameKit__EmptyLabel(string name);

    // ---------------------------------------------------------------- our names

    /// @notice The default parent: every player, NPC and contract lives under tallyport.eth. Scripts can override the
    ///         label (env TALLYPORT_ENS_LABEL), so a test run never collides with the real one.
    string internal constant PARENT_LABEL = "tallyport";

    // ---------------------------------------------------------------- chains (ENSIP-9, ENSIP-11)

    /// @notice Ethereum's coin type (SLIP-44 60): the address record every wallet and app reads.
    uint256 internal constant ETH_COIN_TYPE = 60;
    /// @notice The default EVM coin type: an address here is used on every EVM chain without its own record.
    uint256 internal constant DEFAULT_EVM_COIN_TYPE = 0x80000000;

    // ---------------------------------------------------------------- text records

    /// @notice The player's picture. The names key writes it at registration; the player may change it.
    string internal constant AVATAR_KEY = "avatar";
    /// @notice The player's shop sign ("Paint your shop sign"). Only the player writes it (and the names key).
    string internal constant DESCRIPTION_KEY = "description";
    /// @notice The player's title (e.g. "Spice Runner"). Written by the names key.
    string internal constant TITLE_KEY = "tallyport.title";
    /// @notice Comma list of the stamps the player has earned. Written by the names key.
    string internal constant STAMPS_KEY = "tallyport.stamps";
    /// @notice "verified" once the player passed the Town Pass (World ID). Written by the names key.
    string internal constant HUMAN_KEY = "tallyport.human";
    /// @notice The value of HUMAN_KEY for a verified human.
    string internal constant HUMAN_VERIFIED = "verified";

    // ---------------------------------------------------------------- ENSv2 registry roles

    uint256 internal constant ROLE_REGISTRAR = 1 << 0;
    uint256 internal constant ROLE_SET_PARENT = 1 << 8;
    uint256 internal constant ROLE_UNREGISTER = 1 << 12;
    uint256 internal constant ROLE_RENEW = 1 << 16;
    uint256 internal constant ROLE_SET_SUBREGISTRY = 1 << 20;
    uint256 internal constant ROLE_SET_RESOLVER = 1 << 24;
    uint256 internal constant ROLE_UPGRADE = 1 << 124;

    // ---------------------------------------------------------------- ENSv2 resolver roles

    uint256 internal constant ROLE_SET_ADDRESS = 1 << 0;
    uint256 internal constant ROLE_SET_TEXT = 1 << 4;

    /// @notice A role's admin bit: holding it lets you grant that role to others.
    function admin(uint256 roles) internal pure returns (uint256) {
        return roles << 128;
    }

    // ---------------------------------------------------------------- encoding

    /// @notice "sam.tallyport.eth" → the DNS wire format ENS uses: each label prefixed by its length, then a zero.
    function dnsEncode(string memory name) internal pure returns (bytes memory out) {
        bytes memory s = bytes(name);
        out = new bytes(s.length + 2);
        uint256 lengthAt = 0;
        uint256 count = 0;
        for (uint256 i = 0; i < s.length; ++i) {
            if (s[i] == ".") {
                // forge-lint: disable-next-line(require-revert-in-loop) a bad name must stop here, wherever it is
                if (count == 0) revert NameKit__EmptyLabel(name);
                out[lengthAt] = bytes1(SafeCast.toUint8(count)); // a label longer than 255 bytes is refused
                lengthAt = i + 1;
                count = 0;
            } else {
                out[i + 1] = s[i];
                ++count;
            }
        }
        if (count == 0) revert NameKit__EmptyLabel(name);
        out[lengthAt] = bytes1(SafeCast.toUint8(count));
        out[s.length + 1] = 0;
    }

    /// @notice ENS's namehash: the fixed id of a name, built from the right (eth, then tallyport, then sam).
    function namehash(string memory name) internal pure returns (bytes32 node) {
        bytes memory s = bytes(name);
        uint256 end = s.length;
        for (uint256 i = s.length; i > 0; --i) {
            if (s[i - 1] == ".") {
                node = keccak256(abi.encodePacked(node, _labelHash(s, i, end)));
                end = i - 1;
            }
        }
        node = keccak256(abi.encodePacked(node, _labelHash(s, 0, end)));
    }

    /// @notice "tallyport" → "tallyport.eth".
    function parentName(string memory parentLabel) internal pure returns (string memory) {
        return string.concat(parentLabel, ".eth");
    }

    /// @notice ("sam", "tallyport") → "sam.tallyport.eth".
    function fullName(string memory label, string memory parentLabel) internal pure returns (string memory) {
        return string.concat(label, ".", parentLabel, ".eth");
    }

    /// @dev keccak256 of s[start:end], hashed in place.
    function _labelHash(bytes memory s, uint256 start, uint256 end) private pure returns (bytes32 h) {
        assembly ("memory-safe") {
            h := keccak256(add(add(s, 0x20), start), sub(end, start))
        }
    }
}
