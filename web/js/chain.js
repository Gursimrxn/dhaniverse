// Chain access for the console and dashboard: viem clients, an injected wallet on the configured chain, tolerant reads
// against ABIs that may still be the spec's fallback, and revert messages in plain words.
import {
  createPublicClient, createWalletClient, custom, http, defineChain, getAddress, isAddress, keccak256, toBytes,
  BaseError, ContractFunctionRevertedError, UserRejectedRequestError, zeroAddress,
} from "viem";
import { ABI, ABI_SOURCE } from "../abi/index.js";

// The two chains we run on, as viem 2.57 defines them (inlined: importing viem/chains pulls in hundreds of modules).
const sepolia = defineChain({
  id: 11155111,
  name: "Sepolia",
  nativeCurrency: { name: "Sepolia Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: ["https://11155111.rpc.thirdweb.com"] } },
  blockExplorers: { default: { name: "Etherscan", url: "https://sepolia.etherscan.io" } },
  contracts: { multicall3: { address: "0xca11bde05977b3631167028862be2a173976ca11", blockCreated: 751532 } },
  testnet: true,
});
const anvil = defineChain({
  id: 31337,
  name: "Anvil",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: ["http://127.0.0.1:8545"] } },
  testnet: true,
});

export { ABI, ABI_SOURCE, getAddress, isAddress, zeroAddress };

/** viem chain for the deployment. `rpcUrl` in deployments.json (a public read RPC, never a keyed one) overrides the default. */
export function chainFrom(dep) {
  const id = Number(dep?.chainId);
  const rpc = dep?.rpcUrl || dep?.rpc_url || dep?.rpc || null;
  let chain = id === sepolia.id ? sepolia : id === anvil.id ? anvil : null;
  if (!chain) {
    if (!id || !rpc) throw new Error(`Unknown chain ${id || "(none)"}: deployments.json needs chainId and rpcUrl.`);
    chain = defineChain({
      id, name: dep.network || `Chain ${id}`,
      nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
      rpcUrls: { default: { http: [rpc] } },
    });
  }
  if (rpc) chain = { ...chain, rpcUrls: { ...chain.rpcUrls, default: { http: [rpc] } } };
  return chain;
}

export function publicClientFor(chain) {
  return createPublicClient({ chain, transport: http(undefined, { timeout: 12_000, retryCount: 1 }) });
}

export function explorerTx(chain, hash) {
  const base = chain?.blockExplorers?.default?.url;
  return base ? `${base}/tx/${hash}` : null;
}
export function explorerAddr(chain, addr) {
  const base = chain?.blockExplorers?.default?.url;
  return base ? `${base}/address/${addr}` : null;
}

/** Address of a deployed contract by name; USDC also from the top-level `usdc` field. Null when absent or zero. */
export function addressOf(dep, name) {
  const c = dep?.contracts || {};
  const raw = name === "USDC" ? dep?.usdc || c.USDC || c.MockUSDC : c[name];
  return typeof raw === "string" && isAddress(raw) && raw.toLowerCase() !== zeroAddress ? getAddress(raw) : null;
}

/** keccak256 of the template name, e.g. templateId("spice_run"). Must match CampaignEscrow's template constants. */
export const templateId = (name) => keccak256(toBytes(name));

// ---------------------------------------------------------------- ABI helpers

export function fnAbi(contract, fn) {
  return (ABI[contract] || []).find((i) => i.type === "function" && i.name === fn) || null;
}
export const hasFn = (contract, fn) => Boolean(fnAbi(contract, fn));
export function eventAbi(contract, ev) {
  return (ABI[contract] || []).find((i) => i.type === "event" && i.name === ev) || null;
}

/** Turns a read result into {outputName: value}. Single struct outputs come back from viem as objects already. */
export function named(contract, fn, result) {
  const f = fnAbi(contract, fn);
  if (!f) return result;
  if (f.outputs.length === 1) {
    const o = f.outputs[0];
    if (o.type === "tuple" && result && typeof result === "object" && !Array.isArray(result)) return result;
    if (o.type === "tuple" && Array.isArray(result)) return Object.fromEntries(o.components.map((c, i) => [c.name || i, result[i]]));
    return { [o.name || "value"]: result };
  }
  if (Array.isArray(result)) return Object.fromEntries(f.outputs.map((o, i) => [o.name || String(i), result[i]]));
  return result;
}

/** First field present on obj among names (case-insensitive). */
export function pick(obj, names) {
  if (!obj || typeof obj !== "object") return undefined;
  const keys = Object.keys(obj);
  for (const n of names) {
    const k = keys.find((key) => key.toLowerCase() === n.toLowerCase());
    if (k !== undefined && obj[k] !== undefined) return obj[k];
  }
  return undefined;
}

/**
 * Reads a view if the ABI has it; resolves undefined (never throws) when the function or address is missing or the
 * call reverts, so a page shows "—" instead of breaking while contracts are still landing.
 */
export async function tryRead(client, address, contract, fn, args = []) {
  if (!client || !address || !hasFn(contract, fn)) return undefined;
  try {
    return await client.readContract({ address, abi: ABI[contract], functionName: fn, args });
  } catch {
    return undefined;
  }
}

/** First view among several candidate names that exists and answers. */
export async function tryReadAny(client, address, contract, fns, args = []) {
  for (const fn of fns) {
    if (!hasFn(contract, fn)) continue;
    const v = await tryRead(client, address, contract, fn, args);
    if (v !== undefined) return v;
  }
  return undefined;
}

// ---------------------------------------------------------------- wallet

/** EIP-6963 discovery, falling back to window.ethereum. */
function discoverProvider(waitMs = 400) {
  return new Promise((resolve) => {
    const found = [];
    const onAnnounce = (e) => found.push(e.detail);
    window.addEventListener("eip6963:announceProvider", onAnnounce);
    window.dispatchEvent(new Event("eip6963:requestProvider"));
    setTimeout(() => {
      window.removeEventListener("eip6963:announceProvider", onAnnounce);
      resolve(found[0]?.provider || window.ethereum || null);
    }, found.length ? 0 : waitMs);
  });
}

export async function connectWallet(chain) {
  const provider = await discoverProvider();
  if (!provider) throw new Error("No browser wallet found. Install MetaMask, Rabby or Coinbase Wallet and reload.");
  const wallet = createWalletClient({ chain, transport: custom(provider) });
  const [account] = await wallet.requestAddresses();
  if (!account) throw new Error("The wallet didn't share an account.");
  await ensureChain(wallet, chain);
  return { wallet, account: getAddress(account), provider };
}

export async function ensureChain(wallet, chain) {
  if ((await wallet.getChainId()) === chain.id) return;
  try {
    await wallet.switchChain({ id: chain.id });
  } catch (e) {
    const code = e?.code ?? e?.cause?.code;
    if (code === 4902 || /unrecognized chain|unknown chain|not added/i.test(e?.message || "")) {
      await wallet.addChain({ chain });
      await wallet.switchChain({ id: chain.id });
    } else {
      throw e;
    }
  }
}

// ---------------------------------------------------------------- errors

/** Contract custom errors (Contract__Reason) and wallet errors → one plain sentence. */
export function chainErrText(e) {
  if (e instanceof BaseError) {
    if (e.walk((x) => x instanceof UserRejectedRequestError) || /rejected|denied/i.test(e.shortMessage || "")) {
      return "You cancelled it in your wallet. Nothing was sent.";
    }
    const revert = e.walk((x) => x instanceof ContractFunctionRevertedError);
    if (revert instanceof ContractFunctionRevertedError) {
      const name = revert.data?.errorName;
      if (name) {
        const args = (revert.data.args || []).map((a) => (typeof a === "bigint" ? a.toString() : String(a))).join(", ");
        return `${ERROR_WORDS[name.split("__").pop()] || "The contract refused it"} (${name}${args ? `: ${args}` : ""}).`;
      }
      if (revert.reason) return `The contract refused it: ${revert.reason}.`;
    }
    return e.shortMessage || e.message;
  }
  return e?.message || String(e);
}

const ERROR_WORDS = {
  ERC20InsufficientBalance: "Your wallet doesn't hold enough USDC",
  ERC20InsufficientAllowance: "The USDC approval is too small",
  PayoutTooSmall: "The payout is below the minimum",
  BreaksQuarterRule: "The payout breaks the 25% rule (food for the quest's energy at the ceiling price × 4)",
  BadWindow: "The start and end times don't work",
  BudgetTooSmall: "The budget after the fee doesn't cover one payout",
  BadLimits: "Slots and the per-human cap must be at least 1",
  BadKind: "Unknown funding type",
  TooManyOpen: "Too many campaigns are open right now",
  ZeroAddress: "An address is missing (deliver-to?)",
  UnknownCampaign: "There's no such campaign",
  NotSponsor: "Only the campaign's sponsor can do that",
  NotEnded: "The campaign hasn't ended yet: cancel it first, or wait for the end",
  AlreadyRefunded: "It was already refunded",
  Closed: "The campaign is closed",
  DailyCapReached: "Today's payout cap is reached",
};
