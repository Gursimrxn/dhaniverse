// Every Arkiv read the publisher makes. Each one filters on the trusted writer (`$owner`) and the
// `env` attribute: a named schema's tag can be written by anyone, so the owner filter is what makes
// a row ours.

import type { PublicArkivClient } from "@arkiv-network/sdk"
import { MAX_LIMIT, and, asc, desc, eq, gt, gte, lt, or } from "@arkiv-network/sdk/query"
import { i32, u64 } from "@arkiv-network/sdk/schema"
import type { Hex } from "viem"
import {
  campaignFromRow,
  paperFromRow,
  priceTickFromRow,
  profileFromRow,
  rushBoardFromRow,
  seasonFromRow,
  type Row,
} from "../entities.ts"
import { SCHEMAS, type EntityType } from "../schemas.ts"

// The SDK types each builder by its schema; the generic paths below cross schemas, so they go
// through this one loosely typed view. Every call still runs the SDK's runtime checks.
type LooseBuilder = {
  from(schema: unknown): LooseBuilder
  ownedBy(owner: Hex): LooseBuilder
  where(...e: unknown[]): LooseBuilder
  orderBy(o: unknown): LooseBuilder
  limit(n: number): LooseBuilder
  offset(n: number): LooseBuilder
  toString(): string
  fetch(): Promise<{ entities: readonly Row[]; blockNumber: bigint }>
}

function select(client: PublicArkivClient, selection?: Record<string, true>): LooseBuilder {
  const c = client as unknown as { select(s?: unknown): LooseBuilder }
  return selection ? c.select(selection) : c.select()
}

/** The column that identifies an entity of each type within one env, and how its value is typed. */
export const NATURAL_KEY: Record<EntityType, { column: string; value: (id: string) => unknown }> = {
  campaign: { column: "campaignId", value: (id) => u64(BigInt(id)) },
  rush_board: { column: "day", value: (id) => u64(BigInt(id)) },
  price_tick: { column: "startTs", value: (id) => u64(BigInt(id)) },
  profile: { column: "name", value: (id) => id },
  paper: { column: "day", value: (id) => u64(BigInt(id)) },
  season: { column: "season", value: (id) => i32(Number(id)) },
}

const HAS_FP: ReadonlySet<EntityType> = new Set(["campaign", "profile"])
const IDS_PER_QUERY = 10

/** `atBlock`: the block the answer was read at, so `expiresAtBlock - atBlock` is the time left in blocks. */
export type Existing = { key: Hex; fp: string | null; expiresAtBlock: bigint | null; atBlock: bigint | null }

/** Which of these ids already have a live entity from `owner`: used to reconcile after a restart or an unclear failure. */
export async function findExisting(
  client: PublicArkivClient,
  owner: Hex,
  type: EntityType,
  env: string,
  ids: string[],
): Promise<Map<string, Existing>> {
  const found = new Map<string, Existing>()
  const { column, value } = NATURAL_KEY[type]
  const selection: Record<string, true> = { $key: true, $expiresAt: true, [column]: true }
  if (HAS_FP.has(type)) selection.fp = true
  for (let i = 0; i < ids.length; i += IDS_PER_QUERY) {
    const chunk = ids.slice(i, i + IDS_PER_QUERY)
    const match = chunk.length === 1 ? eq(column, value(chunk[0] as string) as never) : or(...chunk.map((id) => eq(column, value(id) as never)))
    const res = await select(client, selection)
      .from(SCHEMAS[type])
      .ownedBy(owner)
      .where(and(eq("env", env), match))
      .limit(MAX_LIMIT)
      .fetch()
    for (const row of res.entities) {
      const cell = row[column] as { value?: unknown } | undefined
      const id = cell?.value === undefined ? null : String(cell.value)
      if (id === null || !row.$key) continue
      const fpCell = row.fp as { value?: unknown } | undefined
      found.set(id, {
        key: row.$key as Hex,
        fp: typeof fpCell?.value === "string" ? fpCell.value : null,
        expiresAtBlock: typeof row.$expiresAt === "bigint" ? row.$expiresAt : null,
        atBlock: res.blockNumber,
      })
    }
  }
  return found
}

export type Reader = ReturnType<typeof makeReader>

export function makeReader(client: PublicArkivClient, owner: Hex, env: string) {
  const base = (type: EntityType) => select(client).from(SCHEMAS[type]).ownedBy(owner)

  return {
    owner,
    env,

    /** Live cards with slots left, soonest-ending first: the Bounty Board. */
    async campaigns(nowSec: number) {
      const res = await base("campaign")
        .where(and(eq("env", env), eq("status", "live"), gt("endsAt", u64(nowSec)), gt("slotsLeft", i32(0))))
        .orderBy(asc("endsAt"))
        .limit(MAX_LIMIT)
        .fetch()
      return { block: res.blockNumber, cards: res.entities.map(campaignFromRow) }
    },

    /** One closed day's Rush board, or the latest when `day` is null. */
    async rushBoard(day: number | null) {
      const q = base("rush_board")
      const res = await (day === null
        ? q.where(eq("env", env)).orderBy(desc("day")).limit(1)
        : q.where(and(eq("env", env), eq("day", u64(day)))).limit(1)
      ).fetch()
      const row = res.entities[0]
      return { block: res.blockNumber, board: row ? rushBoardFromRow(row) : null }
    },

    /** Price batches that start in [fromSec, toSec), oldest first, at most `maxRows`. */
    async prices(fromSec: number, toSec: number, maxRows = 2_100) {
      const ticks: ReturnType<typeof priceTickFromRow>[] = []
      let block = 0n
      for (let offset = 0; offset < maxRows; offset += MAX_LIMIT) {
        const res = await base("price_tick")
          .where(and(eq("env", env), gte("startTs", u64(fromSec)), lt("startTs", u64(toSec))))
          .orderBy(asc("startTs"))
          .limit(MAX_LIMIT)
          .offset(offset)
          .fetch()
        block = res.blockNumber
        ticks.push(...res.entities.map(priceTickFromRow))
        if (res.entities.length < MAX_LIMIT) break
      }
      return { block, ticks: ticks.slice(0, maxRows) }
    },

    async profile(name: string) {
      const res = await base("profile").where(and(eq("env", env), eq("name", name))).limit(1).fetch()
      const row = res.entities[0]
      return { block: res.blockNumber, profile: row ? profileFromRow(row) : null }
    },

    /** One day's paper, or the latest when `day` is null. */
    async paper(day: number | null) {
      const q = base("paper")
      const res = await (day === null
        ? q.where(eq("env", env)).orderBy(desc("day")).limit(1)
        : q.where(and(eq("env", env), eq("day", u64(day)))).limit(1)
      ).fetch()
      const row = res.entities[0]
      return { block: res.blockNumber, paper: row ? paperFromRow(row) : null }
    },

    async seasons() {
      const res = await base("season").where(eq("env", env)).orderBy(desc("season")).limit(MAX_LIMIT).fetch()
      return { block: res.blockNumber, seasons: res.entities.map(seasonFromRow) }
    },
  }
}

/** The query string the Bounty Board sends, for the README and the judges. */
export function bountyBoardQueryText(client: PublicArkivClient, owner: Hex, env: string, nowSec: number): string {
  return select(client)
    .from(SCHEMAS.campaign)
    .ownedBy(owner)
    .where(and(eq("env", env), eq("status", "live"), gt("endsAt", u64(nowSec)), gt("slotsLeft", i32(0))))
    .orderBy(asc("endsAt"))
    .toString()
}
