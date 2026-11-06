//! Tallyport's chain crate: connects the game server to Ethereum (Sepolia, or a local anvil). Build spec §3.3.
//!
//! - [`ChainLedger`]: the synchronous `Ledger` facade (`submit` enqueues, `poll` drains), backed by its own thread.
//! - [`WorldIdVerifier`]: the `HumanVerifier` for the Town Pass.
//! - [`types`]: this crate's mirror of the server's `Intent` / `Observation` / `HumanId`.
//!
//! Inside: [`wallets`] (server-held HD wallets), [`eip712`] (tickets and vouchers), [`plan`] (intent → transactions),
//! [`sender`] (per-key queues), [`exec`] (the executor), [`indexer`] (confirmed logs → observations), [`balances`].
//!
//! Wiring it into the server (the types serialize exactly like `rules::chain`'s, so a serde round trip maps them):
//!
//! ```ignore
//! let cfg = chain::ChainConfig::from_process_env(chain::Network::Anvil)?; // keys from the environment only
//! let mut ledger = chain::ChainLedger::start(cfg)?;  // checks the node's chain id, then runs on its own thread
//! ledger.submit(intent);                              // never blocks
//! for o in ledger.poll() {                           // confirmed, in (block, log_index) order
//!     hub.input(Input::Chain { block: o.block, log_index: o.log_index, time: o.time, observed: o.observed });
//! }
//! ```

pub mod balances;
pub mod bindings;
pub mod config;
pub mod deployments;
pub mod draw;
pub mod eip712;
pub mod exec;
pub mod gas;
pub mod indexer;
pub mod intents;
pub mod ledger;
pub mod plan;
pub mod revert;
pub mod rpc;
pub mod sender;
pub mod store;
pub mod types;
pub mod wallets;
pub mod worldid;

pub use config::{ChainConfig, Network};
pub use ledger::{ChainError, ChainLedger, ChainStatus};
pub use types::{
    AccountId, Bucket, HumanId, Intent, Observation, Observed, TicketRange, NOT_A_LOG,
};
pub use worldid::WorldIdVerifier;
