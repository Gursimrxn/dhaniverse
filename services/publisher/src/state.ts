// What the publisher remembers between runs: which entities it wrote (key, fingerprint, expiry), and
// the records it has seen but not yet written (a closed day's board, a closed price window, a new
// paper). It is a cache, not the truth: after a restart or an unclear failure the publisher asks
// Arkiv what exists before creating anything.

import { mkdir, readFile, rename, writeFile } from "node:fs/promises"
import { join } from "node:path"
import type { BoardRow, Paper, Person } from "./city.ts"
import type { PriceWindow } from "./entities.ts"
import type { EntityType } from "./schemas.ts"

export type Tracked = { key: `0x${string}`; fp: string; expiresAtMs: number }

export type BoardInput = { day: number; season: number | null; board: string; rows: BoardRow[] }
export type SeasonInput = { season: number; endedDay: number; board: BoardRow[]; people: Person[] }

export type Pending =
  | { type: "rush_board"; id: string; input: BoardInput; attempts: number }
  | { type: "price_tick"; id: string; input: PriceWindow; attempts: number }
  | { type: "paper"; id: string; input: Paper; bodyRef: string | null; attempts: number; inline: boolean }
  | { type: "season"; id: string; input: SeasonInput; snapshotRef: string | null; attempts: number }

export type State = {
  v: 1
  env: string
  writer: string | null
  tracked: Record<EntityType, Record<string, Tracked>>
  pending: Pending[]
  lastDay: number | null
  dayBoard: BoardInput | null
  lastSeason: number | null
  seasonView: { board: BoardRow[]; people: Person[] } | null
  lastPaperDay: number | null
  priceWindow: PriceWindow | null
}

export function emptyState(env: string, writer: string | null): State {
  return {
    v: 1,
    env,
    writer,
    tracked: { campaign: {}, rush_board: {}, price_tick: {}, profile: {}, paper: {}, season: {} },
    pending: [],
    lastDay: null,
    dayBoard: null,
    lastSeason: null,
    seasonView: null,
    lastPaperDay: null,
    priceWindow: null,
  }
}

export interface StateStore {
  load(): Promise<State>
  save(state: State): Promise<void>
}

export class FileStateStore implements StateStore {
  private readonly file: string
  private readonly dir: string
  private readonly env: string
  private readonly writer: string | null
  private chain: Promise<void> = Promise.resolve()

  constructor(dir: string, env: string, writer: string | null) {
    this.dir = dir
    this.env = env
    this.writer = writer
    this.file = join(dir, `state-${env}.json`)
  }

  async load(): Promise<State> {
    let raw: string
    try {
      raw = await readFile(this.file, "utf8")
    } catch {
      return emptyState(this.env, this.writer)
    }
    const parsed = JSON.parse(raw) as State
    if (parsed.v !== 1 || parsed.env !== this.env) return emptyState(this.env, this.writer)
    // Keys belong to their owner: a different writer starts with nothing tracked, but keeps what it hasn't written.
    if (parsed.writer !== this.writer) {
      const fresh = emptyState(this.env, this.writer)
      return { ...parsed, writer: this.writer, tracked: fresh.tracked }
    }
    return parsed
  }

  /** Atomic (write then rename) and serialised, so a crash never leaves half a file. */
  save(state: State): Promise<void> {
    const text = JSON.stringify(state)
    this.chain = this.chain
      .catch(() => {})
      .then(async () => {
        await mkdir(this.dir, { recursive: true })
        const tmp = `${this.file}.tmp`
        await writeFile(tmp, text, "utf8")
        await rename(tmp, this.file)
      })
    return this.chain
  }
}

export class MemoryStateStore implements StateStore {
  state: State
  saves = 0
  constructor(state: State) {
    this.state = state
  }
  async load(): Promise<State> {
    return structuredClone(this.state)
  }
  async save(state: State): Promise<void> {
    this.saves += 1
    this.state = structuredClone(state)
  }
}
