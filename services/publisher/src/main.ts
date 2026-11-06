// Entry point: read config, build the pieces, run the poll loop, the flush loop and the read API.

import { resolve } from "node:path"
import { makeClients } from "./arkiv/client.ts"
import { bountyBoardQueryText, makeReader } from "./arkiv/queries.ts"
import { SdkWriter } from "./arkiv/writer.ts"
import { fetchCity } from "./city.ts"
import { ConfigError, loadConfig } from "./config.ts"
import { log, setLevel, throttled } from "./log.ts"
import { Publisher } from "./publisher.ts"
import { makeReadApi } from "./readapi.ts"
import { createSaveMirror, restoreLines } from "./save.ts"
import { FileStateStore } from "./state.ts"
import { Swarm } from "./swarm.ts"

async function main(): Promise<void> {
  let cfg
  try {
    cfg = loadConfig()
  } catch (err) {
    if (err instanceof ConfigError) {
      log.error("configuration error", { error: err.message })
      process.exit(2)
    }
    throw err
  }
  setLevel(cfg.logLevel)

  const clients = makeClients(cfg.arkiv)
  const writer = clients.walletClient ? new SdkWriter(clients.walletClient, clients.publicClient) : null
  const reader = clients.trusted ? makeReader(clients.publicClient, clients.trusted, cfg.env) : null
  const swarm = new Swarm(cfg.bee)

  // Say once what will and won't happen.
  if (writer) log.info("Arkiv writes on", { chain: clients.chain.name, chainId: clients.chain.id, writer: writer.address, env: cfg.env })
  else log.warn("Arkiv writes off: ARKIV_PRIVATE_KEY is not set. Nothing will be written to Arkiv; no entity ids are invented.")
  if (!reader) log.warn("Arkiv reads off: no writer address to trust (set ARKIV_PRIVATE_KEY or ARKIV_WRITER_ADDRESS). The read API will answer 503.")
  if (cfg.arkiv.chain === "rabdi" && !cfg.arkiv.accessKey) {
    log.warn("ARKIV_ACCESS_KEY is empty: using Arkiv's public RPC, which is heavily rate limited (https://hub.arkiv.network/access-keys)")
  }
  if (swarm.configured) {
    log.info("Swarm uploads on", { bee: cfg.bee.url, pin: cfg.bee.pin, deferred: cfg.bee.deferred })
    swarm
      .stamp()
      .then((s) => log.info("postage batch", { ...s }))
      .catch((err) => log.warn("could not read the postage batch from Bee", { error: err }))
  } else {
    log.warn("Swarm uploads off: BEE_URL and BEE_POSTAGE_BATCH are not both set. Papers go to Arkiv inline, season snapshots and campaign bundles are skipped; no references are invented.")
  }

  const store = new FileStateStore(resolve(cfg.stateDir), cfg.env, writer?.address ?? null)
  const saveMirror = createSaveMirror(cfg, clients.publicClient, writer?.address ?? null)
  const publisher = new Publisher(
    {
      env: cfg.env,
      priceBatchMs: cfg.priceBatchMs,
      profileFallbackDays: cfg.profileFallbackDays,
      maxOpsPerTx: cfg.arkiv.maxOpsPerTx,
      txTimeoutMs: cfg.arkiv.txTimeoutMs,
    },
    writer,
    swarm,
    store,
    Date.now,
    saveMirror,
  )
  await publisher.init()

  const startedAt = Date.now()
  let lastCityError: string | null = null
  const server = makeReadApi({
    reader,
    swarm,
    cacheMs: cfg.readCacheMs,
    queryTimeoutMs: cfg.arkiv.queryTimeoutMs,
    corsOrigins: cfg.corsOrigins,
    restoreToken: cfg.restoreToken ?? null,
    restoreAllowRemote: cfg.restoreAllowRemote,
    restore:
      clients.trusted && cfg.logKey
        ? (town, from) => restoreLines(clients.publicClient, clients.trusted as `0x${string}`, cfg.env, cfg.logKey as Buffer, town, from)
        : null,
    uploadsPerHour: cfg.uploadsPerHour,
    uploadsPerDay: cfg.uploadsPerDay,
    queryInfo: () =>
      clients.trusted
        ? {
            query: bountyBoardQueryText(clients.publicClient, clients.trusted, cfg.env, Math.floor(Date.now() / 1000)),
            rpc: (clients.chain.rpcUrls.default.http[0] ?? "").replace(cfg.arkiv.accessKey ? encodeURIComponent(cfg.arkiv.accessKey) : "\u0000", "<your-access-key>"),
            chainId: clients.chain.id,
            owner: clients.trusted,
            env: cfg.env,
          }
        : null,
    health: () => ({
      ok: true,
      up_s: Math.round((Date.now() - startedAt) / 1000),
      env: cfg.env,
      server: { url: cfg.serverUrl, last_poll: publisher.stats.lastPollAt && new Date(publisher.stats.lastPollAt).toISOString(), last_error: lastCityError },
      arkiv: {
        writes: Boolean(writer),
        reads: Boolean(reader),
        chain_id: clients.chain.id,
        writer: writer?.address ?? null,
        trusted_owner: clients.trusted,
        txs: publisher.stats.txs,
        last_tx: publisher.stats.lastTx,
        last_error: publisher.stats.lastArkivError,
        waiting_records: publisher.pendingCount,
        written: publisher.stats.entitiesWritten,
      },
      save: saveMirror ? saveMirror.status() : { state: "off" },
      swarm: { uploads: swarm.configured, reads: swarm.readable, uploaded: publisher.stats.swarmUploads, last_error: publisher.stats.lastSwarmError },
    }),
  })
  server.listen(cfg.port, cfg.host, () => {
    const addr = server.address()
    log.info("read API listening", { address: typeof addr === "object" && addr ? `${addr.address}:${addr.port}` : String(addr) })
  })

  // Poll loop: reading the server never waits on Arkiv or Swarm.
  const cityWarn = throttled(5 * 60_000)
  let stopping = false
  const poll = async () => {
    try {
      const snap = await fetchCity(cfg.serverUrl, cfg.cityTimeoutMs)
      publisher.observe(snap)
      if (lastCityError) log.info("the game server is answering again")
      lastCityError = null
      await publisher.persist()
    } catch (err) {
      lastCityError = (err as Error).message
      cityWarn("city", () => log.warn("could not read the game server's /city; will keep trying", { url: cfg.serverUrl, error: err }))
    }
  }
  const pollTimer = setInterval(() => void poll(), cfg.pollIntervalMs)
  void poll()

  // Flush loop: one Arkiv transaction at a time; straight on again while there's a backlog.
  let flushTimer: NodeJS.Timeout | undefined
  const flushLoop = async () => {
    if (stopping) return
    let next = cfg.arkiv.flushIntervalMs
    try {
      const { more } = await publisher.flush()
      if (more) next = 2_000
    } catch (err) {
      log.error("flush crashed; continuing", { error: err })
    }
    if (!stopping) flushTimer = setTimeout(() => void flushLoop(), next)
  }
  if (writer) flushTimer = setTimeout(() => void flushLoop(), 3_000)

  const stop = async (signal: string) => {
    if (stopping) return
    stopping = true
    log.info("stopping", { signal })
    clearInterval(pollTimer)
    clearTimeout(flushTimer)
    server.close()
    await publisher.persist().catch(() => {})
    process.exit(0)
  }
  process.on("SIGINT", () => void stop("SIGINT"))
  process.on("SIGTERM", () => void stop("SIGTERM"))
  process.on("unhandledRejection", (err) => log.error("unhandled rejection (kept running)", { error: err }))
}

void main()
