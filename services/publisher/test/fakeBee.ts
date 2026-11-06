// A Bee node in memory, as a `fetch`: POST /bzz (single file or multipart collection), GET /bzz/{ref}/{path},
// GET /stamps/{id}. References are sha256 of the content, so they are stable and 64 hex like Bee's.

import { createHash } from "node:crypto"

export type BeeRequest = { method: string; url: string; headers: Record<string, string>; body: Uint8Array }

export class FakeBee {
  readonly requests: BeeRequest[] = []
  readonly stored = new Map<string, Map<string, { type: string; data: Uint8Array }>>()
  down = false
  status: number | null = null
  encryptedRefs = false

  fetch = async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
    const url = String(input)
    const headers: Record<string, string> = {}
    new Headers(init?.headers).forEach((v, k) => (headers[k] = v))
    const body = init?.body ? new Uint8Array(init.body as ArrayBuffer) : new Uint8Array()
    const method = init?.method ?? "GET"
    this.requests.push({ method, url, headers, body })
    if (this.down) throw new TypeError("fetch failed")
    if (this.status) return new Response(JSON.stringify({ message: "nope" }), { status: this.status })
    const u = new URL(url)
    if (method === "POST" && u.pathname === "/bzz") {
      if (!/^[0-9a-f]{64}$/.test(headers["swarm-postage-batch-id"] ?? "")) return new Response("{}", { status: 400 })
      const files = new Map<string, { type: string; data: Uint8Array }>()
      const ct = headers["content-type"] ?? ""
      if (ct.startsWith("multipart/form-data")) {
        const form = await new Response(body, { headers: { "content-type": ct } }).formData()
        for (const entry of form.getAll("file")) {
          const f = entry as File
          files.set(f.name, { type: f.type, data: new Uint8Array(await f.arrayBuffer()) })
        }
      } else {
        files.set(u.searchParams.get("name") ?? "file", { type: ct, data: body })
      }
      const ref = createHash("sha256").update(body).digest("hex")
      this.stored.set(ref, files)
      return new Response(JSON.stringify({ reference: this.encryptedRefs ? ref + ref : ref }), { status: 201 })
    }
    const m = /^\/bzz\/([0-9a-f]{64})\/(.*)$/.exec(u.pathname)
    if (method === "GET" && m) {
      const files = this.stored.get(m[1] as string)
      const f = files?.get(m[2] || (headers["swarm-index-document"] ?? "index.json")) ?? (files && !m[2] ? [...files.values()][0] : undefined)
      if (!f) return new Response("{}", { status: 404 })
      return new Response(f.data as unknown as BodyInit, { status: 200, headers: { "content-type": f.type, "content-length": String(f.data.length) } })
    }
    if (method === "GET" && u.pathname.startsWith("/stamps/")) {
      return Response.json({ batchID: u.pathname.slice(8), usable: true, depth: 20, bucketDepth: 16, amount: "100000000", batchTTL: 86_400, utilizationRatio: 0.01, immutableFlag: true, label: "test" })
    }
    return new Response("{}", { status: 404 })
  }
}

export const BATCH = "c".repeat(64)
