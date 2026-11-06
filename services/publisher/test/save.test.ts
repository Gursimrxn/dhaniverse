// The save on Arkiv, end to end: a save file on disk, the publisher's flush, the in-memory Arkiv node, and
// `GET /log` reading it all back.

import assert from "node:assert/strict"
import { randomBytes } from "node:crypto"
import { appendFileSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs"
import type { AddressInfo } from "node:net"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { after, test } from "node:test"
import { makeClients } from "../src/arkiv/client.ts"
import { SdkWriter } from "../src/arkiv/writer.ts"
import { loadConfig } from "../src/config.ts"
import { parseKey } from "../src/crypto.ts"
import { setSink } from "../src/log.ts"
import { Publisher } from "../src/publisher.ts"
import { makeReadApi } from "../src/readapi.ts"
import { BATCH_LIMIT, SaveMirror, arkivTip, createSaveMirror, restoreLines } from "../src/save.ts"
import { MemoryStateStore, emptyState } from "../src/state.ts"
import { Swarm } from "../src/swarm.ts"
import { FakeArkiv } from "./fakeArkiv.ts"
import { snapshot } from "./helpers.ts"
import { arkivConfig } from "./helpers.ts"

const logs: string[] = []
setSink((line) => logs.push(line))

const KEY = parseKey("ab".repeat(32))
const SETUP = JSON.stringify({ seed: 7, rules: "[rules]", quests: "[q]", chain: "offline", town_id: "town1" })
const dir = mkdtempSync(join(tmpdir(), "save-test-"))
const servers: { close(): void }[] = []
after(() => servers.forEach((s) => s.close()))

type Pad = () => string
const noPad: Pad = () => ""
let fileNo = 0
const line = (seq: number, pad = "") => JSON.stringify({ seq, input: { Tick: { n: seq, pad } }, events: [{ Moved: seq }] })

function append(path: string, first: number, last: number, pad: Pad = noPad): void {
  let out = ""
  for (let s = first; s <= last; s++) out += `${line(s, pad())}\n`
  appendFileSync(path, out)
}
/** A save file with a setup line and lines 1..last. */
function save(last: number, pad: Pad = noPad): string {
  const path = join(dir, `save-${fileNo++}.jsonl`)
  writeFileSync(path, `${SETUP}\n`)
  append(path, 1, last, pad)
  return path
}
const expected = (last: number) => [SETUP, ...Array.from({ length: last }, (_, i) => line(i + 1))]

const TOKEN = "t".repeat(40)

let lastTip: string | null = null

function rig(over: Record<string, unknown> = {}) {
  const holder: { mirror: SaveMirror | null } = { mirror: null }
  const fake = new FakeArkiv()
  const clients = makeClients(arkivConfig(), fake.transport(), 5)
  const writer = new SdkWriter(clients.walletClient!, clients.publicClient)
  const clock = { t: Date.now() }
  const start = (path: string, key: Buffer | null = KEY) => {
    const mirror = createSaveMirror({ savePath: path, logKey: key ?? undefined, env: "test" }, clients.publicClient, writer.address)
    const store = new MemoryStateStore(emptyState("test", writer.address))
    const swarm = new Swarm({ url: undefined, postageBatch: undefined, pin: true, deferred: true, timeoutMs: 1_000 })
    holder.mirror = mirror
    const p = new Publisher({ env: "test", priceBatchMs: 300_000, profileFallbackDays: 7, maxOpsPerTx: 12, txTimeoutMs: 5_000 }, writer, swarm, store, () => clock.t, mirror)
    return { p, mirror }
  }
  const api = makeReadApi({
    reader: null,
    swarm: new Swarm({ url: undefined, postageBatch: undefined, pin: true, deferred: true, timeoutMs: 1_000 }),
    cacheMs: 0,
    queryTimeoutMs: 2_000,
    corsOrigins: ["*"],
    uploadsPerHour: 1,
    uploadsPerDay: 1,
    queryInfo: () => null,
    health: () => ({ ok: true, save: holder.mirror?.status() ?? null }),
    restoreToken: TOKEN,
    ...over,
    restore: (town, from) => restoreLines(clients.publicClient, writer.address, "test", KEY, town, from),
    restoreTip: (town) => arkivTip(clients.publicClient, writer.address, "test", town),
  })
  servers.push(api)
  const listening = new Promise((ok) => api.listen(0, "127.0.0.1", () => ok(null)))
  const get = async (path: string, auth?: string) => {
    await listening
    return fetch(`http://127.0.0.1:${(api.address() as AddressInfo).port}${path}`, { headers: auth ? { authorization: auth } : {} })
  }
  const restore = async (from = 0, town = "town1") => {
    const res = await get(`/log?town=${town}&from=${from}`, `Bearer ${TOKEN}`)
    assert.equal(res.status, 200)
    lastTip = res.headers.get("x-arkiv-tip")
    const body = await res.text()
    return body === "" ? [] : body.replace(/\n$/, "").split("\n")
  }
  return { fake, clients, writer, clock, start, restore, get }
}

/** Flushes until nothing more is waiting; returns the transactions sent. */
async function drain(p: Publisher): Promise<number> {
  let txs = 0
  for (let i = 0; i < 50; i++) {
    const r = await p.flush()
    if (r.sent > 0) txs++
    if (!r.more) break
  }
  return txs
}

const logEntities = (fake: FakeArkiv) =>
  fake.ofSchema("dhaniverse.log.v1").sort((a, b) => Number(a.attributes.get("fromSeq")!.value) - Number(b.attributes.get("fromSeq")!.value))

test("mirrors a save in order", async () => {
  const r = rig()
  const { p } = r.start(save(250))
  await p.init()
  await drain(p)
  const cities = r.fake.ofSchema("dhaniverse.city.v1")
  assert.equal(cities.length, 1)
  assert.equal(cities[0]!.attributes.get("townId")?.value, "town1")
  assert.equal(cities[0]!.attributes.get("chain")?.value, "offline")
  const batches = logEntities(r.fake)
  assert.ok(batches.length >= 1)
  assert.equal(batches[0]!.attributes.get("prevHash")?.value, "0".repeat(64))
  assert.deepEqual(await r.restore(0), expected(250))
  assert.equal(lastTip, "250", "GET /log says how far Arkiv goes, so a cut-short answer is caught")
  assert.deepEqual(await r.restore(200), expected(250).slice(200), "from=200 starts at line 200, no setup line")
  // Nothing readable in clear on Arkiv.
  const moved = Buffer.from("Moved").toString("hex")
  for (const e of [...cities, ...batches]) assert.ok(!String(e.attributes.get("payload")!.value).includes(moved))
})

test("restarts where it left off", async () => {
  const r = rig()
  const path = save(100)
  const first = r.start(path)
  await first.p.init()
  await drain(first.p)
  assert.equal(logEntities(r.fake).length, 1)
  const hash1 = logEntities(r.fake)[0]!.attributes.get("hash")!.value

  append(path, 101, 150)
  const second = r.start(path) // a new publisher that remembers nothing
  await second.p.init()
  await drain(second.p)
  const batches = logEntities(r.fake)
  assert.equal(batches.length, 2, "only the new lines were written")
  assert.equal(batches[1]!.attributes.get("fromSeq")?.value, 101n)
  assert.equal(batches[1]!.attributes.get("toSeq")?.value, 150n)
  assert.equal(batches[1]!.attributes.get("prevHash")?.value, hash1)
  assert.equal(r.fake.ofSchema("dhaniverse.city.v1").length, 1, "the city is not created twice")
  assert.deepEqual(await r.restore(0), expected(150))
})

test("splits at 96 KiB", async () => {
  const r = rig()
  const path = save(400, () => randomBytes(750).toString("base64"))
  const lines = readFileSync(path, "utf8").trimEnd().split("\n")
  const { p } = r.start(path)
  await p.init()
  await drain(p)
  const batches = logEntities(r.fake)
  assert.ok(batches.length >= 3, `${batches.length} batches`)
  let next = 1n
  for (const b of batches) {
    const bytes = (String(b.attributes.get("payload")!.value).length - 2) / 2
    assert.ok(bytes <= BATCH_LIMIT + 28, `payload ${bytes} bytes`)
    assert.equal(b.attributes.get("fromSeq")?.value, next)
    next = (b.attributes.get("toSeq")!.value as bigint) + 1n
  }
  assert.equal(next, 401n)
  assert.deepEqual(await r.restore(0), lines)
})

test("ignores a half line at the end", async () => {
  const r = rig()
  const path = save(3)
  appendFileSync(path, line(4).slice(0, 20))
  const { p } = r.start(path)
  await p.init()
  await drain(p)
  assert.deepEqual(await r.restore(0), expected(3))
  appendFileSync(path, `${line(4).slice(20)}\n`)
  await drain(p)
  assert.deepEqual(await r.restore(0), expected(4))
})

async function threeBatches() {
  const r = rig()
  const path = save(30)
  const { p } = r.start(path)
  await p.init()
  await drain(p)
  append(path, 31, 60)
  await drain(p)
  append(path, 61, 90)
  await drain(p)
  assert.equal(logEntities(r.fake).length, 3)
  return r
}

test("restore stops on a broken chain", async () => {
  // A changed ciphertext byte: the batch won't decrypt.
  let r = await threeBatches()
  const payload = logEntities(r.fake)[1]!.attributes.get("payload")!
  const hex = String(payload.value)
  payload.value = hex.slice(0, 60) + (hex[60] === "0" ? "1" : "0") + hex.slice(61)
  let out = await r.restore(0)
  assert.match(JSON.parse(out.at(-1)!).error, /decrypt/)
  assert.deepEqual(out.slice(0, -1), expected(30), "the good batch before it was streamed, nothing after")

  // A changed link: the third batch no longer follows the second.
  r = await threeBatches()
  logEntities(r.fake)[2]!.attributes.get("prevHash")!.value = "f".repeat(64)
  out = await r.restore(0)
  assert.match(JSON.parse(out.at(-1)!).error, /broken chain/)
  assert.deepEqual(out.slice(0, -1), expected(60))
})

test("restore stops on a gap", async () => {
  const r = await threeBatches()
  r.fake.entities.delete(logEntities(r.fake)[1]!.key)
  const out = await r.restore(0)
  assert.match(JSON.parse(out.at(-1)!).error, /gap/)
  assert.deepEqual(out.slice(0, -1), expected(30))
})

test("renews entities under 150 days", async () => {
  const r = rig()
  const { p } = r.start(save(10))
  await p.init()
  await drain(p)
  const all = () => [...r.fake.ofSchema("dhaniverse.city.v1"), ...r.fake.ofSchema("dhaniverse.log.v1")]
  assert.equal(all().length, 2)
  const day = 24 * 3600 * 1000
  const blocksPerDay = 43_200n

  r.fake.block += 20n * blocksPerDay
  r.clock.t += 2 * day
  assert.equal((await p.flush()).sent, 0, "20 days old: nothing to renew")

  r.fake.block += 140n * blocksPerDay // 160 days old: 20 left
  r.clock.t += 2 * day
  assert.equal((await p.flush()).sent, 2, "the city and the log batch are extended")
  for (const e of all()) assert.ok(e.expiresAt - r.fake.block > 170n * blocksPerDay, "back to about 180 days")

  r.clock.t += 2 * day
  assert.equal((await p.flush()).sent, 0, "nothing left to renew")
})

test("no log mirror without a key", async () => {
  const r = rig()
  logs.length = 0
  const { p, mirror } = r.start(save(10), null)
  assert.equal(mirror, null)
  assert.ok(logs.some((l) => l.includes("DHANIVERSE_LOG_KEY")), "it says why")
  await p.init()
  assert.deepEqual(await p.flush(), { sent: 0, more: false })
  assert.equal(r.fake.entities.size, 0)
  assert.throws(() => loadConfig({ DHANIVERSE_LOG_KEY: "nothex" }), /DHANIVERSE_LOG_KEY/)
  assert.equal(loadConfig({ DHANIVERSE_LOG_KEY: "ab".repeat(32), SAVE_PATH: "x" }).logKey?.length, 32)
})

test("restore needs the token", async () => {
  const r = rig()
  const { p } = r.start(save(5))
  await p.init()
  await drain(p)
  const url = "/log?town=town1&from=0"
  assert.equal((await r.get(url)).status, 401)
  assert.equal((await r.get(url, "Bearer wrong")).status, 401)
  assert.equal((await r.get(url, `Bearer ${"x".repeat(40)}`)).status, 401)
  assert.equal((await r.get(url, `Bearer ${TOKEN}`)).status, 200)
  assert.ok(!logs.some((l) => l.includes(TOKEN) || l.includes("Moved")), "neither the token nor a decrypted line is logged")
})

test("restore is off without a token configured", async () => {
  const r = rig({ restoreToken: null })
  assert.equal((await r.get("/log?town=town1&from=0", `Bearer ${TOKEN}`)).status, 404)
  assert.throws(() => loadConfig({ DHANIVERSE_RESTORE_TOKEN: "short" }), /at least 32/)
})

test("restore refuses a remote address", async () => {
  const url = "/log?town=town1&from=0"
  const remote = rig({ peer: () => "203.0.113.9" })
  assert.equal((await remote.get(url, `Bearer ${TOKEN}`)).status, 403)
  assert.equal((await rig({ peer: () => "203.0.113.9", restoreAllowRemote: true }).get(url, `Bearer ${TOKEN}`)).status, 200)
})

test("an oversized line stops the mirror but not the public writes", async () => {
  const r = rig()
  const path = save(0)
  appendFileSync(path, `${line(1, randomBytes(200 * 1024).toString("base64"))}
`)
  const { p, mirror } = r.start(path)
  await p.init()
  logs.length = 0
  p.observe(
    snapshot({
      observedAt: r.clock.t,
      bounty: [{ id: "1", sponsor: "S", title: "T", template: "spice_run", payout: 1n, energy: 1, slotsLeft: 1, endsAt: Math.floor(r.clock.t / 1000) + 86_400, status: "live", swarmRef: null }],
    }),
  )
  assert.equal((await p.flush()).sent, 1, "the public card went")
  assert.equal(r.fake.ofSchema("dhaniverse.campaign.v1").length, 1)
  assert.equal(mirror!.status().state, "stopped")
  assert.match(mirror!.status().error!, /line 1 \(at byte \d+\)/)
  assert.ok(logs.some((l) => l.includes("STOPPED")))
  assert.equal(r.fake.ofSchema("dhaniverse.log.v1").length + r.fake.ofSchema("dhaniverse.city.v1").length, 0)
  assert.equal((await p.flush()).sent, 0, "and nothing keeps failing")
})

test("a garbled line shows in /health", async () => {
  const r = rig()
  const path = save(2)
  appendFileSync(path, "{this is not json\n")
  const { p } = r.start(path)
  await p.init()
  await p.flush()
  const health = (await (await r.get("/health")).json()) as { save: { state: string; error: string; lastSeq: number; offset: number } }
  assert.equal(health.save.state, "stuck")
  assert.match(health.save.error, /byte \d+/)
  assert.equal(health.save.lastSeq, 2)
  assert.ok(health.save.offset > 0)
})

test("restore skips an exact duplicate batch", async () => {
  const r = await threeBatches()
  const mid = logEntities(r.fake)[1]!
  const key = ("0x" + "ab".repeat(32)) as `0x${string}`
  r.fake.entities.set(key, { ...mid, key, attributes: new Map(mid.attributes) })
  assert.deepEqual(await r.restore(0), expected(90))
})
