// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {NameKit} from "../../src/names/NameKit.sol";

/// @notice The name helpers, checked against Foundry's own `cast namehash` and the DNS wire format.
///         These run everywhere (no Sepolia needed), so CI always checks them.
contract NameKitTest is Test {
    function test_coinTypes_ethIs60() public pure {
        assertEq(NameKit.ETH_COIN_TYPE, 60);
        assertEq(NameKit.DEFAULT_EVM_COIN_TYPE, 0x80000000);
    }

    function test_namehash_matchesCast() public pure {
        assertEq(NameKit.namehash("eth"), 0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae);
        assertEq(NameKit.namehash("tallyport.eth"), vm.ensNamehash("tallyport.eth"));
        assertEq(NameKit.namehash("sam.tallyport.eth"), vm.ensNamehash("sam.tallyport.eth"));
        assertEq(NameKit.namehash("spice-merchant.tallyport.eth"), vm.ensNamehash("spice-merchant.tallyport.eth"));
    }

    function test_dnsEncode_lengthPrefixedLabelsThenAZero() public pure {
        assertEq(NameKit.dnsEncode("sam.tallyport.eth"), hex"0373616d0974616c6c79706f72740365746800");
        assertEq(NameKit.dnsEncode("tallyport.eth"), hex"0974616c6c79706f72740365746800");
    }

    function test_dnsEncode_refusesEmptyLabels() public {
        vm.expectRevert(abi.encodeWithSelector(NameKit.NameKit__EmptyLabel.selector, "sam..eth"));
        this.encode("sam..eth");
        vm.expectRevert(abi.encodeWithSelector(NameKit.NameKit__EmptyLabel.selector, ".eth"));
        this.encode(".eth");
    }

    /// @dev External wrapper, so a library revert can be caught by expectRevert.
    function encode(string calldata name) external pure returns (bytes memory) {
        return NameKit.dnsEncode(name);
    }

    function test_names() public pure {
        assertEq(NameKit.fullName("sam", NameKit.PARENT_LABEL), "sam.tallyport.eth");
        assertEq(NameKit.parentName(NameKit.PARENT_LABEL), "tallyport.eth");
    }

    function test_adminBit_isTheRoleShiftedUp128() public pure {
        assertEq(NameKit.admin(NameKit.ROLE_REGISTRAR), uint256(1) << 128);
    }
}
