// Prints the writer address for ARKIV_PRIVATE_KEY (never the key), for the README and the faucet.
import { privateKeyToAccount } from "viem/accounts"
import { loadConfig } from "../src/config.ts"

const cfg = loadConfig()
if (!cfg.arkiv.privateKey) {
  console.error("ARKIV_PRIVATE_KEY is not set")
  process.exit(2)
}
console.log(privateKeyToAccount(cfg.arkiv.privateKey).address)
