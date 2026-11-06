# Arkiv as the game's database

The founder's decision: Arkiv is the game's database, all of it. Speed doesn't matter; winning the Arkiv track does,
so as much of the game as makes sense lives on Arkiv, and the town can be rebuilt from Arkiv alone.

## What exists today

- **The server is event-sourced.** Its save (`server/crates/server/src/log.rs`) is one append-only file of JSON lines:
  the first line is what the city started from (seed, rules, quest book, chain mode), and each later line is an input
  with the events it caused. Loading replays every input through the rules and checks it still causes the same
  events, so the save can't drift from the rules.
- **The publisher** (`services/publisher`, Node, `@arkiv-network/sdk` 1.0.1) writes a public read model to Arkiv's
  Rabdi testnet (chain 7794095): six entity types (campaign, rush_board, price_tick, profile, paper, season) with real
  expiry, batched into one transaction per flush, reconciled after restarts, and read back through a cached read
  API. It was rehearsed on the real network: 10 transactions, 17 entity writes, 3.4 to 20.4 s from submit to receipt
  (`arkiv/how-you-use-arkiv.md`).
- The game's truth still lives in the server's save file.

## The change, in four parts

1. **The save lives on Arkiv.** Every line of the save is written to Arkiv, and the server can start from Arkiv
   alone. The local file becomes a write-ahead cache.
2. **Much more of the town is public on Arkiv:** the feed, every chest draw, stamps and medals, streaks, the house
   pool's daily statement, the Town Goal, quest completions per campaign, and skill-game runs with their replays once
   the game layer lands.
3. **The browser reads Arkiv directly** for every board, profile, replay and history, and shows the block it read at,
   with a link to the explorer.
4. **Private data is encrypted.** Arkiv is public; secrets, World ID results and name-to-wallet links never appear in
   clear.

## 1. The save on Arkiv

### Entities

| Schema | One per | Attributes (indexed in bold) | Payload | Expiry |
|---|---|---|---|---|
| `dhaniverse.city.v1` | town | **`env`**, **`townId`**, `chain`, `rulesHash`, `startedAt` | the setup line, encrypted | 180 days, renewed every 30 |
| `dhaniverse.log.v1` | batch of save lines | **`env`**, **`townId`**, **`fromSeq`** (u64), **`toSeq`** (u64), `prevHash`, `hash` | the batch's lines as JSONL, gzipped, then encrypted | 180 days, renewed every 30 |

- **Encryption:** AES-256-GCM with a key from `DHANIVERSE_LOG_KEY` (32 bytes, hex, an environment variable like every
  other secret). The key never leaves the server and the publisher. The nonce is stored with the ciphertext.
- **A hash chain:** `hash` is SHA-256 of the batch's plaintext, and `prevHash` is the previous batch's `hash`, so a
  missing, reordered or altered batch is caught on restore.
- **Batch size:** a batch closes at the publisher's flush or at 96 KiB of compressed lines, whichever comes first,
  under Arkiv's 128 KiB payload limit.
- **Order:** batches are written strictly in `seq` order, and a batch is only sent after the previous one landed, so
  there is never a gap on Arkiv.
- **Renewal:** Arkiv's longest lifetime is about 182 days. A renewal job extends every `city` and `log` entity of a live
  town by 180 days every 30 days.

### Writing

The publisher tails the server's save file. It is append-only and already flushed to disk on the server's clock. The
publisher turns new lines into `log` batches, in the same `executeBatch` transactions as the public entities, behind
the public ones in priority. On restart it asks Arkiv for the town's highest `toSeq` and carries on from the next
line. That reconciliation already exists for creates.

### Restoring

The server gains `--arkiv <publisher URL>`. On start, if the local save is missing or ends before Arkiv's tip, it asks
the publisher for `GET /log?town=<id>&from=<seq>`. The publisher queries Arkiv in order, decrypts each batch, checks
the hash chain, and streams the lines. The server rebuilds its local file and then replays it exactly as today, so
every event is checked against the rules on the way. Lines the local file has beyond Arkiv's tip (written, not yet
landed) are kept, and the publisher sends them after start.

**The drill:** delete the local save, start the server with `--arkiv`, and get the same world: the same events and the
same final hash. This is a test, and a demo for the track.

## 2. The town in public on Arkiv

The six existing types stay. All schemas move to the `dhaniverse.` prefix as `.v1`; the testnet data can start over.
New types, all derived from the save's events by the publisher:

| Schema | One per | Attributes (indexed in bold) | Expiry, and the job it does |
|---|---|---|---|
| `dhaniverse.feed.v1` | batch of notable events | **`env`**, **`day`**, **`kind`**, `actor`, `at`, `items` (bytes) | 7 days: the feed forgets on its own |
| `dhaniverse.chest.v1` | chest opening | **`env`**, **`day`**, **`player`**, `kind`, `pityBefore`, `outcome` (a kind, never an amount), `seedHash`, `seed` | 30 days: the public record that every draw followed the odds plate and the pity rule |
| `dhaniverse.stamp.v1` | stamp or medal earned | **`env`**, **`player`**, **`stamp`**, `day` | the season's end, renewed: a passport that fades with the season |
| `dhaniverse.streak.v1` | player | **`env`**, **`player`**, `daysOfLast7`, `chestTier` | 8 days, renewed on each login day: when the entity expires, the streak is broken |
| `dhaniverse.pool.v1` | city day | **`env`**, **`day`**, `opening`, `budget`, `spentFixed`, `spentSurprise`, `inflow` | 90 days: the house pool's daily statement, the treasury's public books |
| `dhaniverse.goal.v1` | city day | **`env`**, **`day`**, `count`, `target` | 2 days: the Town Goal lanterns |
| `dhaniverse.quest.v1` | campaign and day | **`env`**, **`campaignId`**, **`day`**, `completions` | the campaign's end plus 30 days: the sponsor dashboard's numbers |
| `dhaniverse.run.v1` | skill-game run (when the game layer lands) | **`env`**, **`game`**, **`day`**, **`player`**, **`score`**, `medal`, `seedHash`, `seed`, `inputs` (bytes) | 7 days, 30 for each day's leader: replays and the leader's ghost |

The privacy rule stays as `arkiv/schema.md` states it: names, titles, ranks, stamps and outcome kinds in public; never
a balance, never an amount a player was paid, never a wallet, never anything from World ID. The pool's statement is
the house pool's own public books, not any player's money.

## 3. The browser reads Arkiv directly

- A small read client in the engine, loaded after the first playable frame (so it never counts against the 1 MB),
  queries Rabdi's public RPC with the SDK's read-only query builder. If the RPC fails, it falls back to the publisher's
  cached read API.
- It is used by the Bounty Board, the Rush boards and ghosts, profiles and the passport, the feed, the chest record
  ("every chest drawn today"), the market chart and the paper archive.
- Every panel that shows Arkiv data says which block it was read at and links to the Rabdi explorer.
- The page's Content Security Policy allows `connect-src` to the Rabdi RPC.

## 4. Private data

Secrets and their hashes, World ID results, name-to-wallet links and balances live only inside the encrypted log.
This is a call made for the founder: the alternative is keeping them off Arkiv entirely, on the server only, at the
cost of the "rebuild from Arkiv alone" drill.

## 5. Limits and cost

- Payloads ≤ 128 KiB, strings ≤ 128 bytes, ≤ 31 columns per schema, lifetime ≤ about 182 days (hence renewal).
- Writes take 3 to 20 s to land. The game never waits for them; the local save is the write-ahead cache. A player's
  action can show "saved to Arkiv" when its batch lands.
- Testnet gas is paid in tGLM from the faucet. The rehearsal's ten transactions cost 0.0028 tGLM.

## 6. For the track

- `arkiv/` stays current: the schema (every entity), how we use it (the save on Arkiv, the restore and the drill),
  the friction log, why Arkiv, and reach.
- A runnable query script for every schema, and the restore drill as a script.

## Order of work

1. **The save on Arkiv (publisher).** `log` and `city` entities, encrypted and hash-chained, from tailing the save;
   renewal; `GET /log` for restore. Tested end to end with the existing in-memory fake Arkiv node
   (`services/publisher/test/fakeArkiv.ts`), including a broken hash chain and a gap.
2. **Restore (server).** `--arkiv`, rebuilding the local save from `GET /log`; the drill as an integration test.
3. **The public town (publisher).** The new projections from the save's events, with fake-node tests for every
   schema, attribute and expiry, and the contract test extended.
4. **The browser's read client** (engine), with proof links. The panels that use it come with the game layer, which
   the founder supervises.
5. **The docs and scripts** for the track.
