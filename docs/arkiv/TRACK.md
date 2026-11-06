# Dhaniverse on Arkiv: the track entry

Dhaniverse is a town game about money (USDC on chain, a Rust server, a Godot client). **Arkiv is its database.**
The whole save lives on Arkiv, encrypted and hash-chained, and the server can be rebuilt from Arkiv alone. Everything
the town may know in public lives on Arkiv too, as queryable, self-expiring entities that the game reads back with a
proof link.

- Network: Rabdi testnet, chain `7794095`, RPC `https://rpc.rabdi.db-chain.testnet.arkiv.network`,
  explorer <https://rabdi.explorer.arkiv.network>. SDK: `@arkiv-network/sdk` 1.0.1.
- Writer (the only owner every read trusts): `0x584A19Fd7AbDe7aa89aE759CE4b8E018901eeF97`,
  <https://rabdi.explorer.arkiv.network/address/0x584A19Fd7AbDe7aa89aE759CE4b8E018901eeF97>.
- Every attribute, index and expiry: [`arkiv/schema.md`](../../arkiv/schema.md). Code: `services/publisher`.

## What lives on Arkiv, and why

| Entity | What | Lifetime | Why Arkiv |
|---|---|---|---|
| `dhaniverse.city.v1` | a town's setup line (seed, rules, quest book), AES-256-GCM encrypted | 180 days, renewed | the town can start from Arkiv alone |
| `dhaniverse.log.v1` | every save line, in batches: gzipped, encrypted, `prevHash` → `hash` chained, `fromSeq`/`toSeq` indexed | 180 days, renewed | the save itself; a missing, reordered or altered batch is caught on restore |
| `dhaniverse.chest.v1` | every chest draw: tier, contents, the pity counter (a golden drop as yes/no, never an amount) | 30 days | a public record that every draw followed the odds plate and the pity rule |
| `dhaniverse.feed.v1` | every feed post | 7 days | the feed forgets on its own, no cleanup job |
| `dhaniverse.stamp.v1` | every stamp and first earned | the season's end | a passport that fades with the season |
| `dhaniverse.streak.v1` | each player's login streak | 8 days, renewed each login day | the expiry *is* the streak breaking |
| `dhaniverse.pool.v1` | the house pool's daily statement | 90 days | the treasury's books in public |
| `dhaniverse.campaign.v1` | sponsor bounty cards, slots left | the campaign's end | the Bounty Board reads it in game; it empties itself |
| `dhaniverse.rush_board.v1` | each closed day's Market Rush board | 48 h | yesterday's and today's boards |
| `dhaniverse.price_tick.v1` | the FOOD price, 5-minute candles | 7 days | the market chart's week |
| `dhaniverse.profile.v1`, `paper.v1`, `season.v1` | public profiles, the daily paper, season snapshots | season / 30 / 180 days | the town's public record |

What never goes on Arkiv in clear: balances, amounts anyone was paid, wallets, secret hashes, World ID results. They
exist only inside the encrypted `log` payloads; the privacy tests check every public attribute against a save full of
them (and against the real `server/save.jsonl`).

Arkiv features used: named schemas with indexed columns (`defineSchema`, `.indexed()`), typed queries with
`ownedBy`, `orderBy` and pagination, `executeBatch` (one atomic transaction per flush, mixing schemas), expiry as
business logic (`ExpirationTime.atDate`/`fromSeconds`), `extendEntity` for renewals and streaks, patches for
mutable rows, `bytes` payloads near the 128 KiB limit.

## How to verify each entity

Every row is owned by the writer above; filter on it, because anyone can write a schema tag.

```sh
# Any entity by key, with its owner and expiry (no key needed)
curl -s https://rpc.rabdi.db-chain.testnet.arkiv.network -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,
  "method":"arkiv_query","params":["$key = ENTITY_KEY",{"select":{"key":true,"owner":true,"expiresAt":true,"attributes":true}}]}'

# All of one type, e.g. today's chest draws
curl -s https://rpc.rabdi.db-chain.testnet.arkiv.network -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,
  "method":"arkiv_query","params":["arkiv.schema = str('\''dhaniverse.chest.v1'\'') AND env = str('\''live'\'') AND $owner = addr(0x584A19Fd7AbDe7aa89aE759CE4b8E018901eeF97)",
  {"select":{"key":true,"expiresAt":true,"attributes":true},"limit":"0x64"}]}'
```

- **city / log:** the payloads are ciphertext (check: no readable JSON). `hash` of batch *n* equals `prevHash` of
  batch *n+1*; `fromSeq` of *n+1* is `toSeq` of *n* + 1. The restore drill checks all of it with the key.
- **chest:** `pityBefore` climbs by one per daily draw and resets after `outcome = golden_drop`; with `pity_every`
  from the odds plate, a draw with `pityBefore + 1 >= pity_every` has `contents.pity = true`.
- **streak:** query a player; if it's gone, they missed 8 days. `$expiresAt` moves on every login day.
- **pool:** `inflow = closing − opening + spentFixed + spentSurprise + spentSafety`.
- **In game:** every panel answer from the publisher carries `block`, `explorer.block` and each row's `entity_key`.

## The 2-minute demo (the restore drill is the star)

1. **(0:00) The town.** Start the publisher (`npm start` in `services/publisher`, with `SAVE_PATH` and the keys) and
   the server. Play for a moment: open a chest, finish an errand. *"Every line of this save is going to Arkiv."*
2. **(0:20) It's on Arkiv.** `curl :8787/health` shows the last transaction; open the writer's address on the
   explorer. Run the chest query above: the draw we just made, with its pity counter. Show a `log` entity: the payload
   is ciphertext, the `prevHash`/`hash` chain is in the clear.
3. **(0:50) Destroy it.** Stop the server. `del save.jsonl`. *"The only copy of this town is now on Arkiv."*
4. **(1:00) The drill.** `server --save save.jsonl --arkiv http://127.0.0.1:8787 --town <id>` with
   `DHANIVERSE_RESTORE_TOKEN` set. It prints `restored from Arkiv: town …, N new line(s)` and the city replays every
   line through the rules (any line that doesn't replay identically stops it). Log in: same player, same chests,
   same streak.
5. **(1:30) Tamper with it.** `npm run drill -- --fake --save <copy> --break` alters one batch; the same command
   now stops with `ARKIV RESTORE FAILED, nothing was written: … broken chain`. *"Arkiv is the database, and the chain
   makes it honest."*
6. **(1:50) The public town.** The Bounty Board, the Rush board, a profile with stamps and streak, each showing
   "on Arkiv · block N".

The drill is also a test: `cargo test -p server --test arkiv_drill` (write a save, publish it to a fake Arkiv node
with the real publisher code, wipe it, restore it, compare the replayed world; then a broken chain).
