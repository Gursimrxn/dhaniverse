// The read API: what the game's Bounty Board (through the server's `/arkiv/campaigns` proxy), the
// town website and the sponsor console read. Every answer comes from a live Arkiv query (behind a
// short cache), never from the publisher's own memory, and says which block it was read at.
//
//   GET  /health
//   GET  /campaigns                      live campaign cards (the Bounty Board)
//   GET  /boards/rush?day=N              a closed day's Rush board (latest without ?day)
//   GET  /prices?from=&to=               price batches, unix seconds (default: the last 24 h; at most 7 days)
//   GET  /prices/history?days=7          the last 1-7 days of price batches, without the per-sample series
//   GET  /profiles/:name                 a player's public profile, stamps, firsts, medals and streak
//   GET  /chests?day=                    chest draws (tier, contents, pity), newest first
//   GET  /feed?day=                      the town feed, newest first
//   GET  /pool?day=                      a closed day's house pool statement (latest without ?day)
//   GET  /papers/:day                    a day's paper index entry (`latest` for the newest)
//   GET  /seasons                        finished seasons and their Swarm snapshots
//   GET  /log?town=&from=                the town's save, restored from Arkiv: JSONL, setup line first when from=0
//   GET  /query                          the Bounty Board's Arkiv query, for anyone to run
//   POST /swarm/campaign-bundle          story JSON + images → Swarm reference (= metaHash)
//   GET  /swarm/campaign-bundle/:ref     a bundle's index.json, read back through Bee

import { timingSafeEqual } from "node:crypto"
import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http"
import type { Reader } from "./arkiv/queries.ts"
import { BundleError, LIMITS, buildBundle, parseBundleForm, uploadBundle } from "./bundle.ts"
import { RateLimiter, ReadCache } from "./cache.ts"
import { log } from "./log.ts"
import { withTimeout } from "./retry.ts"
import { publicSwarmRef } from "./swarmRef.ts"
import { SwarmError, type Swarm } from "./swarm.ts"

export type ReadApiDeps = {
  reader: Reader | null
  swarm: Swarm
  cacheMs: number
  queryTimeoutMs: number
  corsOrigins: string[]
  uploadsPerHour: number
  uploadsPerDay: number
  /** The live Bounty Board query text and the RPC it runs on, for /query. */
  queryInfo: () => { query: string; rpc: string; chainId: number; owner: string | null; env: string } | null
  health: () => Record<string, unknown>
  /** The Arkiv explorer (no trailing slash), for the proof links in every answer; null on a local chain. */
  explorer?: string | null
  /** The last save line Arkiv holds for a town (sent as `x-arkiv-tip` with `GET /log`). */
  restoreTip?: ((town: string) => Promise<number>) | null
  /** The save's lines from Arkiv (see `restoreLines`); absent when there is no log key or no Arkiv to read. */
  restore?: ((town: string, from: number) => AsyncIterable<string>) | null
  /** Bearer token for `GET /log` (32+ chars). Absent: the route does not exist (404). */
  restoreToken?: string | null
  /** Let non-loopback addresses use `GET /log` (still needs the token). */
  restoreAllowRemote?: boolean
  /** The caller's address; tests replace it. */
  peer?: (req: IncomingMessage) => string | undefined
  now?: () => number
}

const MAX_RANGE_S = 7 * 24 * 3600
const TOWN = /^[A-Za-z0-9_-]{1,128}$/
const NAME = /^[A-Za-z0-9 _.\-]{1,64}$/

class HttpError extends Error {
  readonly status: number
  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
}

function send(res: ServerResponse, status: number, body: unknown, extra: Record<string, string> = {}): void {
  const text = JSON.stringify(body, (_, v) => (typeof v === "bigint" ? v.toString() : v))
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(text),
    "x-content-type-options": "nosniff",
    ...extra,
  })
  res.end(text)
}

function intParam(v: string | null, name: string, min: number, max: number): number | null {
  if (v === null || v === "") return null
  if (!/^\d+$/.test(v)) throw new HttpError(400, `${name} must be a whole number`)
  const n = Number(v)
  if (n < min || n > max) throw new HttpError(400, `${name} must be from ${min} to ${max}`)
  return n
}

async function readBody(req: IncomingMessage, max: number): Promise<Uint8Array> {
  const declared = Number(req.headers["content-length"] ?? "0")
  if (declared > max) throw new HttpError(413, `the upload is larger than ${max} bytes`)
  const chunks: Buffer[] = []
  let size = 0
  for await (const chunk of req) {
    size += (chunk as Buffer).length
    if (size > max) throw new HttpError(413, `the upload is larger than ${max} bytes`)
    chunks.push(chunk as Buffer)
  }
  return new Uint8Array(Buffer.concat(chunks))
}

export function makeReadApi(deps: ReadApiDeps): Server {
  const now = deps.now ?? Date.now
  const cache = new ReadCache(deps.cacheMs)
  const bundleCache = new ReadCache(5 * 60_000, 60 * 60_000)
  const uploads = new RateLimiter(deps.uploadsPerHour, 3_600_000, deps.uploadsPerDay, 86_400_000)
  // Counted for reach.md: requests per route, and how many actually went to Arkiv (cache misses).
  const counts = { requests: {} as Record<string, number>, arkivQueries: 0, bundleUploads: 0 }
  const ROUTES = new Set(["/health", "/campaigns", "/boards/rush", "/prices", "/prices/history", "/profiles", "/papers", "/seasons", "/query", "/log", "/swarm", "/chests", "/feed", "/pool"])
  const count = (route: string) => {
    const r = ROUTES.has(route) ? route : "other"
    counts.requests[r] = (counts.requests[r] ?? 0) + 1
  }

  const cors = (req: IncomingMessage): Record<string, string> => {
    const origin = req.headers.origin
    const allowAll = deps.corsOrigins.includes("*")
    const allowed = allowAll ? "*" : origin && deps.corsOrigins.includes(origin) ? origin : null
    if (!allowed) return {}
    return {
      "access-control-allow-origin": allowed,
      "access-control-allow-methods": "GET, POST, OPTIONS",
      "access-control-allow-headers": "content-type",
      "access-control-max-age": "600",
      ...(allowAll ? {} : { vary: "origin" }),
    }
  }

  const fromArkiv = async <T extends { block: bigint }>(key: string, load: (r: Reader) => Promise<T>) => {
    const reader = deps.reader
    if (!reader) throw new HttpError(503, "Arkiv is not configured on this publisher (no ARKIV_PRIVATE_KEY or ARKIV_WRITER_ADDRESS)")
    try {
      const got = await cache.get(key, () => {
        counts.arkivQueries += 1
        return withTimeout(load(reader), deps.queryTimeoutMs, "Arkiv query")
      })
      const block = got.value.block
      return {
        source: "arkiv",
        owner: reader.owner,
        env: reader.env,
        explorer: deps.explorer ? { block: `${deps.explorer}/block/${block}`, owner: `${deps.explorer}/address/${reader.owner}` } : null,
        cached_at: new Date(got.cachedAt).toISOString(),
        stale: got.stale,
        ...got.value,
      }
    } catch (err) {
      if (err instanceof HttpError) throw err
      log.warn("Arkiv read failed", { key, error: err })
      throw new HttpError(502, "Arkiv did not answer in time; try again shortly")
    }
  }

  async function route(req: IncomingMessage, res: ServerResponse): Promise<void> {
    const url = new URL(req.url ?? "/", "http://publisher.local")
    const path = url.pathname.replace(/\/+$/, "") || "/"
    const method = req.method ?? "GET"
    const headers = cors(req)

    if (method === "OPTIONS") {
      res.writeHead(204, headers)
      res.end()
      return
    }

    if (method === "POST" && path === "/swarm/campaign-bundle") {
      if (!deps.swarm.configured) throw new HttpError(503, "Swarm is not configured on this publisher (BEE_URL, BEE_POSTAGE_BATCH)")
      const ip = req.socket.remoteAddress ?? "unknown"
      if (!uploads.allow(ip)) throw new HttpError(429, "too many uploads; try again later")
      const body = await readBody(req, LIMITS.requestBytes + 64 * 1024)
      const { story, images } = await parseBundleForm(String(req.headers["content-type"] ?? ""), body)
      const bundle = buildBundle(story, images)
      const out = await uploadBundle(deps.swarm, bundle)
      counts.bundleUploads += 1
      log.info("campaign bundle uploaded to Swarm", { ref: out.reference, bytes: out.bytes, images: images.length })
      send(res, 201, out, headers)
      return
    }

    if (method !== "GET" && method !== "HEAD") throw new HttpError(405, "GET, or POST to /swarm/campaign-bundle")
    const short = { ...headers, "cache-control": `public, max-age=${Math.max(1, Math.floor(deps.cacheMs / 1000))}` }

    count(path.startsWith("/profiles/") ? "/profiles" : path.startsWith("/papers/") ? "/papers" : path.startsWith("/swarm/") ? "/swarm" : path)
    if (path === "/health") return send(res, 200, { ...deps.health(), reads: counts }, { ...headers, "cache-control": "no-store" })

    if (path === "/log") {
      // The save is private: no token configured means no such route; CORS headers are never sent for it.
      if (!deps.restoreToken) throw new HttpError(404, "not here")
      const peer = (deps.peer ?? ((r) => r.socket.remoteAddress))(req) ?? ""
      if (!deps.restoreAllowRemote && !["127.0.0.1", "::1", "::ffff:127.0.0.1"].includes(peer)) throw new HttpError(403, "GET /log answers only on this machine")
      const given = Buffer.from(String(req.headers.authorization ?? "").replace(/^Bearer /i, ""))
      const want = Buffer.from(deps.restoreToken)
      if (given.length !== want.length || !timingSafeEqual(given, want)) throw new HttpError(401, "a bearer token is required")
      if (!deps.restore) throw new HttpError(503, "restoring needs DHANIVERSE_LOG_KEY and an Arkiv writer or ARKIV_WRITER_ADDRESS on this publisher")
      const town = url.searchParams.get("town") ?? ""
      if (!TOWN.test(town)) throw new HttpError(400, "town must be the town id from the save")
      const from = intParam(url.searchParams.get("from"), "from", 0, Number.MAX_SAFE_INTEGER) ?? 0
      let tip: number | null = null
      if (deps.restoreTip) {
        try {
          tip = await withTimeout(deps.restoreTip(town), deps.queryTimeoutMs, "Arkiv query")
        } catch (err) {
          log.warn("restore: could not read Arkiv's tip", { town, error: err })
          throw new HttpError(502, "Arkiv did not answer in time; try again shortly")
        }
      }
      res.writeHead(200, {
        "content-type": "application/x-ndjson; charset=utf-8",
        "cache-control": "no-store",
        "x-content-type-options": "nosniff",
        ...(tip === null ? {} : { "x-arkiv-tip": String(tip) }),
      })
      try {
        for await (const line of deps.restore(town, from)) {
          if (!res.write(`${line}
`)) await new Promise((ok) => res.once("drain", ok))
        }
      } catch (err) {
        log.warn("restore stopped", { town, from, error: err })
        res.write(`${JSON.stringify({ error: (err as Error).message })}
`)
      }
      res.end()
      return
    }

    if (path === "/campaigns") {
      const nowSec = Math.floor(now() / 1000)
      return send(res, 200, await fromArkiv("campaigns", (r) => r.campaigns(nowSec)), short)
    }

    if (path === "/boards/rush") {
      const day = intParam(url.searchParams.get("day"), "day", 0, Number.MAX_SAFE_INTEGER)
      const out = await fromArkiv(`rush:${day ?? "latest"}`, (r) => r.rushBoard(day))
      return send(res, out.board ? 200 : 404, out, short)
    }

    if (path === "/prices") {
      const nowSec = Math.floor(now() / 1000)
      const to = intParam(url.searchParams.get("to"), "to", 0, 2 ** 40) ?? nowSec
      const from = intParam(url.searchParams.get("from"), "from", 0, 2 ** 40) ?? to - 24 * 3600
      if (from >= to) throw new HttpError(400, "from must be before to")
      if (to - from > MAX_RANGE_S) throw new HttpError(400, "at most 7 days at a time")
      // Bucket the cache key to the batch size so a polling chart shares one Arkiv read.
      const key = `prices:${Math.floor(from / 60)}:${Math.floor(to / 60)}`
      return send(res, 200, await fromArkiv(key, (r) => r.prices(from, to)), short)
    }

    if (path === "/prices/history") {
      const days = intParam(url.searchParams.get("days"), "days", 1, 7) ?? 7
      const to = Math.floor(now() / 1000)
      const from = to - days * 24 * 3600
      const out = await fromArkiv(`prices-history:${days}:${Math.floor(to / 60)}`, async (r) => {
        const got = await r.prices(from, to)
        return { block: got.block, days, ticks: got.ticks.map(({ series: _series, ...t }) => t) }
      })
      return send(res, 200, out, short)
    }

    if (path === "/chests" || path === "/feed" || path === "/pool") {
      const day = intParam(url.searchParams.get("day"), "day", 0, Number.MAX_SAFE_INTEGER)
      const key = `${path}:${day ?? "latest"}`
      if (path === "/chests") return send(res, 200, await fromArkiv(key, (r) => r.chests(day)), short)
      if (path === "/feed") return send(res, 200, await fromArkiv(key, (r) => r.feed(day)), short)
      const out = await fromArkiv(key, (r) => r.pool(day))
      return send(res, out.pool ? 200 : 404, out, short)
    }

    const profile = /^\/profiles\/([^/]+)$/.exec(path)
    if (profile) {
      const name = decodeURIComponent(profile[1] as string)
      if (!NAME.test(name)) throw new HttpError(400, "not a player name")
      const out = await fromArkiv(`profile:${name}`, (r) => r.player(name))
      const found = out.profile || out.streak || out.stamps.length + out.firsts.length + out.medals.length > 0
      return send(res, found ? 200 : 404, out, short)
    }

    const paper = /^\/papers\/(latest|\d{1,15})$/.exec(path)
    if (paper) {
      const day = paper[1] === "latest" ? null : Number(paper[1])
      const out = await fromArkiv(`paper:${day ?? "latest"}`, (r) => r.paper(day))
      return send(res, out.paper ? 200 : 404, out, short)
    }

    if (path === "/seasons") return send(res, 200, await fromArkiv("seasons", (r) => r.seasons()), short)

    if (path === "/query") {
      const info = deps.queryInfo()
      if (!info) throw new HttpError(503, "Arkiv is not configured on this publisher")
      return send(
        res,
        200,
        {
          ...info,
          json_rpc: { jsonrpc: "2.0", id: 1, method: "arkiv_query", params: [info.query, { select: { key: true, owner: true, expiresAt: true, attributes: true }, limit: "0x64" }] },
        },
        { ...headers, "cache-control": "no-store" },
      )
    }

    const bundle = /^\/swarm\/campaign-bundle\/([0-9a-fA-Fx]{64,66})$/.exec(path)
    if (bundle) {
      const ref = publicSwarmRef(bundle[1])
      if (!ref) throw new HttpError(400, "not a Swarm reference")
      if (!deps.swarm.readable) throw new HttpError(503, "Swarm is not configured on this publisher (BEE_URL)")
      try {
        const got = await bundleCache.get(`bundle:${ref}`, async () => {
          const file = await deps.swarm.download(ref, "index.json", LIMITS.storyBytes)
          return JSON.parse(new TextDecoder().decode(file.data)) as unknown
        })
        return send(res, 200, { source: "swarm", reference: ref, index: got.value }, { ...headers, "cache-control": "public, max-age=3600, immutable" })
      } catch (err) {
        if (err instanceof SwarmError && err.status === 404) throw new HttpError(404, "no such bundle on Swarm")
        if (err instanceof SyntaxError) throw new HttpError(422, "that reference is not a campaign bundle")
        throw new HttpError(502, "Swarm did not answer")
      }
    }

    throw new HttpError(404, "not here")
  }

  return createServer((req, res) => {
    route(req, res).catch((err: unknown) => {
      const status = err instanceof HttpError || err instanceof BundleError ? err.status : err instanceof SwarmError ? 502 : 500
      if (status === 500) log.error("read API error", { path: req.url, error: err })
      const message = status === 500 ? "internal error" : (err as Error).message
      if (!res.headersSent) send(res, status, { error: message }, cors(req))
      else res.end()
    })
  })
}
