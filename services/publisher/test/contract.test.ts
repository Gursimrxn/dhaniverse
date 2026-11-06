// Contract test: the entity shapes and queries, through the real @arkiv-network/sdk, against an
// in-memory node that decodes the transactions as the engine does. If an attribute's name, type,
// indexed flag or expiry drifts from arkiv/schema.md, or a query filters on something that isn't
// indexed, this fails.

import assert from "node:assert/strict"
import { mkdtempSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"
import { makeClients } from "../src/arkiv/client.ts"
import { bountyBoardQueryText, makeReader } from "../src/arkiv/queries.ts"
import { SdkWriter } from "../src/arkiv/writer.ts"
import type { CampaignCard } from "../src/city.ts"
import { campaignDraft, paperDraft, priceTickDraft, profileDraft, rushBoardDraft, seasonDraft } from "../src/entities.ts"
import { parseKey } from "../src/crypto.ts"
import { SaveMirror } from "../src/save.ts"
import { FakeArkiv } from "./fakeArkiv.ts"
import { REF_A, REF_B, arkivConfig } from "./helpers.ts"

const BLOCKS_PER_HOUR = 1800n

function setup() {
  const fake = new FakeArkiv()
  const clients = makeClients(arkivConfig(), fake.transport(), 5)
  const writer = new SdkWriter(clients.walletClient!, clients.publicClient)
  const reader = makeReader(clients.publicClient, writer.address, "test")
  return { fake, clients, writer, reader }
}

function card(over: Partial<CampaignCard> = {}): CampaignCard {
  return {
    id: "7",
    sponsor: "Mango Traders",
    title: "The Spice Run",
    template: "spice_run",
    payout: 500_000n,
    energy: 20,
    slotsLeft: 40,
    endsAt: Math.floor(Date.now() / 1000) + 3 * 86_400,
    status: "live",
    swarmRef: REF_A,
    ...over,
  }
}

/** The wire shape of each schema: attribute → [type, indexed]. Mirrors arkiv/schema.md. */
const SHAPES: Record<string, Record<string, [string, boolean]>> = {
  "dhaniverse.campaign.v1": {
    "arkiv.schema": ["str", true],
    env: ["str", true],
    campaignId: ["u64", true],
    status: ["str", true],
    template: ["str", true],
    sponsor: ["str", true],
    title: ["str", false],
    payout: ["u64", false],
    energy: ["i32", false],
    slotsLeft: ["i32", true],
    endsAt: ["u64", true],
    metaHash: ["str", false],
    fp: ["str", false],
  },
  "dhaniverse.rush_board.v1": {
    "arkiv.schema": ["str", true],
    env: ["str", true],
    day: ["u64", true],
    season: ["i32", true],
    board: ["str", false],
    leader: ["str", false],
    entries: ["i32", false],
    top: ["bytes", false],
  },
  "dhaniverse.price_tick.v1": {
    "arkiv.schema": ["str", true],
    env: ["str", true],
    startTs: ["u64", true],
    endTs: ["u64", true],
    day: ["u64", true],
    open: ["u64", false],
    high: ["u64", false],
    low: ["u64", false],
    close: ["u64", false],
    samples: ["i32", false],
    series: ["bytes", false],
    shock: ["str", false],
  },
  "dhaniverse.profile.v1": {
    "arkiv.schema": ["str", true],
    env: ["str", true],
    name: ["str", true],
    season: ["i32", true],
    title: ["str", false],
    stamps: ["str", false],
    ens: ["str", false],
    fp: ["str", false],
  },
  "dhaniverse.paper.v1": {
    "arkiv.schema": ["str", true],
    env: ["str", true],
    day: ["u64", true],
    headline: ["str", false],
    stories: ["i32", false],
    bodyRef: ["str", false],
  },
  "dhaniverse.season.v1": {
    "arkiv.schema": ["str", true],
    env: ["str", true],
    season: ["i32", true],
    endedDay: ["u64", false],
    snapshotRef: ["str", false],
  },
}

test("every entity type goes on the wire with the documented attributes, types and indexes", async () => {
  const { fake, writer } = setup()
  const now = Date.now()
  const drafts = [
    campaignDraft(card(), "test", now)!,
    rushBoardDraft({ day: 41, season: 2, board: "rush", rows: [{ rank: 1, name: "asha", title: "Regular" }] }, "test", now),
    priceTickDraft({ startMs: now - 300_000, endMs: now, day: 41, samples: [[1, 4000], [2, 4100]], shock: "drought" }, "test", now)!,
    profileDraft({ name: "asha", title: "Regular", stamps: ["spice_run"], ens: "asha.tallyport.eth" }, 2, "test", now + 86_400_000, now),
    paperDraft({ day: 41, headline: "Drought hits the farms", stories: ["Prices up."] }, REF_B, "test", now),
    seasonDraft(1, 168, REF_A, "test", now),
  ]
  await writer.execute(drafts.map((draft) => ({ kind: "create" as const, draft })))
  assert.equal(fake.txs.length, 1, "one transaction for the whole batch")
  for (const [tag, shape] of Object.entries(SHAPES)) {
    const [e] = fake.ofSchema(tag)
    assert.ok(e, `${tag} was written`)
    const got = Object.fromEntries([...e.attributes].map(([n, a]) => [n, [a.type, a.indexed]]))
    assert.deepEqual(got, shape, `${tag} wire shape`)
    assert.equal(e.owner, writer.address.toLowerCase())
  }
})

test("expirations: campaign end, 48 h, 7 days, 30 days", async () => {
  const { fake, writer } = setup()
  const now = Date.now()
  const ends = Math.floor(now / 1000) + 10 * 3600
  await writer.execute([
    { kind: "create", draft: campaignDraft(card({ endsAt: ends }), "test", now)! },
    { kind: "create", draft: rushBoardDraft({ day: 1, season: null, board: "rush", rows: [] }, "test", now) },
    { kind: "create", draft: priceTickDraft({ startMs: now, endMs: now + 1, day: 1, samples: [[1, 1]], shock: null }, "test", now)! },
    { kind: "create", draft: paperDraft({ day: 1, headline: "h", stories: [] }, null, "test", now) },
  ])
  const at = fake.block
  const life = (tag: string) => (fake.ofSchema(tag)[0]?.expiresAt ?? 0n) - at
  const near = (got: bigint, want: bigint) => assert.ok(got >= want - 3n && got <= want + 3n, `${got} ≈ ${want}`)
  near(life("dhaniverse.campaign.v1"), 10n * BLOCKS_PER_HOUR)
  near(life("dhaniverse.rush_board.v1"), 48n * BLOCKS_PER_HOUR)
  near(life("dhaniverse.price_tick.v1"), 7n * 24n * BLOCKS_PER_HOUR)
  near(life("dhaniverse.paper.v1"), 30n * 24n * BLOCKS_PER_HOUR)
})

test("the Bounty Board query: live, slots left, not ended, ours, soonest first", async () => {
  const { fake, writer, reader, clients } = setup()
  const now = Date.now()
  const nowSec = Math.floor(now / 1000)
  await writer.execute([
    { kind: "create", draft: campaignDraft(card({ id: "1", endsAt: nowSec + 7200 }), "test", now)! },
    { kind: "create", draft: campaignDraft(card({ id: "2", endsAt: nowSec + 3600 }), "test", now)! },
    { kind: "create", draft: campaignDraft(card({ id: "3", slotsLeft: 0 }), "test", now)! },
    { kind: "create", draft: campaignDraft(card({ id: "4", status: "paused" }), "test", now)! },
    { kind: "create", draft: campaignDraft(card({ id: "5" }), "other-env", now)! },
  ])
  // Someone else writes a card with our schema tag: the owner filter must keep it out.
  const intruder = makeClients(
    arkivConfig({ privateKey: "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" }),
    fake.transport(),
    5,
  )
  await new SdkWriter(intruder.walletClient!, intruder.publicClient).execute([
    { kind: "create", draft: campaignDraft(card({ id: "666", title: "Free money" }), "test", now)! },
  ])

  const { cards, block } = await reader.campaigns(nowSec)
  assert.deepEqual(cards.map((c) => c.id), ["2", "1"])
  assert.equal(block, fake.block)
  assert.deepEqual(
    { ...cards[0], entity_key: undefined, expires_at_block: undefined },
    {
      id: "2",
      sponsor: "Mango Traders",
      title: "The Spice Run",
      template: "spice_run",
      payout: "500000",
      energy: 20,
      slots_left: 40,
      ends: nowSec + 3600,
      status: "live",
      swarm: REF_A,
      entity_key: undefined,
      expires_at_block: undefined,
    },
  )
  const q = fake.queries.at(-1)!.query
  assert.match(q, /^arkiv\.schema = str\('dhaniverse.campaign\.v1'\) AND /)
  assert.match(q, new RegExp(`\\$owner = addr\\(${writer.address}\\)`, "i"))
  assert.match(q, /env = str\('test'\)/)
  assert.match(q, /ORDER BY endsAt:u64 ASC$/)
  assert.equal(bountyBoardQueryText(clients.publicClient, writer.address, "test", nowSec), q)
})

test("boards, prices, profiles, papers and seasons read back through their queries", async () => {
  const { writer, reader } = setup()
  const now = Date.now()
  const t0 = Math.floor(now / 1000) - 3600
  const rows = [
    { rank: 1, name: "asha", title: "Regular" },
    { rank: 2, name: "ravi", title: "Newcomer" },
  ]
  await writer.execute([
    { kind: "create", draft: rushBoardDraft({ day: 40, season: 2, board: "rush", rows }, "test", now) },
    { kind: "create", draft: rushBoardDraft({ day: 41, season: 2, board: "rush", rows: rows.slice(0, 1) }, "test", now) },
    ...[0, 1, 2].map((i) => ({
      kind: "create" as const,
      draft: priceTickDraft(
        { startMs: (t0 + i * 300) * 1000, endMs: (t0 + (i + 1) * 300) * 1000, day: 41, samples: [[t0 + i * 300, 4000 + i], [t0 + i * 300 + 15, 4000 + i], [t0 + i * 300 + 30, 4010 + i]], shock: null },
        "test",
        now,
      )!,
    })),
    { kind: "create", draft: profileDraft({ name: "asha", title: "Regular", stamps: ["spice_run", "town_pass"], ens: "asha.tallyport.eth" }, 2, "test", now + 86_400_000, now) },
    { kind: "create", draft: paperDraft({ day: 41, headline: "Drought", stories: ["a", "b"] }, REF_B, "test", now) },
    { kind: "create", draft: paperDraft({ day: 42, headline: "Rain", stories: ["c"] }, null, "test", now) },
    { kind: "create", draft: seasonDraft(1, 168, REF_A, "test", now) },
  ])

  const day40 = await reader.rushBoard(40)
  assert.deepEqual(day40.board?.top, rows)
  assert.equal(day40.board?.leader, "asha")
  assert.equal((await reader.rushBoard(null)).board?.day, 41, "latest board")
  assert.equal((await reader.rushBoard(39)).board, null)

  const prices = await reader.prices(t0, t0 + 600)
  assert.deepEqual(prices.ticks.map((t) => t.start), [t0, t0 + 300])
  assert.deepEqual(prices.ticks[0]?.series, [[t0, 4000], [t0 + 30, 4010]], "unchanged samples are dropped")
  assert.equal(prices.ticks[0]?.high, 4010)

  const p = await reader.profile("asha")
  assert.deepEqual(p.profile?.stamps, ["spice_run", "town_pass"])
  assert.equal(p.profile?.ens, "asha.tallyport.eth")
  assert.equal((await reader.profile("nobody")).profile, null)

  const paper41 = await reader.paper(41)
  assert.equal(paper41.paper?.body_ref, REF_B)
  assert.equal(paper41.paper?.body, null, "body lives on Swarm, not inline")
  const latest = await reader.paper(null)
  assert.equal(latest.paper?.day, 42)
  assert.deepEqual(latest.paper?.body, { headline: "Rain", stories: ["c"] }, "inline only when Swarm had no copy")

  assert.equal((await reader.seasons()).seasons[0]?.snapshot_ref, REF_A)
})

test("patches change only what can change, extensions only move expiry later", async () => {
  const { fake, writer } = setup()
  const now = Date.now()
  const first = campaignDraft(card(), "test", now)!
  const { created } = await writer.execute([{ kind: "create", draft: first }])
  const key = created[0]!
  const updated = campaignDraft(card({ slotsLeft: 39, endsAt: card().endsAt + 86_400 }), "test", now)!
  await writer.execute([{ kind: "patch", draft: updated, entityKey: key, set: { slotsLeft: updated.values.slotsLeft, endsAt: updated.values.endsAt, fp: updated.fp }, extend: true }])
  const e = fake.entities.get(key)!
  assert.equal(e.attributes.get("slotsLeft")?.value, 39)
  assert.equal(e.attributes.get("campaignId")?.value, 7n)
  assert.ok(e.expiresAt > 4n * 24n * BLOCKS_PER_HOUR, "extended to the new end")
  assert.deepEqual(fake.txs.at(-1), { ops: 2, creates: 0, patches: 1, extends: 1 })
})

test("findExisting reconciles by natural key, owner and env", async () => {
  const { writer } = setup()
  const now = Date.now()
  const { created } = await writer.execute([
    { kind: "create", draft: campaignDraft(card({ id: "11" }), "test", now)! },
    { kind: "create", draft: campaignDraft(card({ id: "12" }), "elsewhere", now)! },
  ])
  const found = await writer.findExisting("campaign", "test", ["11", "12", "13"])
  assert.deepEqual([...found.keys()], ["11"])
  assert.equal(found.get("11")?.key, created[0])
  assert.ok(found.get("11")?.fp)
  assert.ok((found.get("11")?.expiresAtBlock ?? 0n) > (found.get("11")?.atBlock ?? 0n))
})

test("strings are cut to Arkiv's 128-byte limit without breaking a character", async () => {
  const { fake, writer } = setup()
  const now = Date.now()
  const long = "मुंबई ".repeat(40)
  await writer.execute([{ kind: "create", draft: campaignDraft(card({ title: long }), "test", now)! }])
  const title = fake.ofSchema("dhaniverse.campaign.v1")[0]!.attributes.get("title")!.value as string
  assert.ok(new TextEncoder().encode(title).length <= 128)
  assert.ok(title.endsWith("…"))
  assert.ok(!title.includes("�"))
})

test("the save's schemas go on the wire with the documented attributes, types, indexes and 180-day expiry", async () => {
  const { fake, clients, writer } = setup()
  const path = join(mkdtempSync(join(tmpdir(), "contract-")), "save.jsonl")
  writeFileSync(path, `${JSON.stringify({ seed: 1, rules: "r", quests: "q", chain: "offline", town_id: "t1" })}\n${JSON.stringify({ seq: 1, input: {}, events: [] })}\n`)
  const mirror = new SaveMirror({ path, key: parseKey("cd".repeat(32)), env: "test" }, clients.publicClient, writer.address)
  const ops = await mirror.plan(Date.now())
  assert.equal(ops.length, 2, "the city and the first batch")
  await writer.execute(ops)
  const SAVE_SHAPES: Record<string, Record<string, [string, boolean]>> = {
    "dhaniverse.city.v1": {
      "arkiv.schema": ["str", true],
      env: ["str", true],
      townId: ["str", true],
      chain: ["str", false],
      rulesHash: ["str", false],
      startedAt: ["u64", false],
      payload: ["bytes", false],
    },
    "dhaniverse.log.v1": {
      "arkiv.schema": ["str", true],
      env: ["str", true],
      townId: ["str", true],
      fromSeq: ["u64", true],
      toSeq: ["u64", true],
      prevHash: ["str", false],
      hash: ["str", false],
      payload: ["bytes", false],
    },
  }
  for (const [tag, shape] of Object.entries(SAVE_SHAPES)) {
    const [e] = fake.ofSchema(tag)
    assert.ok(e, `${tag} was written`)
    assert.deepEqual(Object.fromEntries([...e.attributes].map(([n, a]) => [n, [a.type, a.indexed]])), shape, `${tag} wire shape`)
    assert.equal(e.owner, writer.address.toLowerCase())
    const life = e.expiresAt - fake.block
    assert.ok(life >= 180n * 24n * BLOCKS_PER_HOUR - 3n && life <= 180n * 24n * BLOCKS_PER_HOUR + 3n, `${tag} lives 180 days, got ${life} blocks`)
  }
})
