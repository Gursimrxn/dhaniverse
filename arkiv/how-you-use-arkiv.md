# How Dhaniverse uses Arkiv

## The shape of it

```
                       ┌──────────── game server (Rust) ────────────┐
 players ◀─WebSocket─▶ │ the referee: energy, quests, meals, Rush;  │ ──▶ Ethereum Sepolia (USDC, Uniswap, ENS)
                       │ GET /city = the public view, rebuilt / 5 s │
                       └───────┬───────────────────────▲────────────┘
                     GET /city │ every 15 s            │ GET /arkiv/campaigns (proxy, cached 10 s)
                               ▼                       │
                       ┌──────────── publisher (Node) ─┴────────────┐
                       │ observe → plan → one executeBatch per flush │──▶ Arkiv Rabdi (entities)
                       │ read API: live arkiv_query + short cache    │──▶ Bee → Swarm (content)
                       └──────────────────────▲──────────────────────┘
                                              │ GET /campaigns /boards/rush /prices /profiles /papers
                                  town website, sponsor console
```

The game's truth lives in the server's log and on Sepolia. Arkiv gets a **read model**: the slice of
the town that is public and that someone outside the game wants to query. It is written off the hot
path, in batches, by a sidecar; nothing in the game waits for an Arkiv block.

## Writes

The publisher ([`src/publisher.ts`](../services/publisher/src/publisher.ts)) polls the server's public
`GET /city` and keeps two kinds of work:

- **Current-state entities** (campaign cards, profiles) are re-derived from the latest view at each
  flush and diffed against what was written (a content fingerprint per entity): new ones are created,
  changed ones patched (`patchEntity`-style ops in the batch, only the changeable columns), and a card
  that left the server's list before its end is patched to `status = "ended"`. Because the diff runs
  on the latest view, a burst of changes while Arkiv is slow collapses into one write.
- **Records** (a closed day's Rush board, a closed 5-minute price window, a new paper, a finished
  season) are queued when observed, persisted to disk, and created once.

Every flush builds **one transaction** with the SDK's `executeBatch` (creates, patches and extensions
together; all apply or none do), at most `ARKIV_MAX_OPS_PER_TX` operations, most user-visible first
(cards, then the paper, boards, seasons, price batches, profiles). While there is a backlog it flushes
again after 2 s; otherwise every 20 s. Price ticks are batched by design: one entity per 5 minutes,
not one per sample.

**Expiration does real work.** Cards are created with `ExpirationTime.atDate(campaign end)` and
simply disappear when the campaign ends; boards live 48 h, price batches 7 days, papers 30 days;
profiles live to the season's end and are extended toward the next one only while the player is still
in the town's public list. There is no cleanup job anywhere.

**Failure handling.** Each transaction has a deadline. A failure backs off exponentially with jitter
(5 s up to 5 min). A create is not idempotent on Arkiv (a key is derived from the owner's entity nonce
and a salt), so after any failure that may have landed, and after every restart, the publisher first
asks Arkiv which of the ids it is about to create already exist (by natural key: campaign id, day,
window start, name; owner and env filtered) and patches or skips those instead of duplicating them.

## Reads

The read API ([`src/readapi.ts`](../services/publisher/src/readapi.ts),
[`src/arkiv/queries.ts`](../services/publisher/src/arkiv/queries.ts)) answers every request from a live
`arkiv_query` via the SDK's typed builder (`select().from(schema).ownedBy(writer).where(…)`), behind a
10-second cache with in-flight de-duplication; if Arkiv errors, the last good answer (≤ 5 min old) is
served marked `stale: true`, otherwise a 502. Each answer carries the block it was read at.

| Feature | Reads |
|---|---|
| **Bounty Board** in the town square (game client → server `GET /arkiv/campaigns` → publisher `GET /campaigns`) | live cards with slots left, soonest-ending first |
| Phone/website Rush history | `GET /boards/rush?day=` |
| Market board history chart, website | `GET /prices?from=&to=` |
| ENS-linked profile page | `GET /profiles/:name` |
| Paper archive | `GET /papers/:day` → index on Arkiv, text from Swarm |

The query strings are in [schema.md](schema.md#the-queries). `GET /query` on the publisher returns the
exact Bounty Board query and a JSON-RPC body anyone can POST to the Rabdi RPC.

## What we checked, and how

- The SDK (1.0.1) ships its TypeScript source; the schema/column rules, limits, `executeBatch`,
  `ExpirationTime`, query rendering and RPC shapes used here were read from it and from
  <https://docs.arkiv.network> (fundamentals, schemas, batches, limits, the Rabdi network page).
- Read-only calls against live Rabdi from this code: `getChainId()` = 7794095, `getBlockTiming()` (2 s
  blocks), the reader's queries, and a raw `arkiv_query` with curl.
- The tests run the real SDK end to end against an in-memory node
  ([`test/fakeArkiv.ts`](../services/publisher/test/fakeArkiv.ts)) that decodes the signed `execute`
  transactions (operations, attribute names, type ids, the indexed flag, expiry) and evaluates the
  rendered query strings, including refusing to filter on a column that isn't indexed.

## Measured on Rabdi

A rehearsal on 6 Nov 2026 ran this code against the real network. The offline town ran with three rehearsal players
(names, Rush runs, a Spice Run, a meal, then a skipped day), and the publisher wrote as `env = "dev"` from the writer
[`0x584A19Fd7AbDe7aa89aE759CE4b8E018901eeF97`](https://rabdi.explorer.arkiv.network/address/0x584A19Fd7AbDe7aa89aE759CE4b8E018901eeF97).
Entities tagged `env = "live"` come from the live run.

| | |
|---|---|
| Transactions | 10, all landed, none retried |
| Entity writes | 17: 3 campaign cards, 1 card patch (slots 50 → 49 after a player took the quest), 3 profiles, 1 Rush board, 1 paper, 8 price batches |
| Write latency, submit → receipt | 3.4 to 20.4 s, median 6.6 s, on 2-second blocks. Most of it came before inclusion. Two of the three batches with several operations (profiles; the paper and the board) took 16 and 20 s |
| Gas | about 168k for one create; 439k to 573k for a batch of 3 or 4 operations |
| Cost | 0.0028 tGLM for all 10 transactions |
| Query latency | a raw `arkiv_query`: 0.41 to 0.67 s. Through the read API: 0.34 to 0.46 s on a cache miss, about 2 ms from the cache |
| Restart with an empty state folder | found the 3 cards, 3 profiles and the paper already on Arkiv and created none of them again |
| Failures | none |

The game server's `GET /arkiv/campaigns` (the Bounty Board) returned the cards from Arkiv with the patched slot count.
Season snapshots weren't written: they need Swarm, which wasn't configured for the rehearsal.
