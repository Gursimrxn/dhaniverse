// The town in public, read from the server's save. The save (`server/crates/server/src/log.rs`) is JSONL: a setup
// line, then `{seq, input, events}`. `TownProjector` tails it and turns events into public records:
//   - `chest`  every chest opened: tier, contents (a golden drop as yes/no, never its amount), the pity counter;
//   - `feed`   every feed post, in the server feed's own words (which never hold an amount);
//   - `stamp`  every quest stamp and every first earned, once per player;
//   - `pool`   the house pool's statement for each closed real day (its own books, from chain readings);
//   - streaks  the latest login streak per player (a mutable entity, renewed on each login day).
// It never reads a wallet, a balance, an amount a player was paid, a secret or anything from World ID: those events
// are skipped by name below, and the privacy test checks the result. It holds no state worth saving: on a start it
// replays the save from its first line (the publisher remembers only how far it has queued, `State.townSeq`).

import { open } from "node:fs/promises"
import type { StreakState, TownRecord } from "./entities.ts"

const READ_CHUNK = 8 * 1024 * 1024

type Json = Record<string, any>

/** Reads a number from rules.toml by key (each key name is unique in that file). */
function ruleNumber(rules: string, key: string, fallback: number): number {
  const m = new RegExp(`^\\s*${key}\\s*=\\s*([0-9_]+)`, "m").exec(rules)
  return m ? Number((m[1] as string).replace(/_/g, "")) : fallback
}

const isPerson = (account: unknown): account is string => typeof account === "string" && account !== "" && !account.includes(":")

type PoolDay = {
  day: number
  opening: number | null
  closing: number
  budget: number
  spent: { fixed: number; surprise: number; safety: number }
}

export class TownProjector {
  townId: string | null = null
  lastSeq = 0
  readonly streaks = new Map<string, StreakState>()
  private readonly path: string
  private readonly now: () => number
  private offset = 0
  private records: TownRecord[] = []
  private realDayMs = 86_400_000
  private pityEvery = 10
  private brass = 3
  private gold = 7
  // The rules' clock (the sum of every Advance), and the wall clock it was last pinned to by a chain reading.
  private gameMs = 0
  private anchor: { wallMs: number; gameMs: number } | null = null
  private readonly sinceDrop = new Map<string, number>()
  private readonly draws = new Map<string, number>()
  private readonly stamped = new Set<string>()
  private pool: PoolDay | null = null

  constructor(path: string, now: () => number = Date.now) {
    this.path = path
    this.now = now
  }

  /** Reads whole new lines; a half line at the end waits for the next pass. A replaced save starts over. */
  async read(): Promise<void> {
    let fh
    try {
      fh = await open(this.path, "r")
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === "ENOENT") return
      throw err
    }
    try {
      for (;;) {
        const size = (await fh.stat()).size
        if (size < this.offset) this.reset()
        if (size === this.offset) return
        const buf = Buffer.alloc(Math.min(size - this.offset, READ_CHUNK))
        const { bytesRead } = await fh.read(buf, 0, buf.length, this.offset)
        const data = buf.subarray(0, bytesRead)
        let pos = 0
        let took = false
        for (;;) {
          const nl = data.indexOf(10, pos)
          if (nl < 0) break
          const line = data.toString("utf8", pos, nl).trim()
          if (line) this.take(line)
          this.offset += nl + 1 - pos
          pos = nl + 1
          took = true
        }
        if (!took) return
      }
    } finally {
      await fh.close()
    }
  }

  /** The records from lines after `afterSeq`, oldest first, and forgets them. */
  drain(afterSeq: number): TownRecord[] {
    const out = this.records.filter((r) => r.seq > afterSeq)
    this.records = []
    return out
  }

  private reset(): void {
    Object.assign(this, { townId: null, lastSeq: 0, offset: 0, records: [], gameMs: 0, anchor: null, pool: null })
    for (const m of [this.streaks, this.sinceDrop, this.draws, this.stamped]) m.clear()
  }

  private take(text: string): void {
    const line = JSON.parse(text) as Json
    if (this.townId === null) {
      const rules = String(line.rules ?? "")
      this.townId = String(line.town_id || "none")
      this.realDayMs = ruleNumber(rules, "real_day_ms", 86_400_000) || 86_400_000
      this.pityEvery = ruleNumber(rules, "pity_every", 10)
      this.brass = ruleNumber(rules, "brass_streak", 3)
      this.gold = ruleNumber(rules, "gold_streak", 7)
      return
    }
    const seq = Number(line.seq)
    if (seq !== this.lastSeq + 1) throw new Error(`the save has line ${seq} after line ${this.lastSeq}`)
    this.lastSeq = seq
    const input = (line.input ?? {}) as Json
    if (input.type === "Advance") this.gameMs += Number(input.ms) || 0
    if (input.type === "Chain" && Number(input.time) > 0) this.anchor = { wallMs: Number(input.time) * 1000, gameMs: this.gameMs }
    // ponytail: wall time is the last chain reading plus the rules' clock since; good to seconds, not to the ms.
    const atMs = this.anchor ? this.anchor.wallMs + (this.gameMs - this.anchor.gameMs) : this.now()
    const day = Math.floor(this.gameMs / this.realDayMs)
    const at = { seq, atMs, day }

    if (this.pool && day > this.pool.day) this.closePool(at)
    if (input.type === "Chain") this.observe(input.observed as Json, day)

    for (const e of (line.events ?? []) as Json[]) {
      switch (e.type) {
        case "ChestOpened": {
          if (!isPerson(e.account)) break
          const weekly = e.weekly === true
          const c = (e.contents ?? {}) as Json
          const goldenDrop = Number(c.golden_drop) > 0
          const pityBefore = this.sinceDrop.get(e.account) ?? 0
          let pity = false
          let draw = 0 // the weekly strongbox has no dice
          if (!weekly) {
            // The rules: the pity rule is due on the `pity_every`th chest without a drop; a drop resets the count.
            pity = pityBefore + 1 >= this.pityEvery
            this.sinceDrop.set(e.account, goldenDrop ? 0 : pityBefore + 1)
            draw = (this.draws.get(e.account) ?? 0) + 1
            this.draws.set(e.account, draw)
          }
          this.records.push({
            type: "chest",
            ...at,
            player: e.account,
            kind: weekly ? "weekly" : "daily",
            tier: String(e.tier),
            pityBefore,
            pity,
            draw,
            energy: Number(c.energy) || 0,
            tickets: Number(c.tickets) || 0,
            voucher: c.voucher === true,
            goldenDrop,
          })
          break
        }
        case "FeedPost":
          this.records.push({
            type: "feed",
            ...at,
            postId: Number(e.id),
            kind: String(e.kind ?? "post"),
            actor: isPerson(e.about) ? e.about : null,
            text: String(e.text ?? "").slice(0, 2_000),
          })
          break
        case "QuestDone":
          if (isPerson(e.account) && typeof e.reward?.stamp === "string" && e.reward.stamp) this.stamp(at, e.account, e.reward.stamp, "stamp")
          break
        case "FirstEarned":
          if (isPerson(e.account)) this.stamp(at, e.account, String(e.first), "first")
          break
        case "LoggedIn": {
          if (!isPerson(e.account)) break
          const streak = Number(e.streak) || 0
          const chestTier = streak >= this.gold ? "gold" : streak >= this.brass ? "brass" : "wood"
          this.streaks.set(e.account, { player: e.account, streak, daysOfLast7: Number(e.week_days) || 0, chestTier, day: Number(e.day ?? day), atMs })
          break
        }
        // Everything else stays inside the encrypted save: wallets (WalletReady), balances (BalanceChanged), what was
        // paid or owed (MealEaten, RewardPaid, RewardPending, …), World ID (HumanVerified, VerifyHuman's human_id),
        // the mentor, intents. Nothing here reads them.
      }
    }
  }

  private stamp(at: { seq: number; atMs: number; day: number }, player: string, stamp: string, kind: "stamp" | "first"): void {
    const ref = `${kind}:${player}:${stamp}`
    if (this.stamped.has(ref)) return
    this.stamped.add(ref)
    this.records.push({ type: "stamp", ...at, player, stamp, kind })
  }

  /** The house pool's books from chain readings: balances and budgets (`PoolBalances`), payouts (`Paid`, by bucket). */
  private observe(o: Json | undefined, day: number): void {
    if (!o) return
    if (o.type === "PoolBalances") {
      const p = (this.pool ??= this.newPool(day, null))
      const total = (Number(o.fixed) || 0) + (Number(o.surprise) || 0) + (Number(o.safety) || 0)
      p.opening ??= total
      p.closing = total
      p.budget = (Number(o.budget_fixed) || 0) + (Number(o.budget_surprise) || 0) + (Number(o.budget_safety) || 0)
    } else if (o.type === "Paid") {
      const p = (this.pool ??= this.newPool(day, null))
      const bucket = o.bucket as keyof PoolDay["spent"]
      if (bucket in p.spent) p.spent[bucket] += Number(o.amount) || 0
    }
  }

  private newPool(day: number, opening: number | null): PoolDay {
    return { day, opening, closing: opening ?? 0, budget: 0, spent: { fixed: 0, surprise: 0, safety: 0 } }
  }

  private closePool(at: { seq: number; atMs: number; day: number }): void {
    const p = this.pool as PoolDay
    if (p.opening !== null) {
      this.records.push({
        type: "pool",
        seq: at.seq,
        atMs: at.atMs,
        day: p.day,
        opening: p.opening,
        closing: p.closing,
        budget: p.budget,
        spentFixed: p.spent.fixed,
        spentSurprise: p.spent.surprise,
        spentSafety: p.spent.safety,
      })
    }
    const next = this.newPool(at.day, p.opening === null ? null : p.closing)
    next.budget = p.budget
    this.pool = next
  }
}
