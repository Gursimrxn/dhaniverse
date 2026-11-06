//! `tallyport`: the town server, offline or on a chain. Same flags as `server` (see `--help`), plus:
//!
//! - `--chain anvil|sepolia` (or `CHAIN_MODE`) settles on that chain through the `chain` crate. Keys, RPC and World ID
//!   come from the environment only (see `chain::config`); `--deployments` (or `CHAIN_DEPLOYMENTS`) names the
//!   deployments file; the chain's data dir defaults to `<save>.chain-<network>/` beside the save.
//! - `--chain offline` (the default) is exactly the `server` binary.

use server::app::{self, USAGE};
use server::hub::Links;

fn main() {
    if let Err(problem) = run() {
        eprintln!("tallyport stopped: {problem}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let Some(config) = app::parse_args(&args)? else {
        println!(
            "{}",
            USAGE.replacen(
                "server [flags]",
                "tallyport [flags]  (--chain offline|anvil|sepolia)",
                1
            )
        );
        return Ok(());
    };
    match tallyport::network(config.chain) {
        None => {
            let debug = config.debug;
            app::run(config, |world, _, public_url| {
                Links::offline(world, debug, public_url)
            })
        }
        Some(network) => {
            let chain = tallyport::chain_config(&config, network)?;
            let mut config = config;
            if config.http.deployments.is_none() {
                config.http.deployments = Some(chain.deployments_path.clone());
            }
            println!(
                "chain: {} (chain id {}), deployments {}, data {}",
                network.name(),
                chain.chain_id,
                chain.deployments_path.display(),
                chain.data_dir.display()
            );
            app::run(config, move |world, cfg, public_url| {
                tallyport::chain_links(world, cfg, public_url, chain)
            })
        }
    }
}
