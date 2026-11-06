// AES-256-GCM for the save on Arkiv. Layout of an encrypted blob: 12-byte nonce, the ciphertext, the 16-byte tag.

import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto"

const NONCE = 12
const TAG = 16

/** `DHANIVERSE_LOG_KEY`: 64 hex characters = 32 bytes. */
export function parseKey(hex: string): Buffer {
  if (!/^[0-9a-fA-F]{64}$/.test(hex)) throw new Error("the log key must be 64 hex characters (32 bytes)")
  return Buffer.from(hex, "hex")
}

export function encrypt(key: Buffer, plain: Uint8Array): Buffer {
  const nonce = randomBytes(NONCE)
  const c = createCipheriv("aes-256-gcm", key, nonce)
  const body = Buffer.concat([c.update(plain), c.final()])
  return Buffer.concat([nonce, body, c.getAuthTag()])
}

/** Throws when the key is wrong or a single byte was changed. */
export function decrypt(key: Buffer, blob: Uint8Array): Buffer {
  if (blob.length < NONCE + TAG) throw new Error("encrypted data is too short")
  const b = Buffer.from(blob)
  const d = createDecipheriv("aes-256-gcm", key, b.subarray(0, NONCE))
  d.setAuthTag(b.subarray(b.length - TAG))
  return Buffer.concat([d.update(b.subarray(NONCE, b.length - TAG)), d.final()])
}
