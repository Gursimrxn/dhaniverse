// Treasury dashboard: the technical plan's money-flow diagram as live boxes, from the town's public view (/city) and,
// when contracts are deployed, direct chain reads. Chain values win over the server's when both exist; each box says
// where its number came from. Refreshes every 10 s (pausable).
import { $, loadCity, loadDeployments, usdc, int, bps, pct, toBig, when, untilText, ago, esc, initTheme, errText, shortAddr } from "./core.js";
import {
  ABI_SOURCE, chainFrom, publicClientFor, addressOf, tryRead, tryReadAny, named, pick, explorerAddr,
} from "./chain.js";

initTheme();

const REFRESH_MS = 10_000;
const BUCKETS = [
  { key: "fixed", index: 0, title: "Fixed bucket", sub: "Rush pot, streak bonus, errands", funded: "food revenue (60%)" },
  { key: "surprise", index: 1, title: "Surprise bucket", sub: "Chests, golden coins, mystery quests, the draw", funded: "sponsor fees and yield" },
  { key: "safety", index: 2, title: "Safety bucket", sub: "Rescue meals only", funded: "food revenue (10%)" },
];
const SPLIT = [
  { key: "fixed", label: "House fixed", bps: 6000 },
  { key: "safety", label: "House safety", bps: 1000 },
  { key: "ops", label: "Operations", bps: 2000 },
  { key: "team", label: "Team", bps: 1000 },
];

const S = { dep: null, chain: null, pub: null, paused: false, timer: null, busy: false, lastOk: 0 };

// ---------------------------------------------------------------- data

/** {v, src}: the chain value when we have one, else the server's. */
const val = (chainV, cityV) =>
  chainV !== undefined && chainV !== null ? { v: chainV, src: "chain" } : cityV !== undefined && cityV !== null ? { v: cityV, src: "server" } : { v: undefined, src: null };
const big = (x) => (x?.v === undefined ? null : toBig(x.v));

async function chainReads() {
  if (!S.pub) return {};
  const A = (n) => addressOf(S.dep, n);
  const usdcAddr = A("USDC");
  const bal = (addr) => (addr ? tryRead(S.pub, usdcAddr, "USDC", "balanceOf", [addr]) : undefined);
  const escrow = A("CampaignEscrow"), float = A("FloatManager"), house = A("HousePool"), treasury = A("Treasury");
  const venue = A("MockYieldVault"), hook = A("FoodHook");

  const bucketReads = BUCKETS.map(async (b) => {
    const [balance, today] = await Promise.all([
      tryRead(S.pub, house, "HousePool", "bucketBalance", [b.index]),
      tryRead(S.pub, house, "HousePool", "todayBudget", [b.index]),
    ]);
    const t = today === undefined ? {} : named("HousePool", "todayBudget", today);
    return { balance, budget: pick(t, ["budget"]), spent: pick(t, ["spent"]), left: pick(t, ["left"]) };
  });

  const [liab, capsSum, pendingRefunds, floatTotal, floatLiquid, buffer, lossReserve, yieldEarned, invested, houseBal, treasuryBal, budgetBps, venueName, venueShares, band, buckets] =
    await Promise.all([
      tryRead(S.pub, escrow, "CampaignEscrow", "totalLiabilities"),
      tryRead(S.pub, escrow, "CampaignEscrow", "liveDailyCapSum"),
      tryRead(S.pub, escrow, "CampaignEscrow", "pendingRefunds"),
      tryReadAny(S.pub, float, "FloatManager", ["totalAssets", "totalFloat"]),
      bal(float),
      tryReadAny(S.pub, float, "FloatManager", ["buffer", "targetBuffer", "bufferTarget"]),
      tryReadAny(S.pub, float, "FloatManager", ["lossReserve"]),
      tryReadAny(S.pub, float, "FloatManager", ["totalYieldHarvested", "yieldHarvested", "totalHarvested", "harvested", "yieldEarned"]),
      tryReadAny(S.pub, float, "FloatManager", ["invested", "totalInvested"]),
      bal(house),
      bal(treasury),
      tryReadAny(S.pub, house, "HousePool", ["budgetBps", "BUDGET_BPS"]),
      tryRead(S.pub, venue, "MockYieldVault", "name"),
      tryRead(S.pub, venue, "MockYieldVault", "balanceOf", [float]),
      tryRead(S.pub, hook, "FoodHook", "priceBand"),
      Promise.all(bucketReads),
    ]);

  let venueAssets;
  if (venueShares !== undefined) venueAssets = await tryRead(S.pub, venue, "MockYieldVault", "convertToAssets", [venueShares]);
  const pb = band === undefined ? {} : named("FoodHook", "priceBand", band);
  const price = pick(pb, ["liveUsdcPerFood", "live"]);
  const settings = named("FoodHook", "settings", await tryRead(S.pub, hook, "FoodHook", "settings"));

  return {
    liab, capsSum, pendingRefunds, priceHigh: pick(pb, ["highUsdcPerFood"]), floatTotal, floatLiquid, buffer, lossReserve, yieldEarned, invested: invested ?? venueAssets, houseBal, treasuryBal,
    budgetBps, venueName, venueAddr: venue, price,
    floor: pick(settings, ["floorUsdcPerFood", "floorCentsPerFood", "floor"]), ceiling: pick(settings, ["ceilingUsdcPerFood", "ceilingCentsPerFood", "ceiling"]),
    buckets,
  };
}

function model(city, c) {
  const H = city?.house || {};
  const T = city?.treasury || {};
  const F = city?.float || {};
  const bucketCity = (k) => H[k] || H.buckets?.[k] || {};
  const bounty = Array.isArray(city?.bounty) ? city.bounty : [];
  const buckets = BUCKETS.map((b, i) => {
    const bc = bucketCity(b.key);
    const ch = c.buckets?.[i] || {};
    return {
      ...b,
      balance: val(ch.balance, pick(bc, ["balance"])),
      budget: val(ch.budget, pick(bc, ["budget", "budget_today", "daily_budget"])),
      spent: val(ch.spent, pick(bc, ["spent", "spent_today", "paid_today"])),
    };
  });
  const bucketSum = buckets.every((b) => b.balance.v !== undefined) ? buckets.reduce((s, b) => s + big(b.balance), 0n) : null;
  const venues = Array.isArray(F.venues) ? F.venues : [];
  const venue0 = venues[0] || {};
  const venueName = c.venueName || venue0.name || null;
  const simulated = venue0.simulated === true || /^mock/i.test(venueName || "");
  const capsSum = c.capsSum ?? F.daily_caps_sum ?? F.daily_caps ?? (bounty.length && bounty.every((b) => b.daily_cap !== undefined) ? bounty.reduce((s, b) => s + (toBig(b.daily_cap) || 0n), 0n) : undefined);
  return {
    chainMode: city?.chain || null,
    liab: val(c.liab, F.liabilities ?? F.owed_to_sponsors),
    houseTotal: val(c.houseBal, bucketSum ?? H.total),
    budgetBps: val(c.budgetBps, H.budget_bps) ,
    buckets,
    rescue: H.rescue_meals || H.rescue || {},
    paidToday: H.paid_today,
    foodToday: T.revenue_today ?? city?.food?.usdc_today,
    mealsToday: city?.food?.meals_today ?? city?.meals?.today,
    mealsUsdcToday: city?.food?.usdc_today ?? city?.meals?.usdc_today,
    price: val(c.price, city?.food?.price),
    floor: val(c.floor, city?.food?.floor),
    ceiling: val(c.ceiling, city?.food?.ceiling),
    treasuryBal: val(c.treasuryBal, T.balance),
    split: T.split || T.split_totals || {},
    splitBps: T.split_bps || null,
    harvestToday: T.harvest_today ?? T.revenue_today,
    lastSplit: T.last_split_at,
    floatTotal: val(c.floatTotal, F.total),
    liquid: val(c.floatLiquid, F.liquid),
    invested: val(c.invested, F.invested),
    buffer: val(c.buffer, F.buffer),
    pendingRefunds: c.pendingRefunds ?? F.pending_refunds,
    capsSum,
    yieldEarned: val(c.yieldEarned, F.yield_earned),
    yieldToHouse: F.yield_to_house,
    lossReserve: val(c.lossReserve, F.loss_reserve),
    venueName: venueName ? (simulated && !/simulated/i.test(venueName) ? `${venueName} (simulated yield)` : venueName) : null,
    venueAddr: c.venueAddr || venue0.address || null,
    venueApr: venue0.apr_bps,
    simulated,
    venues,
    lastRebalance: F.last_rebalance_at,
    bounty,
    draw: city?.draw || {},
    fees: city?.campaigns?.fees_total ?? F.fees_total,
  };
}

// ---------------------------------------------------------------- render

const srcTag = (x) => (x?.src ? `<span class="src">${x.src === "chain" ? "on chain" : "town server"}</span>` : "");
const money = (x) => `<span class="money">${usdc(x?.v ?? x)}</span>`;

function node({ title, sub, body = "", cls = "" }) {
  return `<div class="node ${cls}"><span class="node-title">${title}</span>${sub ? `<span class="node-sub">${sub}</span>` : ""}${body}</div>`;
}
const line = (label, value, tag = "") => `<div class="spread small" style="gap:6px"><span class="muted">${label}</span><span>${value}</span></div>${tag}`;

function renderLanes(m) {
  const live = m.bounty.length;
  const laneA = [
    node({ title: "Sponsors", sub: "fund campaigns in USDC", body: line("Live campaigns", `<span class="num">${int(live)}</span>`) }),
    node({ title: "Campaign escrow", sub: "caps, refunds, 10% fee at deposit", cls: "key", body: `${money(m.liab)}<span class="node-sub">owed to sponsors (unspent budgets)</span>${srcTag(m.liab)}${m.fees !== undefined ? line("Fees taken", money(m.fees)) : ""}` }),
    node({ title: "FloatManager", sub: "custody and cash buffer", body: `${line("Liquid", money(m.liquid))}${line("Buffer target", money(m.buffer))}${srcTag(m.liquid)}` }),
    node({ title: esc(m.venueName || "Yield venue"), sub: m.simulated ? "simulated yield, demo only, no lock-in" : "ERC-4626, instant withdraw", body: `${line("Invested", money(m.invested))}${m.venueApr !== undefined ? line("Stated APR", bps(m.venueApr)) : ""}${srcTag(m.invested)}` }),
    node({ title: "House surprise bucket", sub: "80% of yield; 20% to the loss reserve", body: `${line("Yield earned", money(m.yieldEarned))}${line("To the house", money(m.yieldToHouse))}${srcTag(m.yieldEarned)}` }),
  ];
  const splitBox = SPLIT.map((s) => {
    const b = m.splitBps?.[s.key] ?? s.bps;
    return `<div><span class="pct">${bps(b)}</span><span class="tiny muted">${s.label}</span><span class="money small">${usdc(m.split[s.key])}</span></div>`;
  }).join("");
  const laneB = [
    node({ title: "Players", sub: "buy meals for energy", body: line("Meals today", `<span class="num">${int(m.mealsToday)}</span>`) }),
    node({ title: "MealCounter", sub: "FOOD bought and burned in one tx", body: line("USDC for meals today", money(m.mealsUsdcToday)) }),
    node({ title: "Uniswap v4 food pool", sub: "FOOD/USDC, floor and ceiling by hook", body: `${line("Price per FOOD", money(m.price))}${line("Floor · ceiling", `${usdc(m.floor.v, { unit: false })} · ${usdc(m.ceiling.v, { unit: false })}`)}${srcTag(m.price)}` }),
    node({ title: "Farm", sub: "our supplier key sells the harvest", body: line("Harvest sold today", money(m.harvestToday)) }),
    node({ title: "Treasury", sub: "splits food revenue", cls: "key", body: `${line("Waiting for split()", money(m.treasuryBal))}${srcTag(m.treasuryBal)}<div class="split" aria-label="Split totals so far">${splitBox}</div>` }),
  ];
  const bucketNodes = m.buckets.map((b) => {
    const used = pct(b.spent.v, b.budget.v);
    return node({
      title: b.title, sub: b.sub,
      body: `${money(b.balance)}${line("Today's budget", money(b.budget))}${line("Spent today", money(b.spent))}
        <div class="meter${used > 90 ? " alert" : ""}" role="progressbar" aria-label="${b.title} budget used today" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${Math.round(used)}"><span style="width:${used}%"></span></div>${srcTag(b.balance)}`,
    });
  }).join("");
  const rescueToday = pick(m.rescue, ["today", "count_today"]);
  const laneC = [
    `<div class="grid3" style="flex:1">${bucketNodes}</div>`,
    node({ title: "Players", sub: "rewards, rescue meals, the weekly draw", cls: "plate", body: `${line("Paid today", money(m.paidToday))}${line("Rescue meals today", `<span class="num">${int(rescueToday)}</span>`)}` }),
  ];
  const lane = (title, sub, items) => `
    <div class="lane"><div class="lane-title"><h3>${title}</h3><span class="small muted">${sub}</span></div>
      <ol class="flow">${items.map((x) => `<li>${x}</li>`).join("")}</ol></div>`;
  $("#lanes").innerHTML =
    lane("Sponsor money", "deposits, the fee, idle float earning yield", laneA) +
    lane("Food money", "players' meals become the house's fixed rewards", laneB) +
    lane("The house pays players", `each bucket spends at most ${bps(m.budgetBps.v ?? 400)} of its balance a day`, laneC);
}

function renderDetails(m) {
  $("#k-liab").textContent = usdc(m.liab.v);
  $("#k-liab-src").textContent = m.liab.src ? (m.liab.src === "chain" ? "CampaignEscrow.totalLiabilities()" : "town server") : "";
  $("#k-house").textContent = usdc(m.houseTotal.v);
  $("#k-house-src").textContent = m.houseTotal.src ? (m.houseTotal.src === "chain" ? "USDC held by HousePool" : "town server") : "";
  $("#k-food").textContent = usdc(m.foodToday);
  $("#k-yield").textContent = usdc(m.yieldEarned.v);
  $("#k-yield-src").textContent = m.venueName ? `from ${m.venueName}` : "";
  $("#h-bps").textContent = bps(m.budgetBps.v ?? 400);

  $("#buckets").innerHTML = m.buckets.map((b) => `
    <div class="node"><span class="node-title">${b.title}</span><span class="node-sub">Funded by ${b.funded}</span>
      <dl class="facts"><dt>Balance</dt><dd class="money">${usdc(b.balance.v)}</dd><dt>Today's budget</dt><dd class="money">${usdc(b.budget.v)}</dd><dt>Spent today</dt><dd class="money">${usdc(b.spent.v)}</dd><dt>Left today</dt><dd class="money">${b.budget.v !== undefined && b.spent.v !== undefined ? usdc(toBig(b.budget.v) - toBig(b.spent.v)) : "—"}</dd></dl></div>`).join("");
  const r = m.rescue;
  $("#rescue").innerHTML = `<dt>Rescue meals today</dt><dd class="num">${int(pick(r, ["today", "count_today"]))}</dd><dt>Rescue meals, all time</dt><dd class="num">${int(pick(r, ["total", "count"]))}</dd><dt>Paid for rescue meals</dt><dd class="money">${usdc(pick(r, ["usdc_total", "paid_total", "usdc"]))}</dd>`;

  // Buffer formula with live numbers
  const caps = toBig(m.capsSum);
  const pending = toBig(m.pendingRefunds) ?? 0n;
  const total = big(m.floatTotal);
  const liquid = big(m.liquid);
  const computed = caps !== null ? (caps * 45n) / 10n + pending : null;
  const buffer = big(m.buffer) ?? computed;
  const invest = total !== null && buffer !== null ? [(total * 80n) / 100n, total - buffer].reduce((a, b) => (a < b ? a : b)) : null;
  const L = (s) => s.padEnd(9);
  $("#buffer-formula").textContent = [
    `${L("buffer")}= 1.5 × 3 days × Σ live daily caps (${usdc(caps)}) + pending refunds (${usdc(pending)})`,
    `${L("")}= ${usdc(computed)}${big(m.buffer) !== null && computed !== null && big(m.buffer) !== computed ? `   (FloatManager's target: ${usdc(m.buffer.v)})` : ""}`,
    `${L("invest")}= min(80% × float, float − buffer) = ${usdc(invest && invest > 0n ? invest : invest === null ? null : 0n)}`,
    `${L("liquid")}= ${usdc(liquid)}: rebalance withdraws below ${usdc(buffer === null ? null : buffer / 2n)}, deposits above ${usdc(buffer === null ? null : (buffer * 3n) / 2n)}`,
  ].join("\n");
  const reserveTarget = big(m.invested) !== null ? (big(m.invested) * 2n) / 100n : null;
  $("#float-facts").innerHTML = `
    <dt>Float (all sponsor USDC)</dt><dd class="money">${usdc(m.floatTotal.v)}</dd>
    <dt>Liquid in FloatManager</dt><dd class="money">${usdc(m.liquid.v)}</dd>
    <dt>Invested</dt><dd class="money">${usdc(m.invested.v)}</dd>
    <dt>Owed to sponsors</dt><dd class="money">${usdc(m.liab.v)}</dd>
    <dt>Yield earned</dt><dd class="money">${usdc(m.yieldEarned.v)}</dd>
    <dt>Loss reserve</dt><dd><span class="money">${usdc(m.lossReserve.v)}</span>${reserveTarget !== null ? ` <span class="tiny muted">of ${usdc(reserveTarget)} target (2% of invested)</span>` : ""}</dd>
    <dt>Last rebalance</dt><dd>${when(m.lastRebalance)}</dd>`;
  const venues = m.venues.length ? m.venues : m.venueName ? [{ name: m.venueName, address: m.venueAddr, simulated: m.simulated }] : [];
  $("#venues").innerHTML = venues.length
    ? venues.map((v) => {
        const sim = v.simulated || /^mock/i.test(v.name || "");
        const name = sim && !/simulated/i.test(v.name || "") ? `${v.name} (simulated yield)` : v.name;
        return `<div class="notice ${sim ? "alert" : "coin"}"><strong>${esc(name || "Venue")}</strong><span class="small">${sim ? "A demo ERC-4626 vault that accrues a stated rate from an admin-funded drip. Real venues (Aave v3, Morpho) don't support Circle's test USDC on Sepolia. The keeper and accounting are real." : "ERC-4626 venue with instant withdrawals."}${v.apr_bps !== undefined ? ` Stated APR ${bps(v.apr_bps)}.` : ""}${v.assets !== undefined ? ` Holds ${usdc(v.assets)}.` : ""}</span>${v.address ? `<span class="tiny">${addrLink(v.address)}</span>` : ""}</div>`;
      }).join("")
    : `<p class="small muted">No yield venue set yet: all float stays liquid.</p>`;

  const sp = m.split;
  $("#treasury-facts").innerHTML = `
    <dt>Food revenue today</dt><dd class="money">${usdc(m.foodToday)}</dd>
    <dt>Waiting for the next split</dt><dd class="money">${usdc(m.treasuryBal.v)}</dd>
    ${SPLIT.map((s) => `<dt>${s.label} (${bps(m.splitBps?.[s.key] ?? s.bps)}), so far</dt><dd class="money">${usdc(sp[s.key])}</dd>`).join("")}
    <dt>Last split</dt><dd>${when(m.lastSplit)}</dd>`;

  const d = m.draw;
  $("#draw-facts").innerHTML = `
    <dt>Week</dt><dd class="num">${d.week ?? "—"}</dd>
    <dt>Tickets in the draw</dt><dd class="num">${int(d.tickets ?? d.tickets_total)}</dd>
    <dt>Prize</dt><dd class="money">${usdc(d.prize)}</dd>
    ${d.reveal_at || d.draws_at ? `<dt>Draw</dt><dd>${when(d.reveal_at || d.draws_at)}</dd>` : ""}`;

  $("#camp-rows").innerHTML = m.bounty.length
    ? m.bounty.map((b) => `<tr>
        <td><b>${esc(b.title || `Campaign #${b.id}`)}</b><br><span class="tiny muted">#${esc(b.id)}${b.sponsor ? ` · ${esc(b.sponsor_name || shortAddr(b.sponsor))}` : ""}</span></td>
        <td>${esc(b.template || "—")}</td>
        <td class="n money">${usdc(b.payout)}</td>
        <td class="n">${int(b.energy)}</td>
        <td class="n">${int(b.slots_left)}</td>
        <td class="n money">${usdc(b.daily_cap)}</td>
        <td>${untilText(b.ends)}</td></tr>`).join("")
    : `<tr><td colspan="7" class="muted">No live campaigns right now.</td></tr>`;
}

function addrLink(a) {
  const u = explorerAddr(S.chain, a);
  return u ? `<a href="${u}" target="_blank" rel="noopener"><code>${shortAddr(a)}</code></a>` : `<code title="${esc(a)}">${shortAddr(a)}</code>`;
}

function renderAddrs() {
  if (!S.dep) { $("#addrs").innerHTML = `<span class="small muted">No deployments published by this server.</span>`; return; }
  const names = ["CampaignEscrow", "FloatManager", "MockYieldVault", "HousePool", "Treasury", "MealCounter", "Farm", "FoodHook", "FoodRouter", "QuestToken", "USDC"];
  $("#addrs").innerHTML = names.map((n) => [n, addressOf(S.dep, n)]).filter(([, a]) => a)
    .map(([n, a]) => `<div><span>${n === "MockYieldVault" ? "MockYieldVault (simulated yield)" : n}</span>${addrLink(a)}</div>`).join("") || `<span class="small muted">No addresses yet.</span>`;
  const spec = Object.entries(ABI_SOURCE).filter(([, s]) => s === "spec").map(([n]) => n);
  $("#abi-src").textContent = spec.length ? `Reading ${spec.join(", ")} with the spec's interface until their build output lands; some chain numbers fall back to the town server.` : "ABIs from contracts/out.";
}

// ---------------------------------------------------------------- loop

async function refresh() {
  if (S.busy) return;
  S.busy = true;
  try {
    const [cityR, chainR] = await Promise.allSettled([loadCity(), chainReads()]);
    const city = cityR.status === "fulfilled" ? cityR.value : null;
    const c = chainR.status === "fulfilled" ? chainR.value : {};
    if (!city && !S.pub) throw cityR.reason;
    const m = model(city, c);
    renderLanes(m);
    renderDetails(m);
    const pill = $("#net-pill");
    const mode = m.chainMode || (S.chain ? S.chain.name : null);
    pill.textContent = mode ? (mode === "offline" ? "offline (in-process ledger)" : mode) : "unknown";
    pill.className = `pill ${mode === "offline" ? "alert" : "coin"}`;
    const n = $("#page-notice");
    if (!city) { n.hidden = false; n.textContent = `The town server isn't answering (${errText(cityR.reason)}). Showing chain numbers only.`; }
    else if (m.chainMode === "offline") { n.hidden = false; n.textContent = "The town is running offline: these numbers come from its in-process ledger, not from a chain."; }
    else n.hidden = true;
    S.lastOk = Date.now();
  } catch (e) {
    const n = $("#page-notice");
    n.hidden = false;
    n.textContent = `Couldn't load the numbers: ${errText(e)}. Retrying every 10 s.`;
  } finally {
    S.busy = false;
    $("#updated").textContent = S.lastOk ? `Updated ${ago(S.lastOk)}` : "";
  }
}

function schedule() {
  clearInterval(S.timer);
  if (!S.paused) S.timer = setInterval(() => { if (!document.hidden) refresh(); }, REFRESH_MS);
}

async function boot() {
  try {
    S.dep = await loadDeployments();
    S.chain = chainFrom(S.dep);
    S.pub = publicClientFor(S.chain);
  } catch {
    S.dep = S.dep || null; // no contracts yet: run on /city alone
  }
  renderAddrs();
  await refresh();
  schedule();
  setInterval(() => { if (S.lastOk) $("#updated").textContent = `Updated ${ago(S.lastOk)}`; }, 5000);
  document.addEventListener("visibilitychange", () => { if (!document.hidden && !S.paused) refresh(); });
  $("#pause-btn").addEventListener("click", (e) => {
    S.paused = !S.paused;
    e.currentTarget.setAttribute("aria-pressed", String(S.paused));
    e.currentTarget.textContent = S.paused ? "Resume live updates" : "Pause live updates";
    schedule();
    if (!S.paused) refresh();
  });
}

boot();
