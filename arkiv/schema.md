# Arkiv schema

Dhaniverse writes eight entity types to Arkiv's **Rabdi** testnet (chain id `7794095`) with
`@arkiv-network/sdk@1.0.1`. The source of truth is
[`services/publisher/src/schemas.ts`](../services/publisher/src/schemas.ts); the contract test
[`services/publisher/test/contract.test.ts`](../services/publisher/test/contract.test.ts) checks every
attribute's name, type and indexed flag on the wire against the tables below.

## Rules common to every entity

- **Owner:** the publisher's writer wallet (one key, `ARKIV_PRIVATE_KEY`). Address: see
  [README](README.md#writer-wallet). Every read filters `$owner = addr(<writer>)`: a schema tag can be
  written by anyone, so the owner is what makes a row ours.
- **Schema tag:** each type is a named SDK schema, so every entity carries an indexed
  `arkiv.schema = "dhaniverse.<type>.v1"`. A breaking change gets `.v2`, never an edit in place.
- **`env`** (str, indexed) on every entity: `live` for the live run, `dev` for rehearsals, so the two
  never mix in a query.
- **Public only.** Names, titles, stamps, ranks, public campaign terms, the public FOOD price. Never
  balances, never an amount anyone was paid, never a player's wallet, never anything from World ID.
- **Limits honoured:** strings ≤ 128 bytes (cut on a character boundary with `…`), `bytes` ≤ 128 KiB,
  ≤ 31 columns per named schema, lifetime ≤ 180 days (Arkiv's max is 7,884,000 blocks ≈ 182.5 days).
- Only columns we filter on are indexed. Non-indexed columns are still returned and sortable.

## `dhaniverse.campaign.v1` — a Bounty Board card

Written when a campaign appears in the server's `city.bounty`, patched when its slots, status or terms
change, patched to `status = "ended"` if it leaves the list before its end.
**Expires at the campaign's end** (`ExpirationTime.atDate(end)`), so the board empties itself.

| Attribute | Type | Indexed | Meaning | Queried by |
|---|---|---|---|---|
| `env` | str | yes | `live` / `dev` | every query |
| `campaignId` | u64 | yes | `CampaignEscrow` campaign id | reconciliation |
| `status` | str | yes | `live`, `paused`, `cancelled`, `ended` | Bounty Board (`= live`) |
| `template` | str | yes | `spice_run`, `paint_sign`, `town_pass`, `hold_line` | filter by quest type |
| `sponsor` | str | yes | sponsor's display name | sponsor console |
| `title` | str | no | card title | — |
| `payout` | u64 | no | USDC base units per completed claim (the sponsor's public offer) | — |
| `energy` | i32 | no | energy a player spends to take it | — |
| `slotsLeft` | i32 | yes | claims left | Bounty Board (`> 0`) |
| `endsAt` | u64 | yes | unix seconds | Bounty Board (`> now`, sorted asc) |
| `metaHash` | str | no | Swarm reference (64 hex) of the story/media bundle = the on-chain `metaHash` | — (see [swarm.md](swarm.md)) |
| `fp` | str | no | content fingerprint, so a restarted publisher can skip unchanged cards | — |

## `dhaniverse.rush_board.v1` — a closed day's Market Rush board

Written once when a city day closes, from the board as last seen during that day. Rank, name and title
only: the server never publishes scores. **Expires 48 h** after it is written.

| Attribute | Type | Indexed | Meaning | Queried by |
|---|---|---|---|---|
| `env` | str | yes | | every query |
| `day` | u64 | yes | city day number | `/boards/rush?day=`, latest (sorted desc) |
| `season` | i32 | yes (optional) | season number | — |
| `board` | str | no | server board it came from (`rush_today` if the server has a daily board, else `rush`) | — |
| `leader` | str | no | rank 1's name | — |
| `entries` | i32 | no | rows in `top` | — |
| `top` | bytes | no | JSON `[{rank, name, title}]`, at most 50 | — |

## `dhaniverse.price_tick.v1` — five minutes of the FOOD price

One entity per 5-minute window (`PRICE_BATCH_MS`), written after the window closes. One sample per
poll (15 s), stored compactly: only samples where the price moved, plus the first and last.
**Expires 7 days** after it is written.

| Attribute | Type | Indexed | Meaning | Queried by |
|---|---|---|---|---|
| `env` | str | yes | | every query |
| `startTs` | u64 | yes | window start, unix seconds | `/prices?from=&to=` (range, sorted asc) |
| `endTs` | u64 | yes | window end, unix seconds | — |
| `day` | u64 | yes | city day | — |
| `open` `high` `low` `close` | u64 | no | USDC base units per FOOD | — |
| `samples` | i32 | no | samples taken | — |
| `series` | bytes | no | JSON `[[unixSeconds, price], …]` | — |
| `shock` | str | no (optional) | the day's story shock, if any | — |

## `dhaniverse.profile.v1` — a player's public face

Written for each person in the server's public `people` list; patched when the title, stamps or ENS
name change. **Expires at the end of the current season** (from the server's `season.ends_day`,
`day_ms`, `day_elapsed_ms`; 7 days if the server doesn't say), and is **renewed** (an extension) toward the
next season's end when it has less than 2 days left.

| Attribute | Type | Indexed | Meaning | Queried by |
|---|---|---|---|---|
| `env` | str | yes | | every query |
| `name` | str | yes | player name | `/profiles/:name` |
| `season` | i32 | yes (optional) | season number | — |
| `title` | str | no | earned title | — |
| `stamps` | str | no | comma list of earned stamps | — |
| `ens` | str | no (optional) | ENS name, e.g. `asha.tallyport.eth` | — |
| `fp` | str | no | content fingerprint | — |

## `dhaniverse.paper.v1` — the morning paper's index entry

Written once per new paper. The full text goes to Swarm (`bodyRef`); only if Swarm is not configured
or keeps failing (5 tries) does the text go inline in `body` instead. **Expires 30 days.**

| Attribute | Type | Indexed | Meaning | Queried by |
|---|---|---|---|---|
| `env` | str | yes | | every query |
| `day` | u64 | yes | city day of the paper | `/papers/:day`, latest (sorted desc) |
| `headline` | str | no | front-page headline | — |
| `stories` | i32 | no | number of stories | — |
| `bodyRef` | str | no (optional) | Swarm reference of `paper-<day>.json` | — |
| `body` | bytes | no (optional) | JSON `{headline, stories}`, only when Swarm had no copy | — |

## `dhaniverse.season.v1` — a finished season

Written when the server's season number moves on, after its snapshot (final board, people and titles)
is on Swarm. Only written when Swarm is configured. **Expires 180 days.**

| Attribute | Type | Indexed | Meaning | Queried by |
|---|---|---|---|---|
| `env` | str | yes | | every query |
| `season` | i32 | yes | season number | `/seasons` (sorted desc) |
| `endedDay` | u64 | no | city day it ended | — |
| `snapshotRef` | str | no | Swarm reference of `season-<n>.json` | — |

## `dhaniverse.city.v1` — a town's setup (the save's first line)

One per town, written once by the publisher when it first reads the server's save. The payload is the save's
first line (seed, rules, quest book, chain mode), **encrypted**: AES-256-GCM, key `DHANIVERSE_LOG_KEY`, layout
nonce (12 bytes) + ciphertext + tag (16 bytes). **Expires 180 days, renewed** when under 150 days are left.

| Attribute | Type | Indexed | Meaning | Queried by |
|---|---|---|---|---|
| `env` | str | yes | | every query |
| `townId` | str | yes | the save's `town_id` | every query |
| `chain` | str | no | the chain mode the town settles on | — |
| `rulesHash` | str | no | SHA-256 hex of the rules text | — |
| `startedAt` | u64 | no | unix seconds when the publisher first wrote it | — |
| `payload` | bytes | no | encrypted setup line | `GET /log` |

## `dhaniverse.log.v1` — a batch of the save's lines

One per batch. A batch holds consecutive lines of the save (`{seq, input, events}`) as JSONL, **gzipped, then
encrypted** (same layout as above). It closes at the publisher's flush or at 96 KiB of compressed lines. Batches are
written strictly in `seq` order and a batch is sent only after the previous one landed. `hash` is SHA-256 hex of the
batch's plaintext JSONL; `prevHash` is the previous batch's `hash` (64 zeros for the first), so a missing, reordered
or altered batch is caught on restore. **Expires 180 days, renewed** when under 150 days are left.

| Attribute | Type | Indexed | Meaning | Queried by |
|---|---|---|---|---|
| `env` | str | yes | | every query |
| `townId` | str | yes | | every query |
| `fromSeq` | u64 | yes | first line's `seq` | restore |
| `toSeq` | u64 | yes | last line's `seq`; the highest is where a restart continues | restore, restart (`ORDER BY toSeq DESC` limit 1) |
| `prevHash` | str | no | the previous batch's `hash` | — |
| `hash` | str | no | SHA-256 hex of this batch's plaintext | — |
| `payload` | bytes | no | encrypted gzipped JSONL, at most 96 KiB + 28 bytes | restore |

## The queries

All built with the SDK's query builder and sent as `arkiv_query`. With `W` the writer and `E` the env:

| Feature | Query |
|---|---|
| Bounty Board (in game, via the server's `/arkiv/campaigns`) | `arkiv.schema = str('dhaniverse.campaign.v1') AND env = str(E) AND status = str('live') AND endsAt > u64(now) AND slotsLeft > i32(0) AND $owner = addr(W) ORDER BY endsAt:u64 ASC` |
| Rush board for a day | `arkiv.schema = str('dhaniverse.rush_board.v1') AND env = str(E) AND day = u64(D) AND $owner = addr(W)` |
| Latest Rush board | `… rush_board.v1 … AND env = str(E) AND $owner = addr(W) ORDER BY day:u64 DESC` limit 1 |
| Price history | `arkiv.schema = str('dhaniverse.price_tick.v1') AND env = str(E) AND startTs >= u64(from) AND startTs < u64(to) AND $owner = addr(W) ORDER BY startTs:u64 ASC` (pages of 100) |
| Profile | `arkiv.schema = str('dhaniverse.profile.v1') AND env = str(E) AND name = str(N) AND $owner = addr(W)` |
| Paper | `arkiv.schema = str('dhaniverse.paper.v1') AND env = str(E) AND day = u64(D) AND $owner = addr(W)` |
| Where a restart continues | `arkiv.schema = str('dhaniverse.log.v1') AND env = str(E) AND townId = str(T) AND $owner = addr(W) ORDER BY toSeq:u64 DESC` limit 1 |
| Restore a town from line `s` | `arkiv.schema = str('dhaniverse.log.v1') AND env = str(E) AND townId = str(T) AND toSeq >= u64(s) AND $owner = addr(W) ORDER BY toSeq:u64 ASC` (pages of 10, then `toSeq > last`) |
| Reconcile before a create | `arkiv.schema = … AND env = str(E) AND (campaignId = u64(a) OR campaignId = u64(b) …) AND $owner = addr(W)` |

## Expiration at a glance

| Entity | Lifetime | Why |
|---|---|---|
| campaign | until the campaign ends | a card for a finished campaign is noise; expiry removes it with no cleanup job |
| rush_board | 48 h | yesterday's and today's boards are what the phone and website show |
| price_tick | 7 days | the market chart's longest view is a week |
| profile | season end, renewed | profiles of players who stop coming fade with the season |
| paper | 30 days | the paper's archive is a month; the text itself stays on Swarm |
| season | 180 days | the hall of fame, within Arkiv's maximum lifetime |
| city, log | 180 days, renewed under 150 | the save must outlive everything else; the publisher extends them once a day |
