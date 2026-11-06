# Dhaniverse web pages

Three static pages, plain HTML/CSS/ES modules, no build step. The game server serves this folder.

| Page | Served at | What it does |
|---|---|---|
| `verify.html` | `GET /verify?token=…` | Town Pass: World ID (IDKit 4) proof of human, signal = the player's wallet, posted to `POST /verify`. |
| `console.html` | `GET /console` | Sponsor console: connect a wallet, design a campaign under the escrow's rules (25% rule, minimum payout, fee), store its story on Swarm, approve USDC, `createCampaign`; list your campaigns with live stats; cancel and refund. |
| `dashboard.html` | `GET /dashboard` | The money flow as live boxes: escrow → float → yield, meals → food pool → farm → treasury split, house buckets → players. `/city` + chain reads, every 10 s. |

Every other path in this folder (`css/`, `js/`, `abi/`, `fonts/`) is requested relative to the page, so the server must
serve `web/<path>` at `/<path>` (e.g. `/js/core.js` → `web/js/core.js`) with the right `Content-Type`
(`.js` → `text/javascript`, `.otf` → `font/otf`). `web/dev/` and `web/tools/` must **not** be served.

## Endpoints the pages use (same origin)

All amounts are USDC base units (integers; JSON numbers or decimal strings both work). Missing fields render as "—".

- `GET /deployments.json` → `contracts/deployments/<network>.json` as written by the deploy script, plus
  `"rpcUrl"`: a public, keyless read RPC for the browser (optional; else viem's default for the chain).
- `GET /city` → the public view. Fields read: `chain`, `world_app_id`, `bounty[]`, `house`, `treasury`, `float`,
  `food`, `draw` (shapes in the agent report and `dev/city.json`).
- `GET /verify/session?token=T` → `{player, wallet, app_id, action, environment, allow_legacy_proofs,
  rp_context:{rp_id, nonce, created_at, expires_at, signature}, expires_at, verified, rehearsal, human_id?, ens?}`;
  `410 {error:"token_expired"}` / `404` for bad tokens. Called again when the RP signature is about to expire.
- `POST /verify` with `{token, result}` (`result` = IDKit's completion result, or `{offline:true}` for a rehearsal)
  → `200 {ok:true, human_id, ens?, rehearsal?}` or `4xx {ok:false, error, message}` (`error` codes:
  `already_verified`, `token_expired`, `token_used`, `invalid_proof`).
- `POST /swarm/campaign-bundle` (proxied to the publisher) — multipart `story` (JSON: title, story, sponsor, template)
  + `image` → `201 {reference, metaHash}`.

## Libraries (pinned)

- viem 2.57.10 via `https://esm.sh/viem@2.57.10?bundle` (import map in console/dashboard).
- World ID IDKit core 4.6.0 browser global: `https://unpkg.com/@worldcoin/idkit-core@4.6.0/dist/idkit.global.js` (SRI).
- qrcode-generator 2.0.4: `https://unpkg.com/qrcode-generator@2.0.4/dist/qrcode.mjs`.
- Fonts: Instrument Serif, Instrument Sans, JetBrains Mono (Google Fonts); Satoshi Bold self-hosted in `fonts/`
  (Fontshare free licence).

## ABIs

`abi/*.js` are generated: `node web/tools/sync-abi.mjs` after `forge build` (`--check` fails if stale). Contracts not
built yet fall back to the build spec's signatures (marked `source = "spec"`); the pages read optional views
tolerantly and fall back to `/city` numbers, labelled by source.

## Checking locally (dev fixture only)

```sh
node web/dev/serve.mjs                       # /city from web/dev/city.json, /deployments.json → 404
DEV_DEPLOYMENTS=1 node web/dev/serve.mjs     # also web/dev/deployments.json (Sepolia, Circle USDC only)
```

Open `http://127.0.0.1:8099/dashboard`, `/console`, `/verify?token=demo` (IDKit staging), `?token=rehearsal`,
`?token=expired`, `?token=done`. Everything under `dev/` is made-up data for this check and is never used in production.
