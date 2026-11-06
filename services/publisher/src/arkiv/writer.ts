// Turns planned operations into one Arkiv transaction (`executeBatch`: all apply or none do).

import { ExpirationTime, type PublicArkivClient, type WalletArkivClient } from "@arkiv-network/sdk"
import type { Hex } from "viem"
import type { Draft, Expiry } from "../entities.ts"
import { MAX_TTL_MS } from "../entities.ts"
import { ALL_SCHEMAS, type EntityType } from "../schemas.ts"
import { findExisting, type Existing } from "./queries.ts"

export type Op =
  | { kind: "create"; draft: Draft }
  | { kind: "patch"; draft: Draft; entityKey: Hex; set: Record<string, unknown>; extend: boolean }
  | { kind: "extend"; draft: Draft; entityKey: Hex }

export type ExecuteResult = { txHash: Hex; created: Hex[] }

/** What the publisher needs from Arkiv. The SDK implements it below; tests implement it in memory. */
export interface ArkivWriter {
  readonly address: Hex
  execute(ops: Op[]): Promise<ExecuteResult>
  findExisting(type: EntityType, env: string, ids: string[]): Promise<Map<string, Existing>>
}

/** A few minutes past "now" at the least, so a create never lands already dead (blocks are 2 s apart). */
const MIN_LIFETIME = ExpirationTime.fromMinutes(5)

export function toExpiration(expiry: Expiry, now: number = Date.now()) {
  if ("forSeconds" in expiry) {
    return ExpirationTime.fromSeconds(Math.min(expiry.forSeconds, MAX_TTL_MS / 1000))
  }
  const at = Math.min(expiry.atMs, now + MAX_TTL_MS)
  return ExpirationTime.atDate(new Date(at), { atLeast: MIN_LIFETIME })
}

export class SdkWriter implements ArkivWriter {
  readonly address: Hex
  private readonly wallet: WalletArkivClient
  private readonly reader: PublicArkivClient

  constructor(wallet: WalletArkivClient, reader: PublicArkivClient) {
    if (!wallet.account) throw new Error("the wallet client has no account")
    this.wallet = wallet
    this.reader = reader
    this.address = wallet.account.address
  }

  async execute(ops: Op[]): Promise<ExecuteResult> {
    const creates: unknown[] = []
    const patches: unknown[] = []
    const extensions: unknown[] = []
    for (const op of ops) {
      const schema = ALL_SCHEMAS[op.draft.type]
      if (op.kind === "create") {
        creates.push({ schema, values: op.draft.values, expiration: toExpiration(op.draft.expiry) })
      } else if (op.kind === "patch") {
        patches.push({ schema, entityKey: op.entityKey, set: op.set })
        if (op.extend) extensions.push({ entityKey: op.entityKey, expiration: toExpiration(op.draft.expiry) })
      } else {
        extensions.push({ entityKey: op.entityKey, expiration: toExpiration(op.draft.expiry) })
      }
    }
    const batch = {
      ...(creates.length > 0 && { creates }),
      ...(patches.length > 0 && { patches }),
      ...(extensions.length > 0 && { extensions }),
    }
    // The batch spans schemas, which the SDK types per element; its runtime checks still run.
    const res = await (this.wallet.executeBatch as (b: unknown) => Promise<{ txHash: Hex; createdEntities: Hex[] }>)(batch)
    return { txHash: res.txHash, created: res.createdEntities }
  }

  findExisting(type: EntityType, env: string, ids: string[]): Promise<Map<string, Existing>> {
    return findExisting(this.reader, this.address, type, env, ids)
  }
}
