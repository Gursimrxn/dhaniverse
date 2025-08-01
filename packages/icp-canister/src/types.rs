use candid::{CandidType, Deserialize};
use serde::Serialize;
use std::collections::HashMap;

// Wallet Types
#[derive(CandidType, Deserialize, Serialize, Clone, Debug, PartialEq)]
pub enum WalletType {
    MetaMask,
    Phantom,
    Coinbase,
    WalletConnect,
    Injected,
}

#[derive(CandidType, Deserialize, Serialize, Clone, Debug)]
pub struct WalletConnection {
    pub address: String,
    pub chain_id: String,
    pub wallet_type: WalletType,
    pub balance: Option<String>,
}

#[derive(CandidType, Deserialize, Serialize, Clone, Debug)]
pub struct WalletInfo {
    pub name: String,
    pub wallet_type: WalletType,
    pub icon: String,
    pub installed: bool,
    pub download_url: Option<String>,
}

#[derive(CandidType, Deserialize, Serialize, Clone, Debug)]
pub struct WalletStatus {
    pub connected: bool,
    pub address: Option<String>,
    pub wallet_type: Option<WalletType>,
    pub error: Option<String>,
    pub is_connecting: Option<bool>,
    pub balance: Option<String>,
}

// Banking Types
#[derive(CandidType, Deserialize, Serialize, Clone, Debug)]
pub struct DualBalance {
    pub rupees_balance: f64,
    pub token_balance: f64,
    pub last_updated: u64,
}

#[derive(CandidType, Deserialize, Serialize, Clone, Debug, PartialEq)]
pub enum StakingStatus {
    Active,
    Matured,
    Claimed,
}

#[derive(CandidType, Deserialize, Serialize, Clone, Debug)]
pub struct StakingPool {
    pub id: String,
    pub staked_amount: f64,
    pub apy: f64,
    pub start_date: u64,
    pub maturity_date: u64,
    pub current_rewards: f64,
    pub status: StakingStatus,
}

#[derive(CandidType, Deserialize, Serialize, Clone, Debug)]
pub struct ExchangeResult {
    pub success: bool,
    pub from_amount: f64,
    pub to_amount: f64,
    pub rate: f64,
    pub transaction: Option<Web3Transaction>,
    pub error: Option<String>,
}

// Achievement Types
#[derive(CandidType, Deserialize, Serialize, Clone, Debug, PartialEq)]
pub enum AchievementCategory {
    Trading,
    Saving,
    Staking,
    Learning,
}

#[derive(CandidType, Deserialize, Serialize, Clone, Debug, PartialEq)]
pub enum AchievementRarity {
    Common,
    Rare,
    Epic,
    Legendary,
}

#[derive(CandidType, Deserialize, Serialize, Clone, Debug)]
pub struct AchievementReward {
    pub reward_type: String, // "rupees" or "tokens"
    pub amount: f64,
}

#[derive(CandidType, Deserialize, Serialize, Clone, Debug)]
pub struct Achievement {
    pub id: String,
    pub title: String,
    pub description: String,
    pub category: AchievementCategory,
    pub rarity: AchievementRarity,
    pub unlocked: bool,
    pub unlocked_at: Option<u64>,
    pub reward: Option<AchievementReward>,
}

// Transaction Types
#[derive(CandidType, Deserialize, Serialize, Clone, Debug, PartialEq)]
pub enum TransactionType {
    Deposit,
    Withdraw,
    Exchange,
    Stake,
}

#[derive(CandidType, Deserialize, Serialize, Clone, Debug, PartialEq)]
pub enum TransactionStatus {
    Pending,
    Confirmed,
    Failed,
}

#[derive(CandidType, Deserialize, Serialize, Clone, Debug)]
pub struct Web3Transaction {
    pub id: String,
    pub from: String,
    pub to: Option<String>,
    pub amount: f64,
    pub transaction_type: TransactionType,
    pub timestamp: u64,
    pub status: TransactionStatus,
    pub hash: Option<String>,
}

// Authentication Types
#[derive(CandidType, Deserialize, Serialize, Clone, Debug)]
pub struct Web3Session {
    pub wallet_address: String,
    pub wallet_type: WalletType,
    pub chain_id: String,
    pub connected_at: u64,
    pub last_activity: u64,
}

#[derive(CandidType, Deserialize, Serialize, Clone, Debug)]
pub struct User {
    pub id: String,
    pub email: Option<String>,
    pub game_username: String,
    pub wallet_address: Option<String>,
    pub auth_method: String, // "email", "google", "web3"
    pub created_at: u64,
    pub updated_at: u64,
}

#[derive(CandidType, Deserialize, Serialize, Clone, Debug)]
pub struct AuthResult {
    pub success: bool,
    pub user: Option<User>,
    pub token: Option<String>,
    pub is_new_user: Option<bool>,
    pub error: Option<String>,
}

#[derive(CandidType, Deserialize, Serialize, Clone, Debug)]
pub struct Web3AuthRequest {
    pub wallet_address: String,
    pub signature: String,
    pub message: String,
    pub timestamp: u64,
}

// State Management Types
#[derive(CandidType, Deserialize, Serialize, Clone, Debug, Default)]
pub struct CanisterState {
    pub users: HashMap<String, UserData>,
    pub sessions: HashMap<String, Web3Session>,
    pub wallet_connections: HashMap<String, WalletConnection>,
    pub global_settings: GlobalSettings,
}

#[derive(CandidType, Deserialize, Serialize, Clone, Debug)]
pub struct UserData {
    pub wallet_address: String,
    pub dual_balance: DualBalance,
    pub staking_pools: Vec<StakingPool>,
    pub achievements: Vec<Achievement>,
    pub transactions: Vec<Web3Transaction>,
    pub created_at: u64,
    pub last_activity: u64,
}

#[derive(CandidType, Deserialize, Serialize, Clone, Debug)]
pub struct GlobalSettings {
    pub exchange_rate: f64, // 1 Rupee = 0.1 Token
    pub staking_apys: HashMap<u32, f64>, // Duration -> APY mapping
    pub achievement_definitions: Vec<Achievement>,
    pub session_timeout: u64, // in nanoseconds
}

impl Default for GlobalSettings {
    fn default() -> Self {
        let mut staking_apys = HashMap::new();
        staking_apys.insert(30, 5.0);  // 30 days -> 5% APY
        staking_apys.insert(90, 7.0);  // 90 days -> 7% APY
        staking_apys.insert(180, 10.0); // 180 days -> 10% APY

        Self {
            exchange_rate: 0.1,
            staking_apys,
            achievement_definitions: Vec::new(),
            session_timeout: 24 * 60 * 60 * 1_000_000_000, // 24 hours in nanoseconds
        }
    }
}

impl UserData {
    pub fn new(wallet_address: String) -> Self {
        let now = ic_cdk::api::time();
        Self {
            wallet_address,
            dual_balance: DualBalance {
                rupees_balance: 25000.0, // Starting balance
                token_balance: 0.0,
                last_updated: now,
            },
            staking_pools: Vec::new(),
            achievements: Vec::new(),
            transactions: Vec::new(),
            created_at: now,
            last_activity: now,
        }
    }
}

// Utility functions for type conversions
impl From<&str> for WalletType {
    fn from(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "metamask" => WalletType::MetaMask,
            "phantom" => WalletType::Phantom,
            "coinbase" => WalletType::Coinbase,
            "walletconnect" => WalletType::WalletConnect,
            _ => WalletType::Injected,
        }
    }
}

impl From<&str> for TransactionType {
    fn from(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "deposit" => TransactionType::Deposit,
            "withdraw" => TransactionType::Withdraw,
            "exchange" => TransactionType::Exchange,
            "stake" => TransactionType::Stake,
            _ => TransactionType::Deposit,
        }
    }
}

impl From<&str> for AchievementCategory {
    fn from(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "trading" => AchievementCategory::Trading,
            "saving" => AchievementCategory::Saving,
            "staking" => AchievementCategory::Staking,
            "learning" => AchievementCategory::Learning,
            _ => AchievementCategory::Trading,
        }
    }
}

impl From<&str> for AchievementRarity {
    fn from(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "common" => AchievementRarity::Common,
            "rare" => AchievementRarity::Rare,
            "epic" => AchievementRarity::Epic,
            "legendary" => AchievementRarity::Legendary,
            _ => AchievementRarity::Common,
        }
    }
}