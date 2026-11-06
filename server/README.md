# Dhaniverse server

The city's rules and the live server, in Rust. The server decides what happened, Godot shows it, and the chain settles
the money. USDC is the only money.

```
crates/rules    pure rules: apply(state, role, command) returns events or a named refusal. Energy, meals, Market Rush,
                quests, chests, streaks, the draw, rescue meals, and mirrors of the house pool and the campaigns
crates/agents   Kofi the farm, the residents, the mentor and The Tally, all sending commands through the rules
crates/server   WebSocket and HTTP, the event log, the clocks, and the Ledger and HumanVerifier seams to the chain
crates/chain    the chain: wallets, EIP-712, the executor and indexer, World ID. Implements the seams
DEPLOY.md       how to host a town
rules.toml      every tunable number, in one file
quests.toml     every quest's words: titles, stories, steps
PROTOCOL.md     the messages Godot sends and receives, and the HTTP endpoints
```

## How the money moves

The rules never touch money. When something should happen on chain (a meal bought, a reward paid, a quest's claim), the
rules emit an `Intent` event, which the save logs like any other. The hub hands it to the `Ledger`. What the chain did
comes back from the `Ledger` as an `Observation`, which enters the world as a logged `Input::Chain`, so a replay of the
save sees the chain exactly as it was and rebuilds the same world.

```rust
pub trait Ledger: Send {
    fn submit(&mut self, intent: Intent);   // never blocks; idempotent by the intent's ref
    fn poll(&mut self) -> Vec<Observed>;    // what the chain did, confirmed, in block order
}
pub trait HumanVerifier: Send + Sync {
    fn verify(&self, player_wallet: &str, proof: &Value) -> Result<HumanId, String>;
    fn session_context(&self, player: &str, player_wallet: &str) -> Result<Value, String>;
    fn app_id(&self) -> Option<String> { None }
}
```

Both are in `server::ledger`, with the words (`Intent`, `Observation`, `Observed`, `Bucket`, `HumanId`) re-exported from
`rules::chain`. **Offline** (`--chain offline`, the default, for tests and for playing without keys), `OfflineLedger`
plays the contracts' money rules in memory (HousePool's 4% daily budget and per-human cap, the Treasury's split,
CampaignEscrow's 25% rule, slots, caps and advances, the kiosk's swap, names and records, the draw), and `OfflineVerifier`
takes a rehearsal proof on a `--debug` server. Offline, food is bought and sold in the town's own pool. On **anvil** or
**Sepolia** the `chain` crate's binary calls `server::app::run` with its own `Links`; this binary refuses to start
anything but offline.

Rewards are never promised past the pool: each kind of reward has a share of its bucket's day budget, nothing is sent
past what the chain says the bucket may still pay today, and a reward for someone without the Town Pass is held, owed,
and paid with its own ref when they get it.

## Building on this machine

This machine has no MSVC `link.exe`, so the default Rust toolchain can't link. Use the GNU one, from `server/`:

```bash
RUSTUP_TOOLCHAIN=stable-x86_64-pc-windows-gnu cargo test --workspace
```

In PowerShell, set it first:

```powershell
$env:RUSTUP_TOOLCHAIN='stable-x86_64-pc-windows-gnu'
```

It isn't pinned in the repo, because that would break macOS and Linux. On a machine with a working default toolchain,
plain `cargo` is fine.

Build output goes wherever `CARGO_TARGET_DIR` points. On this machine that's `D:\pbuild`, shared with other projects,
so there's no `server/target`. The `Cargo.toml` profiles keep debug info small because D: is short on space.

## Running

```bash
RUSTUP_TOOLCHAIN=stable-x86_64-pc-windows-gnu cargo run -p server --release -- --debug
```

| Flag | Default | Meaning |
|---|---|---|
| `--config` | none | Read these settings from a TOML file (`addr = "…"`, `publisher_url = "…"`, …); flags win. Never put a secret in it |
| `--addr` | `127.0.0.1:7878` | Where to listen, this machine only by default. `0.0.0.0:7878` lets other machines join (see below). Port 0 picks a free one and prints it |
| `--save` | `save.jsonl` | The save. Created if it's missing |
| `--rules` | `rules.toml` | Used only when starting a new save |
| `--quests` | `quests.toml` | The quest book, used only when starting a new save. The built-in copy if the file's missing |
| `--seed` | `1` | The city's seed, for a new save |
| `--chain` | `offline` (or `CHAIN_MODE`) | `offline`, `anvil` or `sepolia`. Kept in the save: a save settles where it always did |
| `--deployments` | none | `contracts/deployments/<network>.json`, served to the pages as `/deployments.json` |
| `--publisher-url` | `PUBLISHER_URL`, else `http://127.0.0.1:8787` | The Arkiv/Swarm publisher sidecar, for `/arkiv/campaigns` and `/swarm/campaign-bundle` |
| `--web` | `../web` if it's there | The web pages: `verify.html`, `console.html`, `dashboard.html` and their files. `web/dev` and `web/tools` are never served |
| `--public-url` | `PUBLIC_URL`, else `http://<addr>` | How browsers reach this server, for Town Pass links. Behind a proxy, its `https://` address |
| `--public-rpc-url` | `PUBLIC_RPC_URL` | A keyless read RPC the pages may use |
| `--world-app-id` | `WORLD_APP_ID` | The World ID app id the pages show |
| `--debug` | off | Allows the rehearsal commands in PROTOCOL.md, and the offline Town Pass |
| `--speed` | `1` | Runs the clock faster. Needs `--debug` |
| `--heartbeat-ms` | `5000` | How often the clock moves. 0 stops it, so only skips move time |
| `--behind-proxy` | off | Rate-limit by `X-Forwarded-For`. Only for use behind a TLS proxy |
| `--new-if-incompatible` | off | If the save won't replay, move it to `<save>.old-<timestamp>` and start a new city, instead of stopping |

Secrets (wallet seed, signing keys, RPC keys) are environment variables read by the chain crate, never flags, files or
the save.

**To rehearse:** start with `--debug`. From the client: `Fund` puts USDC in your wallet, `PassTown` gives you the Town
Pass, `FundBucket` fills a house bucket, `NewCampaign` opens a campaign, `ReadyChest` readies your chest, `Skip` moves
time (a day closes the Rush pot; a week, the draw), and `NextSeason` starts a season. The offline ledger opens the
campaigns in `rules.toml`'s `[[offline.campaigns]]` when a new city starts, so the Bounty Board has cards at once.

**To start a new city:** point `--save` at a new file, or delete the old one.

**To play across machines:** on one laptop, run with `--addr 0.0.0.0:7878`. It may need letting through Windows Firewall. Others connect to `ws://<that laptop's address>:7878`, which `ipconfig` shows. This is plain WebSocket with no encryption, so use it only on a network you trust.

**To host it:** listen on `127.0.0.1` with `--behind-proxy` and `--public-url https://town.example.com`, and put a TLS
proxy in front, so players connect over `wss://` and secrets aren't sent in the clear. With Caddy, this is the whole
config:

```
town.example.com {
    reverse_proxy 127.0.0.1:7878
}
```

`--behind-proxy` makes the rate limits count the address in `X-Forwarded-For`, the last one, which the proxy added. Don't use it without a proxy, because then a client could write that header itself. The limits are in `crates/server/src/limits.rs`.

**A save keeps what it started with,** inside its first line: the rules, the quest book, the seed, the chain mode and
its town id, so
editing `rules.toml` or `quests.toml` changes new cities only. If the code's rules or agents have changed since a save
was written, it refuses to load and says which line replays differently, unless `--new-if-incompatible` is on. The old
file is never deleted. There's no migration: a save from older code (protocol 2's included) can't be carried forward.

## The save

One append-only file of JSON lines: the setup, then each input with the events it caused. Inputs are player commands,
connects, disconnects, time passing, World ID's answers and what the chain did. Intents for the chain are events, so
they're in the save too, and after a restart everything still owed an answer is sent again; each is idempotent by its
ref. On the chain every ref carries the town id, a random 8-byte hex chosen when the save is made (`<town_id>:<ref>`;
draw weeks carry its first 32 bits), so several saves can share one chain without mixing up their refs, and what the
chain says about another town's refs is ignored. Clients only ever see the plain refs. Agents aren't logged, because they're worked out again from the seed and the state. Starting up replays every line
and checks it still causes the same events.

Time since the last heartbeat isn't saved, so a crash loses at most one heartbeat of clock. Half a line left by a crash
is dropped. Nothing else is ever rewritten. Town Pass links and the offline ledger aren't saved: links are asked for
again, and the offline ledger is rebuilt from what the world saw.

## Tests

`cargo test --workspace` covers the rules (`crates/rules/tests`: the food market, a player's day, quests, chests and the
draw, and the money invariants), the clock and agents (`crates/server/tests/city.rs`), rebuilding from the log
(`replay.rs`), whole flows against the offline ledger with a save full of chain observations (`flows.rs`), privacy
(`privacy.rs`, `public_view.rs` and the feed's own tests), and a real client against the real binary (`headless.rs`,
`v3.rs` and the rest). To read the headless client's transcript:

```bash
RUSTUP_TOOLCHAIN=stable-x86_64-pc-windows-gnu cargo test -p server --test headless -- --nocapture --test-threads=1
```
