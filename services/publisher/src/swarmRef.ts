// Swarm references that may go on a public Arkiv entity.
//
// A plain Swarm reference is a 32-byte content address (64 hex). An *encrypted* reference is 64
// bytes (128 hex): the address followed by the decryption key. Putting one of those on a public
// entity would publish the key with it, so they are refused here, at the one gate every reference
// passes through on its way to Arkiv.

export function publicSwarmRef(input: unknown): string | null {
  if (typeof input !== "string") return null
  const hex = input.trim().replace(/^0x/i, "").toLowerCase()
  if (/^[0-9a-f]{64}$/.test(hex) && !/^0{64}$/.test(hex)) return hex
  return null
}

export function isEncryptedRef(input: unknown): boolean {
  return typeof input === "string" && /^(0x)?[0-9a-fA-F]{128}$/.test(input.trim())
}

/** The bytes32 a contract stores for a reference (`CampaignParams.metaHash`). */
export function refToBytes32(ref: string): `0x${string}` {
  const clean = publicSwarmRef(ref)
  if (clean === null) throw new Error("not a public 32-byte Swarm reference")
  return `0x${clean}`
}
