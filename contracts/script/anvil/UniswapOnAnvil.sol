// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

/// @notice Uniswap v4 on a local anvil chain, at the SAME addresses as on Ethereum Sepolia, running Uniswap's own
///         deployed bytecode (fetched from Sepolia by script/anvil/fetch_uniswap.sh into script/anvil/uniswap/*.hex).
///         So the server talks to one set of Uniswap addresses everywhere, and a player's swap on anvil goes through
///         the real Universal Router → PoolManager path. dev_chain.sh places the code with anvil_setCode; tests use
///         etchUniswap(). Source of the addresses: https://docs.uniswap.org/contracts/v4/deployments (Sepolia).
/// @dev Constructor-set storage is restored by hand: PositionManager's ERC-721 name/symbol (slots 0, 1) and
///      nextTokenId = 1 (slot 8, read from Sepolia). Everything else these contracts need is immutable (in the
///      bytecode, and valid because the addresses match) or starts empty. Permit2 and PositionManager rebuild their
///      EIP-712 domain separators for anvil's chain id.
abstract contract UniswapOnAnvil {
    address internal constant POOL_MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    address internal constant POSITION_MANAGER = 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4;
    address internal constant UNIVERSAL_ROUTER = 0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b;
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant STATE_VIEW = 0xE1Dd9c3fA50EDB962E442f60DfBc432e24537E4C;
    address internal constant V4_QUOTER = 0x68aFa8b853cAa7a2D40B0F6AEE5C4DbC147C8244;

    bytes32 internal constant POSM_NAME_SLOT_VALUE = 0x556e697377617020763420506f736974696f6e73204e46540000000000000030;
    bytes32 internal constant POSM_SYMBOL_SLOT_VALUE =
        0x554e492d56342d504f534d000000000000000000000000000000000000000016;
    uint256 internal constant POSM_NEXT_TOKEN_ID_SLOT = 8;

    Vm private constant VM_ = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Places Uniswap's Sepolia bytecode at its Sepolia addresses (tests only; dev_chain.sh does the same).
    function etchUniswap() internal {
        _etch(POOL_MANAGER, "PoolManager");
        _etch(POSITION_MANAGER, "PositionManager");
        _etch(UNIVERSAL_ROUTER, "UniversalRouter");
        _etch(PERMIT2, "Permit2");
        _etch(STATE_VIEW, "StateView");
        _etch(V4_QUOTER, "V4Quoter");
        VM_.store(POSITION_MANAGER, bytes32(0), POSM_NAME_SLOT_VALUE);
        VM_.store(POSITION_MANAGER, bytes32(uint256(1)), POSM_SYMBOL_SLOT_VALUE);
        VM_.store(POSITION_MANAGER, bytes32(POSM_NEXT_TOKEN_ID_SLOT), bytes32(uint256(1)));
    }

    function _etch(address at, string memory name) private {
        string memory path = string.concat(VM_.projectRoot(), "/script/anvil/uniswap/", name, ".hex");
        VM_.etch(at, VM_.parseBytes(VM_.trim(VM_.readFile(path))));
    }
}
