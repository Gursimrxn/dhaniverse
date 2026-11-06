// Backoff and timeouts. Nothing in the publisher waits on Arkiv or Bee without a deadline.

export class TimeoutError extends Error {
  constructor(what: string, ms: number) {
    super(`${what} took longer than ${ms} ms`)
    this.name = "TimeoutError"
  }
}

/** Rejects with TimeoutError if `promise` hasn't settled in `ms`. The work itself may still finish later. */
export function withTimeout<T>(promise: Promise<T>, ms: number, what: string): Promise<T> {
  let timer: NodeJS.Timeout | undefined
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new TimeoutError(what, ms)), ms)
    timer.unref?.()
  })
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer))
}

/** Exponential backoff with full jitter: attempt 1 waits up to base, attempt n up to base·2^(n-1), capped. */
export function backoffMs(attempt: number, baseMs: number, capMs: number, random: () => number = Math.random): number {
  const ceiling = Math.min(capMs, baseMs * 2 ** Math.max(0, attempt - 1))
  return Math.round(ceiling / 2 + (random() * ceiling) / 2)
}

/** Tracks failures of one dependency and says when it may be tried again. */
export class Backoff {
  private failures = 0
  private notBefore = 0
  private readonly baseMs: number
  private readonly capMs: number
  private readonly now: () => number

  constructor(baseMs: number, capMs: number, now: () => number = Date.now) {
    this.baseMs = baseMs
    this.capMs = capMs
    this.now = now
  }

  ready(): boolean {
    return this.now() >= this.notBefore
  }

  get attempts(): number {
    return this.failures
  }

  get retryAt(): number {
    return this.notBefore
  }

  failed(): number {
    this.failures += 1
    const wait = backoffMs(this.failures, this.baseMs, this.capMs)
    this.notBefore = this.now() + wait
    return wait
  }

  succeeded(): void {
    this.failures = 0
    this.notBefore = 0
  }
}

export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}
