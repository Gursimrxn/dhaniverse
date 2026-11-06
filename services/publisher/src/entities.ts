// Pure functions from what the server published to what goes on Arkiv, and back from an Arkiv row
// to what the read API returns. No I/O here: the contract test drives these through the real SDK.

import { createHash } from "node:crypto"
import { i32, u64 } from "@arkiv-network/sdk/schema"
import type { CampaignCard, Paper, Person, BoardRow } from "./city.ts"
import { publicSwarmRef } from "./swarmRef.ts"
import type { DraftType, EntityType } from "./schemas.ts"

/** When an entity should stop existing. Resolved to an SDK expiration by the writer. */
export type Expiry = { atMs: number } | { forSeconds: number }

export type Draft = {
  type: DraftType
  /** Identity within (type, env): what the publisher dedupes and reconciles on. */
  id: string
  values: Record<string, unknown>
  expiry: Expiry
  /** Unix ms the entity is expected to expire, for the publisher's own bookkeeping. */
  expiresAtMs: number
  fp: string
}

const HOUR = 3_600_000
const DAY = 24 * HOUR
export const RUSH_BOARD_TTL_MS = 48 * HOUR
export const PRICE_TICK_TTL_MS = 7 * DAY
export const PAPER_TTL_MS = 30 * DAY
export const SEASON_TTL_MS = 180 * DAY
/** Arkiv's MAX_LIFETIME is 7,884,000 blocks ≈ 182.5 days at 2 s; stay inside it. */
export const MAX_TTL_MS = 180 * DAY

const enc = new TextEncoder()

/** Cuts a string to fit Arkiv's 128-byte string limit without splitting a character. */
export function fitStr(s: string, maxBytes = 128): string {
  if (enc.encode(s).length <= maxBytes) return s
  let out = ""
  let used = 0
  for (const ch of s) {
    const n = enc.encode(ch).length
    if (used + n + 3 > maxBytes) break // room for the ellipsis (3 bytes)
    out += ch
    used += n
  }
  return `${out}…`
}

export function fingerprint(content: unknown): string {
  const json = JSON.stringify(content, (_, v) => (typeof v === "bigint" ? v.toString() : v))
  return createHash("sha256").update(json).digest("hex").slice(0, 16)
}

const json = (v: unknown): Uint8Array => enc.encode(JSON.stringify(v))

function clampTtl(atMs: number, now: number): number {
  return Math.min(atMs, now + MAX_TTL_MS)
}

export function campaignDraft(card: CampaignCard, env: string, now: number): Draft | null {
  const endMs = card.endsAt * 1000
  if (endMs <= now) return null
  const content = {
    status: card.status,
    template: card.template,
    sponsor: card.sponsor,
    title: card.title,
    payout: card.payout,
    energy: card.energy,
    slotsLeft: card.slotsLeft,
    endsAt: card.endsAt,
    metaHash: card.swarmRef,
  }
  const fp = fingerprint(content)
  const values: Record<string, unknown> = {
    env,
    campaignId: u64(BigInt(card.id)),
    status: card.status,
    template: fitStr(card.template),
    sponsor: fitStr(card.sponsor),
    title: fitStr(card.title),
    payout: u64(card.payout),
    energy: i32(Math.min(card.energy, 2_147_483_647)),
    slotsLeft: i32(Math.min(card.slotsLeft, 2_147_483_647)),
    endsAt: u64(card.endsAt),
    fp,
  }
  const ref = card.swarmRef === null ? null : publicSwarmRef(card.swarmRef)
  if (ref) values.metaHash = ref
  const atMs = clampTtl(endMs, now)
  return { type: "campaign", id: card.id, values, expiry: { atMs }, expiresAtMs: atMs, fp }
}

export function rushBoardDraft(
  input: { day: number; season: number | null; board: string; rows: BoardRow[] },
  env: string,
  now: number,
): Draft {
  const rows = input.rows.slice(0, 50).map((r) => ({ rank: r.rank, name: r.name, title: r.title }))
  const values: Record<string, unknown> = {
    env,
    day: u64(input.day),
    board: fitStr(input.board),
    entries: rows.length,
    top: json(rows),
  }
  if (input.season !== null) values.season = i32(input.season)
  if (rows[0]) values.leader = fitStr(rows[0].name)
  return {
    type: "rush_board",
    id: String(input.day),
    values,
    expiry: { forSeconds: RUSH_BOARD_TTL_MS / 1000 },
    expiresAtMs: now + RUSH_BOARD_TTL_MS,
    fp: fingerprint(rows),
  }
}

export type PriceWindow = {
  startMs: number
  endMs: number
  day: number
  /** [unixSeconds, price] in time order. */
  samples: [number, number][]
  shock: string | null
}

/** Keeps the samples where the price moved, plus the first and the last. */
export function compactSeries(samples: [number, number][]): [number, number][] {
  const out: [number, number][] = []
  samples.forEach((s, i) => {
    const prev = out[out.length - 1]
    if (i === 0 || i === samples.length - 1 || !prev || prev[1] !== s[1]) out.push(s)
  })
  return out
}

export function priceTickDraft(w: PriceWindow, env: string, now: number): Draft | null {
  if (w.samples.length === 0) return null
  const prices = w.samples.map((s) => s[1])
  const startTs = Math.floor(w.startMs / 1000)
  const series = compactSeries(w.samples)
  const values: Record<string, unknown> = {
    env,
    startTs: u64(startTs),
    endTs: u64(Math.floor(w.endMs / 1000)),
    day: u64(w.day),
    open: u64(prices[0] as number),
    high: u64(Math.max(...prices)),
    low: u64(Math.min(...prices)),
    close: u64(prices[prices.length - 1] as number),
    samples: w.samples.length,
    series: json(series),
  }
  if (w.shock) values.shock = fitStr(w.shock)
  return {
    type: "price_tick",
    id: String(startTs),
    values,
    expiry: { forSeconds: PRICE_TICK_TTL_MS / 1000 },
    expiresAtMs: now + PRICE_TICK_TTL_MS,
    fp: fingerprint(series),
  }
}

export function profileDraft(p: Person, season: number | null, env: string, expiresAtMs: number, now: number): Draft {
  const content = { title: p.title, stamps: p.stamps, ens: p.ens, season }
  const fp = fingerprint(content)
  const values: Record<string, unknown> = {
    env,
    name: fitStr(p.name),
    title: fitStr(p.title),
    stamps: fitStr(p.stamps.join(",")),
    fp,
  }
  if (season !== null) values.season = i32(season)
  if (p.ens) values.ens = fitStr(p.ens)
  const atMs = clampTtl(Math.max(expiresAtMs, now + HOUR), now)
  return { type: "profile", id: p.name, values, expiry: { atMs }, expiresAtMs: atMs, fp }
}

export function paperDraft(paper: Paper, bodyRef: string | null, env: string, now: number): Draft {
  const values: Record<string, unknown> = {
    env,
    day: u64(paper.day),
    headline: fitStr(paper.headline),
    stories: paper.stories.length,
  }
  const ref = bodyRef === null ? null : publicSwarmRef(bodyRef)
  if (ref) values.bodyRef = ref
  else values.body = json({ headline: paper.headline, stories: paper.stories })
  return {
    type: "paper",
    id: String(paper.day),
    values,
    expiry: { forSeconds: PAPER_TTL_MS / 1000 },
    expiresAtMs: now + PAPER_TTL_MS,
    fp: fingerprint({ paper, ref }),
  }
}

export function seasonDraft(season: number, endedDay: number, snapshotRef: string, env: string, now: number): Draft {
  const ref = publicSwarmRef(snapshotRef)
  if (ref === null) throw new Error("season snapshot needs a public Swarm reference")
  return {
    type: "season",
    id: String(season),
    values: { env, season: i32(season), endedDay: u64(endedDay), snapshotRef: ref },
    expiry: { forSeconds: SEASON_TTL_MS / 1000 },
    expiresAtMs: now + SEASON_TTL_MS,
    fp: fingerprint({ season, endedDay, ref }),
  }
}

/** Patch only what a card or profile can change; identity columns never move. */
export const PATCHABLE: Partial<Record<EntityType, string[]>> = {
  campaign: ["status", "sponsor", "title", "template", "payout", "energy", "slotsLeft", "endsAt", "metaHash", "fp"],
  profile: ["title", "stamps", "ens", "season", "fp"],
}

// ---- reading back -------------------------------------------------------------------------------

type Cell = { value: unknown } | undefined
const v = (c: unknown): unknown => (c && typeof c === "object" && "value" in c ? (c as { value: unknown }).value : undefined)
const s = (c: unknown): string | null => {
  const x = v(c)
  return typeof x === "string" ? x : null
}
const n = (c: unknown): number | null => {
  const x = v(c)
  if (typeof x === "number") return x
  if (typeof x === "bigint") return Number(x)
  return null
}
const bigStr = (c: unknown): string | null => {
  const x = v(c)
  return typeof x === "bigint" || typeof x === "number" ? x.toString() : null
}
function hexJson(c: unknown): unknown {
  const x = v(c)
  if (typeof x !== "string" || !x.startsWith("0x")) return null
  try {
    return JSON.parse(Buffer.from(x.slice(2), "hex").toString("utf8"))
  } catch {
    return null
  }
}

export type Row = Record<string, Cell | unknown>

const meta = (row: Row) => ({
  entity_key: row.$key ?? null,
  expires_at_block: typeof row.$expiresAt === "bigint" ? row.$expiresAt.toString() : null,
})

/** The same field names as the server's `city.bounty` cards, plus where the card lives on Arkiv. */
export function campaignFromRow(row: Row) {
  return {
    id: bigStr(row.campaignId),
    sponsor: s(row.sponsor),
    title: s(row.title),
    template: s(row.template),
    payout: bigStr(row.payout),
    energy: n(row.energy),
    slots_left: n(row.slotsLeft),
    ends: n(row.endsAt),
    status: s(row.status),
    swarm: s(row.metaHash),
    ...meta(row),
  }
}

export function rushBoardFromRow(row: Row) {
  return {
    day: n(row.day),
    season: n(row.season),
    board: s(row.board),
    leader: s(row.leader),
    entries: n(row.entries),
    top: hexJson(row.top) ?? [],
    ...meta(row),
  }
}

export function priceTickFromRow(row: Row) {
  return {
    start: n(row.startTs),
    end: n(row.endTs),
    day: n(row.day),
    open: n(row.open),
    high: n(row.high),
    low: n(row.low),
    close: n(row.close),
    samples: n(row.samples),
    series: hexJson(row.series) ?? [],
    shock: s(row.shock),
    ...meta(row),
  }
}

export function profileFromRow(row: Row) {
  const stamps = s(row.stamps)
  return {
    name: s(row.name),
    title: s(row.title),
    stamps: stamps ? stamps.split(",").filter(Boolean) : [],
    ens: s(row.ens),
    season: n(row.season),
    ...meta(row),
  }
}

export function paperFromRow(row: Row) {
  return {
    day: n(row.day),
    headline: s(row.headline),
    stories: n(row.stories),
    body_ref: s(row.bodyRef),
    body: hexJson(row.body),
    ...meta(row),
  }
}

export function seasonFromRow(row: Row) {
  return { season: n(row.season), ended_day: n(row.endedDay), snapshot_ref: s(row.snapshotRef), ...meta(row) }
}
