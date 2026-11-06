// Unit tests: config, the /city parser, entity builders, Swarm references, retry and cache.

import assert from "node:assert/strict"
import { test } from "node:test"
import { ReadCache, RateLimiter } from "../src/cache.ts"
import { fetchCity, parseCity, toUnixSeconds } from "../src/city.ts"
import { ConfigError, loadConfig } from "../src/config.ts"
import { campaignDraft, compactSeries, fitStr, priceTickDraft } from "../src/entities.ts"
import { Backoff, TimeoutError, backoffMs, withTimeout } from "../src/retry.ts"
import { isEncryptedRef, publicSwarmRef, refToBytes32 } from "../src/swarmRef.ts"
import { REF_A, TEST_KEY } from "./helpers.ts"

test("config: defaults with nothing set, so the publisher runs as a no-op", () => {
  const c = loadConfig({})
  assert.equal(c.arkiv.privateKey, undefined)
  assert.equal(c.bee.url, undefined)
  assert.equal(c.serverUrl, "http://127.0.0.1:7878")
  assert.equal(c.port, 8787)
  assert.equal(c.env, "dev")
  assert.equal(c.arkiv.chain, "rabdi")
})

test("config: validates keys, batch ids, urls and numbers, without echoing the key", () => {
  const c = loadConfig({ ARKIV_PRIVATE_KEY: TEST_KEY.slice(2), BEE_URL: "http://localhost:1633/", BEE_POSTAGE_BATCH: `0x${"AB".repeat(32)}` })
  assert.equal(c.arkiv.privateKey, TEST_KEY)
  assert.equal(c.bee.url, "http://localhost:1633")
  assert.equal(c.bee.postageBatch, "ab".repeat(32))
  const bad = "0xnotakeybutlongenoughtobesecret"
  assert.throws(() => loadConfig({ ARKIV_PRIVATE_KEY: bad }), (e: Error) => e instanceof ConfigError && !e.message.includes(bad))
  assert.throws(() => loadConfig({ BEE_POSTAGE_BATCH: "1234" }), ConfigError)
  assert.throws(() => loadConfig({ SERVER_URL: "ftp://x" }), ConfigError)
  assert.throws(() => loadConfig({ POLL_INTERVAL_MS: "10" }), ConfigError)
  assert.throws(() => loadConfig({ PUBLISHER_ENV: "Has Spaces" }), ConfigError)
})

const CITY = {
  protocol: 3,
  day: 41,
  day_ms: 3_600_000,
  day_elapsed_ms: 600_000,
  chain: "sepolia",
  season: { number: 2, shock: "drought", ends_day: 168 },
  food: { price: 4120, open_price: 4000, shock: { kind: "drought" } },
  paper: { day: 41, headline: "Drought", stories: ["one", 7, "two"] },
  boards: { rush: [{ rank: 2, name: "ravi", title: "Newcomer" }, { rank: 1, name: "asha", title: "Regular" }] },
  people: [{ name: "asha", title: "Regular", stamps: ["town_pass"], ens: "asha.tallyport.eth" }, { name: "asha", title: "dup" }, { title: "no name" }],
  bounty: [
    { id: 7, sponsor: "Mango", title: "Spice Run", template: "spice_run", payout: "500000", energy: 20, slots_left: 40, ends: 1_794_000_000, swarm: `0x${REF_A}` },
    { id: 8, sponsor: "X", title: "Leaky", template: "spice_run", payout: 1, energy: 1, slots_left: 1, ends: 1_794_000_000, swarm: REF_A + REF_A },
    { id: 9, title: "Broken" },
  ],
}

test("city: reads the public view, tolerant about shape, strict about values", () => {
  const s = parseCity(CITY, 1000)
  assert.equal(s.day, 41)
  assert.equal(s.price, 4120)
  assert.equal(s.shock, '{"kind":"drought"}')
  assert.deepEqual(s.season, { number: 2, endsDay: 168 })
  assert.deepEqual(s.paper, { day: 41, headline: "Drought", stories: ["one", "two"] })
  assert.deepEqual(s.rush?.rows.map((r) => r.name), ["asha", "ravi"], "sorted by rank")
  assert.deepEqual(s.people.map((p) => p.name), ["asha"], "deduplicated, nameless dropped")
  assert.equal(s.bounty?.length, 2)
  assert.equal(s.bounty?.[0]?.swarmRef, REF_A, "0x stripped")
  assert.equal(s.bounty?.[0]?.payout, 500_000n)
  assert.equal(s.bounty?.[1]?.swarmRef, null, "an encrypted (128-hex) reference never reaches a public entity")
  assert.equal(s.problems.length, 2)
})

test("city: a pre-v3 server without bounty is not an empty bounty", () => {
  const s = parseCity({ day: 3, food: { price: 4000 } }, 1)
  assert.equal(s.bounty, null)
  assert.throws(() => parseCity({ nope: 1 }, 1), /no day/)
  assert.throws(() => parseCity([], 1), /not return a JSON object/)
})

test("city: fetchCity gives up after its deadline and on non-200", async () => {
  await assert.rejects(fetchCity("http://x", 50, async () => new Response("{}", { status: 503 })), /503/)
  await assert.rejects(
    fetchCity("http://x", 20, (_u, init) => new Promise((_, reject) => init?.signal?.addEventListener("abort", () => reject(new Error("aborted"))))),
    /aborted/,
  )
})

test("toUnixSeconds: seconds, milliseconds and ISO dates", () => {
  assert.equal(toUnixSeconds(1_794_000_000), 1_794_000_000)
  assert.equal(toUnixSeconds(1_794_000_000_123), 1_794_000_000)
  assert.equal(toUnixSeconds("2026-11-07T03:30:00Z"), Date.UTC(2026, 10, 7, 3, 30) / 1000)
  assert.equal(toUnixSeconds("soon"), null)
})

test("swarm references: plain 32-byte only; encrypted ones refused", () => {
  assert.equal(publicSwarmRef(`0x${REF_A.toUpperCase()}`), REF_A)
  assert.equal(publicSwarmRef(REF_A + REF_A), null)
  assert.equal(publicSwarmRef("0".repeat(64)), null)
  assert.equal(isEncryptedRef(REF_A + REF_A), true)
  assert.equal(refToBytes32(REF_A), `0x${REF_A}`)
  assert.throws(() => refToBytes32("nope"))
})

test("entities: fitStr, series compaction, ended campaigns are not created", () => {
  assert.equal(fitStr("short"), "short")
  assert.ok(new TextEncoder().encode(fitStr("x".repeat(500))).length <= 128)
  assert.deepEqual(compactSeries([[1, 5], [2, 5], [3, 6], [4, 6], [5, 6]]), [[1, 5], [3, 6], [5, 6]])
  const now = Date.now()
  const card = { id: "1", sponsor: "s", title: "t", template: "spice_run", payout: 1n, energy: 1, slotsLeft: 1, endsAt: Math.floor(now / 1000) - 1, status: "live" as const, swarmRef: null }
  assert.equal(campaignDraft(card, "dev", now), null)
  assert.equal(priceTickDraft({ startMs: 0, endMs: 1, day: 0, samples: [], shock: null }, "dev", now), null)
  // A campaign that runs past Arkiv's maximum lifetime is capped inside it.
  const far = campaignDraft({ ...card, endsAt: Math.floor(now / 1000) + 400 * 86_400 }, "dev", now)!
  assert.ok(far.expiresAtMs <= now + 180 * 86_400_000)
})

test("retry: backoff grows, is capped, and resets", () => {
  assert.equal(backoffMs(1, 1000, 60_000, () => 1), 1000)
  assert.equal(backoffMs(3, 1000, 60_000, () => 1), 4000)
  assert.equal(backoffMs(20, 1000, 60_000, () => 1), 60_000)
  let t = 0
  const b = new Backoff(1000, 60_000, () => t)
  assert.ok(b.ready())
  b.failed()
  assert.ok(!b.ready())
  t += 60_000
  assert.ok(b.ready())
  b.succeeded()
  assert.equal(b.attempts, 0)
})

test("retry: withTimeout rejects slow work", async () => {
  await assert.rejects(withTimeout(new Promise(() => {}), 10, "slow thing"), TimeoutError)
  assert.equal(await withTimeout(Promise.resolve(3), 1000, "fast"), 3)
})

test("cache: dedupes concurrent loads, serves stale on error, then gives up", async () => {
  let t = 0
  let calls = 0
  const c = new ReadCache(1000, 5000, 10, () => t)
  const load = async () => ++calls
  const [a, b] = await Promise.all([c.get("k", load), c.get("k", load)])
  assert.equal(calls, 1)
  assert.equal(a.value, b.value)
  t = 2000
  const stale = await c.get("k", async () => {
    throw new Error("down")
  })
  assert.equal(stale.stale, true)
  t = 10_000
  await assert.rejects(c.get("k", async () => {
    throw new Error("down")
  }))
})

test("rate limiter: per caller and overall", () => {
  let t = 0
  const r = new RateLimiter(2, 1000, 3, 10_000, () => t)
  assert.ok(r.allow("a"))
  assert.ok(r.allow("a"))
  assert.ok(!r.allow("a"))
  assert.ok(r.allow("b"))
  assert.ok(!r.allow("c"), "global cap")
  t = 20_000
  assert.ok(r.allow("a"))
})
