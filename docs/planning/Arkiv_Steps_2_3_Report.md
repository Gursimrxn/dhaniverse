# Arkiv steps 2 and 3: report

Steps 2 (restore) and 3 (the public town) are built, along with the read API for the game and the track doc. All of
it is tested against the in-memory Arkiv node. **The live Rabdi run has not happened:** `services/publisher/.env`
doesn't exist, so no writer key is configured there. I checked for it and did not look anywhere else. The run waits
for `ARKIV_PRIVATE_KEY` for `0x584A19Fd7AbDe7aa89aE759CE4b8E018901eeF97` (funded, 19.997 tGLM) in that file. After
that it is one command (below).

## What's built

### Step 2: restore (server)

- `server/crates/server/src/arkiv.rs` (new) adds `--arkiv <publisher URL>` and `--town <id>`. They are flags and also
  `server.toml` keys, wired into `app.rs` `open_save`. Before the save opens, the server calls the publisher's
  `GET /log` with `Authorization: Bearer $DHANIVERSE_RESTORE_TOKEN`. It only calls `127.0.0.1`, `localhost` or
  `[::1]`.
  - **Missing save:** it is rebuilt whole. This needs `--town`.
  - **Existing save:** it gets only the lines Arkiv has beyond it. Lines it has beyond Arkiv's tip (written but not
    yet landed) are kept. A half line left by a crash is dropped first.
  - **Who checks what:** as the spec says, the publisher decrypts with `DHANIVERSE_LOG_KEY` and checks the chain:
    every `prevHash` link, every batch's SHA-256, and no gaps. The key never reaches the server. The server checks
    that:
    - the setup line is the town it asked for;
    - the lines run in order;
    - the answer reaches **`x-arkiv-tip`**. This is a new header on `GET /log` that gives the last line on Arkiv.
      Without it, a stream cut short would quietly restore an older town; with it, the restore fails.
  - **Failure is loud.** Any error stops the server with `ARKIV RESTORE FAILED, nothing was written: …`. That covers
    a broken chain, a gap, a bad decrypt, a short answer, a 401 and the wrong town.
  - **Nothing half-written.** Lines go to `<save>.arkiv-restore` first. They replace or extend the save only when the
    whole answer is good.
  - Then the save opens as always: every line is replayed and checked against the rules.
- `http.rs` gains one route, `GET /arkiv/<route>`. It passes the public reads through to the publisher, so the
  web-embedded game can reach them. Allowed routes are listed in `arkiv::read_path`, and `/log` is never one of them.
- `services/publisher/scripts/drill.ts` (new) is the drill's publisher half. With `--fake` it uses the in-memory node,
  for `cargo test`. Without it, it runs on Rabdi from `.env` (`npm run drill -- --save <file>`).

### Step 3: the public town (publisher)

`services/publisher/src/town.ts` (new) replays the save from its first line on every start and turns its events into
public records. The publisher:
- queues each line once (`State.townSeq`);
- writes the records oldest first;
- checks them against Arkiv after a lost state file, so nothing is written twice;
- always leaves two places per transaction for the save's own batch.

| Schema | From | Lifetime |
|---|---|---|
| `dhaniverse.chest.v1` | `ChestOpened`: tier, kind, `pityBefore` (worked out the way the rules do), `outcome` (`golden_drop`/`voucher`/`plain`), `draw`, and contents with `golden_drop` as yes/no | 30 days from the draw |
| `dhaniverse.feed.v1` | `FeedPost`, in the server feed's own words | 7 days from the post |
| `dhaniverse.stamp.v1` | quest stamps (`QuestDone.reward.stamp`) and firsts (`FirstEarned`), once per player | the season's end |
| `dhaniverse.streak.v1` | `LoggedIn`: streak, days of the last 7, chest tier. Patched and extended on each login day | 8 days; when it expires, the streak is broken |
| `dhaniverse.pool.v1` | the chain readings in the save (`PoolBalances`, and `Paid` by bucket), one per closed real day | 90 days |

The Market Rush board, the bounty campaigns with slots left and the FOOD price history were already on Arkiv before
this work. They come from the server's public view, as `rush_board.v1`, `campaign.v1` and `price_tick.v1`, and are
unchanged. Rebuilding them from events would mean re-implementing the rules' standings and campaign state.

**Privacy.** The projector reads only the events in the table. It never reads wallets, balances, amounts paid,
secret hashes or World ID results. The privacy test fills a save with all of those and checks that no public
attribute holds any of them. It also runs the real `server/save.jsonl`: it collects that file's `human_id`s,
addresses and secret hashes and makes the same check.

### Read API (publisher)

These are documented in `services/publisher/README.md`. Each answer carries `block`, `owner`, `env` and
`explorer: {block, owner}` (links to the Rabdi explorer). Every row carries its `entity_key` and `expires_at_block`.
The game reaches each route as `GET /arkiv/<route>` on the server.

| Route | Answer |
|---|---|
| `GET /campaigns` | live bounty cards with `slots_left` (existing; the game's `/arkiv/campaigns`) |
| `GET /boards/rush?day=` | a closed day's Rush board; the latest without `day` (existing) |
| `GET /prices/history?days=7` | new: 1 to 7 days of price candles, without the per-sample series |
| `GET /profiles/:name` | extended: `profile`, `stamps`, `firsts`, `medals` and `streak` (null once broken) |
| `GET /chests?day=` | new: chest draws, newest first |
| `GET /feed?day=` | new: feed posts, newest first |
| `GET /pool?day=` | new: a closed day's pool statement |
| `GET /log?town=&from=` | now also sends `x-arkiv-tip` |

### Docs

- `docs/arkiv/TRACK.md`: what lives on Arkiv and why, how to verify each entity, and the 2-minute demo built around
  the drill.
- `arkiv/schema.md`: the five new schemas, with their queries and expiries.

## Tests and results

### `cargo test -p server`: all 104 tests pass, 1 ignored (an existing test)

Run with `CARGO_TARGET_DIR=D:/pbuild-arkiv`.

- `tests/arkiv_drill.rs`, 3 tests:
  - A save is written, published by the real publisher code to the fake Arkiv node, wiped and restored. The file
    comes back byte for byte, the replayed `World` is identical, and the seq matches.
  - A save missing its last lines gets just those lines back.
  - The real `server` binary starts from Arkiv alone with `--arkiv --town`.
  - A broken chain stops both the restore and the binary: non-zero exit, `broken chain` on stderr, no save written.
  - These need Node 24 on the PATH. Without it they print SKIPPED and pass.
- `arkiv.rs` unit tests, 5:
  - a whole restore, with the token sent;
  - topping up a save, and keeping lines that are ahead of Arkiv;
  - a broken chain, a gap, a short answer, the wrong town and a 401 all write nothing;
  - loopback only;
  - the list of routes allowed through `/arkiv/<route>`.

### `npm test` in `services/publisher`: 79 pass, 0 fail

That is the 68 from before plus 11 new ones in `test/town.test.ts`:
- the wire shape (names, types, indexes, owner) of all five schemas;
- chest pity, outcome, draw number and the 30-day expiry;
- the feed;
- each stamp written once;
- streaks: created, patched, extended, and broken by expiry;
- pool numbers and inflow;
- nothing private, on a synthetic save and on the real one;
- a restart, and a lost state file, with no duplicates;
- the save keeping its two places during a backlog;
- the read API, with entity keys, block and explorer links.

`save.test.ts` now also checks `x-arkiv-tip`. `npm run typecheck` is clean.

### Manual check

`drill.ts --fake` on a copy of the real `server/save.jsonl` (2,715 lines). `GET /log` gave the file back byte for
byte. On the way it wrote, in 10 transactions:
- 12 streaks, 51 feed posts, 32 stamps and 4 chest draws;
- 1 city entity and 1 log batch.

## Live run status

Not run, because `services/publisher/.env` is absent and there is no writer key to use. The run keeps writes small:
one city, one or two log batches and a few dozen town entities. To do it:

```sh
cd services/publisher
# .env: ARKIV_PRIVATE_KEY, ARKIV_ACCESS_KEY, PUBLISHER_ENV=live, DHANIVERSE_LOG_KEY, DHANIVERSE_RESTORE_TOKEN
npm run drill -- --save <small save>       # prints READY <port> <town> <tip> and logs every tx hash
# in another shell, with the same token in the environment:
server --save restored.jsonl --arkiv http://127.0.0.1:<port> --town <town>
```

The drill logs the transaction hashes and counts. `GET /chests`, `/feed` and `/pool` on the drill's port give the
entity keys for this report and the explorer.

## Decisions and what's left

- **No `seedHash` or `seed` on chest entities,** though the spec has them. The city seed drives the market's shocks as
  well as the chests. Seeds are small (the default is 1), so even a hash would give the seed away. This needs a
  per-season seed commitment in the rules crate, which I did not touch.
- **`town_pass` is published as a first.** Holding the Town Pass is already public in the game: the profile, the feed
  and the paper all show it. The World ID nullifier never leaves the encrypted save. If the founder wants it off
  Arkiv, drop it in `town.ts`.
- **Medals:** no medal events exist yet. `stamp.v1` takes `kind = medal` once the game layer emits them.
- **Not in this brief, not built:** `run.v1`, `goal.v1` and `quest.v1` from the spec.
- **Stamps** expire at the season's end, or after 180 days when the server doesn't give an end. There is no renewal
  for a season longer than 180 days.
- **Explorer links:** Arkiv documents no page for a single entity. The proof link is therefore the block and the
  writer's address, plus the entity key, which anyone can check with one `arkiv_query`.
- **Slow recovery on a long save:** if the publisher loses its state, it checks every town record against Arkiv again,
  10 ids per query. It is slow but writes nothing twice.
- **Step 4 not done:** the browser's direct read client and the game panels.
- **`cargo check -p tallyport` not run:** its chain crate is being edited by another agent. Tallyport doesn't build a
  `ServerConfig` itself, so the new fields don't affect it.

## Sources (Arkiv docs, checked during this work)

- Limits: <https://docs.arkiv.network/reference/limits/>. 31 columns per named schema, 128-byte strings, 128 KiB of
  bytes per entity, a 7,884,000-block lifetime, 100 rows per page.
- Expiration: <https://docs.arkiv.network/writing/expiration/>. `fromSeconds` must be a multiple of 2 s; `atDate`
  takes `atLeast`; `extendEntity` counts from now.
- Batches: <https://docs.arkiv.network/writing/batches/>. `executeBatch` is atomic, can mix schemas, and returns
  `createdEntities` in order.
- Filtering: <https://docs.arkiv.network/querying/filter/>. Only indexed columns, typed values, and
  `ownedBy`/`createdBy`.
- Get entity: <https://docs.arkiv.network/querying/get-entity/>
- Schemas and a first entity: <https://docs.arkiv.network/start-here/first-entity/>
- Rabdi: <https://docs.arkiv.network/networks/rabdi/>. Chain 7794095, 2 s blocks, the explorer.
- npm: the latest `@arkiv-network/sdk` is 1.0.1, the version in use (checked with `npm view`; last modified
  2026-11-02).
