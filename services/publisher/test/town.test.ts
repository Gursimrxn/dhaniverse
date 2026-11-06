// The town in public, end to end: a save on disk → TownProjector → the publisher's flush → the in-memory Arkiv node
// (real SDK, real transactions) → the read API. One test per projection, the wire contract of every new schema, the
// privacy rule, restarts, and the save's room in each transaction.

import assert from "node:assert/strict"
import { appendFileSync, existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs"
import type { AddressInfo } from "node:net"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { after, test } from "node:test"
import { makeClients } from "../src/arkiv/client.ts"
import { makeReader } from "../src/arkiv/queries.ts"
import { SdkWriter } from "../src/arkiv/writer.ts"
import { parseKey } from "../src/crypto.ts"
import { setSink } from "../src/log.ts"
import { Publisher } from "../src/publisher.ts"
import { makeReadApi } from "../src/readapi.ts"
import { createSaveMirror } from "../src/save.ts"
import { MemoryStateStore, emptyState } from "../src/state.ts"
import { Swarm } from "../src/swarm.ts"
import { TownProjector } from "../src/town.ts"
import { FakeArkiv, type StoredEntity } from "./fakeArkiv.ts"
import { arkivConfig } from "./helpers.ts"

setSink(() => {})
const DAY = 86_400_000
const BLOCK_MS = 2_000
/** Amounts, a wallet and a World ID result that must never reach Arkiv. */
const SECRET = 987_654_321
const WALLET = "0x5ec12e7a11e7000000000000000000000000beef"
const HUMAN = "0x49f33f999323eeed76c3c17a3203ef946c06562039b69777170c00431e9e2c38"
const RULES = "[clock]\nreal_day_ms = 86400000\n[chest]\npity_every = 3\nbrass_streak = 3\ngold_streak = 7\n"
const dir = mkdtempSync(join(tmpdir(), "town-test-"))
const servers: { close(): void }[] = []
after(() => servers.forEach((s) => s.close()))
const swarm = new Swarm({ url: undefined, postageBatch: undefined, pin: true, deferred: true, timeoutMs: 1_000 })

/** Two real days of a small town, with every private thing the save holds. */
function townLines(t0: number): object[] {
  const chain = (time: number, observed: object, events: object[] = []) => ({ input: { type: "Chain", block: 1, log_index: 0, time, observed }, events })
  const cmd = (command: object, events: object[]) => ({ input: { type: "Command", by: "Player", command }, events })
  const chest = (golden: number, weekly = false) => cmd({ type: "OpenChest", account: "asha", weekly }, [
    { type: "ChestOpened", account: "asha", weekly, tier: weekly ? "gold" : "wood", contents: { energy: 10, tickets: 1, voucher: false, golden_drop: golden } },
    { type: "TicketsEarned", account: "asha", tickets: 1, why: "chest", total: 3 },
  ])
  const quest = (stamp: string) => cmd({ type: "QuestStep", account: "asha", quest: "harbour", step: "deliver" }, [
    { type: "QuestDone", account: "asha", quest: "harbour", title: "The Harbour Run", reward: { usdc: SECRET, tickets: 2, title: null, stamp } },
    { type: "Intent", intent: { type: "PayHouse", player: "asha", human_id: HUMAN, bucket: "fixed", amount: SECRET, ref: "t:q:asha:1" } },
    { type: "RewardPaid", account: "asha", amount: SECRET, why: "quest", ref: "q:asha:1", tx: "0xabc" },
    { type: "FirstEarned", account: "asha", first: "first_quest" },
  ])
  return [
    chain(t0, { type: "PoolBalances", fixed: 100_000_000, surprise: 100_000_000, safety: 20_000_000, budget_fixed: 4_000_000, budget_surprise: 4_000_000, budget_safety: 800_000 }, [{ type: "LedgerUpdated", part: "house" }]),
    { input: { type: "Claim", player: "asha", secret_hash: "f".repeat(64) }, events: [] },
    { input: { type: "Connect", player: "asha" }, events: [
      { type: "Arrived", account: "asha", energy: 100 },
      { type: "LoggedIn", account: "asha", day: 0, streak: 1, week_days: 1 },
      { type: "WalletReady", account: "asha", address: WALLET },
      { type: "BalanceChanged", account: "asha", usdc: SECRET },
    ] },
    cmd({ type: "VerifyHuman", account: "asha", human_id: HUMAN }, [
      { type: "HumanVerified", account: "asha" },
      { type: "FirstEarned", account: "asha", first: "town_pass" },
      { type: "FeedPost", id: 1, day: 0, kind: "first", text: "asha got the Town Pass.", about: "asha" },
    ]),
    chest(0),
    chest(0),
    chest(SECRET), // the third without a drop: the pity rule (pity_every = 3) pays one
    chest(0),
    quest("harbour"),
    quest("harbour"), // the same stamp again: not a second entity
    cmd({ type: "BuyMeal", account: "asha", item: "thali" }, [{ type: "MealEaten", account: "asha", item: "thali", usdc: SECRET, food: SECRET, energy: 50, from_ration: 0, ref: "m1", tx: "0xdef" }]),
    chain(t0 + 60, { type: "Paid", bucket: "fixed", player: "asha", human_id: HUMAN, amount: 40_000, ref: "t:q:asha:1", tx: "0xabc" }),
    chain(t0 + 61, { type: "PoolBalances", fixed: 99_960_000, surprise: 102_500_000, safety: 20_000_000, budget_fixed: 4_000_000, budget_surprise: 4_000_000, budget_safety: 800_000 }),
    { input: { type: "Advance", ms: DAY }, events: [{ type: "FeedPost", id: 2, day: 1, kind: "bounty", text: "A new bounty is up on the board in the square.", about: null }] },
    { input: { type: "Connect", player: "asha" }, events: [{ type: "LoggedIn", account: "asha", day: 1, streak: 3, week_days: 2 }] },
    chest(0, true),
    { input: { type: "Advance", ms: 5_000 }, events: [{ type: "MentorSays", account: "asha", about: "money", text: `you have ${SECRET}` }] },
  ]
}

function writeSave(lines: object[], name = `save-${Math.random().toString(36).slice(2)}`): string {
  const path = join(dir, `${name}.jsonl`)
  const setup = { seed: 42, rules: RULES, quests: "", chain: "offline", town_id: "town7" }
  writeFileSync(path, [setup, ...lines.map((l, i) => ({ seq: i + 1, ...l }))].map((l) => `${JSON.stringify(l)}\n`).join(""))
  return path
}

function rig() {
  const fake = new FakeArkiv()
  const clients = makeClients(arkivConfig(), fake.transport(), 5)
  const writer = new SdkWriter(clients.walletClient!, clients.publicClient)
  const store = new MemoryStateStore(emptyState("test", writer.address))
  const start = (path: string, opts: { maxOps?: number; logKey?: Buffer } = {}) => {
    const mirror = opts.logKey ? createSaveMirror({ savePath: path, logKey: opts.logKey, env: "test" }, clients.publicClient, writer.address) : null
    const p = new Publisher(
      { env: "test", priceBatchMs: 300_000, profileFallbackDays: 7, maxOpsPerTx: opts.maxOps ?? 12, txTimeoutMs: 5_000 },
      writer,
      swarm,
      store,
      Date.now,
      mirror,
      new TownProjector(path),
    )
    return p
  }
  return { fake, clients, writer, store, start }
}

async function drain(p: Publisher): Promise<void> {
  await p.init()
  for (let i = 0; i < 60; i++) {
    const r = await p.flush()
    if (r.sent === 0 && !r.more) return
  }
  throw new Error("never drained")
}

const attr = (e: StoredEntity, name: string) => e.attributes.get(name)?.value
const jsonOf = (e: StoredEntity, name: string) => JSON.parse(Buffer.from(String(attr(e, name)).slice(2), "hex").toString("utf8"))
const lifeDays = (fake: FakeArkiv, e: StoredEntity) => (Number(e.expiresAt - fake.block) * BLOCK_MS) / DAY

const SHAPES: Record<string, Record<string, [string, boolean]>> = {
  "dhaniverse.feed.v1": {
    "arkiv.schema": ["str", true], env: ["str", true], postId: ["u64", true], day: ["u64", true], kind: ["str", true],
    actor: ["str", false], at: ["u64", false], items: ["bytes", false],
  },
  "dhaniverse.chest.v1": {
    "arkiv.schema": ["str", true], env: ["str", true], day: ["u64", true], player: ["str", true], seq: ["u64", true],
    kind: ["str", false], tier: ["str", false], pityBefore: ["i32", false], outcome: ["str", true], draw: ["i32", false],
    contents: ["bytes", false], at: ["u64", false],
  },
  "dhaniverse.stamp.v1": {
    "arkiv.schema": ["str", true], env: ["str", true], player: ["str", true], stamp: ["str", true], kind: ["str", true],
    ref: ["str", true], day: ["u64", false], at: ["u64", false], seq: ["u64", false],
  },
  "dhaniverse.streak.v1": {
    "arkiv.schema": ["str", true], env: ["str", true], player: ["str", true], streak: ["i32", false],
    daysOfLast7: ["i32", false], chestTier: ["str", false], day: ["u64", false], fp: ["str", false],
  },
  "dhaniverse.pool.v1": {
    "arkiv.schema": ["str", true], env: ["str", true], day: ["u64", true], opening: ["u64", false], closing: ["u64", false],
    budget: ["u64", false], spentFixed: ["u64", false], spentSurprise: ["u64", false], spentSafety: ["u64", false], inflow: ["u64", false],
  },
}

// Two days before now, so day 1 is yesterday and everything is still alive.
const T0 = Math.floor((Date.now() - 2 * DAY) / 1000)

test("every town schema goes on the wire with the documented attributes, types, indexes and owner", async () => {
  const r = rig()
  await drain(r.start(writeSave(townLines(T0))))
  for (const [tag, shape] of Object.entries(SHAPES)) {
    const [e] = r.fake.ofSchema(tag)
    assert.ok(e, `${tag} was written`)
    // Optional columns (actor) may be absent on some rows; compare on a row that has them all.
    const full = r.fake.ofSchema(tag).find((x) => x.attributes.size === Object.keys(shape).length) ?? e
    assert.deepEqual(Object.fromEntries([...full.attributes].map(([n, a]) => [n, [a.type, a.indexed]])), shape, `${tag} wire shape`)
    assert.equal(full.owner, r.writer.address.toLowerCase())
  }
})

test("chests: every draw with tier, contents and the pity counter; a golden drop is yes/no, never the amount", async () => {
  const r = rig()
  await drain(r.start(writeSave(townLines(T0))))
  const draws = r.fake.ofSchema("dhaniverse.chest.v1").sort((a, b) => Number(attr(a, "seq")) - Number(attr(b, "seq")))
  assert.equal(draws.length, 5)
  assert.deepEqual(draws.map((d) => attr(d, "pityBefore")), [0, 1, 2, 0, 1])
  assert.deepEqual(draws.map((d) => attr(d, "outcome")), ["plain", "plain", "golden_drop", "plain", "plain"])
  assert.deepEqual(draws.map((d) => attr(d, "draw")), [1, 2, 3, 4, 0])
  assert.deepEqual(draws.map((d) => attr(d, "kind")), ["daily", "daily", "daily", "daily", "weekly"])
  assert.deepEqual(jsonOf(draws[2]!, "contents"), { energy: 10, tickets: 1, voucher: false, golden_drop: true, pity: true })
  assert.equal(attr(draws[4]!, "tier"), "gold")
  assert.equal(attr(draws[4]!, "day"), 1n)
  for (const d of draws) assert.ok(Math.abs(lifeDays(r.fake, d) - (30 - (Date.now() / 1000 - Number(attr(d, "at"))) / 86_400)) < 0.01, "30 days from the draw")
})

test("feed: one entity per post, the server's words, 7 days from the post", async () => {
  const r = rig()
  await drain(r.start(writeSave(townLines(T0))))
  const posts = r.fake.ofSchema("dhaniverse.feed.v1").sort((a, b) => Number(attr(a, "postId")) - Number(attr(b, "postId")))
  assert.deepEqual(posts.map((p) => attr(p, "kind")), ["first", "bounty"])
  assert.equal(attr(posts[0]!, "actor"), "asha")
  assert.equal(posts[1]!.attributes.has("actor"), false)
  assert.deepEqual(jsonOf(posts[1]!, "items"), [{ id: 2, text: "A new bounty is up on the board in the square." }])
  const age = (Date.now() / 1000 - Number(attr(posts[0]!, "at"))) / 86_400
  assert.ok(Math.abs(lifeDays(r.fake, posts[0]!) - (7 - age)) < 0.01)
})

test("stamps and firsts: each once per player, until the season's end", async () => {
  const r = rig()
  await drain(r.start(writeSave(townLines(T0))))
  const got = r.fake.ofSchema("dhaniverse.stamp.v1").map((s) => `${attr(s, "kind")}:${attr(s, "stamp")}`).sort()
  assert.deepEqual(got, ["first:first_quest", "first:town_pass", "stamp:harbour"])
  for (const s of r.fake.ofSchema("dhaniverse.stamp.v1")) assert.ok(lifeDays(r.fake, s) > 179, "no season end known: Arkiv's longest life")
})

test("streaks: created on login, patched and extended on the next login day, broken by expiry", async () => {
  const r = rig()
  const lines = townLines(T0)
  const path = writeSave(lines.slice(0, 3))
  const p = r.start(path)
  await drain(p)
  let [s] = r.fake.ofSchema("dhaniverse.streak.v1")
  assert.equal(attr(s!, "streak"), 1)
  assert.equal(attr(s!, "chestTier"), "wood")
  const firstLife = s!.expiresAt
  appendFileSync(path, lines.slice(3).map((l, i) => `${JSON.stringify({ seq: i + 4, ...l })}\n`).join(""))
  await drain(p)
  const all = r.fake.ofSchema("dhaniverse.streak.v1")
  assert.equal(all.length, 1, "patched, not a second entity")
  s = all[0]
  assert.equal(attr(s!, "streak"), 3)
  assert.equal(attr(s!, "daysOfLast7"), 2)
  assert.equal(attr(s!, "chestTier"), "brass")
  assert.ok(s!.expiresAt > firstLife, "extended")
  assert.ok(Math.abs(lifeDays(r.fake, s!) - 7) < 0.05, "8 days from yesterday's login")
  r.fake.block += BigInt((8 * DAY) / BLOCK_MS)
  assert.equal(r.fake.ofSchema("dhaniverse.streak.v1").length, 0, "no login for 8 days: the streak is gone")
})

test("pool: a closed day's statement from chain readings; inflow balances the books", async () => {
  const r = rig()
  await drain(r.start(writeSave(townLines(T0))))
  const pools = r.fake.ofSchema("dhaniverse.pool.v1")
  assert.equal(pools.length, 1, "only day 0 has closed")
  const p = pools[0]!
  assert.equal(attr(p, "day"), 0n)
  assert.equal(attr(p, "opening"), 220_000_000n)
  assert.equal(attr(p, "closing"), 222_460_000n)
  assert.equal(attr(p, "budget"), 8_800_000n)
  assert.equal(attr(p, "spentFixed"), 40_000n)
  assert.equal(attr(p, "spentSurprise"), 0n)
  assert.equal(attr(p, "inflow"), 2_500_000n)
  assert.ok(lifeDays(r.fake, p) > 88 && lifeDays(r.fake, p) < 90)
})

function assertNothingPrivate(entities: StoredEntity[], secrets: string[]): void {
  for (const e of entities) {
    for (const [name, a] of e.attributes) {
      const raw = String(a.value)
      const text = a.type === "bytes" ? Buffer.from(raw.slice(2), "hex").toString("utf8") : raw
      for (const secret of secrets) assert.ok(!text.toLowerCase().includes(secret.toLowerCase()), `${attr(e, "arkiv.schema")}.${name} holds ${secret}`)
    }
  }
}

test("nothing private reaches Arkiv: no amount paid, balance, wallet, World ID result or secret hash", async () => {
  const r = rig()
  await drain(r.start(writeSave(townLines(T0))))
  const town = Object.keys(SHAPES).flatMap((tag) => r.fake.ofSchema(tag))
  assert.ok(town.length >= 10)
  assertNothingPrivate(town, [String(SECRET), WALLET, HUMAN, HUMAN.slice(2), "f".repeat(64)])
})

test("the real save in server/save.jsonl: its wallets and World ID results stay off Arkiv", async (t) => {
  const real = join(import.meta.dirname, "../../../server/save.jsonl")
  if (!existsSync(real)) return t.skip("no server/save.jsonl here")
  const text = readFileSync(real, "utf8")
  const secrets = new Set<string>()
  for (const m of text.matchAll(/"(?:human_id|address|secret_hash)":"(0x)?([0-9a-fA-F]{20,})"/g)) secrets.add(m[2] as string)
  const r = rig()
  const path = join(dir, "real.jsonl")
  writeFileSync(path, text)
  await drain(r.start(path, { maxOps: 50 }))
  const town = Object.keys(SHAPES).flatMap((tag) => r.fake.ofSchema(tag))
  assert.ok(r.fake.ofSchema("dhaniverse.chest.v1").length > 0 && r.fake.ofSchema("dhaniverse.feed.v1").length > 0)
  assert.ok(secrets.size > 0)
  assertNothingPrivate(town, [...secrets])
})

test("a restart queues nothing twice; a lost state file is reconciled against Arkiv", async () => {
  const r = rig()
  const path = writeSave(townLines(T0))
  await drain(r.start(path))
  const count = () => Object.keys(SHAPES).reduce((n, tag) => n + r.fake.ofSchema(tag).length, 0)
  const before = count()
  const txs = r.fake.txs.length
  await drain(r.start(path)) // same state store: townSeq remembers
  assert.equal(r.fake.txs.length, txs, "nothing new to send")
  r.store.state = emptyState("test", r.writer.address) // the state file is gone
  await drain(r.start(path))
  assert.equal(count(), before, "found on Arkiv, not created again")
})

test("a town backlog leaves room for the save's own batch in every transaction", async () => {
  const r = rig()
  const many = Array.from({ length: 30 }, (_, i) => ({ input: { type: "Advance", ms: 1 }, events: [{ type: "FeedPost", id: i + 1, day: 0, kind: "board", text: `post ${i}`, about: null }] }))
  const path = writeSave([{ input: { type: "Chain", block: 1, log_index: 0, time: T0, observed: { type: "Noop" } }, events: [] }, ...many])
  const p = r.start(path, { maxOps: 6, logKey: parseKey("ab".repeat(32)) })
  await p.init()
  await p.flush()
  assert.equal(r.fake.ofSchema("dhaniverse.log.v1").length, 1, "the save went in the first transaction")
  assert.equal(r.fake.ofSchema("dhaniverse.feed.v1").length, 4, "with as many posts as fit beside it")
  await drain(p)
  assert.equal(r.fake.ofSchema("dhaniverse.feed.v1").length, 30)
})

test("the read API: chests, feed, pool, a player's profile and price history, each with entity keys, block and explorer links", async () => {
  const r = rig()
  await drain(r.start(writeSave(townLines(T0))))
  const api = makeReadApi({
    reader: makeReader(r.clients.publicClient, r.writer.address, "test"),
    swarm,
    cacheMs: 0,
    queryTimeoutMs: 2_000,
    corsOrigins: ["*"],
    uploadsPerHour: 1,
    uploadsPerDay: 1,
    explorer: "https://rabdi.explorer.arkiv.network",
    queryInfo: () => null,
    health: () => ({ ok: true }),
  })
  servers.push(api)
  await new Promise<void>((ok) => api.listen(0, "127.0.0.1", ok))
  const get = async (path: string) => {
    const res = await fetch(`http://127.0.0.1:${(api.address() as AddressInfo).port}${path}`)
    return { status: res.status, body: (await res.json()) as Record<string, any> }
  }
  const proof = (body: Record<string, any>) => {
    assert.equal(body.source, "arkiv")
    assert.match(String(body.block), /^\d+$/)
    assert.equal(body.explorer.block, `https://rabdi.explorer.arkiv.network/block/${body.block}`)
    assert.equal(body.explorer.owner, `https://rabdi.explorer.arkiv.network/address/${r.writer.address}`)
  }
  const key = /^0x[0-9a-f]{64}$/

  const chests = await get("/chests")
  proof(chests.body)
  assert.equal(chests.body.draws.length, 5)
  assert.equal(chests.body.draws[0].kind, "weekly", "newest first")
  assert.match(chests.body.draws[0].entity_key, key)
  assert.equal((await get("/chests?day=0")).body.draws.length, 4)

  const feed = await get("/feed")
  proof(feed.body)
  assert.deepEqual(feed.body.posts.map((p: { id: number }) => p.id), [2, 1])
  assert.match(feed.body.posts[0].entity_key, key)

  const pool = await get("/pool")
  proof(pool.body)
  assert.equal(pool.body.pool.day, 0)
  assert.equal(pool.body.pool.inflow, "2500000")
  assert.match(pool.body.pool.entity_key, key)
  assert.equal((await get("/pool?day=5")).status, 404)

  const asha = await get("/profiles/asha")
  assert.equal(asha.status, 200)
  proof(asha.body)
  assert.deepEqual(asha.body.stamps.map((s: { stamp: string }) => s.stamp), ["harbour"])
  assert.deepEqual(asha.body.firsts.map((s: { stamp: string }) => s.stamp).sort(), ["first_quest", "town_pass"])
  assert.equal(asha.body.streak.streak, 3)
  assert.equal(asha.body.streak.chest_tier, "brass")
  assert.match(asha.body.streak.entity_key, key)
  assert.equal((await get("/profiles/nobody")).status, 404)

  const prices = await get("/prices/history")
  proof(prices.body)
  assert.equal(prices.body.days, 7)
  assert.deepEqual(prices.body.ticks, [])
  assert.equal((await get("/prices/history?days=8")).status, 400)
})
