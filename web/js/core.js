// Shared helpers for the Tallyport pages: server endpoints, USDC formatting, small DOM helpers, theme toggle.
// No chain code here (see chain.js), so the verify page loads without viem.

/** Base URL of the game server. Same origin by default; a page may set <meta name="tallyport-api" content="https://…">. */
export const API = (document.querySelector('meta[name="tallyport-api"]')?.content || "").replace(/\/$/, "");

export class HttpError extends Error {
  constructor(status, body, message) {
    super(message || `HTTP ${status}`);
    this.status = status;
    this.body = body;
  }
}

/** Fetches JSON from the game server. Throws HttpError with the parsed body on non-2xx. */
export async function getJSON(path, { timeout = 10_000, signal } = {}) {
  return requestJSON(path, { method: "GET", timeout, signal });
}

export async function postJSON(path, body, { timeout = 30_000 } = {}) {
  return requestJSON(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    timeout,
  });
}

export async function requestJSON(path, { timeout = 10_000, signal, ...init } = {}) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(new DOMException("timeout", "TimeoutError")), timeout);
  if (signal) signal.addEventListener("abort", () => ctrl.abort(signal.reason), { once: true });
  try {
    const res = await fetch(API + path, { ...init, signal: ctrl.signal, headers: { Accept: "application/json", ...(init.headers || {}) } });
    const text = await res.text();
    let body = null;
    try { body = text ? JSON.parse(text) : null; } catch { body = { error: text.slice(0, 200) }; }
    if (!res.ok) throw new HttpError(res.status, body, body?.message || body?.error || `HTTP ${res.status}`);
    return body;
  } catch (e) {
    if (e?.name === "AbortError" || e?.name === "TimeoutError") throw new Error(`The server didn't answer ${path} in time.`);
    throw e;
  } finally {
    clearTimeout(timer);
  }
}

/** The public city view. Throws if the server is down. */
export const loadCity = () => getJSON("/city");
/** Contract addresses written by the deploy script: {chainId, contracts:{…}, usdc, uniswap, ens, startBlock, rpcUrl?}. */
export const loadDeployments = () => getJSON("/deployments.json");

// ---------------------------------------------------------------- USDC (6 decimals; base units are integers)

export const USDC_DECIMALS = 6;
const UNIT = 1_000_000n;

/** Coerces a base-unit amount (bigint, integer number, or decimal-integer string) to bigint, or null if absent/invalid. */
export function toBig(v) {
  if (v === null || v === undefined || v === "") return null;
  if (typeof v === "bigint") return v;
  if (typeof v === "number") return Number.isFinite(v) ? BigInt(Math.trunc(v)) : null;
  if (typeof v === "string" && /^-?\d+$/.test(v.trim())) return BigInt(v.trim());
  return null;
}

/**
 * Base units → "0.001 USDC". Keeps at least two decimals and at most six (exact, never rounded).
 * Missing values render as an em dash so a gap is never mistaken for zero.
 */
export function usdc(v, { unit = true, sign = false } = {}) {
  let b = toBig(v);
  if (b === null) return "—";
  const neg = b < 0n;
  if (neg) b = -b;
  const whole = b / UNIT;
  const frac6 = (b % UNIT).toString().padStart(6, "0");
  let frac = frac6.replace(/0+$/, "");
  if (frac.length < 2) frac = frac6.slice(0, 2);
  const s = `${neg ? "−" : sign && b > 0n ? "+" : ""}${whole.toLocaleString("en-US")}.${frac}`;
  return unit ? `${s} USDC` : s;
}

/** "1.5" → 1500000n. Returns null for empty input; throws a plain-English Error for bad input. */
export function parseUsdc(text) {
  const s = String(text ?? "").trim().replace(/,/g, "");
  if (s === "") return null;
  if (!/^\d*(\.\d*)?$/.test(s) || s === ".") throw new Error("Enter an amount like 0.50");
  const [w, f = ""] = s.split(".");
  if (f.length > USDC_DECIMALS) throw new Error("USDC has at most 6 decimal places");
  return BigInt(w || "0") * UNIT + BigInt((f + "000000").slice(0, 6));
}

/** Plain integer formatting ("12,400"). */
export function int(v) {
  const b = toBig(v);
  return b === null ? "—" : b.toLocaleString("en-US");
}

/** Basis points → "4%" / "12.5%". */
export function bps(v) {
  const n = Number(v);
  if (!Number.isFinite(n)) return "—";
  return `${(n / 100).toLocaleString("en-US", { maximumFractionDigits: 2 })}%`;
}

export function pct(part, whole) {
  const p = toBig(part), w = toBig(whole);
  if (p === null || w === null || w === 0n) return 0;
  return Math.max(0, Math.min(100, Number((p * 10_000n) / w) / 100));
}

// ---------------------------------------------------------------- time

/** Unix seconds (number|string|bigint) → local date-time string. */
export function when(sec) {
  const n = Number(sec);
  if (!Number.isFinite(n) || n <= 0) return "—";
  return new Date(n * 1000).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
}

export function ago(ms) {
  const s = Math.round((Date.now() - ms) / 1000);
  if (s < 5) return "just now";
  if (s < 60) return `${s} s ago`;
  if (s < 3600) return `${Math.round(s / 60)} min ago`;
  return `${Math.round(s / 3600)} h ago`;
}

export function untilText(sec) {
  const d = Number(sec) - Date.now() / 1000;
  if (!Number.isFinite(d)) return "—";
  if (d <= 0) return "ended";
  if (d < 3600) return `${Math.ceil(d / 60)} min left`;
  if (d < 86400 * 2) return `${Math.ceil(d / 3600)} h left`;
  return `${Math.ceil(d / 86400)} days left`;
}

// ---------------------------------------------------------------- DOM

export const $ = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

export function esc(s) {
  return String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

/** Sets textContent on every element matching [data-bind="key"] inside root. */
export function bind(root, key, text) {
  for (const el of root.querySelectorAll(`[data-bind="${key}"]`)) el.textContent = text;
}

export function shortAddr(a) {
  return typeof a === "string" && a.length > 12 ? `${a.slice(0, 6)}…${a.slice(-4)}` : a || "—";
}

/** Read and write a per-viewer convenience value. Storage may be unavailable; never rely on it. */
export const store = {
  get(key, fallback = null) {
    try { const v = localStorage.getItem(key); return v === null ? fallback : JSON.parse(v); } catch { return fallback; }
  },
  set(key, value) {
    try { localStorage.setItem(key, JSON.stringify(value)); } catch { /* storage blocked: fine */ }
  },
};

/** Theme toggle: cycles system → light → dark. */
export function initTheme() {
  const root = document.documentElement;
  const saved = store.get("tallyport.theme");
  if (saved === "light" || saved === "dark") root.dataset.theme = saved;
  const btn = document.getElementById("theme-btn");
  if (!btn) return;
  const label = () => {
    const t = root.dataset.theme || "system";
    btn.textContent = t === "dark" ? "☾" : t === "light" ? "☀" : "◐";
    btn.setAttribute("aria-label", `Colour theme: ${t}. Change theme`);
    btn.title = `Theme: ${t}`;
  };
  label();
  btn.addEventListener("click", () => {
    const t = root.dataset.theme;
    const next = !t ? "light" : t === "light" ? "dark" : null;
    if (next) root.dataset.theme = next; else delete root.dataset.theme;
    store.set("tallyport.theme", next);
    label();
  });
}

/** Human-readable message from anything thrown. */
export function errText(e) {
  if (!e) return "Something went wrong.";
  if (typeof e === "string") return e;
  return e.shortMessage || e.message || String(e);
}
