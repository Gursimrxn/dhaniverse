# Web3 audit: World ID and Uniswap

I checked both sponsor integrations against each sponsor's current official docs, read for this audit, not from
memory. I also made read-only calls to the real contracts on Sepolia and to World's verify API. No transaction was
sent and no key was read. Nothing is committed.

## Summary

| | State before | State now |
|---|---|---|
| World ID (Town Pass) | Already on World ID 4.0 / IDKit 4.6.0 (the latest). Five gaps in how proofs were checked. | Gaps fixed; app and RP ids configurable, the founder's as defaults; flow documented in `World_ID_Flow.md` |
| Uniswap v4 (Spice Run and FOOD market) | Addresses, call shapes and v4 patterns correct. The founder's "FOOD only in the game" rule wasn't implemented. | FOOD allowlist built, tested and wired into the deploy script, locked after deploy |
| Tests | Foundry not installed, contract libraries missing | forge **217 passed, 0 failed, 11 skipped** (ENS fork tests need `SEPOLIA_RPC_URL`); cargo workspace **all passed** (chain 64, server and rules suites, tallyport) |

---

## 1. World ID

### Docs read

- IDKit integration (steps 1 to 6): https://docs.world.org/world-id/idkit/integrate
- Verify API, `POST https://developer.world.org/api/v4/verify/{rp_id}`: https://docs.world.org/api-reference/developer-portal/verify
- RP signature algorithm and test vectors: https://docs.world.org/world-id/idkit/signatures
- Presets and request config (`proofOfHuman`, `allow_legacy_proofs`): https://docs.world.org/world-id/idkit/credentials
- 4.0 migration, legacy proofs and nullifiers: https://docs.world.org/world-id/4-0-migration
- `@worldcoin/idkit-core` on npm: latest is **4.6.0**, the version pinned in `web/verify.html`. I re-hashed the
  pinned file and the SRI hash matches. The global build sets `globalThis.IDKit` with `request` and `proofOfHuman`,
  as `web/js/verify.js` uses them.

### Checked end to end

- The one-time link (`hub.rs` `town_pass` and `VerifyDesk`): 15 minutes, single use, needs a wallet and refuses
  someone who already has the pass.
- `GET /verify/session`: signs a fresh RP context per call. The server's message layout and EIP-191 signature match
  World's algorithm byte for byte. A new test reproduces World's published signature vector exactly.
- Proof verification (`chain/src/worldid.rs`): forwards the IDKit result unchanged to the v4 endpoint, as World's docs
  say, and checks `success`, `environment` and the nullifier.
- Nullifier uniqueness per action: `rules::State::verify_human` keeps nullifier → player in the replayed state and
  refuses `HumanTaken` and `AlreadyHuman`. `rules/tests/games.rs::one_world_id_holds_one_player` covers it.
- After `HumanVerified`: `RegisterName` (ENS), the Town Pass quest step, `retry_owed` (pays what's held) and the
  referral check, all in `human.rs`.
- The founder's values, checked live against `developer.world.org` with a dummy proof (harmless):
  `rp_f24fbbc28154fb5c` and `app_eca8340a4f71973c608bbaa31a7af47e` are both registered and migrated to 4.0. The API
  ran the proof check for both. An unknown RP id answers `app_not_migrated`.

### Bugs found and fixed

1. **Legacy 3.0 proofs were always on** (`allow_legacy_proofs: true`, hard-coded in `tallyport/src/lib.rs`, with the
   page defaulting to true). World's docs: with legacy proofs on you must "track both v3 and v4 nullifiers to prevent
   double-claims". The two can't be linked, so one person could hold two players: one with a 3.0 proof, one after
   upgrading to 4.0. Now off by default (`WORLD_ALLOW_LEGACY_PROOFS`). The server enforces it too: a `3.0` result is
   refused, so a hand-made POST can't get around the page.
2. **A result with no `action` was accepted.** The check only ran when `action` was present. Now the action is
   required and must match.
3. **No check of the result's own `environment` before verifying.** World's docs ask for one. Added: a staging proof
   never reaches the API on a production server.
4. **Session proofs weren't explicitly refused.** Every response must now carry a `nullifier`, not a
   `session_nullifier`. The verify API's `action`, when it returns one, must match too.
5. **App id and RP id:** the RP id fell back only to `WORLD_APP_ID`, and the `--world-app-id` flag reached the pages
   but not the verifier. Now `WORLD_APP_ID` / `WORLD_RP_ID` / `WORLD_ACTION` come from the environment with the
   founder's values as defaults. New flag `--world-rp-id`. Both flags override the environment in the chain binary
   (`app.rs`, `tallyport/src/lib.rs`, `chain/src/config.rs`).

Already correct, so I left them alone: signal binding to the wallet (all three IDKit encodings of an address), the
single-use nonce bound to the wallet with a 300 s TTL, the single-use link token, nullifier normalisation (32-byte
lowercase hex), and the verify endpoint and its error mapping.

### Godot gate

The API already supports starting verification right after `ClaimName`, once `you.wallet` is set (`TownPass` →
`result.url` → token). For the web build there's one catch. The server doesn't answer CORS preflight, so the embedded
IDKit must POST `/verify` with `Content-Type: text/plain` (the body is still JSON). The exact flow, payloads and
errors are in `docs/planning/World_ID_Flow.md`.

### Tests added (cargo)

- `worldid::rp_signature_matches_worlds_published_vector`
- `worldid::only_4_0_uniqueness_proofs_for_our_action_and_environment_count`: refuses 3.0 by default, unknown
  versions, a missing action, an environment mismatch and a session-proof shape, none of which reaches the API; takes
  3.0 when the operator allows it.
- `config::world_id_defaults_to_the_founders_app_and_is_4_0_only`
- `rp_signature_matches_cast` now runs for real, since `cast` is installed, and passes.

---

## 2. Uniswap v4

### Docs read

- Deployments (Sepolia 11155111): https://developers.uniswap.org/contracts/v4/deployments (docs.uniswap.org now
  redirects there).
- Swap quickstart (Universal Router, `V4_SWAP`, `SWAP_EXACT_IN_SINGLE` / `SETTLE_ALL` / `TAKE_ALL`, Permit2):
  https://developers.uniswap.org/contracts/v4/quickstart/swap
- v4-periphery `IV4Router` (main): https://github.com/Uniswap/v4-periphery/blob/main/src/interfaces/IV4Router.sol
- Universal Router releases (2.0.0, 2.1.1, 2.1.2, 2.2.0): https://github.com/Uniswap/universal-router/releases

### Addresses: all match the official page and answer on chain

| Contract | Address (`contracts/deployments/sepolia.config.json`) | On-chain check (eth_call) |
|---|---|---|
| PoolManager | 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543 | code 24,009 B |
| Universal Router (2.0) | 0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b | code 19,540 B |
| PositionManager | 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4 | `poolManager()` = PoolManager, `permit2()` = Permit2 |
| StateView | 0xe1dd9c3fa50edb962e442f60dfbc432e24537e4c | `poolManager()` = PoolManager; `getSlot0` on the live ETH/USDC 0.3% pool works |
| V4Quoter | 0x68aFa8b853cAa7a2D40B0F6AEE5C4DbC147C8244 | `poolManager()` = PoolManager; `quoteExactInputSingle(((c0,c1,fee,ts,hooks),zeroForOne,exactAmount,hookData))` returns `(amountOut, gasEstimate)`, the shape the server uses |
| Permit2 | 0x000000000022D473030F116dDEE9F6B43aC78BA3 | code 9,152 B |
| USDC (Circle) | 0x1c7d4b196cb0c7b01d743fbc6116a902379c7238 | `symbol` USDC, 6 decimals |

### Checked, and correct as written

- **Hook flags and address mining:** FoodHook uses `beforeInitialize`, `beforeAddLiquidity`, `beforeSwap` and
  `afterSwap`. `Deploy.s.sol` mines a CREATE2 salt through `0x4e59…956C` so that the low 14 bits equal those flags
  exactly, and the constructor calls `Hooks.validateHookPermissions`. Proved on a throwaway local anvil with
  Uniswap's Sepolia bytecode: the full deploy runs.
- **Router-only:** `beforeSwap` and `beforeAddLiquidity` refuse any `sender` but FoodRouter. `beforeInitialize`
  allows only the admin, one pool, and a starting price inside the floor and ceiling.
- **unlock and callback:** `unlockCallback` refuses any caller but the PoolManager.
- **Delta settlement:** `sync` → `transferFrom` → `settle` for debts, and `take` for credits. This is the documented
  v4 order.
- **Sign convention:** a buy is exact output (positive `amountSpecified`), a sale exact input.
- **sqrtPriceLimit:** today's band edge in the trade's direction. `_atLimit` stops a call when the price already sits
  there, so v4's `PriceLimitAlreadyExceeded` can't fire.
- **Meals:** bought at the live pool price, with the rest from the ration shop at band-high, then burned.
- **Spice Run swap:** Universal Router `V4_SWAP` with `SWAP_EXACT_IN_SINGLE`, `SETTLE_ALL` and `TAKE_ALL`. The
  5-field `ExactInputSingleParams` matches the documented quickstart and the deployed 2.0 router. QuestPool.t.sol runs
  it against that router's own bytecode.
- **Permit2:** USDC `approve(Permit2, max)`, then `Permit2.approve(router, max, now + 30 days)`, renewed when it
  expires before the deadline. This is the AllowanceTransfer pattern.
- **Quotes:** V4Quoter by `eth_call`. A swap needs a quote under 60 s old and takes at least the quote less 1%
  (`rules.toml`: `quote_fresh_ms 60000`, `slippage_bps 100`, `quote_every_ms 15000`). `min_out` always goes on chain
  as `amountOutMinimum`.
- **Swap attribution:** the v4 `Swap` event's `sender` is the router, so the indexer attributes by the transaction's
  `from`. It reads amounts from the swapper's side (v4 convention). Both are right.

### Bugs and gaps found, and fixed

1. **The founder's rule wasn't implemented: FOOD was a plain ERC-20.** `FoodToken` now has a both-sides transfer
   allowlist:
   - Members: the PoolManager, FoodRouter, Farm, MealCounter and the holder (the admin).
   - The holder sets it once. `lockAllowlist()` then freezes it forever.
   - Mint (deploy only) and burn are the only exceptions.
   - `Deploy.s.sol` adds the members and locks the list. On a local deploy: `allowlistLocked = true`, all five allowed,
     a stranger not.
   - `docs/architecture/spec.json` updated to match.
2. **A trap for later, documented in `bindings.rs`.** Uniswap's Sepolia list also has Universal Router 2.1.1 / 2.1.2
   / 2.2.0. 2.1.1 changed the swap encoding (per-hop `minHopPriceX36`), and v4-periphery main has a 6-field
   `ExactInputSingleParams`. The 2.0 address is the right one for today's 5-field encoding. Switching addresses means
   changing the struct.

Naming nit, not changed: `fee_bps` in the quote protocol actually carries Uniswap's fee in pips (3000 = 0.30%). It's
consistent across server, offline and client, and documented in `rules/src/chain.rs`.

### Tests added (forge): `test/food/FoodLockdown.t.sol`, 12 tests, all passing

- The allowlist holds exactly the game's contracts and is locked. It can't be changed after the lock, and only the
  holder can set it.
- An outsider can't receive FOOD, and `transferFrom` to an outsider fails. FOOD forced onto an outsider (test cheat)
  can't move.
- A PoolManager `take` to an outsider reverts with the allowlist's own error.
- An outsider can't swap in our pool, call the router, or seed a second, hookless FOOD/USDC pool.
- A harvest sale still works under the lock. Meals, the ration shop, forged, expired and reused tickets are covered
  by the existing MealCounter suite, which now runs on the locked token.

Existing kits updated: `TownWorld` deploys and locks like production. `FoodWorld` allowlists its test keys.

### What the allowlist does not stop (by design)

- The admin key is on the list, as the design doc says. A malicious admin could seed a second pool from its own FOOD.
  Hand the admin to a multisig after the demo, as `spec.json` already asks.
- After the lock, a new FoodRouter can't join the list. Replacing the router now means a new FOOD token. That's the
  price of "nothing anyone can change".

---

## 3. Tooling

- Foundry stable installed to `D:\foundry\bin` (forge, cast, anvil, chisel). It's the official Windows release zip, so
  no shell profile was edited and nothing went on C:.
- The contract submodules (forge-std v1.17.0, OpenZeppelin v5.7.0, v4-core v4.0.0, and v4-core's solmate) were empty.
  I initialised them at their pinned revisions.
- **forge test: 217 passed, 0 failed, 11 skipped.** 205 before this work. The 11 skipped are ENS fork tests that need
  `SEPOLIA_RPC_URL`.
- **cargo test --workspace** (`CARGO_TARGET_DIR=D:/pbuild-web3`, gnu toolchain): every suite passes, including chain
  (64), server, rules and tallyport.
- `forge lint -D warnings src` has 42 warnings, none in FoodToken; they were there before (modifier-wrapping style
  elsewhere). `forge fmt --check` is clean on the new files. The old files are CRLF, so fmt flags them all.
- I couldn't regenerate `docs/architecture/Contracts_Architecture.md`: python isn't runnable here. Run
  `docs/architecture/build_docs.py` once.
- D: is nearly full (about 5 GB free after the builds).
- Another agent's commit (`33ca4b4`, docs(arkiv)) swept in my `spec.json` edit. The content is right, but it sits in
  their commit.

## 4. What still needs the founder

1. **World ID keys:** set `RP_SIGNING_KEY` (Developer Portal → the app → RP signing key) in the server's gitignored
   env. Without it, World ID stays off: the Town Pass is closed, or rehearsal-only with `--debug`.
2. **The action:** confirm that action `tallyport-town-pass` exists for app `app_eca8…` in the Developer Portal as a
   4.0 action, with one verification per person. If it has another name, set `WORLD_ACTION`. I couldn't confirm the
   action from outside.
3. **Legacy proofs:** decide whether to allow 3.0 proofs (`WORLD_ALLOW_LEGACY_PROOFS=true`). That lets in people who
   haven't upgraded the World App, at the cost of the two-player loophole above. It's off by default. For a demo with
   the simulator, use `WORLD_ENVIRONMENT=staging`.
4. **Funding:** Sepolia ETH for the deployer, keeper, gas station and names key. Circle test USDC
   (faucet.circle.com) for the deployer: `poolUsdc` + campaign budget + vault drip + house seeds, per
   `sepolia.config.json`.
5. **Deploy:** run `script/Deploy.s.sol` on Sepolia. It now sets and locks FOOD's allowlist. Then run
   `script/names/CityNames.s.sol`, then hand admin roles to a multisig. Not done here: no transactions were sent.
6. **Public URL:** run the server with a public HTTPS `--public-url`, so Town Pass links work from a phone.
