// The publisher: turns what the game server shows in public into Arkiv entities and Swarm content.
//
// - `observe(snapshot)` runs on every poll. It is synchronous and does no I/O: it samples the price,
//   notices a closed day, a new season and a new paper, and queues those records.
// - `flush()` runs on its own timer, off the poll path. It plans one Arkiv transaction (creates,
//   patches and extensions, at most `maxOpsPerTx`), uploads whatever Swarm content that needs first,
//   and sends it. A failure backs off; nothing is lost (queued records are persisted) and nothing
//   the game does waits on it.

import type { Snapshot } from "./city.ts"
import {
  PATCHABLE,
  PRICE_TICK_TTL_MS,
  campaignDraft,
  fingerprint,
  paperDraft,
  priceTickDraft,
  profileDraft,
  rushBoardDraft,
  seasonDraft,
  type Draft,
  type PriceWindow,
} from "./entities.ts"
import type { ArkivWriter, Op } from "./arkiv/writer.ts"
import { log, throttled } from "./log.ts"
import { Backoff, TimeoutError, withTimeout } from "./retry.ts"
import type { SaveMirror } from "./save.ts"
import { isSaveType, type EntityType } from "./schemas.ts"
import type { State, StateStore, Pending } from "./state.ts"
import type { Swarm } from "./swarm.ts"

const HOUR = 3_600_000
const DAY = 24 * HOUR
const BLOCK_MS = 2_000
/** Renew a profile when it has less than this left and the season (or fallback) lets it live longer. */
const RENEW_WITHIN_MS = 2 * DAY
const MAX_SAMPLES_PER_WINDOW = 2_000
const MAX_SEASON_PEOPLE = 500
/** Swarm attempts for a paper body before the paper goes up with its text inline instead. */
const PAPER_SWARM_ATTEMPTS = 5

export type PublisherOptions = {
  env: string
  priceBatchMs: number
  profileFallbackDays: number
  maxOpsPerTx: number
  txTimeoutMs: number
}

export type PublisherStats = {
  polls: number
  lastPollAt: number | null
  txs: number
  /** `ms`: wall-clock time from sending the transaction to having its receipt. */
  lastTx: { hash: string; at: number; ops: number; ms: number } | null
  lastArkivError: string | null
  lastSwarmError: string | null
  entitiesWritten: Record<string, number>
  swarmUploads: number
}

type Planned = { op: Op; pending: Pending | null }

const ORDER: EntityType[] = ["campaign", "paper", "rush_board", "season", "price_tick", "profile"]

export class Publisher {
  state!: State
  latest: Snapshot | null = null
  readonly stats: PublisherStats = {
    polls: 0,
    lastPollAt: null,
    txs: 0,
    lastTx: null,
    lastArkivError: null,
    lastSwarmError: null,
    entitiesWritten: {},
    swarmUploads: 0,
  }
  private readonly opts: PublisherOptions
  private readonly writer: ArkivWriter | null
  private readonly swarm: Swarm
  private readonly store: StateStore
  private readonly now: () => number
  private readonly save: SaveMirror | null
  private readonly unsynced = new Set<EntityType>(ORDER)
  private readonly arkivBackoff: Backoff
  private readonly swarmBackoff: Backoff
  private readonly warn = throttled(10 * 60_000)
  private flushing = false
  private dirty = false

  constructor(opts: PublisherOptions, writer: ArkivWriter | null, swarm: Swarm, store: StateStore, now: () => number = Date.now, save: SaveMirror | null = null) {
    this.opts = opts
    // The save goes on Arkiv through the same writer, so without one there is nothing to mirror.
    this.save = writer ? save : null
    this.writer = writer
    this.swarm = swarm
    this.store = store
    this.now = now
    this.arkivBackoff = new Backoff(5_000, 5 * 60_000, now)
    this.swarmBackoff = new Backoff(5_000, 5 * 60_000, now)
  }

  async init(): Promise<void> {
    this.state = await this.store.load()
  }

  get arkivEnabled(): boolean {
    return this.writer !== null
  }

  get pendingCount(): number {
    return this.state.pending.length
  }

  // ---- observing ------------------------------------------------------------------------------

  observe(s: Snapshot): void {
    const st = this.state
    this.latest = s
    this.stats.polls += 1
    this.stats.lastPollAt = s.observedAt

    // Price: one sample per poll into the current window; a window that has ended becomes a record.
    this.closeDueWindow(s.observedAt)
    if (s.price !== null) {
      const B = this.opts.priceBatchMs
      const start = Math.floor(s.observedAt / B) * B
      let w = st.priceWindow
      if (!w) w = st.priceWindow = { startMs: start, endMs: start + B, day: s.day, samples: [], shock: s.shock }
      if (w.samples.length < MAX_SAMPLES_PER_WINDOW) w.samples.push([Math.floor(s.observedAt / 1000), s.price])
      if (s.shock) w.shock = s.shock
    }

    // A day that has closed: its board, as last seen during that day.
    if (st.lastDay !== null && s.day > st.lastDay && st.dayBoard && st.dayBoard.day === st.lastDay && st.dayBoard.rows.length > 0) {
      this.queue({ type: "rush_board", id: String(st.dayBoard.day), input: st.dayBoard, attempts: 0 })
    }
    if (st.lastDay === null || s.day >= st.lastDay) {
      st.lastDay = s.day
      if (s.rush) st.dayBoard = { day: s.day, season: s.season?.number ?? null, board: s.rush.board, rows: s.rush.rows }
    }

    // A season that has ended: its final board and people, as a snapshot on Swarm.
    if (s.season) {
      if (st.lastSeason !== null && s.season.number > st.lastSeason && st.seasonView) {
        if (this.swarm.configured) {
          this.queue({
            type: "season",
            id: String(st.lastSeason),
            input: { season: st.lastSeason, endedDay: s.day, board: st.seasonView.board, people: st.seasonView.people },
            snapshotRef: null,
            attempts: 0,
          })
        } else {
          log.info("season ended; no snapshot because Swarm is not configured", { season: st.lastSeason })
        }
      }
      if (st.lastSeason === null || s.season.number >= st.lastSeason) {
        st.lastSeason = s.season.number
        st.seasonView = { board: s.rush?.rows ?? [], people: s.people.slice(0, MAX_SEASON_PEOPLE) }
      }
    }

    // A new paper.
    if (s.paper && s.paper.day !== st.lastPaperDay) {
      this.queue({ type: "paper", id: String(s.paper.day), input: s.paper, bodyRef: null, attempts: 0, inline: false })
      st.lastPaperDay = s.paper.day
    }

    for (const p of s.problems) this.warn(`city:${p}`, () => log.warn("the server's /city has something the publisher can't read", { problem: p }))
    this.dirty = true
  }

  private closeDueWindow(now: number): void {
    const w = this.state.priceWindow
    if (w && now >= w.endMs) {
      if (w.samples.length > 0) this.queue({ type: "price_tick", id: String(Math.floor(w.startMs / 1000)), input: w, attempts: 0 })
      this.state.priceWindow = null
      this.dirty = true
    }
  }

  private queue(p: Pending): void {
    // Writes off: nothing to queue for (a backlog would only grow). Arkiv is a no-op for this run.
    if (!this.writer) return
    const list = this.state.pending
    const at = list.findIndex((x) => x.type === p.type && x.id === p.id)
    if (at >= 0) list[at] = p
    else list.push(p)
  }

  /** Records too old to be worth writing (they would expire on arrival, or nearly). */
  private prune(now: number): void {
    const before = this.state.pending.length
    // A price window older than the tick lifetime would be dead on arrival; anything else is written late rather than never.
    this.state.pending = this.state.pending.filter((p) => p.type !== "price_tick" || p.input.endMs > now - PRICE_TICK_TTL_MS + HOUR)
    for (const type of ORDER) {
      for (const [id, t] of Object.entries(this.state.tracked[type])) {
        if (t.expiresAtMs < now - HOUR) delete this.state.tracked[type][id]
      }
    }
    if (this.state.pending.length !== before) this.dirty = true
  }

  async persist(): Promise<void> {
    if (!this.dirty) return
    this.dirty = false
    await this.store.save(this.state)
  }

  // ---- flushing -------------------------------------------------------------------------------

  /** Sends at most one transaction. Returns how many operations went, and whether more are waiting. */
  async flush(): Promise<{ sent: number; more: boolean }> {
    if (!this.writer || this.flushing || !this.arkivBackoff.ready()) return { sent: 0, more: false }
    this.flushing = true
    const now = this.now()
    try {
      this.closeDueWindow(now)
      this.prune(now)
      const planned = await this.plan(now)
      if (planned.length === 0) {
        await this.persist()
        return { sent: 0, more: false }
      }
      const batch = planned.slice(0, this.opts.maxOpsPerTx)
      const types = new Set(batch.map((b) => b.op.draft.type))
      const sentSave = batch.some((b) => isSaveType(b.op.draft.type))
      let result: Awaited<ReturnType<ArkivWriter["execute"]>>
      const sentAt = Date.now()
      try {
        result = await withTimeout(this.writer.execute(batch.map((b) => b.op)), this.opts.txTimeoutMs, "Arkiv transaction")
      } catch (err) {
        // Unclear whether it landed: ask Arkiv before creating any of these again.
        for (const t of types) if (!isSaveType(t)) this.unsynced.add(t)
        if (sentSave) this.save?.failed()
        for (const b of batch) if (b.pending) b.pending.attempts += 1
        let wait = this.arkivBackoff.failed()
        if (err instanceof TimeoutError && wait < 90_000) {
          // A timed-out transaction may still land; give it time before reconciling.
          this.arkivBackoff.failed()
          wait = this.arkivBackoff.retryAt - now
        }
        this.stats.lastArkivError = (err as Error).message
        this.warn("arkiv-write", () =>
          log.warn("Arkiv write failed; will retry", { error: err, ops: batch.length, retryInMs: wait, attempts: this.arkivBackoff.attempts }),
        )
        this.dirty = true
        await this.persist()
        return { sent: 0, more: false }
      }
      const ms = Date.now() - sentAt
      this.arkivBackoff.succeeded()
      this.applyResult(batch, result.created)
      this.stats.txs += 1
      this.stats.lastTx = { hash: result.txHash, at: now, ops: batch.length, ms }
      this.stats.lastArkivError = null
      log.info("Arkiv batch written", {
        tx: result.txHash,
        ops: batch.length,
        ms,
        kinds: summarise(batch),
        waiting: planned.length - batch.length,
      })
      this.dirty = true
      await this.persist()
      return { sent: batch.length, more: planned.length > batch.length || (sentSave && this.save?.hasMore === true) }
    } catch (err) {
      // Reconciliation reads failed, or a Swarm prepare threw unexpectedly.
      const wait = this.arkivBackoff.failed()
      this.stats.lastArkivError = (err as Error).message
      this.warn("arkiv-plan", () => log.warn("Arkiv unavailable while planning; will retry", { error: err, retryInMs: wait }))
      return { sent: 0, more: false }
    } finally {
      this.flushing = false
    }
  }

  private applyResult(batch: Planned[], created: `0x${string}`[]): void {
    let c = 0
    for (const { op, pending } of batch) {
      const { type, id } = op.draft
      if (isSaveType(type)) {
        // The save mirror keeps its own books (it asks Arkiv again after a restart); only a create has a new key.
        if (op.kind === "create") c++
        this.save?.landed(op)
        this.stats.entitiesWritten[`${type}:${op.kind}`] = (this.stats.entitiesWritten[`${type}:${op.kind}`] ?? 0) + 1
        continue
      }
      const prev = this.state.tracked[type][id]
      if (op.kind === "create") {
        const key = created[c++]
        if (key) this.state.tracked[type][id] = { key, fp: op.draft.fp, expiresAtMs: op.draft.expiresAtMs }
      } else if (op.kind === "patch") {
        this.state.tracked[type][id] = {
          key: op.entityKey,
          fp: op.draft.fp,
          expiresAtMs: op.extend ? op.draft.expiresAtMs : (prev?.expiresAtMs ?? op.draft.expiresAtMs),
        }
      } else {
        this.state.tracked[type][id] = { key: op.entityKey, fp: prev?.fp ?? op.draft.fp, expiresAtMs: op.draft.expiresAtMs }
      }
      if (pending) this.resolve(pending)
      this.stats.entitiesWritten[`${type}:${op.kind}`] = (this.stats.entitiesWritten[`${type}:${op.kind}`] ?? 0) + 1
    }
  }

  private resolve(p: Pending): void {
    this.state.pending = this.state.pending.filter((x) => !(x.type === p.type && x.id === p.id))
  }

  /** Everything that should be written now, most user-visible first. */
  async plan(now: number): Promise<Planned[]> {
    const s = this.latest
    const env = this.opts.env

    // 1. Ask Arkiv about anything we might create but whose existence we aren't sure of.
    await this.reconcile(now)

    const out: Planned[] = []

    // 2. Campaign cards (mutable).
    if (s?.bounty) {
      const present = new Set<string>()
      for (const card of s.bounty) {
        const draft = campaignDraft(card, env, now)
        if (!draft) continue
        present.add(draft.id)
        const op = this.diff(draft, now)
        if (op) out.push({ op, pending: null })
      }
      // Gone from the server's list before its end: say so, rather than leave it looking live.
      for (const [id, t] of Object.entries(this.state.tracked.campaign)) {
        if (present.has(id) || t.expiresAtMs <= now) continue
        const fp = fingerprint(`ended:${id}`)
        if (t.fp === fp) continue
        const draft: Draft = { type: "campaign", id, values: {}, expiry: { atMs: t.expiresAtMs }, expiresAtMs: t.expiresAtMs, fp }
        out.push({ op: { kind: "patch", draft, entityKey: t.key, set: { status: "ended", fp }, extend: false }, pending: null })
      }
    }

    // 3. Queued records (immutable once written).
    const byType = (type: EntityType) => this.state.pending.filter((p) => p.type === type)
    for (const type of ["paper", "rush_board", "season", "price_tick"] as const) {
      for (const p of byType(type)) {
        if (this.isLive(type, p.id, now)) {
          this.resolve(p)
          this.dirty = true
          continue
        }
        const draft = await this.draftFor(p, now)
        if (draft) out.push({ op: { kind: "create", draft }, pending: p })
      }
    }

    // 4. Profiles (mutable, renewed toward season end).
    if (s) {
      const expiresAtMs = seasonEndMs(s) ?? now + this.opts.profileFallbackDays * DAY
      for (const person of s.people) {
        const draft = profileDraft(person, s.season?.number ?? null, env, expiresAtMs, now)
        const op = this.diff(draft, now)
        if (op) out.push({ op, pending: null })
      }
    }

    // 5. The save on Arkiv: after everything public.
    if (this.save) out.push(...(await this.save.plan(now)).map((op) => ({ op, pending: null })))

    return out
  }

  private isLive(type: EntityType, id: string, now: number): boolean {
    const t = this.state.tracked[type][id]
    return Boolean(t && t.expiresAtMs > now)
  }

  /** create, patch, extend or nothing, for a mutable entity. */
  private diff(draft: Draft, now: number): Op | null {
    if (isSaveType(draft.type)) return null
    const t = this.state.tracked[draft.type][draft.id]
    if (!t || t.expiresAtMs <= now) return { kind: "create", draft }
    const later = draft.expiresAtMs > t.expiresAtMs + 60_000
    if (t.fp !== draft.fp) {
      const cols = PATCHABLE[draft.type] ?? []
      const set: Record<string, unknown> = {}
      for (const c of cols) if (draft.values[c] !== undefined) set[c] = draft.values[c]
      return { kind: "patch", draft, entityKey: t.key, set, extend: later }
    }
    if (draft.type === "profile" && later && t.expiresAtMs - now < RENEW_WITHIN_MS) {
      return { kind: "extend", draft, entityKey: t.key }
    }
    if (draft.type === "campaign" && later) return { kind: "extend", draft, entityKey: t.key }
    return null
  }

  private async draftFor(p: Pending, now: number): Promise<Draft | null> {
    const env = this.opts.env
    switch (p.type) {
      case "price_tick":
        return priceTickDraft(p.input as PriceWindow, env, now)
      case "rush_board":
        return rushBoardDraft(p.input, env, now)
      case "paper": {
        if (p.bodyRef === null && !p.inline) {
          if (!this.swarm.configured) p.inline = true
          else if (!this.swarmBackoff.ready()) return null
          else {
            try {
              const body = new TextEncoder().encode(JSON.stringify({ kind: "tallyport.paper", v: 1, ...p.input }, null, 2))
              p.bodyRef = await this.swarm.uploadFile(`paper-${p.input.day}.json`, "application/json", body)
              this.swarmBackoff.succeeded()
              this.stats.swarmUploads += 1
              this.dirty = true
              log.info("paper uploaded to Swarm", { day: p.input.day, ref: p.bodyRef })
            } catch (err) {
              p.attempts += 1
              this.swarmFailed(err)
              if (p.attempts >= PAPER_SWARM_ATTEMPTS) {
                p.inline = true
                log.warn("paper going to Arkiv with its text inline: Swarm kept failing", { day: p.input.day })
              } else return null
            }
          }
        }
        return paperDraft(p.input, p.bodyRef, env, now)
      }
      case "season": {
        if (p.snapshotRef === null) {
          if (!this.swarm.configured || !this.swarmBackoff.ready()) return null
          try {
            const body = new TextEncoder().encode(JSON.stringify({ kind: "tallyport.season-snapshot", v: 1, env, ...p.input }, null, 2))
            p.snapshotRef = await this.swarm.uploadFile(`season-${p.input.season}.json`, "application/json", body)
            this.swarmBackoff.succeeded()
            this.stats.swarmUploads += 1
            this.dirty = true
            log.info("season snapshot uploaded to Swarm", { season: p.input.season, ref: p.snapshotRef })
          } catch (err) {
            p.attempts += 1
            this.swarmFailed(err)
            return null
          }
        }
        return seasonDraft(p.input.season, p.input.endedDay, p.snapshotRef, env, now)
      }
    }
  }

  private swarmFailed(err: unknown): void {
    const wait = this.swarmBackoff.failed()
    this.stats.lastSwarmError = (err as Error).message
    this.warn("swarm", () => log.warn("Swarm upload failed; will retry", { error: err, retryInMs: wait }))
  }

  /** For each type not known to be in sync, look up the ids we would create. */
  private async reconcile(now: number): Promise<void> {
    if (!this.writer || this.unsynced.size === 0) return
    const s = this.latest
    const candidates: Partial<Record<EntityType, Set<string>>> = {}
    const add = (type: EntityType, id: string) => {
      if (!this.unsynced.has(type) || this.isLive(type, id, now)) return
      ;(candidates[type] ??= new Set()).add(id)
    }
    for (const card of s?.bounty ?? []) if (card.endsAt * 1000 > now) add("campaign", card.id)
    for (const p of this.state.pending) add(p.type, p.id)
    for (const person of s?.people ?? []) add("profile", person.name)

    for (const type of ORDER) {
      if (!this.unsynced.has(type)) continue
      const ids = [...(candidates[type] ?? [])]
      if (ids.length > 0) {
        const found = await this.writer.findExisting(type, this.opts.env, ids)
        for (const [id, e] of found) {
          const fallback = this.state.tracked[type][id]?.expiresAtMs ?? now + HOUR
          const left = e.expiresAtBlock !== null && e.atBlock !== null ? Number(e.expiresAtBlock - e.atBlock) * BLOCK_MS : null
          this.state.tracked[type][id] = { key: e.key, fp: e.fp ?? "", expiresAtMs: left !== null ? now + left : fallback }
        }
        if (found.size > 0) {
          log.info("found entities already on Arkiv; not creating them again", { type, count: found.size })
          this.dirty = true
        }
      }
      this.unsynced.delete(type)
    }
  }
}

function summarise(batch: Planned[]): Record<string, number> {
  const out: Record<string, number> = {}
  for (const { op } of batch) out[`${op.draft.type}:${op.kind}`] = (out[`${op.draft.type}:${op.kind}`] ?? 0) + 1
  return out
}

/** When the current season ends, from the server's clock fields, if it gives them. */
export function seasonEndMs(s: Snapshot): number | null {
  if (!s.season || s.season.endsDay === null || s.dayMs === null) return null
  const elapsed = s.dayElapsedMs ?? 0
  const left = (s.season.endsDay - s.day) * s.dayMs - elapsed
  return left > 0 ? s.observedAt + left : null
}
