//! Solidity bindings: everything this crate knows about the contracts' shapes lives here.
//!
//! Matches the compiled contracts in `contracts/out` (checked 6 Nov 2026) and Uniswap v4 / Permit2 / ENSv2. `tests::matches_compiled_abis` checks every selector and event signature here against
//! `contracts/out/**.json` whenever those files exist, so drift between this file and the contracts fails a test.

#![allow(clippy::too_many_arguments)]

use alloy::sol;

sol! {
    // ------------------------------------------------------------------ EIP-712 structs (spec §2.13)

    #[derive(Debug, PartialEq, Eq)]
    struct MealTicket {
        address player;
        bytes32 item;
        uint256 food;
        uint256 maxUsdc;
        bytes32 ref;
        uint64 expiry;
    }

    #[derive(Debug, PartialEq, Eq)]
    struct PayoutVoucher {
        address player;
        bytes32 humanId;
        uint8 source;
        uint256 amount;
        bytes32 ref;
        uint64 expiry;
    }

    #[derive(Debug, PartialEq, Eq)]
    struct CampaignClaim {
        uint256 campaignId;
        address player;
        bytes32 humanId;
        uint256 amount;
        bytes32 ref;
        uint64 expiry;
    }

    #[derive(Debug, PartialEq, Eq)]
    struct AdvanceVoucher {
        uint256 campaignId;
        address player;
        bytes32 humanId;
        uint256 amount;
        bytes32 ref;
        uint64 expiry;
    }

    #[derive(Debug, PartialEq, Eq)]
    struct CampaignParams {
        bytes32 template;
        bytes32 metaHash;
        uint256 budget;
        uint256 payoutPerClaim;
        uint32 energyCost;
        uint32 maxClaims;
        uint16 perHumanCap;
        uint64 start;
        uint64 end;
        uint8 kind;
        address deliverTo;
        address questToken;
    }

    // ------------------------------------------------------------------ tokens

    #[derive(Debug)]
    interface IERC20 {
        function approve(address spender, uint256 amount) external returns (bool);
        function allowance(address owner, address spender) external view returns (uint256);
        function balanceOf(address account) external view returns (uint256);
        function transfer(address to, uint256 amount) external returns (bool);
        function symbol() external view returns (string);
        function decimals() external view returns (uint8);
    }

    // ------------------------------------------------------------------ Tallyport contracts (spec §2)

    #[derive(Debug)]
    interface IMealCounter {
        function buyMeal(MealTicket t, bytes sig) external;
        event MealEaten(
            address indexed player, bytes32 indexed ref, bytes32 item, uint256 usdcPaid, uint256 foodBurned,
            uint256 fromRation
        );
    }

    #[derive(Debug)]
    interface IFarm {
        function sell(uint256 food, bytes32 ref) external;
        event HarvestSold(bytes32 indexed ref, uint256 offered, uint256 sold, uint256 usdc);
    }

    #[derive(Debug)]
    interface ITreasury {
        function split() external;
        event Split(uint256 total, uint256 fixedShare, uint256 safety, uint256 ops, uint256 team);
    }

    #[derive(Debug)]
    interface IHousePool {
        function pay(PayoutVoucher v, bytes sig) external;
        /// Rescue meal: a SAFETY voucher spent on a meal bought for `v.player` through MealCounter.buyMealFor.
        function payMeal(PayoutVoucher v, bytes32 item, uint256 food, bytes sig) external;
        function bucketBalance(uint8 bucket) external view returns (uint256);
        function todayBudget(uint8 bucket) external view returns (uint256 budget, uint256 spent, uint256 left);
        event Paid(uint8 indexed source, address indexed player, bytes32 indexed humanId, uint256 amount, bytes32 ref);
    }

    #[derive(Debug)]
    interface ICampaignEscrow {
        function claim(CampaignClaim c, bytes sig) external;
        function advance(AdvanceVoucher a, bytes sig) external;
        function totalLiabilities() external view returns (uint256);
        function questToken(uint256 campaignId) external view returns (address);
        function openCampaigns() external view returns (uint256[] memory);
        event CampaignCreated(uint256 indexed campaignId, address indexed sponsor, CampaignParams params, uint256 net, uint256 fee);
        event Claimed(
            uint256 indexed campaignId, address indexed player, bytes32 indexed humanId, uint256 amount,
            uint256 advanceRepaid, bytes32 ref
        );
        event Advanced(
            uint256 indexed campaignId, address indexed player, bytes32 indexed humanId, uint256 amount, bytes32 ref
        );
        event Refunded(uint256 indexed campaignId, address indexed sponsor, uint256 amount, uint256 advancesUnpaid);
        event Cancelled(uint256 indexed campaignId);
        event PausedSet(uint256 indexed campaignId, bool paused);
    }

    #[derive(Debug)]
    interface IFloatManager {
        function rebalance() external;
        function harvestYield() external;
        function totalAssets() external view returns (uint256);
        function liquid() external view returns (uint256);
        function invested() external view returns (uint256);
        function lossReserve() external view returns (uint256);
        function buffer() external view returns (uint256);
        function yieldEarned() external view returns (uint256);
    }

    #[derive(Debug)]
    interface ISpiceMerchant {
        function deliver(uint256 campaignId, address token, uint256 amount, bytes32 questRef) external;
        event Delivered(
            uint256 indexed campaignId, address indexed player, address indexed token, uint256 amount, bytes32 questRef
        );
    }

    #[derive(Debug)]
    interface ILuckyLedger {
        function commit(uint256 week, bytes32 seedHash, bytes32 ticketsRoot, uint256 ticketCount, uint256 prize) external;
        function reveal(uint256 week, bytes32 seed) external;
        function claim(uint256 week, address player, uint256 from, uint256 to, bytes32[] proof) external;
        event Committed(
            uint256 indexed week, bytes32 seedHash, bytes32 ticketsRoot, uint256 ticketCount, uint256 prize, uint256 block_
        );
        event Revealed(uint256 indexed week, bytes32 seed, bytes32 entropyBlockHash, uint256 winnerIndex);
        event DrawClaimed(uint256 indexed week, address indexed player, uint256 prize);
    }

    // ------------------------------------------------------------------ food market (contracts/src/food, existing)

    #[derive(Debug)]
    interface IFoodHook {
        event DayOpened(uint256 indexed day, uint256 openPrice);
        event TradeCounted(uint256 indexed day, uint256 usdc, uint256 food, uint256 priceAfter);
    }

    // ------------------------------------------------------------------ Uniswap v4

    #[derive(Debug, PartialEq, Eq)]
    struct PoolKey {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    #[derive(Debug)]
    interface IPoolManager {
        event Swap(
            bytes32 indexed id, address indexed sender, int128 amount0, int128 amount1, uint160 sqrtPriceX96,
            uint128 liquidity, int24 tick, uint24 fee
        );
    }

    /// v4-periphery's `IV4Router.ExactInputSingleParams`, 5 fields, as the Universal Router at 0x3A9D…F98b decodes it.
    /// Universal Router 2.1.x (also on Uniswap's Sepolia list) adds `uint256 minHopPriceX36` before `hookData`:
    /// switching `uniswap.universalRouter` to one of those needs this struct changed too.
    #[derive(Debug)]
    struct ExactInputSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountIn;
        uint128 amountOutMinimum;
        bytes hookData;
    }

    /// v4-periphery's `IV4Quoter.QuoteExactSingleParams`.
    #[derive(Debug)]
    struct QuoteExactSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 exactAmount;
        bytes hookData;
    }

    /// v4-periphery's V4Quoter (not a view: it simulates the swap and reverts internally; called with eth_call).
    #[derive(Debug)]
    interface IV4Quoter {
        function quoteExactInputSingle(QuoteExactSingleParams params)
            external returns (uint256 amountOut, uint256 gasEstimate);
    }

    #[derive(Debug)]
    interface IUniversalRouter {
        function execute(bytes commands, bytes[] inputs, uint256 deadline) external payable;
    }

    #[derive(Debug)]
    interface IPermit2 {
        function approve(address token, address spender, uint160 amount, uint48 expiration) external;
        function allowance(address user, address token, address spender)
            external view returns (uint160 amount, uint48 expiration, uint48 nonce);
    }

    /// v4-core's `PoolSwapTest`: the swap router on a local chain without the UniversalRouter.
    #[derive(Debug)]
    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    #[derive(Debug)]
    struct TestSettings {
        bool takeClaims;
        bool settleUsingBurn;
    }

    #[derive(Debug)]
    interface IPoolSwapTest {
        function swap(PoolKey key, SwapParams params, TestSettings testSettings, bytes hookData)
            external payable returns (int256 delta);
    }

    // ------------------------------------------------------------------ ENSv2 (contracts/src/names/ENSv2.sol)

    /// ENSv2 Enhanced Access Control: `account` gets `roleBitmap`.
    #[derive(Debug, PartialEq, Eq)]
    struct Grant {
        address account;
        uint256 roleBitmap;
    }

    /// ENS's factory: our own copy of an ENS contract at a predictable address.
    #[derive(Debug)]
    interface IVerifiableFactory {
        function deployProxy(address implementation, uint256 salt, bytes data) external returns (address);
        function predictProxyAddress(address deployer, uint256 salt) external view returns (address);
    }

    #[derive(Debug)]
    interface IEnsRegistry {
        function register(string label, address owner, address registry, address resolver, uint256 roleBitmap, uint64 expiry)
            external returns (uint256 tokenId);
        function getResolver(string label) external view returns (address);
        function findTokenId(string label) external view returns (uint256);
        function ownerOf(uint256 tokenId) external view returns (address);
    }

    #[derive(Debug)]
    interface IPermissionedResolver {
        function initialize(Grant[] grants, bytes[] calls) external;
        function grantSetterRoles(bytes setter, address account) external returns (bool);
        function setAddress(bytes name, uint256 coinType, bytes addressBytes) external;
        function setText(bytes name, string key, string value) external;
        function multicall(bytes[] calls) external returns (bytes[] memory);
    }

    // ------------------------------------------------------------------ errors worth naming in IntentFailed

    #[derive(Debug)]
    interface IStdErrors {
        error Error(string message);
        error Panic(uint256 code);
    }
}

/// ENSv2 role bits (contracts/src/names/NameKit.sol, from ENSv2's RegistryRolesLib / PermissionedResolverLib).
pub mod ens {
    use alloy::primitives::U256;
    pub const ROLE_SET_ADDRESS: u32 = 0;
    pub const ROLE_SET_TEXT: u32 = 4;
    pub const ROLE_UPGRADE: u32 = 124;
    /// The default EVM coin type (ENSIP-19).
    pub const DEFAULT_EVM_COIN_TYPE: u64 = 0x8000_0000;
    pub fn role(bit: u32) -> U256 {
        U256::from(1u8) << bit as usize
    }
    /// A role's admin bit: holding it lets you grant that role.
    pub fn admin(roles: U256) -> U256 {
        roles << 128usize
    }
}

/// Uniswap's v4 command and action bytes (UniversalRouter `Commands`, v4-periphery `Actions`).
pub mod uniswap {
    pub const V4_SWAP: u8 = 0x10;
    pub const SWAP_EXACT_IN_SINGLE: u8 = 0x06;
    pub const SETTLE_ALL: u8 = 0x0c;
    pub const TAKE_ALL: u8 = 0x0f;
    /// `TickMath.MIN_SQRT_PRICE + 1` and `MAX_SQRT_PRICE - 1`: "no price limit" for PoolSwapTest.
    pub const MIN_SQRT_PRICE_PLUS_ONE: u128 = 4_295_128_740;
    pub const MAX_SQRT_PRICE_MINUS_ONE: &str = "1461446703485210103287273052203988822378723970341";
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloy::json_abi::JsonAbi;
    use alloy::sol_types::{SolCall, SolEvent};
    use std::path::{Path, PathBuf};

    fn out_dir() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../contracts/out")
    }

    /// The compiled ABI for `contract` if `forge build` has produced it.
    fn abi(file: &str, contract: &str) -> Option<JsonAbi> {
        let p = out_dir()
            .join(format!("{file}.sol"))
            .join(format!("{contract}.json"));
        let raw = std::fs::read_to_string(p).ok()?;
        let v: serde_json::Value = serde_json::from_str(&raw).ok()?;
        serde_json::from_value(v.get("abi")?.clone()).ok()
    }

    fn check(
        file: &str,
        contract: &str,
        fns: &[(&str, [u8; 4])],
        events: &[(&str, alloy::primitives::B256)],
    ) -> bool {
        let Some(abi) = abi(file, contract) else {
            eprintln!("skip {contract}: no compiled ABI yet");
            return false;
        };
        for (sig, sel) in fns {
            let found = abi.functions().any(|f| f.selector() == *sel);
            assert!(found, "{contract}: no function {sig} in the compiled ABI");
        }
        for (sig, topic) in events {
            let found = abi.events().any(|e| e.selector() == *topic);
            assert!(
                found,
                "{contract}: no event {sig} in the compiled ABI (check types and order)"
            );
        }
        true
    }

    macro_rules! f {
        ($t:ty) => {
            (<$t>::SIGNATURE, <$t>::SELECTOR)
        };
    }
    macro_rules! e {
        ($t:ty) => {
            (<$t>::SIGNATURE, <$t>::SIGNATURE_HASH)
        };
    }

    /// Indexed-ness changes how a log decodes but not its topic hash, so compare it too.
    fn indexed_flags(file: &str, contract: &str, event: &str) -> Option<Vec<bool>> {
        let abi = abi(file, contract)?;
        let e = abi.events().find(|e| e.name == event)?;
        Some(e.inputs.iter().map(|i| i.indexed).collect())
    }

    #[test]
    fn matches_compiled_abis() {
        use IFoodHook::*;
        check(
            "FoodHook",
            "FoodHook",
            &[],
            &[e!(DayOpened), e!(TradeCounted)],
        );
        check(
            "MealCounter",
            "MealCounter",
            &[f!(IMealCounter::buyMealCall)],
            &[e!(IMealCounter::MealEaten)],
        );
        check(
            "Farm",
            "Farm",
            &[f!(IFarm::sellCall)],
            &[e!(IFarm::HarvestSold)],
        );
        check(
            "Treasury",
            "Treasury",
            &[f!(ITreasury::splitCall)],
            &[e!(ITreasury::Split)],
        );
        check(
            "HousePool",
            "HousePool",
            &[
                f!(IHousePool::payCall),
                f!(IHousePool::payMealCall),
                f!(IHousePool::bucketBalanceCall),
                f!(IHousePool::todayBudgetCall),
            ],
            &[e!(IHousePool::Paid)],
        );
        check(
            "CampaignEscrow",
            "CampaignEscrow",
            &[
                f!(ICampaignEscrow::claimCall),
                f!(ICampaignEscrow::advanceCall),
                f!(ICampaignEscrow::totalLiabilitiesCall),
                f!(ICampaignEscrow::questTokenCall),
                f!(ICampaignEscrow::openCampaignsCall),
            ],
            &[
                e!(ICampaignEscrow::CampaignCreated),
                e!(ICampaignEscrow::Claimed),
                e!(ICampaignEscrow::Advanced),
                e!(ICampaignEscrow::Refunded),
                e!(ICampaignEscrow::Cancelled),
                e!(ICampaignEscrow::PausedSet),
            ],
        );
        check(
            "FloatManager",
            "FloatManager",
            &[
                f!(IFloatManager::rebalanceCall),
                f!(IFloatManager::harvestYieldCall),
                f!(IFloatManager::totalAssetsCall),
                f!(IFloatManager::liquidCall),
                f!(IFloatManager::investedCall),
                f!(IFloatManager::lossReserveCall),
                f!(IFloatManager::bufferCall),
                f!(IFloatManager::yieldEarnedCall),
            ],
            &[],
        );
        check(
            "SpiceMerchant",
            "SpiceMerchant",
            &[f!(ISpiceMerchant::deliverCall)],
            &[e!(ISpiceMerchant::Delivered)],
        );
        check(
            "LuckyLedger",
            "LuckyLedger",
            &[
                f!(ILuckyLedger::commitCall),
                f!(ILuckyLedger::revealCall),
                f!(ILuckyLedger::claimCall),
            ],
            &[
                e!(ILuckyLedger::Committed),
                e!(ILuckyLedger::Revealed),
                e!(ILuckyLedger::DrawClaimed),
            ],
        );
        check("PoolManager", "PoolManager", &[], &[e!(IPoolManager::Swap)]);
        check(
            "PoolSwapTest",
            "PoolSwapTest",
            &[f!(IPoolSwapTest::swapCall)],
            &[],
        );

        // ENSv2 (the interfaces we call, as compiled from contracts/src/names/ENSv2.sol).
        check(
            "ENSv2",
            "IPermissionedResolver",
            &[
                f!(IPermissionedResolver::initializeCall),
                f!(IPermissionedResolver::setAddressCall),
                f!(IPermissionedResolver::setTextCall),
                f!(IPermissionedResolver::multicallCall),
                f!(IPermissionedResolver::grantSetterRolesCall),
            ],
            &[],
        );
        check(
            "ENSv2",
            "IVerifiableFactory",
            &[
                f!(IVerifiableFactory::deployProxyCall),
                f!(IVerifiableFactory::predictProxyAddressCall),
            ],
            &[],
        );
        check(
            "ENSv2",
            "IRegistry",
            &[
                f!(IEnsRegistry::registerCall),
                f!(IEnsRegistry::getResolverCall),
                f!(IEnsRegistry::findTokenIdCall),
                f!(IEnsRegistry::ownerOfCall),
            ],
            &[],
        );

        for (file, contract, event, want) in [
            (
                "FoodHook",
                "FoodHook",
                "TradeCounted",
                vec![true, false, false, false],
            ),
            (
                "MealCounter",
                "MealCounter",
                "MealEaten",
                vec![true, true, false, false, false, false],
            ),
            (
                "HousePool",
                "HousePool",
                "Paid",
                vec![true, true, true, false, false],
            ),
            (
                "CampaignEscrow",
                "CampaignEscrow",
                "Claimed",
                vec![true, true, true, false, false, false],
            ),
            (
                "CampaignEscrow",
                "CampaignEscrow",
                "Advanced",
                vec![true, true, true, false, false],
            ),
            (
                "CampaignEscrow",
                "CampaignEscrow",
                "Refunded",
                vec![true, true, false, false],
            ),
            (
                "CampaignEscrow",
                "CampaignEscrow",
                "CampaignCreated",
                vec![true, true, false, false, false],
            ),
            (
                "Farm",
                "Farm",
                "HarvestSold",
                vec![true, false, false, false],
            ),
            ("Treasury", "Treasury", "Split", vec![false; 5]),
            (
                "SpiceMerchant",
                "SpiceMerchant",
                "Delivered",
                vec![true, true, true, false, false],
            ),
            (
                "LuckyLedger",
                "LuckyLedger",
                "Committed",
                vec![true, false, false, false, false, false],
            ),
            (
                "LuckyLedger",
                "LuckyLedger",
                "Revealed",
                vec![true, false, false, false],
            ),
            (
                "LuckyLedger",
                "LuckyLedger",
                "DrawClaimed",
                vec![true, true, false],
            ),
            (
                "PoolManager",
                "PoolManager",
                "Swap",
                vec![true, true, false, false, false, false, false, false],
            ),
        ] {
            if let Some(got) = indexed_flags(file, contract, event) {
                assert_eq!(
                    got, want,
                    "{contract}.{event}: indexed parameters differ from bindings.rs"
                );
            }
        }
    }

    #[test]
    fn known_selectors() {
        // ENSv2 calls as contracts/src/names/ENSv2.sol declares them.
        assert_eq!(
            IPermissionedResolver::initializeCall::SIGNATURE,
            "initialize((address,uint256)[],bytes[])"
        );
        assert_eq!(
            IPermissionedResolver::grantSetterRolesCall::SIGNATURE,
            "grantSetterRoles(bytes,address)"
        );
        assert_eq!(
            IVerifiableFactory::deployProxyCall::SIGNATURE,
            "deployProxy(address,uint256,bytes)"
        );
        assert_eq!(
            ens::admin(ens::role(ens::ROLE_SET_TEXT)),
            alloy::primitives::U256::from(1u8) << 132usize
        );
        // Fixed by the ERC-20 standard and by the existing FoodHook / Uniswap v4 contracts.
        assert_eq!(IERC20::approveCall::SELECTOR, [0x09, 0x5e, 0xa7, 0xb3]);
        assert_eq!(IERC20::balanceOfCall::SELECTOR, [0x70, 0xa0, 0x82, 0x31]);
        assert_eq!(
            IUniversalRouter::executeCall::SELECTOR,
            [0x35, 0x93, 0x56, 0x4c]
        );
        assert_eq!(
            IPoolManager::Swap::SIGNATURE,
            "Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)"
        );
    }
}
