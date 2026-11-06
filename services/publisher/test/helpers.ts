import type { ArkivConfig } from "../src/config.ts"
import type { Snapshot } from "../src/city.ts"

// A well-known throwaway key (anvil's account #0). Never holds anything on Arkiv.
export const TEST_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as const
export const TEST_ADDRESS = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" as const

export function arkivConfig(over: Partial<ArkivConfig> = {}): ArkivConfig {
  return {
    privateKey: TEST_KEY,
    accessKey: "test-access-key",
    rpcUrl: undefined,
    chain: "rabdi",
    writerAddress: undefined,
    flushIntervalMs: 1_000,
    maxOpsPerTx: 12,
    txTimeoutMs: 10_000,
    queryTimeoutMs: 5_000,
    ...over,
  }
}

export const NOW = Date.UTC(2026, 10, 6, 6, 0, 0)

export function snapshot(over: Partial<Snapshot> = {}): Snapshot {
  return {
    observedAt: NOW,
    day: 10,
    chain: "sepolia",
    season: { number: 1, endsDay: 168 },
    dayMs: 3_600_000,
    dayElapsedMs: 0,
    price: 4000,
    shock: null,
    paper: null,
    rush: null,
    people: [],
    bounty: null,
    problems: [],
    ...over,
  }
}

export const REF_A = "a".repeat(63) + "1"
export const REF_B = "b".repeat(63) + "2"
