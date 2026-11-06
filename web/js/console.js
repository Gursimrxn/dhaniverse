// Sponsor console: connect a wallet, design a campaign under the escrow's rules, fund it, and manage it.
import { decodeEventLog } from "viem";
import {
  $, API, loadCity, loadDeployments, usdc, parseUsdc, int, bps, pct, when, ago, esc, store, initTheme, errText, shortAddr,
  HttpError,
} from "./core.js";
import {
  ABI, ABI_SOURCE, chainFrom, publicClientFor, connectWallet, ensureChain, addressOf, templateId, fnAbi, hasFn, eventAbi,
  named, pick, tryRead, tryReadAny, chainErrText, explorerTx, explorerAddr, isAddress, getAddress, zeroAddress,
} from "./chain.js";

initTheme();

const ZERO32 = `0x${"0".repeat(64)}`;
const DAY = 86_400;
const MAX_IMAGE = 1_000_000;

/** Templates the game knows (rules.toml quest templates). Defaults follow the technical plan's quest table. */
const TEMPLATES = {
  spice_run: {
    title: "Spice Run", tag: "Uniswap",
    what: "Players swap USDC for your token on Uniswap and deliver it to the Spice Merchant.",
    energy: 30, payout: "1.00", slots: 100, cap: 1,
    note: "Payout = the cargo money back (0.50) + the reward (0.50).",
  },
  paint_sign: {
    title: "Paint your shop sign", tag: "ENS",
    what: "Players set the description record on their own ENS name.",
    energy: 20, payout: "0.25", slots: 200, cap: 1,
  },
  town_pass: {
    title: "Town Pass", tag: "World ID",
    what: "Players verify with World ID: one human, one player.",
    energy: 0, payout: "0.15", slots: 300, cap: 1,
  },
  hold_line: {
    title: "Hold the line", tag: "Token",
    what: "Players hold your token for three days; the indexer checks balances at random.",
    energy: 20, payout: "0.50", slots: 100, cap: 1,
  },
};
const TEMPLATE_BY_HASH = Object.fromEntries(Object.keys(TEMPLATES).map((k) => [templateId(k).toLowerCase(), k]));

const S = {
  city: null, dep: null, chain: null, pub: null,
  wallet: null, account: null, provider: null,
  escrow: null, usdcAddr: null,
  balance: null, allowance: null,
  rules: { feeBps: 1000n, minPayout: 150_000n, energyPerFood: 10n, ceiling: null, source: "" },
  busy: false,
};

// ---------------------------------------------------------------- boot

async function boot() {
  renderTemplates();
  setDefaults("spice_run");
  wireForm();
  $("#abi-src").textContent = `Escrow ABI: ${ABI_SOURCE.CampaignEscrow === "spec" ? "spec fallback (contracts not built yet)" : ABI_SOURCE.CampaignEscrow}`;

  const [city, dep] = await Promise.allSettled([loadCity(), loadDeployments()]);
  S.city = city.status === "fulfilled" ? city.value : null;
  S.dep = dep.status === "fulfilled" ? dep.value : null;

  if (!S.dep) {
    notice(`This server doesn't publish contract addresses yet (/deployments.json: ${errText(dep.reason)}). Campaigns can't be created until the contracts are deployed.`);
    $("#net-pill").textContent = "no contracts";
    $("#net-pill").className = "pill bad";
    validate();
    return;
  }
  try {
    S.chain = chainFrom(S.dep);
  } catch (e) {
    notice(errText(e));
    validate();
    return;
  }
  S.pub = publicClientFor(S.chain);
  S.escrow = addressOf(S.dep, "CampaignEscrow");
  S.usdcAddr = addressOf(S.dep, "USDC");
  $("#net-pill").textContent = S.chain.name;
  $("#net-pill").className = "pill coin";
  const quest = addressOf(S.dep, "QuestToken");
  if (quest && !$("#f-token").value) $("#f-token").value = quest;

  const missing = [!S.escrow && "CampaignEscrow", !S.usdcAddr && "USDC"].filter(Boolean);
  if (missing.length) notice(`deployments.json has no ${missing.join(" or ")} address yet.`);
  else if (S.city?.chain === "offline") notice("The town is running offline right now, so it won't see new campaigns until it runs on the chain again. You can still fund one.");
  if (!window.ethereum) notice("No browser wallet found. Install MetaMask, Rabby or Coinbase Wallet to fund a campaign.", true);

  $("#connect-btn").disabled = !S.escrow || !S.usdcAddr;
  await loadRules();
  validate();
}

function notice(text, append = false) {
  const n = $("#page-notice");
  n.hidden = false;
  n.textContent = append && n.textContent ? `${n.textContent} ${text}` : text;
}

async function loadRules() {
  const r = S.rules;
  const big = (v) => (typeof v === "bigint" ? v : typeof v === "number" ? BigInt(v) : undefined);
  r.feeBps = big(await tryReadAny(S.pub, S.escrow, "CampaignEscrow", ["feeBps", "FEE_BPS", "platformFeeBps", "PLATFORM_FEE_BPS"])) ?? 1000n;
  r.minPayout = big(await tryReadAny(S.pub, S.escrow, "CampaignEscrow", ["minPayout", "MIN_PAYOUT"])) ?? 150_000n;
  r.energyPerFood = big(await tryReadAny(S.pub, S.escrow, "CampaignEscrow", ["ENERGY_PER_FOOD", "energyPerFood"])) ?? 10n;

  const hook = addressOf(S.dep, "FoodHook");
  let ceiling = big(await tryRead(S.pub, hook, "FoodHook", "ceilingUsdcPerFood"));
  if (ceiling === undefined) {
    const settings = named("FoodHook", "settings", await tryRead(S.pub, hook, "FoodHook", "settings"));
    ceiling = big(pick(settings, ["ceilingUsdcPerFood", "ceilingCentsPerFood", "ceiling"]));
  }
  if (ceiling !== undefined) {
    r.ceiling = ceiling;
    r.source = `FoodHook ceiling read live: ${usdc(ceiling)} per FOOD, ${r.energyPerFood} energy per FOOD.`;
  } else {
    r.ceiling = null;
    r.source = "Couldn't read FoodHook's ceiling from the chain, so the 25% rule can't be checked here. The escrow still enforces it.";
  }
  $("#s-feepct").textContent = bps(r.feeBps);
  $("#ceiling-src").textContent = r.source;
}

// ---------------------------------------------------------------- form

function renderTemplates() {
  $("#templates").innerHTML = Object.entries(TEMPLATES).map(([k, t], i) => `
    <label class="tpl">
      <input type="radio" name="template" value="${k}" ${i === 0 ? "checked" : ""}>
      <span class="face">
        <span class="spread"><b>${esc(t.title)}</b><span class="pill">${esc(t.tag)}</span></span>
        <span class="small muted">${esc(t.what)}</span>
        <span class="tiny muted">Suggested: ${t.energy} energy · ${t.payout} USDC</span>
      </span>
    </label>`).join("");
}

const template = () => document.querySelector('input[name="template"]:checked')?.value || "spice_run";

function toLocalInput(sec) {
  const d = new Date(sec * 1000);
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}
const fromLocalInput = (v) => (v ? Math.floor(new Date(v).getTime() / 1000) : NaN);

function setDefaults(k) {
  const t = TEMPLATES[k];
  $("#f-energy").value = t.energy;
  $("#f-payout").value = t.payout;
  $("#f-slots").value = t.slots;
  $("#f-cap").value = t.cap;
  if (!$("#f-budget").value) $("#f-budget").value = "100";
  if (!$("#f-start").value) {
    const start = Math.ceil((Date.now() / 1000 + 600) / 300) * 300;
    $("#f-start").value = toLocalInput(start);
    $("#f-end").value = toLocalInput(start + 7 * DAY);
  }
  $("#spice-fields").hidden = k !== "spice_run";
  $("#h-payout").textContent = t.note || "Paid to the player when the server verifies the action.";
}

function wireForm() {
  $("#templates").addEventListener("change", () => { setDefaults(template()); validate(); });
  for (const id of ["f-budget", "f-payout", "f-energy", "f-slots", "f-cap", "f-start", "f-end", "f-token", "f-deliver", "f-title", "f-story", "f-sponsor", "f-kind", "f-image"]) {
    $(`#${id}`).addEventListener("input", validate);
    $(`#${id}`).addEventListener("change", validate);
  }
  $("#form").addEventListener("submit", (e) => { e.preventDefault(); create(); });
  $("#connect-btn").addEventListener("click", connect);
  $("#refresh-btn").addEventListener("click", () => refreshMine());
}

function setErr(id, msg) {
  const e = $(`#e-${id}`);
  const input = $(`#f-${id}`);
  if (e) { e.hidden = !msg; e.textContent = msg || ""; }
  if (input) {
    input.setAttribute("aria-invalid", msg ? "true" : "false");
    if (e) input.setAttribute("aria-errormessage", `e-${id}`);
  }
}

/** Reads the form, checks every rule, renders the summary. Returns the values when creatable, else null. */
function validate() {
  const r = S.rules;
  const errs = {};
  const checks = [];
  const k = template();
  const v = { template: k, kind: Number($("#f-kind").value) };

  const money = (id) => {
    try { return parseUsdc($(`#f-${id}`).value); } catch (e) { errs[id] = e.message; return null; }
  };
  const whole = (id, min, max) => {
    const raw = $(`#f-${id}`).value.trim();
    if (raw === "") { errs[id] = "Required"; return null; }
    if (!/^\d+$/.test(raw)) { errs[id] = "Whole numbers only"; return null; }
    const n = Number(raw);
    if (n < min || n > max) { errs[id] = `Between ${min.toLocaleString()} and ${max.toLocaleString()}`; return null; }
    return n;
  };

  v.budget = money("budget");
  v.payout = money("payout");
  if (v.budget === null && !errs.budget) errs.budget = "Required";
  if (v.payout === null && !errs.payout) errs.payout = "Required";
  v.energy = whole("energy", 0, 100);
  v.slots = whole("slots", 1, 4_294_967_295);
  v.cap = whole("cap", 1, 65_535);
  v.start = fromLocalInput($("#f-start").value);
  v.end = fromLocalInput($("#f-end").value);
  const now = Math.floor(Date.now() / 1000);
  if (!Number.isFinite(v.start)) errs.start = "Required";
  else if (v.start < now - 60) errs.start = "Pick a time from now on";
  if (!Number.isFinite(v.end)) errs.end = "Required";
  else if (Number.isFinite(v.start) && v.end <= v.start + 3600) errs.end = "Must end at least an hour after it starts";
  if (v.cap !== null && v.slots !== null && v.cap > v.slots) errs.cap = "Can't be more than the slots";

  if (k === "spice_run") {
    const tok = $("#f-token").value.trim();
    if (!tok) errs.token = "Required for the Spice Run";
    else if (!isAddress(tok)) errs.token = "Not a valid address";
    else v.questToken = getAddress(tok);
    const dl = $("#f-deliver").value.trim();
    if (dl && !isAddress(dl)) errs.deliver = "Not a valid address";
    else v.deliverTo = dl ? getAddress(dl) : S.account || null;
  } else {
    v.deliverTo = S.account || null;
  }

  const img = $("#f-image").files?.[0];
  if (img && img.size > MAX_IMAGE) errs.image = `That image is ${(img.size / 1e6).toFixed(1)} MB; the limit is 1 MB.`;
  else if (img && !/^image\/(png|jpeg|webp)$/.test(img.type)) errs.image = "PNG, JPEG or WebP only";
  setErr("image", errs.image);
  if (!$("#f-title").value.trim()) errs.title = "Give it a title";
  if (!$("#f-story").value.trim()) errs.story = "Write what the quest-giver says";

  // Money summary
  let fee = null, spend = null, covers = null, daily = null;
  if (v.budget !== null) {
    fee = (v.budget * r.feeBps) / 10_000n;
    spend = v.budget - fee;
  }
  if (spend !== null && v.payout && v.payout > 0n) covers = spend / v.payout;
  if (spend !== null && Number.isFinite(v.start) && Number.isFinite(v.end) && v.end > v.start) {
    const days = BigInt(Math.max(1, Math.ceil((v.end - v.start) / DAY)));
    daily = spend / days;
  }
  $("#s-budget").textContent = usdc(v.budget);
  $("#s-fee").textContent = usdc(fee);
  $("#s-spend").textContent = usdc(spend);
  $("#s-covers").textContent = covers === null ? "—" : `${int(covers)} completions`;
  $("#s-daily").textContent = daily === null ? "—" : `≈ ${usdc(daily)}`;

  // Rules
  if (v.payout !== null) {
    if (v.payout >= r.minPayout) checks.push(["ok", `Payout ${usdc(v.payout)} is at least the minimum ${usdc(r.minPayout)}.`]);
    else { checks.push(["no", `Payout must be at least ${usdc(r.minPayout)}.`]); errs.payout ||= `At least ${usdc(r.minPayout, { unit: false })}`; }
  }
  if (v.payout !== null && v.energy !== null) {
    if (r.ceiling !== null) {
      // Same arithmetic as CampaignEscrow._ceilingFoodCostX4: energy × 4 × ceiling ÷ ENERGY_PER_FOOD, rounded up.
      const ceilDiv = (a, b) => (a + b - 1n) / b;
      const food = ceilDiv(BigInt(v.energy) * r.ceiling, r.energyPerFood);
      const need = ceilDiv(BigInt(v.energy) * 4n * r.ceiling, r.energyPerFood);
      if (need <= v.payout) {
        checks.push(["ok", `25% rule: food for ${v.energy} energy costs at most ${usdc(food)} at the ceiling price; ×4 = ${usdc(need)} ≤ payout.`]);
      } else {
        checks.push(["no", `25% rule: food for ${v.energy} energy can cost ${usdc(food)}, so the payout must be at least ${usdc(need)}. Raise the payout or lower the energy.`]);
        errs.payout ||= `At least ${usdc(need, { unit: false })} for ${v.energy} energy`;
      }
    } else {
      checks.push(["warn", "25% rule can't be checked here (FoodHook ceiling unknown). The escrow checks it when you create."]);
    }
  }
  if (spend !== null && v.payout) {
    if (spend < v.payout) { checks.push(["no", "The spendable budget doesn't cover a single payout."]); errs.budget ||= "Too small for one payout"; }
    else if (v.slots !== null && covers !== null && BigInt(v.slots) > covers) checks.push(["warn", `The budget covers ${int(covers)} of the ${int(v.slots)} slots; the campaign stops when the money runs out.`]);
    else if (v.slots !== null) checks.push(["ok", `The budget covers all ${int(v.slots)} slots.`]);
  }
  if (S.account) {
    if (S.balance !== null && v.budget !== null) {
      if (S.balance >= v.budget) checks.push(["ok", `Your wallet holds ${usdc(S.balance)}.`]);
      else { checks.push(["no", `Your wallet holds ${usdc(S.balance)}; the budget is ${usdc(v.budget)}.`]); errs.budget ||= "More than your USDC balance"; }
    }
    if (S.allowance !== null && v.budget !== null) {
      checks.push(S.allowance >= v.budget ? ["ok", "USDC already approved for the escrow."] : ["warn", `You'll approve ${usdc(v.budget)} for the escrow first (one extra wallet prompt).`]);
    }
  } else {
    checks.push(["warn", "Connect your wallet to check your balance."]);
  }
  if (!S.escrow) checks.push(["no", "No CampaignEscrow address on this server."]);

  for (const id of ["budget", "payout", "energy", "slots", "cap", "start", "end", "token", "deliver"]) setErr(id, errs[id]);
  if ($("#f-title").value) $("#f-title").dataset.touched = "1";
  setErr("title", $("#f-title").dataset.touched ? errs.title : null);
  if ($("#f-story").value) $("#f-story").dataset.touched = "1";
  setErr("story", $("#f-story").dataset.touched ? errs.story : null);

  $("#checks").innerHTML = checks.map(([s, t]) => `<li class="${s}"><span class="mark" aria-hidden="true">${s === "ok" ? "✓" : s === "no" ? "✕" : "!"}</span><span><span class="sr-only">${s === "ok" ? "Passes: " : s === "no" ? "Fails: " : "Note: "}</span>${esc(t)}</span></li>`).join("");

  const blocking = Object.keys(errs);
  const ok = blocking.length === 0 && Boolean(S.account && S.escrow && S.usdcAddr) && !S.busy;
  $("#create-btn").disabled = !ok;
  $("#create-hint").textContent = !S.account ? "Connect your wallet first." : blocking.length ? "Fix the highlighted fields." : S.busy ? "Working…" : `You'll sign ${S.allowance !== null && v.budget !== null && S.allowance >= v.budget ? "one transaction" : "two transactions"}.`;
  return ok ? v : null;
}

// ---------------------------------------------------------------- wallet

async function connect() {
  const btn = $("#connect-btn");
  btn.disabled = true;
  try {
    const { wallet, account, provider } = await connectWallet(S.chain);
    S.wallet = wallet; S.account = account; S.provider = provider;
    $("#acct").innerHTML = linkAddr(account);
    btn.textContent = "Connected";
    if (!$("#f-deliver").value) $("#f-deliver").placeholder = `${shortAddr(account)} (your wallet)`;
    provider.on?.("accountsChanged", (a) => { if (a?.[0]) { S.account = getAddress(a[0]); $("#acct").innerHTML = linkAddr(S.account); refreshWallet(); refreshMine(); } else location.reload(); });
    provider.on?.("chainChanged", () => refreshWallet());
    await refreshWallet();
    await refreshMine();
    setInterval(() => { if (!S.busy) { refreshWallet(); refreshMine(true); } }, 20_000);
  } catch (e) {
    btn.disabled = false;
    notice(chainErrText(e));
  }
}

function linkAddr(a) {
  const u = explorerAddr(S.chain, a);
  return u ? `<a href="${u}" target="_blank" rel="noopener" title="${a}"><code>${shortAddr(a)}</code></a>` : `<code title="${a}">${shortAddr(a)}</code>`;
}

async function refreshWallet() {
  if (!S.account) return;
  const [bal, allow] = await Promise.all([
    tryRead(S.pub, S.usdcAddr, "USDC", "balanceOf", [S.account]),
    tryRead(S.pub, S.usdcAddr, "USDC", "allowance", [S.account, S.escrow]),
  ]);
  S.balance = bal ?? null;
  S.allowance = allow ?? null;
  $("#bal").textContent = usdc(S.balance);
  validate();
}

// ---------------------------------------------------------------- create

function steps(list) {
  $("#steps").innerHTML = list.map((s) => `<li data-s="${s.s}"><span class="mark" aria-hidden="true">${{ done: "✓", fail: "✕", doing: "…", todo: "○", skip: "–" }[s.s]}</span><span>${s.html}</span></li>`).join("");
}

function txLink(hash) {
  const u = explorerTx(S.chain, hash);
  return u ? ` <a href="${u}" target="_blank" rel="noopener">view tx</a>` : ` <code>${shortAddr(hash)}</code>`;
}

async function uploadBundle(v) {
  const img = $("#f-image").files?.[0];
  // The publisher keeps a whitelist of story fields (title, story, sponsor, template, cta, lines) and drops the rest;
  // questToken is sent for when it learns it (CampaignParams has no quest-token field).
  const story = {
    title: $("#f-title").value.trim(),
    story: $("#f-story").value.trim(),
    template: v.template,
    ...($("#f-sponsor").value.trim() ? { sponsor: $("#f-sponsor").value.trim() } : {}),
    ...(v.questToken ? { questToken: v.questToken } : {}),
  };
  const fd = new FormData();
  fd.append("story", JSON.stringify(story));
  if (img) fd.append("image", img, img.name);
  const res = await fetch(`${API}/swarm/campaign-bundle`, { method: "POST", body: fd });
  let body = null;
  try { body = await res.json(); } catch { /* not JSON */ }
  if (!res.ok) throw new HttpError(res.status, body, body?.message || body?.error || `Swarm upload failed (HTTP ${res.status})`);
  const ref = String(body?.metaHash || body?.reference || "").replace(/^0x/, "").toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(ref)) throw new Error("Swarm returned a reference that isn't 32 bytes, so it can't be the campaign's metaHash.");
  return `0x${ref}`;
}

/** Builds createCampaign's arguments from the ABI's own parameter names, so a reordered struct still encodes right. */
function createArgs(v, metaHash) {
  const f = fnAbi("CampaignEscrow", "createCampaign");
  if (!f) throw new Error("The escrow ABI has no createCampaign.");
  const known = {
    template: templateId(v.template), templateid: templateId(v.template),
    metahash: metaHash, meta: metaHash,
    budget: v.budget,
    payoutperclaim: v.payout, payout: v.payout,
    energycost: BigInt(v.energy), energy: BigInt(v.energy),
    maxclaims: BigInt(v.slots), slots: BigInt(v.slots),
    perhumancap: BigInt(v.cap),
    start: BigInt(v.start), end: BigInt(v.end),
    kind: BigInt(v.kind),
    deliverto: v.deliverTo || S.account,
    questtoken: v.questToken || zeroAddress, token: v.questToken || zeroAddress,
  };
  const val = (p) => {
    const key = (p.name || "").toLowerCase();
    if (!(key in known)) throw new Error(`createCampaign takes "${p.name}", which this console doesn't fill yet. Update web/js/console.js.`);
    return known[key];
  };
  if (f.inputs.length === 1 && f.inputs[0].type === "tuple") {
    return [Object.fromEntries(f.inputs[0].components.map((c) => [c.name, val(c)]))];
  }
  return f.inputs.map(val);
}

async function create() {
  const v = validate();
  if (!v || S.busy) return;
  S.busy = true;
  validate();
  const st = [
    { id: "upload", s: "todo", html: "Store the story on Swarm" },
    { id: "approve", s: "todo", html: `Approve ${usdc(v.budget)} for the escrow` },
    { id: "create", s: "todo", html: "Create the campaign" },
  ];
  const set = (id, s, html) => { const x = st.find((y) => y.id === id); x.s = s; if (html) x.html = html; steps(st); };
  steps(st);
  try {
    await ensureChain(S.wallet, S.chain);

    // 1. Story bundle on Swarm → metaHash
    let metaHash = ZERO32;
    set("upload", "doing", "Storing the story on Swarm…");
    try {
      metaHash = await uploadBundle(v);
      set("upload", "done", `Story stored on Swarm: <code>${metaHash.slice(0, 10)}…</code>`);
    } catch (e) {
      const go = window.confirm(`The story couldn't be stored on Swarm (${errText(e)}).\n\nCreate the campaign without a story? Players will see the template's default text and no title or image.`);
      if (!go) throw new Error("Stopped: the story wasn't stored.");
      set("upload", "skip", "No story bundle (Swarm unavailable): metaHash left empty");
    }

    // 2. USDC approval
    await refreshWallet();
    if (S.allowance !== null && S.allowance >= v.budget) {
      set("approve", "done", "USDC already approved");
    } else {
      set("approve", "doing", `Approve ${usdc(v.budget)} in your wallet…`);
      const hash = await S.wallet.writeContract({
        account: S.account, chain: S.chain, address: S.usdcAddr, abi: ABI.USDC, functionName: "approve", args: [S.escrow, v.budget],
      });
      set("approve", "doing", `Waiting for the approval…${txLink(hash)}`);
      const rc = await S.pub.waitForTransactionReceipt({ hash });
      if (rc.status !== "success") throw new Error("The approval transaction failed.");
      set("approve", "done", `Approved ${usdc(v.budget)}${txLink(hash)}`);
    }

    // 3. createCampaign (simulated first, so a broken rule shows its reason before the wallet prompt)
    set("create", "doing", "Checking with the escrow…");
    const args = createArgs(v, metaHash);
    const { request, result } = await S.pub.simulateContract({
      account: S.account, address: S.escrow, abi: ABI.CampaignEscrow, functionName: "createCampaign", args,
    });
    set("create", "doing", "Confirm the campaign in your wallet…");
    const hash = await S.wallet.writeContract({ ...request, chain: S.chain });
    set("create", "doing", `Waiting for the chain…${txLink(hash)}`);
    const rc = await S.pub.waitForTransactionReceipt({ hash });
    if (rc.status !== "success") throw new Error("The create transaction failed.");
    const id = idFromReceipt(rc) ?? (typeof result === "bigint" ? result : null);
    if (id !== null) rememberId(id);
    set("create", "done", `Campaign ${id !== null ? `#${id}` : ""} created${txLink(hash)}. It reaches the Bounty Board within a minute.`);
    await refreshWallet();
    await refreshMine();
  } catch (e) {
    const doing = st.find((x) => x.s === "doing");
    if (doing) set(doing.id, "fail", esc(chainErrText(e)));
    else steps([...st, { id: "err", s: "fail", html: esc(chainErrText(e)) }]);
  } finally {
    S.busy = false;
    validate();
  }
}

function idFromReceipt(rc) {
  const ev = eventAbi("CampaignEscrow", "CampaignCreated");
  if (!ev) return null;
  for (const log of rc.logs) {
    if (log.address.toLowerCase() !== S.escrow.toLowerCase()) continue;
    try {
      const d = decodeEventLog({ abi: [ev], data: log.data, topics: log.topics });
      const id = pick(d.args, ["id", "campaignId"]);
      if (typeof id === "bigint") return id;
    } catch { /* another event */ }
  }
  return null;
}

// ---------------------------------------------------------------- my campaigns

const idsKey = () => `tallyport.campaigns.${S.chain?.id}.${S.account?.toLowerCase()}`;
function rememberId(id) {
  const ids = new Set(store.get(idsKey(), []));
  ids.add(id.toString());
  store.set(idsKey(), [...ids]);
}

async function idsFromLogs() {
  const ev = eventAbi("CampaignEscrow", "CampaignCreated");
  if (!ev || !S.escrow) return [];
  const sponsorInput = ev.inputs.find((i) => /sponsor|creator|owner/i.test(i.name));
  try {
    const head = await S.pub.getBlockNumber();
    const from = BigInt(S.dep.startBlock ?? 0);
    const out = [];
    const STEP = 9_000n; // public RPCs cap eth_getLogs ranges at about 10,000 blocks
    for (let lo = from; lo <= head; lo += STEP + 1n) {
      const hi = lo + STEP > head ? head : lo + STEP;
      const logs = await S.pub.getLogs({
        address: S.escrow, event: ev, fromBlock: lo, toBlock: hi,
        args: sponsorInput?.indexed ? { [sponsorInput.name]: S.account } : undefined,
      });
      for (const l of logs) {
        if (sponsorInput && !sponsorInput.indexed && String(l.args[sponsorInput.name]).toLowerCase() !== S.account.toLowerCase()) continue;
        const id = pick(l.args, ["id", "campaignId"]);
        if (id !== undefined) out.push(id.toString());
      }
      if (out.length > 200) break;
    }
    return out;
  } catch {
    return [];
  }
}

/** Open (unrefunded) campaigns whose sponsor is the connected wallet. */
async function idsFromOpen() {
  const open = await tryRead(S.pub, S.escrow, "CampaignEscrow", "openCampaigns");
  if (!Array.isArray(open)) return [];
  const rows = await Promise.all(open.slice(0, 100).map(async (id) => {
    const c = named("CampaignEscrow", "campaign", await tryRead(S.pub, S.escrow, "CampaignEscrow", "campaign", [id]));
    return String(pick(c, ["sponsor"]) || "").toLowerCase() === S.account.toLowerCase() ? id.toString() : null;
  }));
  return rows.filter(Boolean);
}

/** Sum refunded to the sponsor for one campaign, from its Refunded event. */
async function refundedAmount(id) {
  const ev = eventAbi("CampaignEscrow", "Refunded");
  if (!ev) return undefined;
  try {
    const logs = await S.pub.getLogs({ address: S.escrow, event: ev, args: { campaignId: id }, fromBlock: BigInt(S.dep.startBlock ?? 0), toBlock: "latest" });
    return logs.reduce((sum, l) => sum + (l.args.amount ?? 0n), 0n);
  } catch {
    return undefined;
  }
}

let refreshing = false;
async function refreshMine(quiet = false) {
  if (!S.account || refreshing) return;
  refreshing = true;
  if (!quiet) $("#mine-updated").textContent = "Loading…";
  try {
    try { S.city = await loadCity(); } catch { /* keep the last one */ }
    const bounty = Array.isArray(S.city?.bounty) ? S.city.bounty : [];
    const mineFromCity = bounty.filter((b) => String(b.sponsor || "").toLowerCase() === S.account.toLowerCase()).map((b) => String(b.id));
    const ids = [...new Set([...store.get(idsKey(), []), ...mineFromCity, ...(await idsFromOpen()), ...(await idsFromLogs())])].sort((a, b) => Number(b) - Number(a));
    if (!ids.length) {
      $("#mine").innerHTML = `<p class="muted">No campaigns from ${shortAddr(S.account)} yet. Create one above.</p>`;
    } else {
      const rows = await Promise.all(ids.map((id) => campaignRow(id, bounty.find((b) => String(b.id) === id))));
      $("#mine").innerHTML = rows.join("");
      for (const b of document.querySelectorAll("#mine [data-act]")) b.addEventListener("click", () => act(b.dataset.act, BigInt(b.dataset.id), b));
    }
    $("#mine-updated").textContent = `Updated ${ago(Date.now())}`;
  } finally {
    refreshing = false;
  }
}

async function campaignRow(id, card) {
  const bid = BigInt(id);
  const [raw, rem, cap, capLeft] = await Promise.all([
    tryRead(S.pub, S.escrow, "CampaignEscrow", "campaign", [bid]),
    tryRead(S.pub, S.escrow, "CampaignEscrow", "remaining", [bid]),
    tryRead(S.pub, S.escrow, "CampaignEscrow", "dailyCap", [bid]),
    tryRead(S.pub, S.escrow, "CampaignEscrow", "dailyCapLeft", [bid]),
  ]);
  const c = raw === undefined ? {} : named("CampaignEscrow", "campaign", raw);
  const p = pick(c, ["params", "p"]) || c; // a nested params struct, or flat fields
  const get = (names, cardKey) => pick(c, names) ?? pick(p, names) ?? (cardKey ? card?.[cardKey] : undefined);

  const sponsor = get(["sponsor", "owner"], "sponsor");
  const templateHash = String(get(["template"]) ?? "").toLowerCase();
  const tKey = card?.template || TEMPLATE_BY_HASH[templateHash] || null;
  const title = card?.title || (tKey ? TEMPLATES[tKey]?.title : null) || `Campaign #${id}`;
  const budget = get(["budget"], "budget");
  const spendable = get(["net", "spendable"], "spendable") ?? (typeof budget === "bigint" ? budget - (budget * S.rules.feeBps) / 10_000n : undefined);
  const payout = get(["payoutPerClaim", "payout"], "payout");
  const maxClaims = get(["maxClaims", "slots"], "slots");
  const claims = get(["claims", "claimCount", "claimed"], "claims") ?? (maxClaims !== undefined && card?.slots_left !== undefined ? BigInt(maxClaims) - BigInt(card.slots_left) : undefined);
  const paid = get(["spent", "paid"], "paid"); // advances included
  const refundedFlag = get(["refunded"]);
  const refunded = typeof refundedFlag === "boolean" ? (refundedFlag ? await refundedAmount(bid) : 0n) : refundedFlag ?? card?.refunded;
  const advances = get(["advancesOut", "outstandingAdvances"], "advances_open");
  const remaining = rem ?? card?.remaining;
  const dailyCap = cap ?? card?.daily_cap;
  const start = Number(get(["start"], "starts") ?? 0);
  const end = Number(get(["end"], "ends") ?? 0);
  const cancelled = Boolean(get(["cancelled", "canceled"]) ?? card?.status === "cancelled");
  const paused = Boolean(get(["paused"]) ?? card?.status === "paused");
  const now = Date.now() / 1000;
  const status = refundedFlag === true ? ["Refunded", ""] : cancelled ? ["Cancelled", "bad"] : paused ? ["Paused by admin", "alert"] : end && now > end ? ["Ended", ""] : start && now < start ? ["Scheduled", "coin"] : ["Live", "good"];
  const ended = cancelled || (end && now > end);
  const isSponsor = !sponsor || String(sponsor).toLowerCase() === S.account.toLowerCase();
  const remBig = typeof remaining === "bigint" ? remaining : remaining !== undefined ? BigInt(remaining) : null;
  const canCancel = isSponsor && !cancelled && !(end && now > end) && hasFn("CampaignEscrow", "cancel");
  const canRefund = isSponsor && ended && remBig !== null && remBig > 0n && hasFn("CampaignEscrow", "refund");
  const humans = card?.humans;
  const cpa = typeof paid !== "undefined" && claims && BigInt(claims) > 0n ? BigInt(paid) / BigInt(claims) : null;
  const used = claims !== undefined && maxClaims !== undefined ? pct(claims, maxClaims) : null;
  const stat = (k, v, money = false) => `<div class="stat"><span class="k">${k}</span><span class="v${money ? " money" : ""}">${v}</span></div>`;

  return `<article class="card camp" aria-labelledby="c-${esc(id)}">
    <div class="camp-head">
      <div class="stack" style="gap:4px">
        <h3 id="c-${esc(id)}">${esc(title)}</h3>
        <span class="small muted">#${esc(id)}${tKey ? ` · ${esc(TEMPLATES[tKey]?.title || tKey)}` : ""} · ${when(start)} → ${when(end)}</span>
      </div>
      <span class="pill ${status[1]}"><span class="dot" aria-hidden="true"></span>${status[0]}</span>
    </div>
    ${used !== null ? `<div><div class="spread small"><span>Slots used</span><span class="num">${int(claims)} / ${int(maxClaims)}</span></div><div class="meter" role="progressbar" aria-label="Slots used" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${Math.round(used)}"><span style="width:${used}%"></span></div></div>` : ""}
    <div class="camp-stats">
      ${stat("Budget", usdc(budget), true)}
      ${stat("Spendable", usdc(spendable), true)}
      ${stat("Paid out (incl. advances)", usdc(paid), true)}
      ${stat("Remaining", usdc(remaining), true)}
      ${stat("Today's cap", `${usdc(dailyCap)}${capLeft !== undefined ? ` <span class="tiny muted">(${usdc(capLeft, { unit: false })} left)</span>` : ""}`, true)}
      ${stat("Refunded", usdc(refunded), true)}
      ${stat("Payout", usdc(payout), true)}
      ${stat("Cost per completion", cpa === null ? "—" : usdc(cpa), true)}
      ${stat("Humans reached", humans === undefined ? "—" : int(humans))}
      ${advances !== undefined ? stat("Open advances", usdc(advances), true) : ""}
    </div>
    ${raw === undefined && !card ? `<p class="tiny muted">No live data for this campaign yet (the escrow ABI may still be the spec fallback, or the town hasn't indexed it).</p>` : ""}
    ${canCancel || canRefund ? `<div class="row">
      ${canCancel ? `<button class="btn ghost small" type="button" data-act="cancel" data-id="${esc(id)}">Cancel campaign</button>` : ""}
      ${canRefund ? `<button class="btn coin small" type="button" data-act="refund" data-id="${esc(id)}">Refund ${usdc(remaining)}</button>` : ""}
    </div>` : ""}
    <p class="tiny muted" data-msg="${esc(id)}" aria-live="polite"></p>
  </article>`;
}

async function act(kind, id, btn) {
  const msg = document.querySelector(`[data-msg="${id}"]`);
  if (kind === "cancel" && !window.confirm(`Cancel campaign #${id}? No new quests start from now; you can refund the unspent budget straight away.`)) return;
  btn.disabled = true;
  S.busy = true;
  try {
    await ensureChain(S.wallet, S.chain);
    msg.textContent = "Checking with the escrow…";
    const { request } = await S.pub.simulateContract({ account: S.account, address: S.escrow, abi: ABI.CampaignEscrow, functionName: kind, args: [id] });
    msg.textContent = "Confirm in your wallet…";
    const hash = await S.wallet.writeContract({ ...request, chain: S.chain });
    msg.innerHTML = `Waiting for the chain…${txLink(hash)}`;
    const rc = await S.pub.waitForTransactionReceipt({ hash });
    if (rc.status !== "success") throw new Error("The transaction failed.");
    msg.innerHTML = `${kind === "cancel" ? "Cancelled" : "Refunded"}.${txLink(hash)}`;
    await refreshWallet();
    await refreshMine(true);
  } catch (e) {
    msg.textContent = chainErrText(e);
    btn.disabled = false;
  } finally {
    S.busy = false;
  }
}

boot().catch((e) => notice(`The console couldn't start: ${errText(e)}`));
