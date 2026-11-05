// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MockUSDC} from "../../src/mocks/MockUSDC.sol";
import {TestKit} from "./TestKit.sol";

/// @notice Checks the test kit itself (and MockUSDC), so a broken kit can't make other tests lie.
contract TestKitTest is TestKit {
    function test_mockUsdc_has6DecimalsAndCirclesPermitDomain() public view {
        assertEq(usdc.decimals(), 6);
        assertEq(usdc.symbol(), "USDC");
        (, string memory name, string memory version, uint256 chainId, address verifying,,) = usdc.eip712Domain();
        assertEq(name, "USDC");
        assertEq(version, "2", "same EIP-712 version as Circle's USDC");
        assertEq(chainId, block.chainid);
        assertEq(verifying, address(usdc));
    }

    function test_moneyUnits_areUsdcBaseUnits() public pure {
        assertEq(dollars(1), 1_000_000, "1 USDC is 1,000,000 base units");
        assertEq(usdcOf(0, 24_000), 24_000, "a thali at launch price is 0.024 USDC");
        assertEq(food(1), 1_000_000, "1 FOOD is 1,000,000 base units");
    }

    function test_namedKeys_areAllDifferent() public view {
        address[8] memory keys = [admin, keeper, ops, team, sam, priya, sponsor, stranger];
        for (uint256 i = 0; i < keys.length; ++i) {
            for (uint256 j = i + 1; j < keys.length; ++j) {
                assertTrue(keys[i] != keys[j], "two named keys share an address");
            }
        }
    }

    function test_localPoolManager_deploys() public {
        assertGt(address(deployPoolManager()).code.length, 0);
    }

    function test_permit_setsAllowanceFromASignature() public {
        (address owner, uint256 key) = makeAddrAndKey("permit owner");
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                sam,
                dollars(3),
                0,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", usdc.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        usdc.permit(owner, sam, dollars(3), deadline, v, r, s);
        assertEq(usdc.allowance(owner, sam), dollars(3));
        assertEq(usdc.nonces(owner), 1);

        vm.expectPartialRevert(MockUSDC.MockUSDC__BadPermit.selector);
        usdc.permit(owner, sam, dollars(3), deadline, v, r, s); // nonce moved on: replay recovers a different signer

        vm.warp(deadline + 1);
        vm.expectRevert(abi.encodeWithSelector(MockUSDC.MockUSDC__PermitExpired.selector, deadline, deadline + 1));
        usdc.permit(owner, sam, dollars(3), deadline, v, r, s);
    }
}
