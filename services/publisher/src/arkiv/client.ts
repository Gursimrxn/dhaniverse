// Builds the Arkiv clients from config. The transport is injectable so tests run the real SDK
// against a mocked JSON-RPC endpoint.

import { createPublicClient, createWalletClient, type PublicArkivClient, type WalletArkivClient } from "@arkiv-network/sdk"
import { localhost, rabdi } from "@arkiv-network/sdk/chains"
import { http, type Chain, type Hex, type Transport } from "viem"
import { privateKeyToAccount } from "viem/accounts"
import type { ArkivConfig } from "../config.ts"

export type ArkivClients = {
  chain: Chain
  publicClient: PublicArkivClient
  walletClient: WalletArkivClient | null
  /** The address whose entities are trusted on read (the writer). null: reads are not possible either. */
  trusted: Hex | null
  writer: Hex | null
}

export function makeChain(cfg: ArkivConfig): Chain {
  if (cfg.chain === "localhost") {
    return cfg.rpcUrl ? { ...localhost, rpcUrls: { default: { http: [cfg.rpcUrl] } } } : localhost
  }
  // rabdi() warns on the console when there is no access key; main.ts says so through the log instead.
  const original = console.warn
  console.warn = () => {}
  try {
    const chain = rabdi({ accessKey: cfg.accessKey })
    return cfg.rpcUrl ? { ...chain, rpcUrls: { default: { http: [cfg.rpcUrl] } } } : chain
  } finally {
    console.warn = original
  }
}

export function makeClients(cfg: ArkivConfig, transport?: Transport, pollingInterval?: number): ArkivClients {
  const chain = makeChain(cfg)
  const t = transport ?? http(undefined, { timeout: cfg.queryTimeoutMs, retryCount: 1 })
  const publicClient = createPublicClient({ chain, transport: t, ...(pollingInterval && { pollingInterval }) }) as PublicArkivClient
  let walletClient: WalletArkivClient | null = null
  let writer: Hex | null = null
  if (cfg.privateKey) {
    const account = privateKeyToAccount(cfg.privateKey)
    writer = account.address
    const wt = transport ?? http(undefined, { timeout: cfg.txTimeoutMs, retryCount: 1 })
    walletClient = createWalletClient({ chain, transport: wt, account, ...(pollingInterval && { pollingInterval }) }) as WalletArkivClient
  }
  return { chain, publicClient, walletClient, writer, trusted: cfg.writerAddress ?? writer }
}
