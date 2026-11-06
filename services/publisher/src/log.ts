// One-line JSON logs. Secrets never reach the output: every value registered with `addSecret` is
// replaced wherever it appears, and any field whose name looks like a key is masked whatever it holds.

type Level = "debug" | "info" | "warn" | "error"
const ORDER: Record<Level, number> = { debug: 10, info: 20, warn: 30, error: 40 }
const SECRET_FIELD = /(private.?key|secret|password|token|mnemonic|seed|authorization)/i

const secrets = new Set<string>()
let threshold: Level = "info"
let sink: (line: string) => void = (line) => process.stdout.write(`${line}\n`)

export function addSecret(value: string | undefined): void {
  if (!value || value.length < 6) return
  secrets.add(value)
  // A hex key also appears without its 0x, and in either case.
  const bare = value.startsWith("0x") ? value.slice(2) : value
  secrets.add(bare)
  secrets.add(bare.toLowerCase())
  secrets.add(bare.toUpperCase())
}

export function setLevel(level: string | undefined): void {
  if (level && level in ORDER) threshold = level as Level
}

/** For tests: capture output instead of writing to stdout. */
export function setSink(fn: (line: string) => void): void {
  sink = fn
}

export function redact(text: string): string {
  let out = text
  for (const secret of secrets) {
    if (secret.length >= 6 && out.includes(secret)) out = out.split(secret).join("[redacted]")
  }
  return out
}

function clean(value: unknown, depth = 0): unknown {
  if (depth > 6) return "[deep]"
  if (value instanceof Error) {
    const cause = (value as { cause?: unknown }).cause
    return {
      name: value.name,
      message: redact(shortMessage(value)),
      ...(cause !== undefined && { cause: clean(cause, depth + 1) }),
    }
  }
  if (typeof value === "string") return redact(value)
  if (typeof value === "bigint") return value.toString()
  if (Array.isArray(value)) return value.slice(0, 50).map((v) => clean(v, depth + 1))
  if (value && typeof value === "object") {
    const out: Record<string, unknown> = {}
    for (const [k, v] of Object.entries(value)) {
      out[k] = SECRET_FIELD.test(k) && v ? "[redacted]" : clean(v, depth + 1)
    }
    return out
  }
  return value
}

/** viem errors carry a multi-paragraph message; the short one is what an operator needs. */
function shortMessage(error: Error): string {
  const short = (error as { shortMessage?: unknown }).shortMessage
  const text = typeof short === "string" && short ? short : error.message
  return text.length > 500 ? `${text.slice(0, 500)}…` : text
}

function write(level: Level, msg: string, fields?: Record<string, unknown>): void {
  if (ORDER[level] < ORDER[threshold]) return
  const entry = { t: new Date().toISOString(), level, msg: redact(msg), ...(clean(fields ?? {}) as object) }
  sink(JSON.stringify(entry))
}

export const log = {
  debug: (msg: string, fields?: Record<string, unknown>) => write("debug", msg, fields),
  info: (msg: string, fields?: Record<string, unknown>) => write("info", msg, fields),
  warn: (msg: string, fields?: Record<string, unknown>) => write("warn", msg, fields),
  error: (msg: string, fields?: Record<string, unknown>) => write("error", msg, fields),
}

/** Logs the first time a key is seen, then once per `everyMs` at most: an outage is one line, not thousands. */
export function throttled(everyMs: number) {
  const last = new Map<string, number>()
  return (key: string, fn: () => void): void => {
    const now = Date.now()
    const prev = last.get(key)
    if (prev === undefined || now - prev >= everyMs) {
      last.set(key, now)
      fn()
    }
  }
}
