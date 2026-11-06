// The server's save on Arkiv. The save (`server/crates/server/src/log.rs`) is a JSONL file: the first line
// is the setup, each later line is `{seq, input, events}`. `SaveMirror` tails it and turns it into
//   - one `dhaniverse.city.v1` entity (the setup line, encrypted), and
//   - `dhaniverse.log.v1` entities, one per batch of lines: gzipped JSONL, AES-256-GCM encrypted,
//     hash-chained (`prevHash` = the previous batch's `hash`, SHA-256 of the plaintext JSONL).
// It plans operations for the publisher's flush and holds no state worth saving: after a restart, or an
// unclear failure, it asks Arkiv for the town's highest `toSeq` and carries on from the next line.
// `restoreLines` is the other direction: it reads Arkiv, decrypts, checks the chain, and yields the lines.

import { createHash } from "node:crypto"
import { open } from "node:fs/promises"
import { gunzipSync, gzipSync } from "node:zlib"
import type { PublicArkivClient } from "@arkiv-network/sdk"
import { MAX_LIMIT, and, asc, desc, eq, gt, gte } from "@arkiv-network/sdk/query"
import { u64 } from "@arkiv-network/sdk/schema"
import type { Hex } from "viem"
import type { Op } from "./arkiv/writer.ts"
import { decrypt, encrypt } from "./crypto.ts"
import { MAX_TTL_MS, type Draft } from "./entities.ts"
import { log, throttled } from "./log.ts"
import { CitySchema, LogSchema } from "./schemas.ts"

const DAY = 86_400_000
const BLOCK_MS = 2_000
export const BATCH_LIMIT = 96 * 1024
const RENEW_UNDER_MS = 150 * DAY
/** How much of the file one pass reads (a bigger backlog takes a few passes). */
const READ_CHUNK = 8 * 1024 * 1024
/** Raw JSONL tried per batch before gzip says whether it fits: bounds the work on a big backlog. */
const RAW_CAP = 4 * 1024 * 1024
const ZEROS = "0".repeat(64)
const RESTORE_PAGE = 10
/** Arkiv's payload limit; an encrypted payload over it can never be written. */
const MAX_PAYLOAD = 128 * 1024
/** After a send that may have landed, how long a tip lower than what we sent is distrusted (the index may lag). */
const INDEX_LAG_MS = 30_000

const sha256 = (b: Uint8Array | string) => createHash("sha256").update(b).digest("hex")

// The SDK types each builder by its schema; one loosely typed view, as in arkiv/queries.ts.
type Builder = {
  from(schema: unknown): Builder
  ownedBy(owner: Hex): Builder
  where(...e: unknown[]): Builder
  orderBy(o: unknown): Builder
  limit(n: number): Builder
  offset(n: number): Builder
  fetch(): Promise<{ entities: readonly Record<string, unknown>[]; blockNumber: bigint }>
}
const select = (client: PublicArkivClient, sel: Record<string, true>): Builder => (client as unknown as { select(s: unknown): Builder }).select(sel)

const cell = (row: Record<string, unknown>, name: string): unknown => (row[name] as { value?: unknown } | undefined)?.value
const text = (row: Record<string, unknown>, name: string): string => String(cell(row, name) ?? "")
const num = (row: Record<string, unknown>, name: string): number => Number(cell(row, name) ?? 0)
const bytesOf = (row: Record<string, unknown>, name: string): Buffer => {
  const v = cell(row, name)
  return typeof v === "string" && v.startsWith("0x") ? Buffer.from(v.slice(2), "hex") : Buffer.alloc(0)
}

const forTown = (env: string, townId: string) => and(eq("env", env), eq("townId", townId))

export type SaveOptions = { path: string; key: Buffer; env: string }

type Planned = { fromSeq: number; toSeq: number; hash: string; count: number }

export class SaveMirror {
  /** From the setup line; null until the file has one. */
  townId: string | null = null
  private readonly opts: SaveOptions
  private readonly client: PublicArkivClient
  private readonly owner: Hex
  private offset = 0
  private setupText: string | null = null
  private lastSeq = 0
  private queue: { seq: number; text: string; off: number }[] = []
  private setupBytes: Buffer | null = null
  /** Set when the mirror can't go on (a payload over the limit); the public writes carry on without it. */
  private stopped: string | null = null
  private error: string | null = null
  /** After a send of unclear fate: the highest `toSeq` we sent, and when a lower tip was first seen. */
  private unsure: { toSeq: number; seenAt: number | null } | null = null
  private moreToRead = false
  /** Arkiv's tip for this town: undefined means "ask Arkiv before writing anything". */
  private tip: { toSeq: number; hash: string } | undefined
  private cityOnArkiv: boolean | undefined
  private planned: Planned | null = null
  private lastRenewCheck: number | null = null
  private readonly renewals = new Map<string, Op>()
  private readonly warn = throttled(10 * 60_000)

  constructor(opts: SaveOptions, client: PublicArkivClient, owner: Hex) {
    this.opts = opts
    this.client = client
    this.owner = owner
  }

  /** Lines read but not yet on Arkiv: when true the flush loop should come straight back. */
  get hasMore(): boolean {
    return this.queue.length > 0 || this.moreToRead
  }

  /** Operations to add to a flush: the city (once), the next batch, and any renewals that are due. */
  async plan(now: number): Promise<Op[]> {
    try {
      await this.readNew()
      this.error = null
    } catch (err) {
      this.error = (err as Error).message
      this.warn("save-read", () => log.warn("could not read the save file; will retry", { path: this.opts.path, error: err }))
    }
    if (this.stopped || this.setupText === null || this.townId === null) return []
    if (this.tip === undefined || this.cityOnArkiv === undefined) {
      await this.sync()
      if (this.unsure) {
        const u = this.unsure
        if ((this.tip as { toSeq: number }).toSeq >= u.toSeq) this.unsure = null
        else if (u.seenAt === null || now - u.seenAt < INDEX_LAG_MS) {
          // Arkiv's tip is behind what we sent: wait, then ask again, before sending those lines a second time.
          u.seenAt ??= now
          this.tip = undefined
          return []
        } else this.unsure = null
      }
    }
    const ops: Op[] = []
    if (!this.cityOnArkiv) {
      const city = this.cityDraft(now)
      if (city) ops.push({ kind: "create", draft: city })
    }
    if (this.stopped) return []
    const batch = this.nextBatch(now)
    if (this.stopped) return []
    if (batch) ops.push(batch)
    await this.checkRenewals(now)
    ops.push(...this.renewals.values())
    return ops
  }

  /** The publisher sent this op and it landed. */
  landed(op: Op): void {
    if (op.kind === "extend") {
      this.renewals.delete(op.entityKey)
    } else if (op.draft.type === "city") {
      this.cityOnArkiv = true
    } else if (this.planned && String(this.planned.fromSeq) === op.draft.id) {
      this.tip = { toSeq: this.planned.toSeq, hash: this.planned.hash }
      this.queue.splice(0, this.planned.count)
      this.planned = null
    }
  }

  /** A send failed or timed out and may have landed: forget what we assumed and ask Arkiv again. */
  failed(): void {
    if (this.planned) this.unsure = { toSeq: Math.max(this.unsure?.toSeq ?? 0, this.planned.toSeq), seenAt: null }
    this.tip = undefined
    this.cityOnArkiv = undefined
    this.planned = null
  }

  // ---- reading the file ------------------------------------------------------------------------

  /** For `/health`. */
  status() {
    return {
      state: this.stopped ? "stopped" : this.error ? "stuck" : "running",
      lastSeq: this.lastSeq,
      queued: this.queue.length,
      offset: this.offset,
      error: this.stopped ?? this.error,
    }
  }

  private stop(why: string): void {
    this.stopped = why
    log.error(`THE LOG MIRROR HAS STOPPED: ${why}. The save is no longer going onto Arkiv; public writes carry on.`)
  }

  private reset(): void {
    this.stopped = null
    this.error = null
    this.unsure = null
    this.setupBytes = null
    this.offset = 0
    this.setupText = null
    this.townId = null
    this.lastSeq = 0
    this.queue = []
    this.moreToRead = false
    this.tip = undefined
    this.cityOnArkiv = undefined
    this.planned = null
  }

  /** Reads whole new lines only: a half line at the end stays in the file for the next pass. */
  private async readNew(): Promise<void> {
    let fh
    try {
      fh = await open(this.opts.path, "r")
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === "ENOENT") return
      throw err
    }
    try {
      const size = (await fh.stat()).size
      let replaced = size < this.offset
      if (!replaced && this.setupBytes) {
        // The same size is not the same save: compare the setup line.
        const head = Buffer.alloc(this.setupBytes.length)
        const got = await fh.read(head, 0, head.length, 0)
        replaced = got.bytesRead < head.length || !head.equals(this.setupBytes)
      }
      if (replaced) this.reset() // a different save took its place
      if (size === this.offset) {
        this.moreToRead = false
        return
      }
      const buf = Buffer.alloc(Math.min(size - this.offset, READ_CHUNK))
      const { bytesRead } = await fh.read(buf, 0, buf.length, this.offset)
      const data = buf.subarray(0, bytesRead)
      let pos = 0
      for (;;) {
        const nl = data.indexOf(10, pos)
        if (nl < 0) break
        const line = data.toString("utf8", pos, nl).replace(/\r$/, "")
        if (line.trim() !== "") this.takeLine(line, this.offset)
        this.offset += nl + 1 - pos
        pos = nl + 1
      }
      this.moreToRead = this.offset < size
    } finally {
      await fh.close()
    }
  }

  private takeLine(line: string, off: number): void {
    try {
      this.parseLine(line, off)
    } catch (err) {
      throw new Error(`save line at byte ${off}: ${(err as Error).message}`)
    }
  }

  private parseLine(line: string, off: number): void {
    if (this.setupText === null) {
      const setup = JSON.parse(line) as { town_id?: string }
      this.setupBytes = Buffer.from(line, "utf8")
      this.setupText = line
      this.townId = String(setup.town_id || "none").slice(0, 128)
      return
    }
    const seq = (JSON.parse(line) as { seq: number }).seq
    if (seq !== this.lastSeq + 1) throw new Error(`the save has line ${seq} after line ${this.lastSeq}`)
    this.lastSeq = seq
    if (this.tip === undefined || seq > this.tip.toSeq) this.queue.push({ seq, text: line, off })
  }

  // ---- asking Arkiv ----------------------------------------------------------------------------

  private async sync(): Promise<void> {
    const townId = this.townId as string
    const where = forTown(this.opts.env, townId)
    const logs = await select(this.client, { $key: true, toSeq: true, hash: true })
      .from(LogSchema)
      .ownedBy(this.owner)
      .where(where)
      .orderBy(desc("toSeq"))
      .limit(1)
      .fetch()
    const city = await select(this.client, { $key: true }).from(CitySchema).ownedBy(this.owner).where(where).limit(1).fetch()
    const top = logs.entities[0]
    this.tip = top ? { toSeq: num(top, "toSeq"), hash: text(top, "hash") } : { toSeq: 0, hash: ZEROS }
    this.cityOnArkiv = city.entities.length > 0
    this.queue = this.queue.filter((l) => l.seq > (this.tip as { toSeq: number }).toSeq)
    if (top) log.info("this town is already on Arkiv; continuing after its last batch", { townId, toSeq: this.tip.toSeq })
  }

  // ---- building ops ----------------------------------------------------------------------------

  private cityDraft(now: number): Draft | null {
    const setup = JSON.parse(this.setupText as string) as { chain?: unknown; rules?: string }
    // A plain name only: a string, or the variant's name when the server writes the mode as an object.
    const c = setup.chain
    const chain = typeof c === "string" ? c : c && typeof c === "object" ? (Object.keys(c)[0] ?? "unknown") : "unknown"
    const payload = encrypt(this.opts.key, Buffer.from(this.setupText as string, "utf8"))
    if (payload.length > MAX_PAYLOAD) {
      this.stop(`the setup line is ${payload.length} bytes encrypted, over Arkiv's ${MAX_PAYLOAD}-byte limit`)
      return null
    }
    return {
      type: "city",
      id: "city",
      values: {
        env: this.opts.env,
        townId: this.townId,
        chain: chain.slice(0, 128),
        rulesHash: sha256(setup.rules ?? ""),
        startedAt: u64(Math.floor(now / 1000)),
        payload,
      },
      expiry: { forSeconds: MAX_TTL_MS / 1000 },
      expiresAtMs: now + MAX_TTL_MS,
      fp: "city",
    }
  }

  /** The longest run of queued lines whose gzip fits in `BATCH_LIMIT` (at least one line). */
  private nextBatch(now: number): Op | null {
    const tip = this.tip
    const q = this.queue
    if (!tip || q.length === 0) return null
    const pack = (n: number) => {
      const plain = Buffer.from(q.slice(0, n).map((l) => `${l.text}\n`).join(""), "utf8")
      return { plain, gz: gzipSync(plain) }
    }
    let rawLines = 0
    let raw = 0
    while (rawLines < q.length && (rawLines === 0 || raw + (q[rawLines] as { text: string }).text.length + 1 <= RAW_CAP)) raw += (q[rawLines++] as { text: string }).text.length + 1
    let good = 1 // fits, or is a single line that can't be helped
    let bad = rawLines + 1
    if (pack(rawLines).gz.length <= BATCH_LIMIT) good = rawLines
    else {
      // Doubling then bisecting: a handful of gzips however long the backlog is.
      let hi = 2
      while (hi < rawLines && pack(hi).gz.length <= BATCH_LIMIT) {
        good = hi
        hi *= 2
      }
      bad = Math.min(hi, rawLines)
      while (bad - good > 1) {
        const mid = (good + bad) >> 1
        if (pack(mid).gz.length <= BATCH_LIMIT) good = mid
        else bad = mid
      }
    }
    const { plain, gz } = pack(good)
    const payload = encrypt(this.opts.key, gz)
    if (payload.length > MAX_PAYLOAD) {
      const l = q[0] as { seq: number; off: number }
      this.stop(`save line ${l.seq} (at byte ${l.off}) is ${payload.length} bytes encrypted, over Arkiv's ${MAX_PAYLOAD}-byte limit`)
      return null
    }
    const fromSeq = (q[0] as { seq: number }).seq
    const toSeq = (q[good - 1] as { seq: number }).seq
    const hash = sha256(plain)
    this.planned = { fromSeq, toSeq, hash, count: good }
    return {
      kind: "create",
      draft: {
        type: "log",
        id: String(fromSeq),
        values: {
          env: this.opts.env,
          townId: this.townId,
          fromSeq: u64(fromSeq),
          toSeq: u64(toSeq),
          prevHash: tip.hash,
          hash,
          payload,
        },
        expiry: { forSeconds: MAX_TTL_MS / 1000 },
        expiresAtMs: now + MAX_TTL_MS,
        fp: hash,
      },
    }
  }

  /** Once a day: extend every city and log entity of this town that has under 150 days left. */
  private async checkRenewals(now: number): Promise<void> {
    if (this.lastRenewCheck !== null && now - this.lastRenewCheck < DAY) return
    for (const schema of [CitySchema, LogSchema]) {
      const type = schema === CitySchema ? "city" : "log"
      for (let offset = 0; ; offset += MAX_LIMIT) {
        const res = await select(this.client, { $key: true, $expiresAt: true })
          .from(schema)
          .ownedBy(this.owner)
          .where(forTown(this.opts.env, this.townId as string))
          .limit(MAX_LIMIT)
          .offset(offset)
          .fetch()
        for (const row of res.entities) {
          const key = row.$key as Hex | undefined
          if (!key || typeof row.$expiresAt !== "bigint") continue
          const left = Number(row.$expiresAt - res.blockNumber) * BLOCK_MS
          if (left >= RENEW_UNDER_MS || this.renewals.has(key)) continue
          const draft: Draft = { type, id: key, values: {}, expiry: { forSeconds: MAX_TTL_MS / 1000 }, expiresAtMs: now + MAX_TTL_MS, fp: "" }
          this.renewals.set(key, { kind: "extend", draft, entityKey: key })
        }
        if (res.entities.length < MAX_LIMIT) break
      }
    }
    this.lastRenewCheck = now
    if (this.renewals.size > 0) log.info("renewing save entities with under 150 days left", { count: this.renewals.size })
  }
}

/** `null` (with the reason in the log) when the mirror can't run; everything else in the publisher still does. */
export function createSaveMirror(
  cfg: { savePath: string | undefined; logKey: Buffer | undefined; env: string },
  client: PublicArkivClient,
  owner: Hex | null,
): SaveMirror | null {
  if (cfg.savePath === undefined) return null
  if (cfg.logKey === undefined) {
    log.error("the log mirror is off: SAVE_PATH is set but DHANIVERSE_LOG_KEY is not. Make one with `openssl rand -hex 32` and keep it with the server's secrets; without it nothing of the save goes on Arkiv.")
    return null
  }
  if (owner === null) {
    log.warn("the log mirror is off: it needs ARKIV_PRIVATE_KEY to write")
    return null
  }
  return new SaveMirror({ path: cfg.savePath, key: cfg.logKey, env: cfg.env }, client, owner)
}

// ---- restoring ---------------------------------------------------------------------------------

/**
 * The setup line (when `from` is 0) and then every save line with `seq >= from`, in order, read from Arkiv.
 * Throws on a broken chain, a gap or a batch that won't decrypt, after the good lines before it were yielded.
 */
export async function* restoreLines(
  client: PublicArkivClient,
  owner: Hex,
  env: string,
  key: Buffer,
  townId: string,
  from: number,
): AsyncGenerator<string> {
  const where = forTown(env, townId)
  if (from === 0) {
    const res = await select(client, { payload: true }).from(CitySchema).ownedBy(owner).where(where).limit(1).fetch()
    const row = res.entities[0]
    if (!row) throw new Error(`no town "${townId}" on Arkiv`)
    try {
      yield decrypt(key, bytesOf(row, "payload")).toString("utf8")
    } catch {
      throw new Error("the setup line would not decrypt: wrong key, or altered on Arkiv")
    }
  }
  const start = Math.max(from, 1)
  let expectFrom: number | null = null
  let expectPrev: string | null = null
  let last: { fromSeq: number; toSeq: number; hash: string } | null = null
  let after = start - 1 // batches whose toSeq is above this
  for (;;) {
    const page = await select(client, { fromSeq: true, toSeq: true, prevHash: true, hash: true, payload: true })
      .from(LogSchema)
      .ownedBy(owner)
      .where(and(eq("env", env), eq("townId", townId), after === start - 1 ? gte("toSeq", u64(start)) : gt("toSeq", u64(after))))
      .orderBy(asc("toSeq"))
      .limit(RESTORE_PAGE)
      .fetch()
    for (const row of page.entities) {
      const fromSeq = num(row, "fromSeq")
      const toSeq = num(row, "toSeq")
      const prevHash = text(row, "prevHash")
      const hash = text(row, "hash")
      const at = `batch ${fromSeq}-${toSeq}`
      if (last && last.fromSeq === fromSeq && last.toSeq === toSeq && last.hash === hash) continue // the same batch written twice
      if (expectFrom === null) {
        if (fromSeq > start) throw new Error(`a gap: lines ${start} to ${fromSeq - 1} are missing before ${at}`)
        if (fromSeq === 1 && prevHash !== ZEROS) throw new Error(`broken chain: ${at} is the first batch but its prevHash is not zero`)
      } else {
        if (fromSeq !== expectFrom) throw new Error(`a gap: ${at} should start at line ${expectFrom}`)
        if (prevHash !== expectPrev) throw new Error(`broken chain: ${at} does not follow the batch before it`)
      }
      let plain: Buffer
      try {
        plain = gunzipSync(decrypt(key, bytesOf(row, "payload")))
      } catch {
        throw new Error(`${at} would not decrypt: wrong key, or altered on Arkiv`)
      }
      if (sha256(plain) !== hash) throw new Error(`broken chain: ${at} does not match its hash`)
      const lines = plain.toString("utf8").split("\n")
      lines.pop() // the text ends with a newline
      if (lines.length !== toSeq - fromSeq + 1) throw new Error(`${at} holds ${lines.length} lines, not ${toSeq - fromSeq + 1}`)
      for (let i = 0; i < lines.length; i++) {
        if ((JSON.parse(lines[i] as string) as { seq?: number }).seq !== fromSeq + i) throw new Error(`${at}: line ${i + 1} is not seq ${fromSeq + i}`)
      }
      for (let i = 0; i < lines.length; i++) if (fromSeq + i >= start) yield lines[i] as string
      last = { fromSeq, toSeq, hash }
      expectFrom = toSeq + 1
      expectPrev = hash
      after = toSeq
    }
    if (page.entities.length < RESTORE_PAGE) return
  }
}

/** The last save line Arkiv holds for a town (0 when none): `GET /log` sends it as `x-arkiv-tip`. */
export async function arkivTip(client: PublicArkivClient, owner: Hex, env: string, townId: string): Promise<number> {
  const res = await select(client, { toSeq: true }).from(LogSchema).ownedBy(owner).where(forTown(env, townId)).orderBy(desc("toSeq")).limit(1).fetch()
  const top = res.entities[0]
  return top ? num(top, "toSeq") : 0
}
