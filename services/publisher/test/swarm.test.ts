// The Bee client and the campaign bundle: headers, multipart layout, validation, failure modes.

import assert from "node:assert/strict"
import { test } from "node:test"
import { BundleError, buildBundle, parseBundleForm, sniffImage, uploadBundle } from "../src/bundle.ts"
import { Swarm, SwarmError, SwarmNotConfigured, multipart } from "../src/swarm.ts"
import { BATCH, FakeBee } from "./fakeBee.ts"

const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 1, 2, 3])
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 16, 0x4a, 0x46])
const SVG = new TextEncoder().encode('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>')
const STORY = { title: "The Spice Run", sponsor: "Mango Traders", template: "spice_run", story: "Bring the saffron home.", lines: ["Hello", "Bye"] }

function swarm(bee = new FakeBee(), configured = true) {
  return {
    bee,
    s: new Swarm(
      configured ? { url: "http://bee.test", postageBatch: BATCH, pin: true, deferred: false, timeoutMs: 1000 } : { url: undefined, postageBatch: undefined, pin: true, deferred: true, timeoutMs: 1000 },
      bee.fetch,
    ),
  }
}

test("uploadFile: POST /bzz with the batch, pin and deferral headers and a file name", async () => {
  const { bee, s } = swarm()
  const ref = await s.uploadFile("paper-1.json", "application/json", new TextEncoder().encode("{}"))
  assert.match(ref, /^[0-9a-f]{64}$/)
  const r = bee.requests[0]!
  assert.equal(r.url, "http://bee.test/bzz?name=paper-1.json")
  assert.equal(r.headers["swarm-postage-batch-id"], BATCH)
  assert.equal(r.headers["swarm-pin"], "true")
  assert.equal(r.headers["swarm-deferred-upload"], "false")
  assert.equal(r.headers["content-type"], "application/json")
  assert.equal(r.headers["swarm-encrypt"], undefined, "never encrypted: public content, keyless references")
})

test("multipart: every part states its filename, Content-Type and Content-Length", async () => {
  const { body, contentType } = multipart([
    { path: "index.json", contentType: "application/json", data: new TextEncoder().encode('{"a":1}') },
    { path: "image-1.png", contentType: "image/png", data: PNG },
  ])
  const text = new TextDecoder("latin1").decode(body)
  assert.match(text, /filename="index.json"\r\nContent-Type: application\/json\r\nContent-Length: 7\r\n\r\n\{"a":1\}/)
  assert.match(text, new RegExp(`filename="image-1.png"\\r\\nContent-Type: image/png\\r\\nContent-Length: ${PNG.length}\\r\\n`))
  const form = await new Response(body as unknown as BodyInit, { headers: { "content-type": contentType } }).formData()
  assert.equal(form.getAll("file").length, 2)
})

test("bundle: story + images become one collection whose reference is the metaHash", async () => {
  const { bee, s } = swarm()
  const out = await uploadBundle(s, buildBundle({ ...STORY, wallet: "0xabc" }, [{ name: "cover.png", declaredType: "image/png", data: PNG }, { name: "x.jpg", declaredType: "image/jpeg", data: JPEG }]))
  assert.match(out.reference, /^[0-9a-f]{64}$/)
  assert.equal(out.metaHash, `0x${out.reference}`)
  assert.deepEqual(out.dropped, ["wallet"], "unknown fields are dropped, and said so")
  const req = bee.requests[0]!
  assert.equal(req.headers["swarm-collection"], "true")
  assert.equal(req.headers["swarm-index-document"], "index.json")
  const files = bee.stored.get(out.reference)!
  assert.deepEqual([...files.keys()], ["index.json", "image-1.png", "image-2.jpg"])
  const index = JSON.parse(new TextDecoder().decode(files.get("index.json")!.data))
  assert.equal(index.kind, "tallyport.campaign-bundle")
  assert.equal(index.wallet, undefined)
  assert.equal(index.images[0].path, "image-1.png")
  assert.match(index.images[0].sha256, /^[0-9a-f]{64}$/)
})

test("bundle validation: types by their bytes, SVG refused, sizes capped, fields required", () => {
  assert.equal(sniffImage(PNG), "image/png")
  assert.equal(sniffImage(SVG), null)
  assert.throws(() => buildBundle(STORY, [{ name: "a.svg", declaredType: "image/svg+xml", data: SVG }]), (e: BundleError) => e.status === 415)
  assert.throws(() => buildBundle(STORY, [{ name: "a.png", declaredType: "image/jpeg", data: PNG }]), /says it is image\/jpeg/)
  const big = new Uint8Array(1024 * 1024 + 1)
  big.set(PNG)
  assert.throws(() => buildBundle(STORY, [{ name: "big.png", declaredType: "image/png", data: big }]), (e: BundleError) => e.status === 413)
  assert.throws(() => buildBundle(STORY, Array.from({ length: 7 }, () => ({ name: "a.png", declaredType: "image/png", data: PNG }))), /at most 6/)
  assert.throws(() => buildBundle({ story: "no title" }, []), /title is required/)
  assert.throws(() => buildBundle({ ...STORY, title: "x".repeat(121) }, []), /longer than 120/)
  assert.throws(() => buildBundle({ ...STORY, template: "Spice Run!" }, []), /template id/)
  assert.throws(() => buildBundle([], []), /JSON object/)
})

test("bundle form: parses the console's multipart form", async () => {
  const form = new FormData()
  form.set("story", JSON.stringify(STORY))
  form.append("image", new File([PNG], "cover.png", { type: "image/png" }))
  const req = new Request("http://x", { method: "POST", body: form })
  const body = new Uint8Array(await req.arrayBuffer())
  const parsed = await parseBundleForm(req.headers.get("content-type")!, body)
  assert.deepEqual(parsed.story, STORY)
  assert.equal(parsed.images.length, 1)
  await assert.rejects(parseBundleForm("application/json", body), (e: BundleError) => e.status === 415)
})

test("Bee failures: unreachable, 402 for a bad batch, encrypted references refused", async () => {
  const bee = new FakeBee()
  const { s } = swarm(bee)
  bee.down = true
  await assert.rejects(s.uploadFile("a.json", "application/json", new Uint8Array([1])), (e: SwarmError) => e.status === null)
  bee.down = false
  bee.status = 402
  await assert.rejects(s.uploadFile("a.json", "application/json", new Uint8Array([1])), /postage batch/)
  bee.status = null
  bee.encryptedRefs = true
  await assert.rejects(s.uploadFile("a.json", "application/json", new Uint8Array([1])), /not a plain 32-byte address/)
})

test("not configured: no upload is attempted and nothing is invented", async () => {
  const { bee, s } = swarm(new FakeBee(), false)
  assert.equal(s.configured, false)
  await assert.rejects(s.uploadFile("a.json", "application/json", new Uint8Array([1])), SwarmNotConfigured)
  await assert.rejects(s.uploadCollection([{ path: "index.json", contentType: "application/json", data: new Uint8Array([1]) }], "index.json"), SwarmNotConfigured)
  assert.equal(bee.requests.length, 0)
})

test("unsafe paths are refused before anything is sent", async () => {
  const { bee, s } = swarm()
  await assert.rejects(s.uploadFile("../etc/passwd", "text/plain", new Uint8Array([1])), /unsafe/)
  await assert.rejects(s.download("a".repeat(64), "../x"), /unsafe/)
  assert.equal(bee.requests.length, 0)
})

test("stamp: reads the postage batch's state", async () => {
  const { s } = swarm()
  const st = await s.stamp()
  assert.equal(st.batchID, BATCH)
  assert.equal(st.usable, true)
  assert.equal(st.depth, 20)
})
