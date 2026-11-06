// An in-memory Arkiv node behind a viem `custom` transport, so tests run the *real* SDK end to end:
// it signs and sends real `execute` transactions (decoded here exactly as the engine would read
// them: operations, attributes, type ids, the indexed flag, expiries) and answers `arkiv_query` by
// evaluating the query string the SDK rendered. It implements only the subset of the query language
// the publisher emits: comparisons, AND, OR, parentheses, ORDER BY, limit and offset.

import {
  type Hex,
  custom,
  decodeAbiParameters,
  decodeFunctionData,
  encodeAbiParameters,
  encodeEventTopics,
  hexToBytes,
  hexToString,
  keccak256,
  parseAbi,
  parseAbiParameters,
  parseTransaction,
  recoverTransactionAddress,
  toHex,
  type TransactionSerialized,
} from "viem"
import { ENTITY_EVENTS_ABI } from "@arkiv-network/sdk"

export const ARKIV_ADDRESS = "0x4400000000000000000000000000000000000044"
const EXECUTE_ABI = parseAbi(["function execute((uint8 operation, bytes operationData)[] ops) external returns (bytes32[] keys)"])
const ATTRS = "(bytes32 name, uint8 typeId, bytes value)[]"
const PAYLOAD = {
  1: parseAbiParameters(`(uint128 salt, uint64 expiresAt, uint64 minLifetime, uint8 creationFlags, ${ATTRS} attributes)`),
  2: parseAbiParameters(`(bytes32 entityKey, ${ATTRS} mutations)`),
  3: parseAbiParameters("(bytes32 entityKey, uint64 expiresAt, uint64 minLifetime)"),
} as const
const TYPE_NAMES: Record<number, string> = { 1: "bool", 2: "i32", 3: "u64", 4: "u256", 5: "dec", 7: "bytes", 8: "str", 9: "addr", 10: "key" }

export type Attr = { type: string; indexed: boolean; value: string | bigint | number }
export type StoredEntity = {
  key: Hex
  owner: Hex
  createdAt: bigint
  updatedAt: bigint
  expiresAt: bigint
  attributes: Map<string, Attr>
}

type Tx = { hash: Hex; block: bigint; logs: unknown[]; from: Hex }

export class FakeArkiv {
  block = 1_000n
  readonly entities = new Map<Hex, StoredEntity>()
  readonly queries: { query: string; options: unknown }[] = []
  readonly txs: { ops: number; creates: number; patches: number; extends: number }[] = []
  private readonly receipts = new Map<Hex, Tx>()
  private readonly nonces = new Map<string, number>()
  private entityNonce = 0n
  /** When set, every request throws (Arkiv is down). */
  down = false
  /** When set, the next `n` sendRawTransaction calls throw before applying. */
  failSends = 0
  /** When set, sendRawTransaction applies the batch but the receipt never arrives (a timeout after landing). */
  swallowReceipts = false

  transport() {
    return custom({ request: ({ method, params }) => this.request(method, params as unknown[]) })
  }

  liveEntities(): StoredEntity[] {
    return [...this.entities.values()].filter((e) => e.expiresAt > this.block)
  }

  ofSchema(tag: string): StoredEntity[] {
    return this.liveEntities().filter((e) => e.attributes.get("arkiv.schema")?.value === tag)
  }

  private async request(method: string, params: unknown[]): Promise<unknown> {
    if (this.down) throw new Error("fake arkiv: connection refused")
    switch (method) {
      case "eth_chainId":
        return "0x76edaf"
      case "eth_blockNumber":
        return toHex(this.block)
      case "eth_estimateGas":
        return "0x100000"
      case "eth_gasPrice":
      case "eth_maxPriorityFeePerGas":
        return "0x1"
      case "eth_getTransactionCount": {
        const who = String(params[0]).toLowerCase()
        return toHex(this.nonces.get(who) ?? 0)
      }
      case "eth_getBlockByNumber":
        return this.blockObject()
      case "eth_sendRawTransaction":
        return this.send(params[0] as TransactionSerialized)
      case "eth_getTransactionReceipt": {
        const tx = this.receipts.get(params[0] as Hex)
        if (!tx || this.swallowReceipts) return null
        return {
          transactionHash: tx.hash,
          transactionIndex: "0x0",
          blockHash: keccak256(toHex(tx.block)),
          blockNumber: toHex(tx.block),
          from: tx.from,
          to: ARKIV_ADDRESS,
          cumulativeGasUsed: "0x1000",
          gasUsed: "0x1000",
          effectiveGasPrice: "0x1",
          contractAddress: null,
          logs: tx.logs,
          logsBloom: `0x${"0".repeat(512)}`,
          status: "0x1",
          type: "0x2",
        }
      }
      case "arkiv_query":
        return this.query(params[0] as string, (params[1] ?? {}) as Record<string, unknown>)
      default:
        // A real node answers -32601 for a method it lacks; viem then falls back without retrying.
        throw Object.assign(new Error(`fake arkiv: ${method} not implemented`), { code: -32601 })
    }
  }

  private blockObject() {
    return {
      number: toHex(this.block),
      hash: keccak256(toHex(this.block)),
      parentHash: keccak256(toHex(this.block - 1n)),
      timestamp: toHex(Math.floor(Date.now() / 1000)),
      baseFeePerGas: "0x1",
      gasLimit: "0x1c9c380",
      gasUsed: "0x0",
      miner: "0x0000000000000000000000000000000000000000",
      nonce: "0x0000000000000000",
      difficulty: "0x0",
      extraData: "0x",
      logsBloom: `0x${"0".repeat(512)}`,
      receiptsRoot: keccak256("0x01"),
      sha3Uncles: keccak256("0x02"),
      size: "0x1",
      stateRoot: keccak256("0x03"),
      transactionsRoot: keccak256("0x04"),
      transactions: [],
      uncles: [],
    }
  }

  private async send(raw: TransactionSerialized): Promise<Hex> {
    if (this.failSends > 0) {
      this.failSends -= 1
      throw new Error("fake arkiv: nonce too low")
    }
    const tx = parseTransaction(raw)
    const from = (await recoverTransactionAddress({ serializedTransaction: raw as never })).toLowerCase() as Hex
    if (tx.to?.toLowerCase() !== ARKIV_ADDRESS) throw new Error("fake arkiv: not an Arkiv transaction")
    const { args } = decodeFunctionData({ abi: EXECUTE_ABI, data: tx.data as Hex })
    this.block += 1n
    const logs: unknown[] = []
    const counts = { ops: 0, creates: 0, patches: 0, extends: 0 }
    for (const op of args[0]) {
      counts.ops += 1
      if (op.operation === 1) {
        counts.creates += 1
        const [p] = decodeAbiParameters(PAYLOAD[1], op.operationData)
        const key = keccak256(encodeAbiParameters(parseAbiParameters("address, uint64, uint128"), [from, this.entityNonce++, p.salt]))
        const expiresAt = maxBig(p.expiresAt, this.block + p.minLifetime)
        this.entities.set(key, {
          key,
          owner: from,
          createdAt: this.block,
          updatedAt: this.block,
          expiresAt,
          attributes: decodeAttributes(p.attributes),
        })
        logs.push(this.log("EntityCreated", { entityKey: key, owner: from }, ["uint64", "uint8"], [expiresAt, p.creationFlags]))
      } else if (op.operation === 2) {
        counts.patches += 1
        const [p] = decodeAbiParameters(PAYLOAD[2], op.operationData)
        const e = this.mustOwn(p.entityKey, from)
        for (const [name, attr] of decodeAttributes(p.mutations)) e.attributes.set(name, attr)
        e.updatedAt = this.block
        logs.push(this.log("EntityPatched", { entityKey: e.key, owner: from }, [], []))
      } else if (op.operation === 3) {
        counts.extends += 1
        const [p] = decodeAbiParameters(PAYLOAD[3], op.operationData)
        const e = this.mustOwn(p.entityKey, from)
        const target = maxBig(p.expiresAt, this.block + p.minLifetime)
        if (target < e.expiresAt) throw new Error("fake arkiv: ExpiryNotExtended")
        e.expiresAt = target
        logs.push(this.log("ExpiryExtended", { entityKey: e.key, owner: from }, ["uint64"], [target]))
      } else {
        throw new Error(`fake arkiv: operation ${op.operation} not supported`)
      }
    }
    this.txs.push(counts)
    const hash = keccak256(raw)
    this.nonces.set(from, (this.nonces.get(from) ?? 0) + 1)
    this.receipts.set(hash, { hash, block: this.block, logs, from })
    return hash
  }

  private mustOwn(key: Hex, from: Hex): StoredEntity {
    const e = this.entities.get(key)
    if (!e || e.expiresAt <= this.block) throw new Error("fake arkiv: EntityNotFound")
    if (e.owner !== from) throw new Error("fake arkiv: NotOwner")
    return e
  }

  private log(eventName: string, indexed: Record<string, Hex>, types: string[], values: unknown[]) {
    const topics = encodeEventTopics({ abi: ENTITY_EVENTS_ABI, eventName: eventName as never, args: indexed as never })
    const data = types.length ? encodeAbiParameters(parseAbiParameters(types.join(", ")), values as never) : "0x"
    return {
      address: ARKIV_ADDRESS,
      topics,
      data,
      blockNumber: toHex(this.block),
      blockHash: keccak256(toHex(this.block)),
      transactionHash: "0x" + "00".repeat(32),
      transactionIndex: "0x0",
      logIndex: "0x0",
      removed: false,
    }
  }

  private query(query: string, options: Record<string, unknown>) {
    this.queries.push({ query, options })
    const { filter, order } = parseQuery(query)
    let rows = this.liveEntities().filter((e) => filter(e))
    if (order) {
      rows.sort((a, b) => {
        const av = sortable(a, order.name)
        const bv = sortable(b, order.name)
        const c = av === bv ? 0 : av === undefined ? 1 : bv === undefined ? -1 : av < bv ? -1 : 1
        return order.desc ? -c : c
      })
    }
    const offset = options.offset ? Number(options.offset) : 0
    const limit = options.limit ? Number(options.limit) : 100
    const total = rows.length
    rows = rows.slice(offset, offset + limit)
    const select = (options.select ?? {}) as Record<string, unknown>
    return {
      data: rows.map((e) => this.rpcEntity(e, select)),
      blockNumber: toHex(this.block),
      ...(select.count ? { count: toHex(total) } : {}),
    }
  }

  private rpcEntity(e: StoredEntity, select: Record<string, unknown>) {
    const out: Record<string, unknown> = {}
    if (select.key) out.key = e.key
    if (select.owner) out.owner = e.owner
    if (select.creator) out.creator = e.owner
    if (select.createdAt) out.createdAt = toHex(e.createdAt)
    if (select.updatedAt) out.updatedAt = toHex(e.updatedAt)
    if (select.expiresAt) out.expiresAt = toHex(e.expiresAt)
    const wanted = select.attributes
    if (wanted) {
      const names = wanted === true ? [...e.attributes.keys()] : Object.keys(wanted as object)
      out.attributes = names
        .filter((n) => e.attributes.has(n))
        .map((n) => {
          const a = e.attributes.get(n) as Attr
          return { name: n, type: a.type, value: typeof a.value === "bigint" ? toHex(a.value) : a.value }
        })
    }
    return out
  }
}

function maxBig(a: bigint, b: bigint): bigint {
  return a > b ? a : b
}

function decodeAttributes(list: readonly { name: Hex; typeId: number; value: Hex }[]): Map<string, Attr> {
  const out = new Map<string, Attr>()
  for (const a of list) {
    const name = hexToString(a.name).replace(/\u0000+$/, "")
    const type = TYPE_NAMES[a.typeId & 0x7f]
    if (!type) throw new Error(`fake arkiv: unknown type id ${a.typeId}`)
    const indexed = (a.typeId & 0x80) !== 0
    let value: string | bigint | number
    if (type === "str") value = new TextDecoder().decode(hexToBytes(a.value))
    else if (type === "bytes") value = a.value.toLowerCase()
    else if (type === "i32") value = Number(BigInt.asIntN(32, BigInt(a.value)))
    else if (type === "addr") value = `0x${a.value.slice(-40)}`
    else if (type === "key") value = a.value
    else value = BigInt(a.value)
    out.set(name, { type, indexed, value })
  }
  return out
}

function sortable(e: StoredEntity, name: string): string | bigint | number | undefined {
  if (name === "$expiresAt") return e.expiresAt
  return e.attributes.get(name)?.value
}

// ---- the query subset ---------------------------------------------------------------------------

type Pred = (e: StoredEntity) => boolean

function parseValue(type: string, raw: string): string | bigint | number {
  if (type === "str") return raw.slice(1, -1).replace(/''/g, "'")
  if (type === "addr" || type === "key") return raw.toLowerCase()
  if (type === "i32") return Number(raw)
  return BigInt(raw)
}

export function parseQuery(q: string): { filter: Pred; order: { name: string; desc: boolean } | null } {
  let text = q
  let order: { name: string; desc: boolean } | null = null
  const m = /\s+ORDER BY\s+([$A-Za-z0-9._-]+)(?::[a-z0-9]+)?\s+(ASC|DESC)\s*$/.exec(text)
  if (m) {
    order = { name: m[1] as string, desc: m[2] === "DESC" }
    text = text.slice(0, m.index)
  }
  const tokens = text.match(/\(|\)|AND|OR|[$A-Za-z0-9._-]+\s*(?:>=|<=|!=|=|>|<)\s*[a-z0-9]+\((?:'(?:[^']|'')*'|[^)]*)\)/g) ?? []
  let i = 0
  const expr = (): Pred => {
    let left = term()
    while (tokens[i] === "OR") {
      i++
      const l = left
      const r = term()
      left = (e) => l(e) || r(e)
    }
    return left
  }
  const term = (): Pred => {
    let left = factor()
    while (tokens[i] === "AND") {
      i++
      const l = left
      const r = factor()
      left = (e) => l(e) && r(e)
    }
    return left
  }
  const factor = (): Pred => {
    const t = tokens[i++]
    if (t === "(") {
      const inner = expr()
      if (tokens[i++] !== ")") throw new Error(`fake arkiv: unbalanced query ${q}`)
      return inner
    }
    const a = /^([$A-Za-z0-9._-]+)\s*(>=|<=|!=|=|>|<)\s*([a-z0-9]+)\(((?:'(?:[^']|'')*')|[^)]*)\)$/.exec(t ?? "")
    if (!a) throw new Error(`fake arkiv: cannot parse "${t}" in ${q}`)
    const [, name, op, type, raw] = a as unknown as [string, string, string, string, string]
    const want = parseValue(type, raw)
    return (e) => {
      let have: unknown
      if (name === "$owner") have = e.owner.toLowerCase()
      else if (name === "$key") have = e.key
      else if (name === "$expiresAt") have = e.expiresAt
      else {
        const attr = e.attributes.get(name)
        if (!attr || attr.type !== type || (!attr.indexed && name !== "arkiv.schema")) return false
        have = attr.value
      }
      const h = have as string | bigint | number
      switch (op) {
        case "=":
          return h === want
        case "!=":
          return h !== want
        case ">":
          return h > want
        case ">=":
          return h >= want
        case "<":
          return h < want
        default:
          return h <= want
      }
    }
  }
  const filter = expr()
  if (i !== tokens.length) throw new Error(`fake arkiv: trailing tokens in ${q}`)
  return { filter, order }
}
