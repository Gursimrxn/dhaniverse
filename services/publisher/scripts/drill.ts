// The restore drill's publisher half: put a save on Arkiv (the save itself, encrypted and hash-chained, and the town's
// public records), then serve `GET /log` so the server can rebuild the save with `--arkiv`.
//
//   node scripts/drill.ts --fake --save <file> [--break]   in-memory Arkiv node (the server's `cargo test` drill)
//   npm run drill -- --save <file>                          real Arkiv, from .env (ARKIV_PRIVATE_KEY etc.); keep it small
//
// Needs DHANIVERSE_LOG_KEY and DHANIVERSE_RESTORE_TOKEN in the environment. Prints one line
// `READY <port> <townId> <tip>` when the save is on Arkiv and `GET /log` is listening, then the entity keys written
// (never a key or the token), and runs until stdin closes. `--break` alters one log batch on the fake node first, so
// the restore must refuse it.

import { makeClients } from "../src/arkiv/client.ts"
import { makeReader } from "../src/arkiv/queries.ts"
import { SdkWriter } from "../src/arkiv/writer.ts"
import { loadConfig } from "../src/config.ts"
import { parseKey } from "../src/crypto.ts"
import { log, setSink } from "../src/log.ts"
import { Publisher } from "../src/publisher.ts"
import { makeReadApi } from "../src/readapi.ts"
import { arkivTip, createSaveMirror, restoreLines } from "../src/save.ts"
import { MemoryStateStore, emptyState } from "../src/state.ts"
import { Swarm } from "../src/swarm.ts"
import { TownProjector } from "../src/town.ts"

const args = process.argv.slice(2)
const flag = (name: string) => args.includes(name)
const value = (name: string) => args[args.indexOf(name) + 1]
const savePath = value("--save")
if (!savePath || !args.includes("--save")) throw new Error("--save <file> is required")
const fake = flag("--fake")
setSink((line) => process.stderr.write(`${line}\n`))

const logKey = parseKey(process.env.DHANIVERSE_LOG_KEY ?? "")
const token = process.env.DHANIVERSE_RESTORE_TOKEN ?? ""
if (token.length < 32) throw new Error("DHANIVERSE_RESTORE_TOKEN must be 32+ characters")

let env = "drill"
let clients
let node: import("../test/fakeArkiv.ts").FakeArkiv | null = null
if (fake) {
  const { FakeArkiv } = await import("../test/fakeArkiv.ts")
  const { arkivConfig } = await import("../test/helpers.ts")
  node = new FakeArkiv()
  clients = makeClients(arkivConfig(), node.transport(), 5)
} else {
  const cfg = loadConfig()
  if (!cfg.arkiv.privateKey) throw new Error("the live drill needs ARKIV_PRIVATE_KEY in .env")
  env = cfg.env
  clients = makeClients(cfg.arkiv)
}
const writer = new SdkWriter(clients.walletClient!, clients.publicClient)
const swarm = new Swarm({ url: undefined, postageBatch: undefined, pin: true, deferred: true, timeoutMs: 1_000 })
const mirror = createSaveMirror({ savePath, logKey, env }, clients.publicClient, writer.address)
const store = new MemoryStateStore(emptyState(env, writer.address))
const publisher = new Publisher({ env, priceBatchMs: 300_000, profileFallbackDays: 7, maxOpsPerTx: 12, txTimeoutMs: 180_000 }, writer, swarm, store, Date.now, mirror, new TownProjector(savePath))
await publisher.init()
for (let i = 0; i < 500; i++) {
  const r = await publisher.flush()
  if (publisher.stats.lastArkivError) throw new Error(`Arkiv write failed: ${publisher.stats.lastArkivError}`)
  if (r.sent === 0 && !r.more) break
}
const townId = mirror?.townId
if (!townId) throw new Error("the save has no setup line")

if (node && flag("--break")) {
  const [batch] = node.ofSchema("dhaniverse.log.v1")
  batch!.attributes.get("hash")!.value = "f".repeat(64)
}

const tip = await arkivTip(clients.publicClient, writer.address, env, townId)
const api = makeReadApi({
  reader: makeReader(clients.publicClient, writer.address, env),
  swarm,
  cacheMs: 0,
  queryTimeoutMs: 60_000,
  corsOrigins: [],
  uploadsPerHour: 0,
  uploadsPerDay: 0,
  queryInfo: () => null,
  health: () => ({ ok: true }),
  restoreToken: token,
  restore: (town, from) => restoreLines(clients.publicClient, writer.address, env, logKey, town, from),
  restoreTip: (town) => arkivTip(clients.publicClient, writer.address, env, town),
  explorer: clients.chain.blockExplorers?.default.url ?? null,
})
api.listen(0, "127.0.0.1", () => {
  const port = (api.address() as { port: number }).port
  process.stdout.write(`READY ${port} ${townId} ${tip}\n`)
  log.info("drill: the save is on Arkiv", { env, writer: writer.address, townId, tip, txs: publisher.stats.txs, written: publisher.stats.entitiesWritten, lastTx: publisher.stats.lastTx?.hash })
})
process.stdin.resume()
process.stdin.on("end", () => process.exit(0))
process.stdin.on("close", () => process.exit(0))
