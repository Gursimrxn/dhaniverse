// The campaign bundle the sponsor console uploads: a story JSON plus a few images, stored on Swarm
// as one collection. Its reference is the 32 bytes the console writes on chain as `metaHash`.
//
// Everything in a bundle is public forever (Swarm content is immutable), so the validator keeps to a
// whitelist of story fields, checks every image by its bytes rather than its claimed type, refuses
// SVG (it can carry script), and records nothing about who uploaded it.

import { createHash } from "node:crypto"
import { refToBytes32 } from "./swarmRef.ts"
import type { Swarm, SwarmFile } from "./swarm.ts"

export const LIMITS = {
  requestBytes: 5 * 1024 * 1024,
  storyBytes: 32 * 1024,
  imageBytes: 1024 * 1024,
  images: 6,
  imagesTotalBytes: 4 * 1024 * 1024,
  title: 120,
  sponsor: 80,
  story: 8_000,
  line: 280,
  lines: 20,
  cta: 80,
} as const

export const IMAGE_TYPES = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/webp": "webp",
  "image/gif": "gif",
} as const
type ImageType = keyof typeof IMAGE_TYPES

export class BundleError extends Error {
  readonly status: number
  constructor(message: string, status = 400) {
    super(message)
    this.name = "BundleError"
    this.status = status
  }
}

/** The image's real type, from its first bytes. */
export function sniffImage(b: Uint8Array): ImageType | null {
  const at = (i: number) => b[i] ?? -1
  if (at(0) === 0x89 && at(1) === 0x50 && at(2) === 0x4e && at(3) === 0x47 && at(4) === 0x0d && at(5) === 0x0a) return "image/png"
  if (at(0) === 0xff && at(1) === 0xd8 && at(2) === 0xff) return "image/jpeg"
  if (at(0) === 0x47 && at(1) === 0x49 && at(2) === 0x46 && at(3) === 0x38) return "image/gif"
  const ascii = (from: number, to: number) => String.fromCharCode(...b.subarray(from, to))
  if (b.length >= 12 && ascii(0, 4) === "RIFF" && ascii(8, 12) === "WEBP") return "image/webp"
  return null
}

export type Story = {
  title: string
  sponsor?: string
  template?: string
  story: string
  lines?: string[]
  cta?: string
}

const plain = (s: string) => s.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "").trim()

function field(o: Record<string, unknown>, key: string, max: number, required: boolean): string | undefined {
  const v = o[key]
  if (v === undefined || v === null || v === "") {
    if (required) throw new BundleError(`story.${key} is required`)
    return undefined
  }
  if (typeof v !== "string") throw new BundleError(`story.${key} must be text`)
  const t = plain(v)
  if (required && !t) throw new BundleError(`story.${key} is required`)
  if ([...t].length > max) throw new BundleError(`story.${key} is longer than ${max} characters`)
  return t
}

export function validateStory(raw: unknown): { story: Story; dropped: string[] } {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) throw new BundleError("the story must be a JSON object")
  const o = raw as Record<string, unknown>
  const story: Story = {
    title: field(o, "title", LIMITS.title, true) as string,
    story: field(o, "story", LIMITS.story, true) as string,
  }
  const sponsor = field(o, "sponsor", LIMITS.sponsor, false)
  if (sponsor) story.sponsor = sponsor
  const template = field(o, "template", 32, false)
  if (template) {
    if (!/^[a-z][a-z0-9_]*$/.test(template)) throw new BundleError("story.template must be a template id like spice_run")
    story.template = template
  }
  const cta = field(o, "cta", LIMITS.cta, false)
  if (cta) story.cta = cta
  if (o.lines !== undefined) {
    if (!Array.isArray(o.lines) || o.lines.length > LIMITS.lines) throw new BundleError(`story.lines must be a list of at most ${LIMITS.lines}`)
    story.lines = o.lines.map((l, i) => {
      if (typeof l !== "string") throw new BundleError(`story.lines[${i}] must be text`)
      const t = plain(l)
      if ([...t].length > LIMITS.line) throw new BundleError(`story.lines[${i}] is longer than ${LIMITS.line} characters`)
      return t
    })
  }
  const known = new Set(["title", "story", "sponsor", "template", "cta", "lines", "images"])
  return { story, dropped: Object.keys(o).filter((k) => !known.has(k)) }
}

export type ImageInput = { name: string; declaredType: string; data: Uint8Array }

export type Bundle = { files: SwarmFile[]; index: Record<string, unknown>; dropped: string[] }

export function buildBundle(storyRaw: unknown, images: ImageInput[]): Bundle {
  const { story, dropped } = validateStory(storyRaw)
  if (images.length > LIMITS.images) throw new BundleError(`at most ${LIMITS.images} images`)
  let total = 0
  const files: SwarmFile[] = []
  const listed: Record<string, unknown>[] = []
  images.forEach((img, i) => {
    if (img.data.length === 0) throw new BundleError(`image ${i + 1} is empty`)
    if (img.data.length > LIMITS.imageBytes) throw new BundleError(`image ${i + 1} is larger than 1 MiB`, 413)
    total += img.data.length
    const type = sniffImage(img.data)
    if (type === null) throw new BundleError(`image ${i + 1} is not a PNG, JPEG, WebP or GIF`, 415)
    if (img.declaredType && img.declaredType !== type && img.declaredType !== "application/octet-stream") {
      throw new BundleError(`image ${i + 1} says it is ${img.declaredType} but its bytes are ${type}`, 415)
    }
    const path = `image-${i + 1}.${IMAGE_TYPES[type]}`
    files.push({ path, contentType: type, data: img.data })
    listed.push({ path, type, bytes: img.data.length, sha256: createHash("sha256").update(img.data).digest("hex") })
  })
  if (total > LIMITS.imagesTotalBytes) throw new BundleError("images add up to more than 4 MiB", 413)
  const index = { kind: "tallyport.campaign-bundle", v: 1, ...story, images: listed }
  const indexBytes = new TextEncoder().encode(JSON.stringify(index, null, 2))
  if (indexBytes.length > LIMITS.storyBytes) throw new BundleError("the story is larger than 32 KiB", 413)
  files.unshift({ path: "index.json", contentType: "application/json", data: indexBytes })
  return { files, index, dropped }
}

export async function uploadBundle(swarm: Swarm, bundle: Bundle) {
  const reference = await swarm.uploadCollection(bundle.files, "index.json")
  return {
    reference,
    metaHash: refToBytes32(reference),
    index: `/bzz/${reference}/`,
    files: bundle.files.map((f) => `/bzz/${reference}/${f.path}`),
    bytes: bundle.files.reduce((n, f) => n + f.data.length, 0),
    dropped: bundle.dropped,
  }
}

/** Parses the console's multipart form: a `story` field (JSON text or a .json file) and `image` files. */
export async function parseBundleForm(contentType: string, body: Uint8Array): Promise<{ story: unknown; images: ImageInput[] }> {
  if (!/^multipart\/form-data;\s*boundary=/i.test(contentType)) {
    throw new BundleError("send multipart/form-data with a story field and image files", 415)
  }
  let form: FormData
  try {
    form = await new Response(body as unknown as BodyInit, { headers: { "content-type": contentType } }).formData()
  } catch {
    throw new BundleError("the form could not be read")
  }
  const storyEntry = form.get("story")
  if (storyEntry === null) throw new BundleError("the form has no story field")
  const storyText = typeof storyEntry === "string" ? storyEntry : await storyEntry.text()
  if (new TextEncoder().encode(storyText).length > LIMITS.storyBytes) throw new BundleError("the story is larger than 32 KiB", 413)
  let story: unknown
  try {
    story = JSON.parse(storyText)
  } catch {
    throw new BundleError("the story field is not JSON")
  }
  const images: ImageInput[] = []
  for (const key of ["image", "images"]) {
    for (const entry of form.getAll(key)) {
      if (typeof entry === "string") throw new BundleError(`${key} must be a file`)
      images.push({ name: entry.name, declaredType: entry.type, data: new Uint8Array(await entry.arrayBuffer()) })
    }
  }
  return { story, images }
}
