// The publisher loop, end to end through the real SDK against the in-memory Arkiv node and Bee.

import assert from "node:assert/strict"
import { test } from "node:test"
import { makeClients } from "../src/arkiv/client.ts"
import { SdkWriter } from "../src/arkiv/writer.ts"
import type { CampaignCard, Snapshot } from "../src/city.ts"
import { setSink } from "../src/log.ts"
import { Publisher, type PublisherOptions } from "../src/publisher.ts"
import { MemoryStateStore, emptyState } from "../src/state.ts"
import { Swarm } from "../src/swarm.ts"
import { FakeArkiv } from "./fakeArkiv.ts"
import { BATCH, FakeBee } from "./fakeBee.ts"
import { REF_A, TEST_ADDRESS, arkivConfig, snapshot } from "./helpers.ts"

const logs: string[] = []
setSink((line) => logs.push(line))

const OPTS: PublisherOptions = { env: "test", priceBatchMs: 300_000, profileFallbackDays: 7, maxOpsPerTx: 12, txTimeoutMs: 5_000 }

function rig(opts: Partial<PublisherOptions> = {}, { arkiv = true, bee = true } = {}) {
  const fake = new FakeArkiv()
  const fakeBee = new FakeBee()
  const clients = makeClients(arkivConfig(), fake.transport(), 5)
  const writer = arkiv ? new SdkWriter(clients.walletClient!, clients.publicClient) : null
  const swarm = new Swarm(
    bee ? { url: "http://bee.test", postageBatch: BATCH, pin: true, deferred: true, timeoutMs: 1_000 } : { url: undefined, postageBatch: undefined, pin: true, deferred: true, timeoutMs: 1_000 },
    fakeBee.fetch,
  )
  const store = new MemoryStateStore(emptyState("test", writer?.address ?? null))
  const clock = { t: Date.now() }
  const make = () => new Publisher({ ...OPTS, ...opts }, writer, swarm, store, () => clock.t)
  return { fake, fakeBee, writer, swarm, store, clock, make }
}

// Fixed once: a card built a second later must be the same card, or "nothing changed" tests flake on the clock.
const CARD_ENDS_AT = Math.floor(Date.now() / 1000) + 86_400

function card(over: Partial<CampaignCard> = {}): CampaignCard {
  return {
    id: "1",
    sponsor: "Mango Traders",
    title: "The Spice Run",
    template: "spice_run",
    payout: 500_000n,
    energy: 20,
    slotsLeft: 40,
    endsAt: CARD_ENDS_AT,
    status: "live",
    swarmRef: REF_A,
    ...over,
  }
}

const at = (clock: { t: number }, over: Partial<Snapshot> = {}) => snapshot({ observedAt: clock.t, ...over })

test("without an Arkiv key the publisher observes but writes nothing, and says so without inventing ids", async () => {
  const { make, clock, fake } = rig({}, { arkiv: false })
  const p = make()
  await p.init()
  p.observe(at(clock, { bounty: [card()] }))
  assert.deepEqual(await p.flush(), { sent: 0, more: false })
  assert.equal(fake.entities.size, 0)
  assert.equal(p.arkivEnabled, false)
})

test("campaign cards: created, patched when slots change, marked ended when they leave the board", async () => {
  const { make, clock, fake } = rig()
  const p = make()
  await p.init()
  p.observe(at(clock, { bounty: [card(), card({ id: "2", title: "Paint your sign", template: "paint_sign" })] }))
  assert.equal((await p.flush()).sent, 2)
  assert.equal(fake.ofSchema("tallyport.campaign.v1").length, 2)

  p.observe(at(clock, { bounty: [card(), card({ id: "2", title: "Paint your sign", template: "paint_sign" })] }))
  assert.equal((await p.flush()).sent, 0, "nothing changed, nothing written")

  p.observe(at(clock, { bounty: [card({ slotsLeft: 39 })] }))
  assert.equal((await p.flush()).sent, 2)
  const byId = (id: bigint) => fake.ofSchema("tallyport.campaign.v1").find((e) => e.attributes.get("campaignId")?.value === id)!
  assert.equal(byId(1n).attributes.get("slotsLeft")?.value, 39)
  assert.equal(byId(2n).attributes.get("status")?.value, "ended")
  assert.equal(fake.ofSchema("tallyport.campaign.v1").length, 2, "patched in place, no duplicates")
})

test("price: one entity per five-minute batch, written after the window closes", async () => {
  const { make, clock, fake } = rig()
  const start = Math.ceil(Date.now() / 300_000) * 300_000
  clock.t = start + 1_000
  const p = make()
  await p.init()
  const prices = [4000, 4000, 4100, 4100, 4050]
  for (const price of prices) {
    p.observe(at(clock, { price }))
    clock.t += 15_000
  }
  assert.equal((await p.flush()).sent, 0, "window still open")
  clock.t = start + 300_000 + 1_000
  p.observe(at(clock, { price: 4200 }))
  assert.equal((await p.flush()).sent, 1)
  const [tick] = fake.ofSchema("tallyport.price_tick.v1")
  assert.equal(tick?.attributes.get("startTs")?.value, BigInt(start / 1000))
  assert.equal(tick?.attributes.get("open")?.value, 4000n)
  assert.equal(tick?.attributes.get("high")?.value, 4100n)
  assert.equal(tick?.attributes.get("close")?.value, 4050n)
  assert.equal(tick?.attributes.get("samples")?.value, 5)
})

test("a closed day writes that day's Rush board, as last seen; an empty board is skipped", async () => {
  const { make, clock, fake } = rig()
  const p = make()
  await p.init()
  const rows = [{ rank: 1, name: "asha", title: "Regular" }]
  p.observe(at(clock, { day: 10, rush: { board: "rush", rows: [] } }))
  p.observe(at(clock, { day: 10, rush: { board: "rush", rows } }))
  await p.flush()
  assert.equal(fake.ofSchema("tallyport.rush_board.v1").length, 0, "day 10 not closed yet")
  p.observe(at(clock, { day: 11, rush: { board: "rush", rows: [] } }))
  p.observe(at(clock, { day: 12, rush: { board: "rush", rows: [] } }))
  await p.flush()
  const boards = fake.ofSchema("tallyport.rush_board.v1")
  assert.deepEqual(boards.map((b) => b.attributes.get("day")?.value), [10n])
  assert.equal(boards[0]?.attributes.get("leader")?.value, "asha")
})

test("Arkiv down: the poll path carries on, records are kept, writes resume with backoff", async () => {
  const { make, clock, fake, store } = rig()
  const p = make()
  await p.init()
  fake.down = true
  p.observe(at(clock, { day: 10, rush: { board: "rush", rows: [{ rank: 1, name: "asha", title: "" }] }, bounty: [card()] }))
  p.observe(at(clock, { day: 11 }))
  assert.deepEqual(await p.flush(), { sent: 0, more: false })
  await p.persist()
  assert.equal(store.state.pending.length, 1, "the closed board is persisted")
  fake.down = false
  assert.deepEqual(await p.flush(), { sent: 0, more: false }, "still backing off")
  clock.t += 10 * 60_000
  assert.equal((await p.flush()).sent, 2)
  assert.equal(fake.ofSchema("tallyport.rush_board.v1").length, 1)
  assert.equal(store.state.pending.length, 0)
})

test("a transaction that lands but times out is not written twice", async () => {
  const { make, clock, fake } = rig({ txTimeoutMs: 300 })
  const p = make()
  await p.init()
  p.observe(at(clock, { bounty: [card()] }))
  fake.swallowReceipts = true
  assert.equal((await p.flush()).sent, 0)
  assert.equal(fake.ofSchema("tallyport.campaign.v1").length, 1, "it landed")
  fake.swallowReceipts = false
  clock.t += 10 * 60_000
  await p.flush()
  assert.equal(fake.ofSchema("tallyport.campaign.v1").length, 1, "reconciled, not re-created")
  assert.ok(logs.some((l) => l.includes("found entities already on Arkiv")))
})

test("a restart with a lost state file finds what is already on Arkiv", async () => {
  const { make, clock, fake, store } = rig()
  const p1 = make()
  await p1.init()
  p1.observe(at(clock, { bounty: [card()], people: [{ name: "asha", title: "Regular", stamps: [], ens: null }] }))
  assert.equal((await p1.flush()).sent, 2)
  store.state = emptyState("test", TEST_ADDRESS)
  const p2 = make()
  await p2.init()
  p2.observe(at(clock, { bounty: [card()], people: [{ name: "asha", title: "Regular", stamps: [], ens: null }] }))
  assert.equal((await p2.flush()).sent, 0)
  assert.equal(fake.entities.size, 2)
})

test("the paper's body goes to Swarm and its reference onto the entity", async () => {
  const { make, clock, fake, fakeBee } = rig()
  const p = make()
  await p.init()
  p.observe(at(clock, { paper: { day: 10, headline: "Drought hits the farms", stories: ["Prices rise."] } }))
  assert.equal((await p.flush()).sent, 1)
  const [paper] = fake.ofSchema("tallyport.paper.v1")
  const ref = paper?.attributes.get("bodyRef")?.value as string
  assert.match(ref, /^[0-9a-f]{64}$/)
  assert.equal(paper?.attributes.has("body"), false)
  const upload = fakeBee.requests.find((r) => r.method === "POST")!
  assert.equal(upload.headers["swarm-postage-batch-id"], BATCH)
  assert.equal(upload.headers["swarm-pin"], "true")
  const stored = JSON.parse(new TextDecoder().decode(fakeBee.stored.get(ref)?.get("paper-10.json")?.data))
  assert.equal(stored.headline, "Drought hits the farms")
})

test("Swarm down: the paper waits, then goes up inline after five tries; never a made-up reference", async () => {
  const { make, clock, fake, fakeBee } = rig()
  fakeBee.down = true
  const p = make()
  await p.init()
  p.observe(at(clock, { price: null, paper: { day: 10, headline: "Rain", stories: [] } }))
  for (let i = 0; i < 4; i++) {
    assert.equal((await p.flush()).sent, 0, `try ${i + 1} waits for Swarm`)
    clock.t += 10 * 60_000
  }
  assert.equal((await p.flush()).sent, 1)
  const [paper] = fake.ofSchema("tallyport.paper.v1")
  assert.equal(paper?.attributes.has("bodyRef"), false)
  assert.ok(paper?.attributes.has("body"))
})

test("Bee not configured: papers inline, season snapshots skipped", async () => {
  const { make, clock, fake, fakeBee } = rig({}, { bee: false })
  const p = make()
  await p.init()
  p.observe(at(clock, { season: { number: 1, endsDay: 168 }, paper: { day: 10, headline: "h", stories: [] } }))
  p.observe(at(clock, { season: { number: 2, endsDay: 336 } }))
  await p.flush()
  assert.equal(fakeBee.requests.length, 0)
  assert.equal(fake.ofSchema("tallyport.paper.v1").length, 1)
  assert.equal(fake.ofSchema("tallyport.season.v1").length, 0)
})

test("a finished season is snapshotted to Swarm and indexed on Arkiv", async () => {
  const { make, clock, fake, fakeBee } = rig()
  const p = make()
  await p.init()
  const people = [{ name: "asha", title: "Regular", stamps: ["town_pass"], ens: null }]
  p.observe(at(clock, { day: 167, season: { number: 1, endsDay: 168 }, people, rush: { board: "rush", rows: [{ rank: 1, name: "asha", title: "Regular" }] } }))
  p.observe(at(clock, { day: 168, season: { number: 2, endsDay: 336 }, people }))
  while ((await p.flush()).more);
  const [season] = fake.ofSchema("tallyport.season.v1")
  const ref = season?.attributes.get("snapshotRef")?.value as string
  const snap = JSON.parse(new TextDecoder().decode(fakeBee.stored.get(ref)?.get("season-1.json")?.data))
  assert.equal(snap.season, 1)
  assert.deepEqual(snap.board, [{ rank: 1, name: "asha", title: "Regular" }])
})

test("profiles: created, patched on a title or stamp change, renewed toward season end", async () => {
  const { make, clock, fake } = rig()
  const p = make()
  await p.init()
  const asha = { name: "asha", title: "Newcomer", stamps: [] as string[], ens: null }
  // Season ends in 2 hours of city time.
  p.observe(at(clock, { day: 166, season: { number: 1, endsDay: 168 }, people: [asha] }))
  assert.equal((await p.flush()).sent, 1)
  p.observe(at(clock, { day: 166, season: { number: 1, endsDay: 168 }, people: [{ ...asha, title: "Regular", stamps: ["town_pass"] }] }))
  assert.equal((await p.flush()).sent, 1)
  const [e] = fake.ofSchema("tallyport.profile.v1")
  assert.equal(e?.attributes.get("title")?.value, "Regular")
  assert.equal(e?.attributes.get("stamps")?.value, "town_pass")
  const before = e!.expiresAt
  // The next season starts; the profile is renewed to its end.
  p.observe(at(clock, { day: 168, season: { number: 2, endsDay: 336 }, people: [{ ...asha, title: "Regular", stamps: ["town_pass"] }] }))
  await p.flush()
  const [after] = fake.ofSchema("tallyport.profile.v1")
  assert.ok(after!.expiresAt > before + 100_000n, "extended by about a season")
  assert.equal(fake.ofSchema("tallyport.profile.v1").length, 1)
})

test("a backlog goes out in batches of maxOpsPerTx", async () => {
  const { make, clock, fake } = rig({ maxOpsPerTx: 3 })
  const p = make()
  await p.init()
  const people = Array.from({ length: 7 }, (_, i) => ({ name: `p${i}`, title: "Newcomer", stamps: [], ens: null }))
  p.observe(at(clock, { people }))
  const sent: number[] = []
  for (;;) {
    const r = await p.flush()
    sent.push(r.sent)
    if (!r.more) break
  }
  assert.deepEqual(sent, [3, 3, 1])
  assert.equal(fake.ofSchema("tallyport.profile.v1").length, 7)
})

test("the private key never appears in the logs", async () => {
  const { TEST_KEY } = await import("./helpers.ts")
  const { addSecret, log } = await import("../src/log.ts")
  addSecret(TEST_KEY)
  log.error("boom", { error: new Error(`bad key ${TEST_KEY}`), privateKey: TEST_KEY, nested: { k: TEST_KEY.slice(2) } })
  const last = logs.at(-1)!
  assert.ok(!last.includes(TEST_KEY.slice(2)))
  assert.ok(!last.toLowerCase().includes(TEST_KEY.slice(2).toLowerCase()))
  assert.match(last, /\[redacted\]/)
})
