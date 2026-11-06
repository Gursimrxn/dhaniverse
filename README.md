# Dhaniverse

Dhaniverse is a 3D multiplayer economic life simulation. Players learn how money
works by earning, spending, saving and living in a shared town economy. USDC is
the only money in the game: there are no coins and no play money.

The town runs offline first, then against a local chain or Ethereum Sepolia.

## What is in the repository

| Path | What it is |
|---|---|
| `game/` | Godot 4.7 client: the town, people, HUD, market, bank, phone and paper screens |
| `server/` | Rust: pure rules, agents, the WebSocket/HTTP server, the chain integration and the runnable town binary |
| `contracts/` | Solidity with Foundry: the FOOD/USDC market, MealCounter, Farm, Treasury, HousePool, CampaignEscrow, FloatManager, quests and ENSv2 names |
| `web/` | Town Pass, sponsor console and live treasury dashboard |
| `services/publisher/` | Publishes the town's public data to Arkiv and its content to Swarm, and serves the read API |
| `arkiv/` | Arkiv schema, queries and integration notes |
| `docs/` | Technical plan, contract architecture, game design and runtime specifications |
| `tools/` | Build, test and export scripts |

## Quick start

The server runs without a chain, keys or an Arkiv account:

```bash
cd server
cargo run --release -p server -- --debug
```

Then open the game:

```bash
godot --path game
```

The server serves the web pages at `http://127.0.0.1:7878/console`,
`/dashboard` and `/verify`.

## Contracts

The contracts are Solidity 0.8.26 with Foundry. Initialise the pinned libraries
first:

```bash
git submodule update --init --recursive
cd contracts
forge test
```

`script/dev_chain.sh` starts a local anvil, places Uniswap v4 at its Sepolia
addresses, deploys the contracts and prints the environment the server needs.
`script/Deploy.s.sol` deploys the same set to Sepolia. Launch numbers live in
`deployments/<network>.config.json`; addresses written by a deploy live in
`deployments/<network>.json`.

The plain-English contract map is `docs/architecture/spec.json`; the readable
version is `docs/architecture/Contracts_Architecture.md`. CI checks that the
code and the spec agree. See `contracts/README.md` for the layout.

## Server

```bash
cd server
cargo test --workspace
cargo run --release -p server -- --debug
```

The default mode is offline. `--chain anvil` and `--chain sepolia` use the
chain integration; `server/DEPLOY.md` covers hosting, and `server/PROTOCOL.md`
lists every WebSocket message and HTTP endpoint. Secrets are environment
variables, never files or flags.

The chain binary is separate:

```bash
cargo run --release -p tallyport -- --chain sepolia
```

## Game

Godot 4.7.2 is the engine version. The project entry point is `game/project.godot`.

```bash
godot --path game
godot --headless --path game -s res://tests/run_tests.gd
```

The default world is the valley; the Old Quarter and the test scenes are opened
from their own scenes. The client connects to the server at the address in its
settings.

## Web and publisher

The server serves `web/` directly. `web/README.md` describes the pages, their
endpoints and the pinned browser libraries.

The publisher is a Node 24 sidecar with no build step:

```bash
cd services/publisher
npm ci
npm test
npm start
```

With no Arkiv key and no Bee node it runs as a no-op and says so. See
`services/publisher/README.md` and `arkiv/README.md`.

## Assets and Git LFS

Runtime models, textures, fonts, audio and UI art are in `game/assets`.
`.glb`, `.png`, `.jpg` and the other large binary formats are stored with Git
LFS:

```bash
git lfs install
git lfs pull
```

## Licence

- Code: MIT. See `LICENSE`.
- Original game assets: all rights reserved. See `ASSETS_LICENSE.md`.
- Third-party components and their licences: see `THIRD_PARTY.md`.

The MIT licence does not grant rights to the original art, audio, models or UI.

## Documentation

Start at `docs/README.md`. The technical plan is
`docs/planning/Dhaniverse_Technical_Plan.html`; the contract architecture and
machine-readable spec are in `docs/architecture/`.
