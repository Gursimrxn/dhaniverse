// The read API over HTTP, reading live from the in-memory Arkiv node through the real SDK.

import assert from "node:assert/strict"
import type { AddressInfo } from "node:net"
import { after, before, test } from "node:test"
import { makeClients } from "../src/arkiv/client.ts"
import { bountyBoardQueryText, makeReader } from "../src/arkiv/queries.ts"
import { SdkWriter } from "../src/arkiv/writer.ts"
import { campaignDraft, paperDraft, priceTickDraft, profileDraft, rushBoardDraft } from "../src/entities.ts"
import { setSink } from "../src/log.ts"
import { makeReadApi } from "../src/readapi.ts"
import { Swarm } from "../src/swarm.ts"
import { FakeArkiv } from "./fakeArkiv.ts"
import { BATCH, FakeBee } from "./fakeBee.ts"
import { REF_A, arkivConfig } from "./helpers.ts"

setSink(() => {})
const fake = new FakeArkiv()
const bee = new FakeBee()
const clients = makeClients(arkivConfig(), fake.transport(), 5)
const writer = new SdkWriter(clients.walletClient!, clients.publicClient)
const reader = makeReader(clients.publicClient, writer.address, "test")
const swarm = new Swarm({ url: "http://bee.test", postageBatch: BATCH, pin: true, deferred: true, timeoutMs: 1000 }, bee.fetch)
const nowSec = Math.floor(Date.now() / 1000)

const server = makeReadApi({
  reader,
  swarm,
  cacheMs: 0,
  queryTimeoutMs: 2_000,
  corsOrigins: ["*"],
  uploadsPerHour: 2,
  uploadsPerDay: 100,
  queryInfo: () => ({ query: bountyBoardQueryText(clients.publicClient, writer.address, "test", nowSec), rpc: "https://rpc.example", chainId: 7794095, owner: writer.address, env: "test" }),
  health: () => ({ ok: true }),
})
const unconfigured = makeReadApi({
  reader: null,
  swarm: new Swarm({ url: undefined, postageBatch: undefined, pin: true, deferred: true, timeoutMs: 1000 }),
  cacheMs: 0,
  queryTimeoutMs: 1000,
  corsOrigins: ["https://tallyport.example"],
  uploadsPerHour: 1,
  uploadsPerDay: 1,
  queryInfo: () => null,
  health: () => ({ ok: true }),
})
let base = ""
let base2 = ""

before(async () => {
  const now = Date.now()
  await writer.execute([
    { kind: "create", draft: campaignDraft({ id: "7", sponsor: "Mango", title: "Spice Run", template: "spice_run", payout: 500_000n, energy: 20, slotsLeft: 3, endsAt: nowSec + 3600, status: "live", swarmRef: REF_A }, "test", now)! },
    { kind: "create", draft: rushBoardDraft({ day: 40, season: 1, board: "rush", rows: [{ rank: 1, name: "asha", title: "Regular" }] }, "test", now) },
    { kind: "create", draft: priceTickDraft({ startMs: (nowSec - 600) * 1000, endMs: (nowSec - 300) * 1000, day: 40, samples: [[nowSec - 600, 4000]], shock: null }, "test", now)! },
    { kind: "create", draft: profileDraft({ name: "asha", title: "Regular", stamps: ["town_pass"], ens: null }, 1, "test", now + 86_400_000, now) },
    { kind: "create", draft: paperDraft({ day: 40, headline: "Drought", stories: ["x"] }, REF_A, "test", now) },
  ])
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r))
  await new Promise<void>((r) => unconfigured.listen(0, "127.0.0.1", r))
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
  base2 = `http://127.0.0.1:${(unconfigured.address() as AddressInfo).port}`
})
after(() => {
  server.close()
  unconfigured.close()
})

const get = async (path: string, b = base) => {
  const res = await fetch(b + path)
  return { status: res.status, headers: res.headers, body: (await res.json()) as Record<string, any> }
}

test("GET /campaigns: live cards from Arkiv, with the block they were read at", async () => {
  const r = await get("/campaigns")
  assert.equal(r.status, 200)
  assert.equal(r.body.source, "arkiv")
  assert.equal(r.body.owner, writer.address)
  assert.equal(r.body.cards.length, 1)
  assert.equal(r.body.cards[0].id, "7")
  assert.equal(r.body.cards[0].slots_left, 3)
  assert.equal(r.body.cards[0].swarm, REF_A)
  assert.equal(r.body.block, String(fake.block))
  assert.equal(r.headers.get("access-control-allow-origin"), "*")
})

test("GET /boards/rush, /prices, /profiles/:name, /papers/:day", async () => {
  assert.equal((await get("/boards/rush?day=40")).body.board.leader, "asha")
  assert.equal((await get("/boards/rush")).body.board.day, 40)
  assert.equal((await get("/boards/rush?day=39")).status, 404)
  assert.equal((await get("/boards/rush?day=abc")).status, 400)
  const prices = await get(`/prices?from=${nowSec - 3600}&to=${nowSec}`)
  assert.equal(prices.body.ticks.length, 1)
  assert.equal((await get(`/prices?from=0&to=${30 * 86_400}`)).status, 400, "at most 7 days")
  assert.equal((await get(`/prices?from=10&to=5`)).status, 400)
  assert.deepEqual((await get("/profiles/asha")).body.profile.stamps, ["town_pass"])
  assert.equal((await get("/profiles/nobody")).status, 404)
  assert.equal((await get("/profiles/%3Cscript%3E")).status, 400)
  assert.equal((await get("/papers/40")).body.paper.body_ref, REF_A)
  assert.equal((await get("/papers/latest")).body.paper.day, 40)
  assert.equal((await get("/papers/41")).status, 404)
})

test("Arkiv unreachable: 502 with a plain message, not a crash", async () => {
  fake.down = true
  try {
    const r = await get("/profiles/ravi")
    assert.equal(r.status, 502)
    assert.match(r.body.error, /Arkiv/)
  } finally {
    fake.down = false
  }
})

test("GET /query: the Bounty Board query and a JSON-RPC body anyone can POST", async () => {
  const r = await get("/query")
  assert.equal(r.body.chainId, 7794095)
  assert.match(r.body.query, /dhaniverse.campaign\.v1/)
  assert.equal(r.body.json_rpc.method, "arkiv_query")
})

test("POST /swarm/campaign-bundle: uploads and answers with the reference and metaHash; rate limited", async () => {
  const form = new FormData()
  form.set("story", JSON.stringify({ title: "Spice Run", story: "Bring saffron." }))
  form.append("image", new File([new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1])], "c.png", { type: "image/png" }))
  const res = await fetch(`${base}/swarm/campaign-bundle`, { method: "POST", body: form })
  assert.equal(res.status, 201)
  const out = (await res.json()) as { reference: string; metaHash: string }
  assert.equal(out.metaHash, `0x${out.reference}`)
  const back = await get(`/swarm/campaign-bundle/${out.reference}`)
  assert.equal(back.body.index.title, "Spice Run")
  const bad = new FormData()
  bad.set("story", "{not json")
  assert.equal((await fetch(`${base}/swarm/campaign-bundle`, { method: "POST", body: bad })).status, 400)
  assert.equal((await fetch(`${base}/swarm/campaign-bundle`, { method: "POST", body: form })).status, 429, "two an hour per caller")
})

test("not configured: 503s that say what's missing; CORS only for listed origins", async () => {
  const r = await get("/campaigns", base2)
  assert.equal(r.status, 503)
  assert.match(r.body.error, /ARKIV_PRIVATE_KEY/)
  const up = await fetch(`${base2}/swarm/campaign-bundle`, { method: "POST", body: new FormData() })
  assert.equal(up.status, 503)
  const listed = await fetch(`${base2}/health`, { headers: { origin: "https://tallyport.example" } })
  assert.equal(listed.headers.get("access-control-allow-origin"), "https://tallyport.example")
  const other = await fetch(`${base2}/health`, { headers: { origin: "https://evil.example" } })
  assert.equal(other.headers.get("access-control-allow-origin"), null)
  assert.equal((await get("/nope")).status, 404)
})
