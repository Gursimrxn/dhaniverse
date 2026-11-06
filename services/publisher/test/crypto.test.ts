import assert from "node:assert/strict"
import { randomBytes } from "node:crypto"
import { test } from "node:test"
import { decrypt, encrypt, parseKey } from "../src/crypto.ts"

const key = parseKey("11".repeat(32))
const plain = Buffer.from('{"seq":1,"input":{},"events":[]}\n'.repeat(20))

test("round trip: nonce in front, tag after", () => {
  const blob = encrypt(key, plain)
  assert.equal(blob.length, 12 + plain.length + 16)
  assert.deepEqual(decrypt(key, blob), plain)
})

test("a wrong key fails", () => {
  assert.throws(() => decrypt(parseKey("22".repeat(32)), encrypt(key, plain)))
})

test("a flipped byte fails: in the nonce, the ciphertext and the tag", () => {
  for (const at of [3, 12 + 5, 12 + plain.length + 2]) {
    const blob = encrypt(key, plain)
    blob[at] = (blob[at] as number) ^ 1
    assert.throws(() => decrypt(key, blob), `byte ${at}`)
  }
})

test("two encryptions of the same plaintext differ (fresh nonce)", () => {
  const a = encrypt(key, plain)
  const b = encrypt(key, plain)
  assert.notDeepEqual(a.subarray(0, 12), b.subarray(0, 12))
  assert.notDeepEqual(a, b)
})

test("the key must be 64 hex characters", () => {
  assert.throws(() => parseKey("abcd"))
  assert.throws(() => parseKey("zz".repeat(32)))
  assert.equal(parseKey(randomBytes(32).toString("hex")).length, 32)
})
