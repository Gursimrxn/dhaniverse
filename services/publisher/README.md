# Dhaniverse publisher

A sidecar that puts Dhaniverse's **public** data on [Arkiv](https://docs.arkiv.network) and its content on
[Swarm](https://docs.ethswarm.org), and serves a small read API over Arkiv for the game and the website.

```
game server  ──GET /city (every 15 s)──▶  publisher  ──executeBatch (one tx per flush)──▶  Arkiv (Rabdi)
                                            │  └──POST /bzz (paper text, season snapshots)──▶  Bee ▶ Swarm
sponsor console ──POST /swarm/campaign-bundle──▶ │  (returns the reference = on-chain metaHash)
game (/arkiv/campaigns proxy), website ──GET /campaigns, /boards/rush, /prices, …──▶ live arkiv_query
```

Arkiv is slow next to the game (2-second blocks, a rate-limited public RPC), so it is used only as the
public, queryable, expiring read model. The game never waits on it: the publisher reads the server's
public view on its own timer and writes in batches; if Arkiv or Bee is slow or down it backs off and
retries, and the game carries on. Nothing private goes anywhere: no balances, no amounts anyone paid,
no player wallets.

## What it writes

| Entity (`arkiv.schema`) | Written | Expires | Queried by |
|---|---|---|---|
| `dhaniverse.campaign.v1` | when a card appears or changes (slots, status) | at the campaign's end | Bounty Board (`GET /campaigns`) |
| `dhaniverse.rush_board.v1` | when a city day closes | 48 h | `GET /boards/rush?day=` |
| `dhaniverse.price_tick.v1` | one per 5-minute window | 7 days | `GET /prices?from=&to=` |
| `dhaniverse.profile.v1` | when a title, stamp or ENS name changes | season end, renewed | `GET /profiles/:name` |
| `dhaniverse.paper.v1` | each new paper | 30 days | `GET /papers/:day` (body on Swarm) |
| `dhaniverse.season.v1` | when a season ends (needs Swarm) | 180 days | `GET /seasons` |
| `dhaniverse.city.v1` | once per town, from the save's first line (encrypted) | 180 days, renewed | `GET /log` |
| `dhaniverse.log.v1` | one per batch of save lines (gzipped, encrypted, hash-chained) | 180 days, renewed | `GET /log` |

### The save on Arkiv

With `SAVE_PATH` (the server's `--save` file) and `DHANIVERSE_LOG_KEY` set, the publisher tails the save and
writes it to Arkiv in order. A batch closes at a flush or at 96 KiB of compressed lines; it is gzipped, then
AES-256-GCM encrypted (nonce in front, tag after), and its `hash` (SHA-256 of the plaintext JSONL) is chained
through the next batch's `prevHash`. Only whole lines are read, and a batch is sent only after the one before it
landed, so Arkiv never has a gap. On a restart it asks Arkiv for the town's highest `toSeq` and carries on.
Every `city` and `log` entity with under 150 days left is extended to 180 days (checked once a day).
Without the key it says so and does not start the mirror; everything else still runs.
Generate a key with `openssl rand -hex 32`, and keep it with the server's other secrets: lose it and the
save on Arkiv cannot be read.

Every attribute, index, owner and expiry: [`/arkiv/schema.md`](../../arkiv/schema.md). The schemas in code:
[`src/schemas.ts`](src/schemas.ts). The contract test ([`test/contract.test.ts`](test/contract.test.ts))
fails if the two drift.

## Run

Node 24 runs the TypeScript directly (type stripping); there is no build step.

```sh
cd services/publisher
npm ci
cp .env.example .env        # fill in what you have; everything is optional
npm run address             # prints the writer address for ARKIV_PRIVATE_KEY (never the key)
npm start                   # polls SERVER_URL/city, writes, serves the read API on :8787
npm test                    # unit + contract tests, no network
npm run typecheck
```

With nothing configured it runs as a no-op and says so once: no Arkiv key means no writes (and no
invented entity ids); no `BEE_URL` + `BEE_POSTAGE_BATCH` means no Swarm uploads (and no invented
references; the paper goes to Arkiv with its text inline instead). With only `ARKIV_WRITER_ADDRESS`
set, it serves the read API over someone else's published data without writing.

To go live on Rabdi: make a key (any 32-byte hex; `cast wallet new` works), set `ARKIV_PRIVATE_KEY`,
run `npm run address`, fund that address with tGLM at <https://hub.arkiv.network/faucet>, get a free RPC
access key at <https://hub.arkiv.network/access-keys> into `ARKIV_ACCESS_KEY`, set `PUBLISHER_ENV=live`,
and start it next to the game server.

The game server reaches the read API at `PUBLISHER_URL` (e.g. `http://127.0.0.1:8787`); its
`GET /arkiv/campaigns` proxies to `GET {PUBLISHER_URL}/campaigns`.

## Environment

| Variable | Default | What |
|---|---|---|
| `SERVER_URL` | `http://127.0.0.1:7878` | the game server; the publisher reads `GET /city` |
| `POLL_INTERVAL_MS` | `15000` | how often it reads `/city` |
| `CITY_TIMEOUT_MS` | `5000` | deadline for one read |
| `ARKIV_PRIVATE_KEY` | — | the writer key (hex). **Secret**: env only, redacted from every log line |
| `ARKIV_ACCESS_KEY` | `""` | Arkiv RPC access key; empty uses the public, rate-limited RPC |
| `ARKIV_CHAIN` | `rabdi` | `rabdi` (testnet, chain id 7794095) or `localhost` |
| `ARKIV_RPC_URL` | chain's | override the RPC URL |
| `ARKIV_WRITER_ADDRESS` | key's address | whose entities the read API trusts (read-only mode) |
| `SAVE_PATH` | — | the server's `--save` file to mirror onto Arkiv |
| `DHANIVERSE_LOG_KEY` | — | 64 hex characters (32 bytes): encrypts the save on Arkiv, and decrypts it for `GET /log`. Required for the mirror |
| `DHANIVERSE_RESTORE_TOKEN` | — | 32+ characters: the bearer token `GET /log` requires. Unset: `GET /log` answers 404 |
| `RESTORE_ALLOW_REMOTE` | `false` | let non-loopback addresses use `GET /log` (token still required) |
| `ARKIV_FLUSH_INTERVAL_MS` | `20000` | how often a batch may go out (sooner while there's a backlog) |
| `ARKIV_MAX_OPS_PER_TX` | `12` | operations per transaction |
| `ARKIV_TX_TIMEOUT_MS` | `120000` | deadline for one transaction (then reconcile before retrying) |
| `ARKIV_QUERY_TIMEOUT_MS` | `15000` | deadline for one query |
| `PUBLISHER_ENV` | `dev` | the `env` attribute on every entity; use `live` for the real run |
| `BEE_URL` | — | Bee node API, e.g. `http://localhost:1633` |
| `BEE_POSTAGE_BATCH` | — | postage batch ID (64 hex) that pays for uploads |
| `BEE_PIN` | `true` | pin uploads on our node |
| `BEE_DEFERRED_UPLOAD` | `true` | Bee's default; `false` pushes chunks before answering |
| `BEE_TIMEOUT_MS` | `60000` | deadline for one Bee request |
| `PUBLISHER_HOST` / `PUBLISHER_PORT` | `127.0.0.1` / `8787` | where the read API listens |
| `READ_CACHE_MS` | `10000` | read cache (stale answers served, marked, for up to 5 min if Arkiv errors) |
| `CORS_ORIGINS` | `*` | browser origins allowed |
| `UPLOADS_PER_HOUR` / `UPLOADS_PER_DAY` | `12` / `200` | bundle uploads per caller per hour, and overall per day (they spend postage) |
| `PUBLISHER_STATE_DIR` | `data` | where it remembers what it wrote (a cache; Arkiv is the truth) |
| `PRICE_BATCH_MS` | `300000` | price batch window |
| `PROFILE_FALLBACK_DAYS` | `7` | profile lifetime when the server doesn't say when the season ends |
| `LOG_LEVEL` | `info` | `debug`, `info`, `warn`, `error` |

## Read API

Every answer is a live Arkiv query (behind a short cache) filtered on the writer (`$owner`) and
`env`, and carries `source: "arkiv"`, the `block` it was read at, `owner`, `env`, `cached_at` and `stale`.

| Route | Answer |
|---|---|
| `GET /campaigns` | `{cards: [{id, sponsor, title, template, payout, energy, slots_left, ends, status, swarm, entity_key, expires_at_block}]}`: live, slots left, soonest-ending first. Same field names as the server's `city.bounty`. |
| `GET /boards/rush?day=N` | `{board: {day, season, board, leader, entries, top: [{rank, name, title}]}}`; latest without `day`; 404 if none |
| `GET /prices?from=&to=` | `{ticks: [{start, end, day, open, high, low, close, samples, series: [[t, price]], shock}]}`: unix seconds, default last 24 h, at most 7 days; USDC base units per FOOD |
| `GET /profiles/:name` | `{profile: {name, title, stamps, ens, season}}`; 404 if none |
| `GET /papers/:day` | `{paper: {day, headline, stories, body_ref, body}}`; `/papers/latest` for the newest |
| `GET /seasons` | `{seasons: [{season, ended_day, snapshot_ref}]}` |
| `GET /log?town=&from=` | the save, restored from Arkiv, as JSONL: the setup line (when `from` is 0), then every line with `seq >= from`, in order. Decrypts, checks every `prevHash` link and that each batch starts where the last ended; on a broken chain, a gap or a batch that won't decrypt it ends with `{"error": …}` and stops. Needs `DHANIVERSE_LOG_KEY`, `Authorization: Bearer <DHANIVERSE_RESTORE_TOKEN>`, and a loopback caller |
| `GET /query` | the Bounty Board's query string, RPC URL, chain id and a ready JSON-RPC body |
| `POST /swarm/campaign-bundle` | multipart form: `story` (JSON) + up to 6 `image` files → `201 {reference, metaHash, index, files, bytes, dropped}` |
| `GET /swarm/campaign-bundle/:ref` | that bundle's `index.json`, read back through Bee |
| `GET /health` | what's on, last poll, last transaction, waiting records, last errors (never a key) |

Errors are `{error}` with 400/404/413/415/429, 502 when Arkiv or Bee doesn't answer in time, and 503
when the part isn't configured.

### Campaign bundles (sponsor console)

```js
const form = new FormData()
form.set("story", JSON.stringify({ title: "The Spice Run", sponsor: "Mango Traders", template: "spice_run",
  story: "Bring the saffron home from the harbour.", lines: ["…"], cta: "Take the run" }))
form.append("image", coverFile)                       // PNG, JPEG, WebP or GIF; ≤ 1 MiB each, ≤ 4 MiB total
const res = await fetch(`${PUBLISHER_URL}/swarm/campaign-bundle`, { method: "POST", body: form })
const { metaHash } = await res.json()                 // 0x… bytes32 for CampaignParams.metaHash
```

Story fields are whitelisted (`title` ≤ 120, `story` ≤ 8000, `sponsor` ≤ 80, `template`, `cta`, `lines` ≤ 20 × 280);
unknown fields are dropped and listed in `dropped`. Images are checked by their bytes, not their
claimed type; SVG is refused. The bundle is public and permanent: put nothing private in it.

## Writer wallet and a query to run

- **Writer address (Rabdi):** `0x________________________________________` ← fill in from `npm run address` after the key exists
- **Env attribute for the live run:** `live`
- Explorer: <https://rabdi.explorer.arkiv.network/address/WRITER_ADDRESS>

Run the Bounty Board query yourself, no key needed:

```sh
npm run query -- WRITER_ADDRESS live
```

or straight against the RPC:

```sh
curl -s https://rpc.rabdi.db-chain.testnet.arkiv.network -H 'content-type: application/json' -d '{
  "jsonrpc":"2.0","id":1,"method":"arkiv_query",
  "params":["arkiv.schema = str('\''dhaniverse.campaign.v1'\'') AND env = str('\''live'\'') AND status = str('\''live'\'') AND $owner = addr(WRITER_ADDRESS)",
            {"select":{"key":true,"owner":true,"expiresAt":true,"attributes":true},"limit":"0x64"}]}'
```

## How it behaves when things go wrong

- **Game server down:** logged once per 5 minutes; the read API keeps answering from Arkiv.
- **Arkiv slow or down:** the transaction gets a deadline; failures back off exponentially (5 s → 5 min,
  with jitter). Closed boards, price windows, papers and season snapshots are persisted until written;
  cards and profiles are re-derived from the next `/city`, so only the latest state goes out.
- **A transaction that may have landed** (timeout, lost receipt): before creating anything of those
  types again, the publisher asks Arkiv what already exists for those ids and patches instead of
  duplicating. Same after a restart or a lost state file.
- **Bee down or batch unusable:** the paper waits (5 tries with backoff) and then goes to Arkiv with its
  text inline; season snapshots wait; bundle uploads return 502 with Bee's reason (402 = batch).
- **Secrets:** `ARKIV_PRIVATE_KEY` is registered with the logger before anything else runs; every log
  line is scrubbed of it (with or without `0x`, any case) and of any field named like a key.

## Layout

```
src/main.ts           wiring, poll loop, flush loop, shutdown
src/config.ts         env parsing and validation
src/city.ts           GET /city → Snapshot (tolerant parser)
src/schemas.ts        the Arkiv schemas
src/entities.ts       Snapshot → entity drafts, Arkiv rows → API JSON (pure)
src/publisher.ts      observe / plan / flush, reconciliation, backoff
src/state.ts          what was written, what is waiting (atomic JSON file)
src/arkiv/client.ts   SDK clients (transport injectable)
src/arkiv/writer.ts   one executeBatch per flush
src/arkiv/queries.ts  every Arkiv query (all owner + env filtered)
src/swarm.ts          Bee HTTP API client (POST /bzz, GET /bzz, GET /stamps)
src/swarmRef.ts       the gate: only plain 32-byte references reach a public entity
src/bundle.ts         campaign bundle validation and upload
src/readapi.ts        the HTTP read API
test/fakeArkiv.ts     in-memory Arkiv node behind a viem transport (decodes real execute txs, evaluates queries)
test/fakeBee.ts       in-memory Bee
```

MIT licensed (see `LICENSE`).
