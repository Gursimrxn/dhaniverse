//! Runs an offline town. See README.md for the flags. Anvil and Sepolia run from the tallyport binary (crates/tallyport), which calls
//! `server::app::run` with its own ledger.

use server::app::{self, USAGE};
use server::hub::Links;

fn main() {
    if let Err(problem) = run() {
        eprintln!("server stopped: {problem}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let Some(config) = app::parse_args(&args)? else {
        println!("{USAGE}");
        return Ok(());
    };
    if config.chain.on_chain() {
        return Err(format!(
            "this binary settles offline only; a {} town runs from the tallyport binary (cargo run -p tallyport), \
             which wires its Ledger into server::app::run",
            config.chain.name()
        ));
    }
    let debug = config.debug;
    app::run(config, |world, _, public_url| {
        Links::offline(world, debug, public_url)
    })
}
