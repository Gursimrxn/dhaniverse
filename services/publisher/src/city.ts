// Reads the game server's public view (`GET /city`) and turns it into a Snapshot: only the fields the
// publisher publishes, checked and normalised. The server is another team's moving target, so the
// parser is tolerant about where a field lives and strict about what it holds; anything it can't
// read is left out and reported, never guessed.

import { publicSwarmRef } from "./swarmRef.ts"

export type BoardRow = { rank: number; name: string; title: string }

export type CampaignCard = {
  /** On-chain campaign id, decimal. */
  id: string
  sponsor: string
  title: string
  template: string
  /** USDC base units paid per completed claim (a public campaign parameter, not money anyone was paid). */
  payout: bigint
  energy: number
  slotsLeft: number
  /** Unix seconds. */
  endsAt: number
  status: "live" | "paused" | "cancelled" | "ended"
  /** Swarm reference of the campaign's story/media bundle (64 hex), if any. */
  swarmRef: string | null
}

export type Paper = { day: number; headline: string; stories: string[] }

export type Person = { name: string; title: string; stamps: string[]; ens: string | null }

export type Snapshot = {
  /** Unix ms when the publisher read it. */
  observedAt: number
  day: number
  /** `offline | anvil | sepolia` when the server says. */
  chain: string | null
  season: { number: number; endsDay: number | null } | null
  dayMs: number | null
  dayElapsedMs: number | null
  /** FOOD price in USDC base units. */
  price: number | null
  shock: string | null
  paper: Paper | null
  rush: { board: string; rows: BoardRow[] } | null
  people: Person[]
  /** null when the server doesn't publish a bounty list at all (pre-v3); [] when it publishes an empty one. */
  bounty: CampaignCard[] | null
  problems: string[]
}

type Json = Record<string, unknown>

const isObj = (v: unknown): v is Json => typeof v === "object" && v !== null && !Array.isArray(v)

function num(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v
  if (typeof v === "string" && /^-?\d+(\.\d+)?$/.test(v.trim())) return Number(v)
  return null
}

function whole(v: unknown): number | null {
  const n = num(v)
  return n !== null && Number.isSafeInteger(n) && n >= 0 ? n : null
}

function text(v: unknown, max = 2_000): string | null {
  if (typeof v !== "string") return null
  const t = v.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "").trim()
  return t ? t.slice(0, max) : null
}

function big(v: unknown): bigint | null {
  if (typeof v === "bigint") return v >= 0n ? v : null
  if (typeof v === "number" && Number.isSafeInteger(v) && v >= 0) return BigInt(v)
  if (typeof v === "string" && /^\d{1,30}$/.test(v.trim())) return BigInt(v.trim())
  return null
}

/** Seconds, ms or an ISO date, to unix seconds. */
export function toUnixSeconds(v: unknown): number | null {
  if (typeof v === "string" && !/^\d+$/.test(v.trim())) {
    const ms = Date.parse(v)
    return Number.isNaN(ms) ? null : Math.floor(ms / 1000)
  }
  const n = whole(v)
  if (n === null) return null
  return n > 100_000_000_000 ? Math.floor(n / 1000) : n
}

function first(o: Json, keys: string[]): unknown {
  for (const k of keys) if (o[k] !== undefined && o[k] !== null) return o[k]
  return undefined
}

function parseCard(raw: unknown, problems: string[]): CampaignCard | null {
  if (!isObj(raw)) {
    problems.push("bounty: a card is not an object")
    return null
  }
  const id = big(first(raw, ["id", "campaign", "campaign_id"]))
  const payout = big(first(raw, ["payout", "payout_per_claim"]))
  const energy = whole(first(raw, ["energy", "energy_cost"]))
  const slotsLeft = whole(first(raw, ["slots_left", "slotsLeft"]))
  const endsAt = toUnixSeconds(first(raw, ["ends", "ends_at", "end"]))
  const title = text(raw.title, 500)
  const template = text(raw.template, 64)
  if (id === null || payout === null || energy === null || slotsLeft === null || endsAt === null || !title || !template) {
    problems.push(`bounty: card ${String(raw.id)} is missing id, title, template, payout, energy, slots_left or ends`)
    return null
  }
  const rawRef = first(raw, ["swarm", "swarm_ref", "meta_hash", "metaHash"])
  let swarmRef: string | null = null
  if (rawRef !== undefined && rawRef !== "" && !/^0x0{64}$/i.test(String(rawRef))) {
    swarmRef = publicSwarmRef(rawRef)
    if (swarmRef === null) problems.push(`bounty: card ${id} has an unusable swarm reference; left off the card`)
  }
  const statusRaw = text(raw.status, 16)?.toLowerCase()
  let status: CampaignCard["status"] = "live"
  if (statusRaw === "paused" || statusRaw === "cancelled" || statusRaw === "ended") status = statusRaw
  else if (raw.paused === true) status = "paused"
  return {
    id: id.toString(),
    sponsor: text(raw.sponsor, 200) ?? "unknown",
    title,
    template,
    payout,
    energy,
    slotsLeft,
    endsAt,
    status,
    swarmRef,
  }
}

function parseRows(raw: unknown): BoardRow[] {
  if (!Array.isArray(raw)) return []
  const rows: BoardRow[] = []
  for (const r of raw) {
    if (!isObj(r)) continue
    const rank = whole(r.rank)
    const name = text(r.name, 64)
    if (rank === null || !name) continue
    rows.push({ rank, name, title: text(r.title, 64) ?? "" })
  }
  return rows.sort((a, b) => a.rank - b.rank).slice(0, 50)
}

/** The board the day closes on: the daily Rush board if the server has one, else the Rush board it has. */
const RUSH_BOARDS = ["rush_today", "rush_day", "rush_daily", "rush"]

export function parseCity(body: unknown, observedAt: number): Snapshot {
  const problems: string[] = []
  if (!isObj(body)) throw new Error("/city did not return a JSON object")
  const day = whole(body.day)
  if (day === null) throw new Error("/city has no day")

  const food = isObj(body.food) ? body.food : body
  const price = whole(food.price)
  const shockRaw = food.shock ?? body.shock
  const shock = shockRaw == null ? null : (text(typeof shockRaw === "string" ? shockRaw : JSON.stringify(shockRaw), 120) ?? null)

  let season: Snapshot["season"] = null
  if (isObj(body.season)) {
    const n = whole(body.season.number)
    if (n !== null) season = { number: n, endsDay: whole(body.season.ends_day) }
  }

  let paper: Paper | null = null
  if (isObj(body.paper)) {
    const pd = whole(body.paper.day)
    const headline = text(body.paper.headline, 500)
    if (pd !== null && headline) {
      const stories = Array.isArray(body.paper.stories)
        ? body.paper.stories.map((s) => text(s, 4_000)).filter((s): s is string => s !== null).slice(0, 50)
        : []
      paper = { day: pd, headline, stories }
    } else problems.push("paper: missing day or headline")
  }

  let rush: Snapshot["rush"] = null
  if (isObj(body.boards)) {
    for (const board of RUSH_BOARDS) {
      if (Array.isArray(body.boards[board])) {
        rush = { board, rows: parseRows(body.boards[board]) }
        break
      }
    }
  }

  const people: Person[] = []
  if (Array.isArray(body.people)) {
    const seen = new Set<string>()
    for (const p of body.people) {
      if (!isObj(p)) continue
      const name = text(p.name, 64)
      if (!name || seen.has(name)) continue
      seen.add(name)
      const stampsRaw = p.stamps
      const stamps = Array.isArray(stampsRaw)
        ? stampsRaw.map((s) => text(s, 32)).filter((s): s is string => s !== null)
        : typeof stampsRaw === "string"
          ? stampsRaw.split(",").map((s) => s.trim()).filter(Boolean)
          : []
      people.push({ name, title: text(p.title, 64) ?? "", stamps: stamps.slice(0, 32), ens: text(p.ens, 100) })
    }
  }

  let bounty: CampaignCard[] | null = null
  if (Array.isArray(body.bounty)) {
    bounty = []
    const seen = new Set<string>()
    for (const raw of body.bounty) {
      const card = parseCard(raw, problems)
      if (card && !seen.has(card.id)) {
        seen.add(card.id)
        bounty.push(card)
      }
    }
  }

  return {
    observedAt,
    day,
    chain: text(body.chain, 16),
    season,
    dayMs: whole(body.day_ms),
    dayElapsedMs: whole(body.day_elapsed_ms),
    price,
    shock,
    paper,
    rush,
    people,
    bounty,
    problems,
  }
}

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>

/** One read of `/city`, with a deadline. Throws on anything but a 200 with a parsable body. */
export async function fetchCity(serverUrl: string, timeoutMs: number, fetchImpl: FetchLike = fetch): Promise<Snapshot> {
  const res = await fetchImpl(`${serverUrl}/city`, {
    signal: AbortSignal.timeout(timeoutMs),
    headers: { accept: "application/json", "user-agent": "tallyport-publisher" },
  })
  if (!res.ok) throw new Error(`/city answered ${res.status}`)
  const body: unknown = await res.json()
  return parseCity(body, Date.now())
}
