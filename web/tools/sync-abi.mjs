#!/usr/bin/env node
// Regenerates web/abi/*.js from Foundry's build output (contracts/out). No dependencies.
//
//   node web/tools/sync-abi.mjs            # from the repo root, after `forge build`
//   node web/tools/sync-abi.mjs --check    # exit 1 if any module is out of date (for CI)
//
// For each contract the pages use it keeps only what they need: the listed functions (or every view/pure function plus
// the listed writes), and every event and custom error (so reverts decode into their names). When a contract hasn't
// been built yet it writes the spec's signatures (Tallyport_Build_Spec.md) as a human-readable fallback, marked as such,
// which the pages parse with viem's parseAbi. Re-run whenever the contracts change.
import { readFileSync, writeFileSync, existsSync, readdirSync, mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const WEB = resolve(here, "..");
const OUT = resolve(WEB, "..", "contracts", "out");
const ABI_DIR = join(WEB, "abi");

const ERC20 = ["name", "symbol", "decimals", "totalSupply", "balanceOf", "allowance", "approve"];
const ERC20_HUMAN = [
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address account) view returns (uint256)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 value) returns (bool)",
  "error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed)",
  "error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed)",
];

/**
 * name: the module name the pages import. artifacts: candidate paths under contracts/out (first that exists wins).
 * only: keep exactly these functions. writes: non-view functions to keep (all view/pure functions are kept).
 * human: the spec fallback.
 */
const CONTRACTS = [
  {
    name: "CampaignEscrow",
    artifacts: ["CampaignEscrow.sol/CampaignEscrow.json"],
    writes: ["createCampaign", "cancel", "refund"],
    spec: "§2.6",
    human: [
      "struct CampaignParams { bytes32 template; bytes32 metaHash; uint256 budget; uint256 payoutPerClaim; uint32 energyCost; uint32 maxClaims; uint16 perHumanCap; uint64 start; uint64 end; uint8 kind; address deliverTo; }",
      "function createCampaign(CampaignParams p) returns (uint256)",
      "function cancel(uint256 campaignId)",
      "function refund(uint256 campaignId)",
      "function campaign(uint256 campaignId) view returns ((address sponsor, CampaignParams params, uint256 net, uint256 spent, uint256 advancesOut, uint32 claims, bool paused, bool cancelled, bool refunded))",
      "function campaignCount() view returns (uint256)",
      "function openCampaigns() view returns (uint256[])",
      "function feeBps() view returns (uint256)",
      "function minPayout() view returns (uint256)",
      "function minPayoutFor(uint32 energyCost) view returns (uint256)",
      "function ENERGY_PER_FOOD() view returns (uint256)",
      "function dailyCapLeft(uint256 campaignId) view returns (uint256)",
      "function liveDailyCapSum() view returns (uint256)",
      "function pendingRefunds() view returns (uint256)",
      "function remaining(uint256 campaignId) view returns (uint256)",
      "function dailyCap(uint256 campaignId) view returns (uint256)",
      "function totalLiabilities() view returns (uint256)",
      "event CampaignCreated(uint256 indexed campaignId, address indexed sponsor, CampaignParams params, uint256 net, uint256 fee)",
      "event Claimed(uint256 indexed campaignId, address indexed player, bytes32 indexed humanId, uint256 amount, uint256 advanceRepaid, bytes32 ref)",
      "event Refunded(uint256 indexed campaignId, address indexed sponsor, uint256 amount, uint256 advancesUnpaid)",
      "event Cancelled(uint256 indexed campaignId)",
    ],
  },
  {
    name: "FloatManager",
    artifacts: ["FloatManager.sol/FloatManager.json"],
    writes: [],
    spec: "§2.7",
    human: [],
  },
  {
    name: "HousePool",
    artifacts: ["HousePool.sol/HousePool.json"],
    writes: [],
    spec: "§2.5",
    human: [
      "function budgetBps() view returns (uint256)",
      "function bucketBalance(uint8 bucket) view returns (uint256)",
      "function todayBudget(uint8 bucket) view returns (uint256 budget, uint256 spent, uint256 left)",
    ],
  },
  {
    name: "Treasury",
    artifacts: ["Treasury.sol/Treasury.json"],
    writes: [],
    spec: "§2.4",
    human: [],
  },
  {
    name: "MealCounter",
    artifacts: ["MealCounter.sol/MealCounter.json"],
    writes: [],
    spec: "§2.2",
    human: [],
  },
  {
    name: "MockYieldVault",
    artifacts: ["MockYieldVault.sol/MockYieldVault.json"],
    writes: [],
    spec: "§2.7 (ERC-4626)",
    human: [
      "function name() view returns (string)",
      "function asset() view returns (address)",
      "function totalAssets() view returns (uint256)",
    ],
  },
  {
    name: "FoodHook",
    artifacts: ["FoodHook.sol/FoodHook.json"],
    only: ["settings", "today", "band", "priceBand", "ceilingUsdcPerFood", "dayPrice", "dayTotals", "usdcPerFood", "centsPerFood"],
    spec: "§2.1",
    human: [
      "function settings() view returns (address usdc, address food, uint256 floorUsdcPerFood, uint256 ceilingUsdcPerFood, uint256 bandBps, uint256 dayLengthSeconds, uint256 firstDayStart, bytes32 poolId)",
      "function ceilingUsdcPerFood() view returns (uint256)",
      "function priceBand() view returns (uint256 lowUsdcPerFood, uint256 highUsdcPerFood, uint256 liveUsdcPerFood)",
      "function today() view returns (uint256)",
      "function dayTotals(uint256 day) view returns (uint256 openPrice, uint256 usdcTotal, uint256 foodTotal)",
    ],
  },
  {
    name: "QuestToken",
    artifacts: ["QuestToken.sol/QuestToken.json"],
    only: ERC20,
    spec: "§2.9 (ERC-20)",
    human: ERC20_HUMAN,
  },
  {
    name: "USDC",
    artifacts: ["MockUSDC.sol/MockUSDC.json", "ERC20.sol/ERC20.json"],
    only: ERC20,
    spec: "ERC-20",
    human: ERC20_HUMAN,
  },
];

function findArtifact(candidates) {
  for (const rel of candidates) {
    const p = join(OUT, rel);
    if (existsSync(p)) return { path: p, rel: `contracts/out/${rel}` };
  }
  // Fall back to any non-test, non-script build dir holding <Name>.json.
  if (!existsSync(OUT)) return null;
  const want = candidates[0].split("/").pop();
  for (const dir of readdirSync(OUT)) {
    if (/\.(t|s)\.sol$/.test(dir)) continue;
    const p = join(OUT, dir, want);
    if (existsSync(p)) return { path: p, rel: `contracts/out/${dir}/${want}` };
  }
  return null;
}

function select(abi, c) {
  return abi.filter((item) => {
    if (item.type === "event" || item.type === "error") return true;
    if (item.type !== "function") return false;
    if (c.only) return c.only.includes(item.name);
    return item.stateMutability === "view" || item.stateMutability === "pure" || (c.writes || []).includes(item.name);
  });
}

function moduleText(c) {
  const header = `// Generated by web/tools/sync-abi.mjs. Do not edit by hand: re-run \`node web/tools/sync-abi.mjs\` after \`forge build\`.\n`;
  const found = findArtifact(c.artifacts);
  if (found) {
    const artifact = JSON.parse(readFileSync(found.path, "utf8"));
    const abi = select(artifact.abi || [], c);
    return {
      from: found.rel,
      text: `${header}// Source: ${found.rel}\nexport const source = ${JSON.stringify(found.rel)};\nexport const abi = ${JSON.stringify(abi, null, 1)};\nexport const human = null;\n`,
    };
  }
  return {
    from: "spec fallback",
    text: `${header}// Source: spec fallback (Tallyport_Build_Spec.md ${c.spec}); contracts/out has no ${c.name} yet.\n` +
      `export const source = "spec";\nexport const abi = null;\nexport const human = ${JSON.stringify(c.human, null, 1)};\n`,
  };
}

function indexText() {
  const imports = CONTRACTS.map((c) => `import * as ${c.name} from "./${c.name}.js";`).join("\n");
  const names = CONTRACTS.map((c) => c.name).join(", ");
  return `// Generated by web/tools/sync-abi.mjs. Do not edit by hand.
// ABI[name] is a JSON ABI: from contracts/out when built, else parsed from the spec's human-readable fallback.
import { parseAbi } from "viem";
${imports}

const modules = { ${names} };

export const ABI = Object.fromEntries(
  Object.entries(modules).map(([name, m]) => [name, m.abi ?? (m.human?.length ? parseAbi(m.human) : [])]),
);
/** Where each ABI came from: a contracts/out path, or "spec" for the fallback. */
export const ABI_SOURCE = Object.fromEntries(Object.entries(modules).map(([name, m]) => [name, m.source]));
`;
}

const check = process.argv.includes("--check");
mkdirSync(ABI_DIR, { recursive: true });
let stale = 0;
const write = (file, text) => {
  const p = join(ABI_DIR, file);
  const old = existsSync(p) ? readFileSync(p, "utf8") : null;
  if (old === text) return false;
  if (check) { stale++; console.error(`stale: web/abi/${file}`); return true; }
  writeFileSync(p, text);
  return true;
};
for (const c of CONTRACTS) {
  const { from, text } = moduleText(c);
  const changed = write(`${c.name}.js`, text);
  console.log(`${c.name.padEnd(15)} ${from}${changed && !check ? "  (updated)" : ""}`);
}
write("index.js", indexText());
if (check && stale) process.exit(1);
