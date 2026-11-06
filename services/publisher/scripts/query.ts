// Runs Tallyport's Arkiv queries against the live network and prints what comes back.
//   npm run query -- <writer-address> [env]
// No key needed: reads are free. Uses ARKIV_ACCESS_KEY if set, else the (rate-limited) public RPC.

import { makeClients } from "../src/arkiv/client.ts"
import { bountyBoardQueryText, makeReader } from "../src/arkiv/queries.ts"
import { loadConfig } from "../src/config.ts"

const [owner, envArg] = process.argv.slice(2)
if (!owner || !/^0x[0-9a-fA-F]{40}$/.test(owner)) {
  console.error("usage: npm run query -- <writer-address> [env]")
  process.exit(2)
}
const cfg = loadConfig({ ...process.env, ARKIV_PRIVATE_KEY: "" })
const env = envArg ?? cfg.env
const { publicClient, chain } = makeClients(cfg.arkiv)
const reader = makeReader(publicClient, owner as `0x${string}`, env)
const nowSec = Math.floor(Date.now() / 1000)
const show = (label: string, v: unknown) =>
  console.log(`\n## ${label}\n${JSON.stringify(v, (_, x) => (typeof x === "bigint" ? x.toString() : x), 2)}`)

console.log(`chain ${chain.name} (${chain.id}), block ${await publicClient.getBlockNumber()}, owner ${owner}, env ${env}`)
console.log(`\nBounty Board query:\n  ${bountyBoardQueryText(publicClient, owner as `0x${string}`, env, nowSec)}`)
show("campaigns", await reader.campaigns(nowSec))
show("latest rush board", await reader.rushBoard(null))
show("price batches, last 24 h", await reader.prices(nowSec - 86_400, nowSec))
show("latest paper", await reader.paper(null))
show("seasons", await reader.seasons())
