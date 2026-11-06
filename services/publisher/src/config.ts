// Every setting comes from the environment. Secrets are registered with the logger before anything
// else runs, so no later log line can print them.

import { addSecret } from "./log.ts"

export type ArkivConfig = {
  /** 0x-prefixed 32-byte hex. Absent: the publisher writes nothing to Arkiv. */
  privateKey: `0x${string}` | undefined
  /** Arkiv RPC access key (hub.arkiv.network/access-keys). "" uses the heavily rate-limited public endpoint. */
  accessKey: string
  /** Override the chain's RPC URL (a local Arkiv node, say). */
  rpcUrl: string | undefined
  chain: "rabdi" | "localhost"
  /** Whose entities the read API trusts. Defaults to the writer key's address. */
  writerAddress: `0x${string}` | undefined
  flushIntervalMs: number
  maxOpsPerTx: number
  txTimeoutMs: number
  queryTimeoutMs: number
}

export type BeeConfig = {
  url: string | undefined
  postageBatch: string | undefined
  pin: boolean
  deferred: boolean
  timeoutMs: number
}

export type Config = {
  serverUrl: string
  pollIntervalMs: number
  cityTimeoutMs: number
  /** The `env` attribute on every entity, so rehearsal data and live data never mix in a query. */
  env: string
  host: string
  port: number
  stateDir: string
  priceBatchMs: number
  readCacheMs: number
  profileFallbackDays: number
  corsOrigins: string[]
  uploadsPerHour: number
  uploadsPerDay: number
  logLevel: string
  arkiv: ArkivConfig
  bee: BeeConfig
}

export class ConfigError extends Error {
  constructor(message: string) {
    super(message)
    this.name = "ConfigError"
  }
}

type Env = Record<string, string | undefined>

function str(env: Env, name: string, fallback: string): string {
  const v = env[name]?.trim()
  return v ? v : fallback
}

function optional(env: Env, name: string): string | undefined {
  const v = env[name]?.trim()
  return v ? v : undefined
}

function int(env: Env, name: string, fallback: number, min: number, max: number): number {
  const raw = env[name]?.trim()
  if (!raw) return fallback
  const n = Number(raw)
  if (!Number.isInteger(n) || n < min || n > max) {
    throw new ConfigError(`${name} must be a whole number from ${min} to ${max}, got "${raw}"`)
  }
  return n
}

function bool(env: Env, name: string, fallback: boolean): boolean {
  const raw = env[name]?.trim().toLowerCase()
  if (!raw) return fallback
  if (["1", "true", "yes", "on"].includes(raw)) return true
  if (["0", "false", "no", "off"].includes(raw)) return false
  throw new ConfigError(`${name} must be true or false, got "${raw}"`)
}

function url(env: Env, name: string, fallback?: string): string | undefined {
  const raw = optional(env, name) ?? fallback
  if (raw === undefined) return undefined
  try {
    const u = new URL(raw)
    if (u.protocol !== "http:" && u.protocol !== "https:") throw new Error("not http")
  } catch {
    throw new ConfigError(`${name} must be an http(s) URL, got "${raw}"`)
  }
  return raw.replace(/\/+$/, "")
}

export function loadConfig(env: Env = process.env): Config {
  const rawKey = optional(env, "ARKIV_PRIVATE_KEY")
  // Registered before validation, so even a malformed key can't be echoed by an error message.
  addSecret(rawKey)
  let privateKey: `0x${string}` | undefined
  if (rawKey !== undefined) {
    const hex = rawKey.startsWith("0x") ? rawKey : `0x${rawKey}`
    if (!/^0x[0-9a-fA-F]{64}$/.test(hex)) {
      throw new ConfigError("ARKIV_PRIVATE_KEY must be 32 bytes of hex (64 hex characters, 0x optional)")
    }
    privateKey = hex as `0x${string}`
  }

  const writer = optional(env, "ARKIV_WRITER_ADDRESS")
  if (writer !== undefined && !/^0x[0-9a-fA-F]{40}$/.test(writer)) {
    throw new ConfigError("ARKIV_WRITER_ADDRESS must be a 0x-prefixed 20-byte address")
  }

  const chain = str(env, "ARKIV_CHAIN", "rabdi")
  if (chain !== "rabdi" && chain !== "localhost") {
    throw new ConfigError(`ARKIV_CHAIN must be "rabdi" or "localhost", got "${chain}"`)
  }

  const batch = optional(env, "BEE_POSTAGE_BATCH")
  if (batch !== undefined && !/^(0x)?[0-9a-fA-F]{64}$/.test(batch)) {
    throw new ConfigError("BEE_POSTAGE_BATCH must be a 64-hex-character batch ID")
  }

  const envName = str(env, "PUBLISHER_ENV", "dev")
  if (!/^[a-z0-9][a-z0-9-]{0,31}$/.test(envName)) {
    throw new ConfigError("PUBLISHER_ENV must be 1-32 characters of a-z, 0-9 and -")
  }

  return {
    serverUrl: url(env, "SERVER_URL", "http://127.0.0.1:7878") as string,
    pollIntervalMs: int(env, "POLL_INTERVAL_MS", 15_000, 1_000, 3_600_000),
    cityTimeoutMs: int(env, "CITY_TIMEOUT_MS", 5_000, 500, 60_000),
    env: envName,
    host: str(env, "PUBLISHER_HOST", "127.0.0.1"),
    port: int(env, "PUBLISHER_PORT", 8787, 0, 65_535),
    stateDir: str(env, "PUBLISHER_STATE_DIR", "data"),
    priceBatchMs: int(env, "PRICE_BATCH_MS", 300_000, 10_000, 3_600_000),
    readCacheMs: int(env, "READ_CACHE_MS", 10_000, 0, 600_000),
    profileFallbackDays: int(env, "PROFILE_FALLBACK_DAYS", 7, 1, 180),
    corsOrigins: str(env, "CORS_ORIGINS", "*")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean),
    uploadsPerHour: int(env, "UPLOADS_PER_HOUR", 12, 0, 10_000),
    uploadsPerDay: int(env, "UPLOADS_PER_DAY", 200, 0, 100_000),
    logLevel: str(env, "LOG_LEVEL", "info"),
    arkiv: {
      privateKey,
      accessKey: str(env, "ARKIV_ACCESS_KEY", ""),
      rpcUrl: url(env, "ARKIV_RPC_URL"),
      chain,
      writerAddress: writer as `0x${string}` | undefined,
      flushIntervalMs: int(env, "ARKIV_FLUSH_INTERVAL_MS", 20_000, 1_000, 3_600_000),
      maxOpsPerTx: int(env, "ARKIV_MAX_OPS_PER_TX", 12, 1, 100),
      txTimeoutMs: int(env, "ARKIV_TX_TIMEOUT_MS", 120_000, 5_000, 900_000),
      queryTimeoutMs: int(env, "ARKIV_QUERY_TIMEOUT_MS", 15_000, 1_000, 120_000),
    },
    bee: {
      url: url(env, "BEE_URL"),
      postageBatch: batch?.replace(/^0x/, "").toLowerCase(),
      pin: bool(env, "BEE_PIN", true),
      deferred: bool(env, "BEE_DEFERRED_UPLOAD", true),
      timeoutMs: int(env, "BEE_TIMEOUT_MS", 60_000, 1_000, 600_000),
    },
  }
}
