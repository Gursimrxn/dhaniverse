# Friction log: building on Arkiv

Honest notes from building the Dhaniverse publisher on `@arkiv-network/sdk@1.0.1` against Rabdi, on
6 Nov 2026. What helped, what slowed us down, and what we'd change. The network notes come from a
rehearsal that wrote to Rabdi with a funded key the same day (numbers in
[how-you-use-arkiv.md](how-you-use-arkiv.md#measured-on-rabdi)).

## What worked well

- **The package ships its TypeScript source** (`src/` next to `dist/`). When the docs didn't answer a
  question (batch return values, how a `Date` expiry is placed, the exact RPC shapes), reading the SDK
  answered it in minutes. Please keep doing this.
- **Schemas are a good fit.** `defineSchema("dhaniverse.campaign.v1", { … })` gave typed writes, typed
  reads, and a compile error when we tried to filter on a column we hadn't indexed. The automatic
  `arkiv.schema` tag made our queries short.
- **Checks before the network.** A create that doesn't fit its schema, a string over 128 bytes or an
  expiry past the maximum fails locally, before the block-number read or any gas.
- **Error messages that tell you what to do.** The "succeeded — do not retry it" wording on the
  event-count mismatch is exactly what a caller about to retry needs to hear.
- **`executeBatch`** with creates, patches and extensions across several schemas in one atomic
  transaction is the right primitive for a batch writer.
- **The query builder renders a readable string** (`toString()`), which we print in the build log.
  It made our in-memory test node possible.

## What slowed us down

1. **Old docs outrank new docs.** A web search for the SDK surfaced `arkiv.dev.golem.network` pages
   (labelled SDK v0.4.4 and v0.6.0) showing `mutateEntities`, `buildQuery()`, `expiresIn` and the
   `kaolin` chain. 1.0.1 has `executeBatch`, `select().from()`, `expiration` and `rabdi`. The current
   docs at docs.arkiv.network are right, but you have to know to go there. A banner or redirect on the
   old pages would save every new builder this detour.
2. **Docs URLs redirect in a chain** (`arkiv.network/docs` → `docs.arkiv.network/start-here/fundamentals`
   → trailing slash → `/start-here/introduction/`). Fine in a browser; tools that don't follow
   cross-host redirects (and AI assistants fetching docs) stop at each hop.
3. **Creates aren't idempotent.** An entity key comes from the owner's entity nonce plus a salt, so
   resending a create after a timeout (when you can't tell whether it landed) makes a duplicate. We
   built reconciliation: before re-creating, query by our natural key (campaign id, day, …) and patch
   what already exists. A "create if absent by (owner, salt)" mode, or a key derived without the nonce
   when the caller asks for it, would remove that whole layer for every batch writer.
4. **`executeBatch` drops the expiries it has.** Internally the transaction result carries
   `createdExpiries` and `extendedExpiries` (read from the events), but `executeBatch` returns only the
   keys. We track expiry for renewals, so we estimate it instead. Returning them would be free.
5. **The SDK writes to the console.** `rabdi({ accessKey: "" })` calls `console.warn` once. A service
   with structured JSON logs has to monkey-patch `console.warn` around the call. A `logger`/`onWarning`
   option, or only throwing/returning the condition, would fit servers better.
6. **Mixed-schema batches need a cast.** `executeBatch` infers a tuple of schemas from a literal; a
   batch assembled at runtime from several schemas (any real batch writer) doesn't type-check without
   widening it. A documented "dynamic batch" overload would help.
7. **Pagination is offset-only in the SDK, but the node returns a `cursor`.** A raw `arkiv_query` against
   Rabdi returned `"cursor":"b64:…"` alongside the data; the SDK pages with `offset`, which can skip or
   repeat rows while entities are being written. We page price history by offset (it's append-only by
   time, so it's safe for us); a cursor in the builder would make it safe in general.
8. **No documented batch size or gas ceiling.** The limits page covers attributes, sizes and lifetime
   but not how many operations fit in one transaction. The code has `MAX_TRANSACTION_GAS = 2^24` and
   adds 25% headroom; we picked 12 operations per transaction without a documented basis. On Rabdi one
   create used about 168k gas and a batch of 3 or 4 operations 439k to 573k, so 12 should need around
   2M: far under that ceiling, but we only know it by measuring.
9. **128-byte strings are tight for user text.** Titles and headlines get cut; we wrote a UTF-8-safe
   truncation (Devanagari is 3 bytes a character). Fine as a rule, but a helper in the SDK (or a
   documented "use bytes for anything a person writes") would save everyone writing the same function.
10. **The access key travels in the URL path.** `rabdi({ accessKey })` appends it to the RPC URL. The
    docs say it isn't a secret, but URLs end up in logs and error messages; we mask it ourselves.
11. **Number defaults.** A bare number is an `i32`, and `u64` has no bare form, so every timestamp and
    id is `u64(n)`. The schema knows the column is `u64`; letting a schema-typed write accept a number
    for a `u64` column would remove a common stumble. (The type checker does catch it, which is good.)
12. **Write latency varies a lot, and we can't tell why.** On 2-second blocks, our 10 rehearsal
    transactions took 3.4 to 20.4 s from the call to the receipt (median 6.6 s). Single creates reached
    a block 3.3 to 5.9 s after the call. Of the three batches with several operations, one reached a
    block in 6.5 s and the other two took 13.5 and 18 s. One receipt also came 11.7 s after its block. Nothing in the docs says what
    decides inclusion time (fee, gas, batch size, node load), so we can't tune for it. To reproduce:
    our publisher logs `ms` for every batch ([`src/publisher.ts`](../services/publisher/src/publisher.ts));
    the transactions are under our writer on the explorer. It doesn't hurt us, because nothing in the
    game waits for Arkiv, but an app that writes on a user's click would feel it.

## Testing without a node

There is no in-memory or mock node in the SDK, so we wrote one
(`services/publisher/test/fakeArkiv.ts`): a viem `custom` transport that decodes the signed `execute`
transaction (operations, attribute names, type ids, the indexed flag, expiry), emits the events the
SDK reads back, and evaluates the query strings the builder renders, holding to the same rules
(a filter on an unindexed column matches nothing). It was about an hour of work. An official test
transport, or a documented local node for CI, would help every team.

Small note: viem 2.57 first tries `eth_fillTransaction` when sending; our fake node had to answer
"method not found" (-32601) or viem retried with delays. Rabdi answers that -32601 in about 0.2 s, so
each real write pays one quick extra round trip, not a delayed retry.

## On the network

- Rabdi answered every read we sent from this code (chain id 7794095, 2-second blocks via
  `getBlockTiming`) on the public endpoint without an access key.
- Writes: all 10 rehearsal transactions landed with no errors and no retries (latency in item 12
  above). With an access key, the rate limit never bit.
- Reads: a raw `arkiv_query` took 0.41 to 0.67 s.
- Faucet: <https://hub.arkiv.network/faucet>. 10 tGLM is far more than we need: the 10 transactions
  cost 0.0028 tGLM in all.
