// A short cache in front of Arkiv reads: one request in flight per key, fresh for `ttlMs`, and on an
// Arkiv error the last good answer (up to `staleMs` old) is served marked stale rather than nothing.

type Entry<T> = { value: T; at: number }

export type Cached<T> = { value: T; cachedAt: number; stale: boolean }

export class ReadCache {
  private readonly entries = new Map<string, Entry<unknown>>()
  private readonly inflight = new Map<string, Promise<unknown>>()
  private readonly ttlMs: number
  private readonly staleMs: number
  private readonly maxEntries: number
  private readonly now: () => number

  constructor(ttlMs: number, staleMs = 5 * 60_000, maxEntries = 500, now: () => number = Date.now) {
    this.ttlMs = ttlMs
    this.staleMs = staleMs
    this.maxEntries = maxEntries
    this.now = now
  }

  async get<T>(key: string, load: () => Promise<T>): Promise<Cached<T>> {
    const hit = this.entries.get(key) as Entry<T> | undefined
    const now = this.now()
    if (hit && now - hit.at < this.ttlMs) return { value: hit.value, cachedAt: hit.at, stale: false }
    let p = this.inflight.get(key) as Promise<T> | undefined
    if (!p) {
      p = load().finally(() => this.inflight.delete(key))
      this.inflight.set(key, p)
    }
    try {
      const value = await p
      const at = this.now()
      this.entries.delete(key)
      this.entries.set(key, { value, at })
      if (this.entries.size > this.maxEntries) {
        const oldest = this.entries.keys().next().value
        if (oldest !== undefined) this.entries.delete(oldest)
      }
      return { value, cachedAt: at, stale: false }
    } catch (err) {
      if (hit && now - hit.at < this.staleMs) return { value: hit.value, cachedAt: hit.at, stale: true }
      throw err
    }
  }
}

/** Fixed-window counters, per key and overall: the upload endpoint spends postage, so it is rationed. */
export class RateLimiter {
  private readonly perKey = new Map<string, { count: number; windowStart: number }>()
  private global = { count: 0, windowStart: 0 }
  private readonly perKeyLimit: number
  private readonly perKeyWindowMs: number
  private readonly globalLimit: number
  private readonly globalWindowMs: number
  private readonly now: () => number

  constructor(perKeyLimit: number, perKeyWindowMs: number, globalLimit: number, globalWindowMs: number, now: () => number = Date.now) {
    this.perKeyLimit = perKeyLimit
    this.perKeyWindowMs = perKeyWindowMs
    this.globalLimit = globalLimit
    this.globalWindowMs = globalWindowMs
    this.now = now
  }

  allow(key: string): boolean {
    const now = this.now()
    if (now - this.global.windowStart >= this.globalWindowMs) this.global = { count: 0, windowStart: now }
    let k = this.perKey.get(key)
    if (!k || now - k.windowStart >= this.perKeyWindowMs) {
      k = { count: 0, windowStart: now }
      this.perKey.set(key, k)
    }
    if (k.count >= this.perKeyLimit || this.global.count >= this.globalLimit) return false
    k.count += 1
    this.global.count += 1
    if (this.perKey.size > 10_000) this.perKey.clear()
    return true
  }
}
