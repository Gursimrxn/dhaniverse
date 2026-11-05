// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/// @title MockUSDC
/// @notice A stand-in for Circle's USDC on local chains (anvil) and in tests. NOT real money: anyone can mint it.
///         Never deployed to Sepolia, where Tallyport uses Circle's test USDC.
/// @dev Matches Circle's USDC where our code touches it: 6 decimals and EIP-2612 permit with the same EIP-712 domain
///      name ("USDC") and version ("2"), so the server's permit signing works unchanged on anvil and Sepolia.
///      Spec: docs/architecture/spec.json, contract "MockUSDC".
contract MockUSDC is ERC20, IERC20Permit, EIP712, Nonces {
    /// @notice USDC has 6 decimals: 1,000,000 base units = 1 USDC.
    uint8 private constant DECIMALS = 6;
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /// @notice The permit's deadline has passed.
    error MockUSDC__PermitExpired(uint256 deadline, uint256 nowSeconds);
    /// @notice The permit wasn't signed by the owner it names.
    error MockUSDC__BadPermit(address signer, address owner);

    constructor() ERC20("USDC", "USDC") EIP712("USDC", "2") {}

    /// @notice Test faucet: makes `amount` mock USDC for `to`. Emits Transfer(0, to, amount).
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @inheritdoc IERC20Permit
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
    {
        // forge-lint: disable-next-line(block-timestamp) same deadline rule as EIP-2612
        if (block.timestamp > deadline) revert MockUSDC__PermitExpired(deadline, block.timestamp);
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline));
        address signer = ECDSA.recover(_hashTypedDataV4(structHash), v, r, s);
        if (signer != owner) revert MockUSDC__BadPermit(signer, owner);
        _approve(owner, spender, value);
    }

    /// @inheritdoc IERC20Permit
    function nonces(address owner) public view override(IERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    /// @inheritdoc IERC20Permit
    // forge-lint: disable-next-line(mixed-case-function) the name is fixed by EIP-2612
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
}
