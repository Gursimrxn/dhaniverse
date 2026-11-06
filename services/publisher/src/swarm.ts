// A small client for the Bee HTTP API (openapi/Swarm.yaml, API 8.x), only what the publisher needs:
//   POST /bzz            one file, or a collection sent as multipart/form-data (always a collection)
//   GET  /bzz/{ref}/{p}  read a file back
//   GET  /stamps/{id}    the postage batch's state (usable, TTL, fullness)
// Content is uploaded unencrypted on purpose: everything here is public, and a plain reference
// carries no key. Uploads need a postage batch; there are no fake references when Bee is absent.

import { randomBytes } from "node:crypto"
import type { BeeConfig } from "./config.ts"
import type { FetchLike } from "./city.ts"
import { publicSwarmRef } from "./swarmRef.ts"

export type SwarmFile = { path: string; contentType: string; data: Uint8Array }

export class SwarmNotConfigured extends Error {
  constructor() {
    super("Swarm is not configured (BEE_URL and BEE_POSTAGE_BATCH)")
    this.name = "SwarmNotConfigured"
  }
}

export class SwarmError extends Error {
  readonly status: number | null
  constructor(message: string, status: number | null) {
    super(message)
    this.name = "SwarmError"
    this.status = status
  }
}

export type StampInfo = {
  batchID: string
  usable: boolean
  depth: number | null
  bucketDepth: number | null
  amount: string | null
  batchTTL: number | null
  utilizationRatio: number | null
  immutableFlag: boolean | null
  label: string | null
}

const SAFE_PATH = /^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$/

export class Swarm {
  private readonly cfg: BeeConfig
  private readonly fetchImpl: FetchLike

  constructor(cfg: BeeConfig, fetchImpl: FetchLike = fetch) {
    this.cfg = cfg
    this.fetchImpl = fetchImpl
  }

  /** Both a node and a batch to pay for storage with. */
  get configured(): boolean {
    return Boolean(this.cfg.url && this.cfg.postageBatch)
  }

  /** The node alone is enough to read. */
  get readable(): boolean {
    return Boolean(this.cfg.url)
  }

  private uploadHeaders(contentType: string): Record<string, string> {
    if (!this.configured) throw new SwarmNotConfigured()
    return {
      "content-type": contentType,
      "swarm-postage-batch-id": this.cfg.postageBatch as string,
      "swarm-pin": String(this.cfg.pin),
      "swarm-deferred-upload": String(this.cfg.deferred),
    }
  }

  private async post(path: string, headers: Record<string, string>, body: Uint8Array): Promise<string> {
    let res: Response
    try {
      res = await this.fetchImpl(`${this.cfg.url}${path}`, {
        method: "POST",
        headers,
        body: body as unknown as BodyInit,
        signal: AbortSignal.timeout(this.cfg.timeoutMs),
      })
    } catch (err) {
      throw new SwarmError(`Bee unreachable: ${(err as Error).message}`, null)
    }
    const text = await res.text().catch(() => "")
    if (res.status === 402) {
      throw new SwarmError("Bee refused the upload (402): the postage batch is not usable, expired or full", 402)
    }
    if (!res.ok) throw new SwarmError(`Bee answered ${res.status}: ${text.slice(0, 200)}`, res.status)
    let reference: unknown
    try {
      reference = (JSON.parse(text) as { reference?: unknown }).reference
    } catch {
      throw new SwarmError("Bee returned a body that is not JSON", res.status)
    }
    const ref = publicSwarmRef(reference)
    if (ref === null) {
      // A 128-hex (encrypted) reference would embed its key; it must never reach a public entity.
      throw new SwarmError("Bee returned a reference that is not a plain 32-byte address", res.status)
    }
    return ref
  }

  /** One file. Its reference is a manifest; read it back at /bzz/{ref}. */
  async uploadFile(name: string, contentType: string, data: Uint8Array): Promise<string> {
    if (!SAFE_PATH.test(name)) throw new SwarmError(`unsafe file name "${name}"`, null)
    return this.post(`/bzz?name=${encodeURIComponent(name)}`, this.uploadHeaders(contentType), data)
  }

  /** Several files under one manifest; `/bzz/{ref}/` serves `indexDocument`. */
  async uploadCollection(files: SwarmFile[], indexDocument: string): Promise<string> {
    if (files.length === 0) throw new SwarmError("an empty collection", null)
    const seen = new Set<string>()
    for (const f of files) {
      if (!SAFE_PATH.test(f.path) || seen.has(f.path)) throw new SwarmError(`unsafe or repeated path "${f.path}"`, null)
      seen.add(f.path)
    }
    if (!seen.has(indexDocument)) throw new SwarmError("the index document is not in the collection", null)
    const { body, contentType } = multipart(files)
    const headers = {
      ...this.uploadHeaders(contentType),
      "swarm-collection": "true",
      "swarm-index-document": indexDocument,
    }
    return this.post("/bzz", headers, body)
  }

  /** Reads one file of a manifest. Capped, since what comes back is fetched on a user's behalf. */
  async download(ref: string, path = "", maxBytes = 5 * 1024 * 1024): Promise<{ contentType: string; data: Uint8Array }> {
    if (!this.readable) throw new SwarmNotConfigured()
    const clean = publicSwarmRef(ref)
    if (clean === null) throw new SwarmError("not a Swarm reference", 400)
    if (path && !SAFE_PATH.test(path)) throw new SwarmError("unsafe path", 400)
    let res: Response
    try {
      res = await this.fetchImpl(`${this.cfg.url}/bzz/${clean}/${path}`, { signal: AbortSignal.timeout(this.cfg.timeoutMs) })
    } catch (err) {
      throw new SwarmError(`Bee unreachable: ${(err as Error).message}`, null)
    }
    if (!res.ok) throw new SwarmError(`Bee answered ${res.status}`, res.status)
    const declared = Number(res.headers.get("content-length") ?? "0")
    if (declared > maxBytes) throw new SwarmError("too large", 413)
    const data = new Uint8Array(await res.arrayBuffer())
    if (data.length > maxBytes) throw new SwarmError("too large", 413)
    return { contentType: res.headers.get("content-type") ?? "application/octet-stream", data }
  }

  async stamp(): Promise<StampInfo> {
    if (!this.configured) throw new SwarmNotConfigured()
    const res = await this.fetchImpl(`${this.cfg.url}/stamps/${this.cfg.postageBatch}`, {
      signal: AbortSignal.timeout(this.cfg.timeoutMs),
    })
    if (!res.ok) throw new SwarmError(`Bee answered ${res.status} for the postage batch`, res.status)
    const b = (await res.json()) as Record<string, unknown>
    const numOrNull = (x: unknown) => (typeof x === "number" ? x : null)
    return {
      batchID: String(b.batchID ?? this.cfg.postageBatch),
      usable: b.usable === true,
      depth: numOrNull(b.depth),
      bucketDepth: numOrNull(b.bucketDepth),
      amount: typeof b.amount === "string" ? b.amount : null,
      batchTTL: numOrNull(b.batchTTL),
      utilizationRatio: numOrNull(b.utilizationRatio),
      immutableFlag: typeof b.immutableFlag === "boolean" ? b.immutableFlag : null,
      label: typeof b.label === "string" ? b.label : null,
    }
  }
}

/**
 * multipart/form-data built by hand so every part states its filename (the path in the manifest),
 * Content-Type (stored as the file's type) and Content-Length: Bee's multipart reader reads all three
 * from the part headers (pkg/api/dirs.go). FormData would leave the length out.
 */
export function multipart(files: SwarmFile[]): { body: Uint8Array; contentType: string } {
  const boundary = `----tallyport${randomBytes(12).toString("hex")}`
  const enc = new TextEncoder()
  const chunks: Uint8Array[] = []
  for (const f of files) {
    chunks.push(
      enc.encode(
        `--${boundary}\r\n` +
          `Content-Disposition: form-data; name="file"; filename="${f.path}"\r\n` +
          `Content-Type: ${f.contentType}\r\n` +
          `Content-Length: ${f.data.length}\r\n\r\n`,
      ),
      f.data,
      enc.encode("\r\n"),
    )
  }
  chunks.push(enc.encode(`--${boundary}--\r\n`))
  const total = chunks.reduce((n, c) => n + c.length, 0)
  const body = new Uint8Array(total)
  let at = 0
  for (const c of chunks) {
    body.set(c, at)
    at += c.length
  }
  return { body, contentType: `multipart/form-data; boundary=${boundary}` }
}
