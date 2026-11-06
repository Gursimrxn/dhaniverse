#!/usr/bin/env node
// DEV ONLY. A stand-in for the game server's HTTP routes so the pages can be checked in a browser without the server.
// Serves web/ statically plus the fixture endpoints below. Never used in production: the game server serves web/ and
// answers these routes for real (see web/README.md).
//
//   node web/dev/serve.mjs                 # http://127.0.0.1:8099/dashboard
//   PORT=8100 DEV_DEPLOYMENTS=1 node web/dev/serve.mjs   # also serve dev/deployments.json (Sepolia, USDC only)
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const WEB = resolve(fileURLToPath(new URL("..", import.meta.url)));
const DEV = join(WEB, "dev");
const PORT = Number(process.env.PORT || 8099);
const TYPES = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8", ".json": "application/json", ".otf": "font/otf", ".svg": "image/svg+xml", ".png": "image/png",
};
const PAGES = { "/verify": "verify.html", "/console": "console.html", "/dashboard": "dashboard.html", "/": "dashboard.html" };

const json = (res, status, body) => {
  res.writeHead(status, { "Content-Type": "application/json", "Cache-Control": "no-store" });
  res.end(JSON.stringify(body));
};
const readBody = (req) => new Promise((ok) => { let b = ""; req.on("data", (c) => { b += c; if (b.length > 2e6) req.destroy(); }); req.on("end", () => ok(b)); });

async function city() {
  const c = JSON.parse(await readFile(join(DEV, "city.json"), "utf8"));
  // Make the live refresh visible: nudge today's numbers a little every request.
  const tick = Math.floor(Date.now() / 10_000) % 50;
  c.treasury.revenue_today = String(Number(c.treasury.revenue_today) + tick * 1200);
  c.food.meals_today += tick;
  c.house.fixed.spent = String(Number(c.house.fixed.spent) + tick * 300);
  return c;
}

createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const p = url.pathname;
  try {
    if (req.method === "GET" && p === "/city") return json(res, 200, await city());
    if (req.method === "GET" && p === "/deployments.json") {
      if (!process.env.DEV_DEPLOYMENTS) return json(res, 404, { error: "not_deployed", message: "no deployments for this network yet" });
      return json(res, 200, JSON.parse(await readFile(join(DEV, "deployments.json"), "utf8")));
    }
    if (req.method === "GET" && p === "/verify/session") {
      const token = url.searchParams.get("token");
      if (!token || token === "expired") return json(res, 410, { error: "token_expired", message: "This pass link has expired." });
      const now = Math.floor(Date.now() / 1000);
      return json(res, 200, {
        player: "Asha",
        wallet: "0x8ba1f109551bD432803012645Ac136ddd64DBA72",
        app_id: "app_staging_0000000000000000000000000000",
        action: "tallyport-town-pass",
        environment: "staging",
        allow_legacy_proofs: true,
        rp_context: {
          rp_id: "rp_0000000000000000",
          nonce: `0x00${"ab".repeat(31)}`,
          created_at: now,
          expires_at: now + 300,
          signature: `0x${"11".repeat(64)}1b`,
        },
        expires_at: now + 900,
        verified: token === "done",
        rehearsal: token === "rehearsal",
      });
    }
    if (req.method === "POST" && p === "/verify") {
      const body = JSON.parse((await readBody(req)) || "{}");
      if (body?.result?.offline) return json(res, 200, { ok: true, human_id: `0x${"7".repeat(64)}`, ens: "asha.tallyport.eth", rehearsal: true });
      return json(res, 400, { ok: false, error: "invalid_proof", message: "World ID didn't accept the proof (dev stub)." });
    }
    if (req.method === "POST" && p === "/swarm/campaign-bundle") {
      await readBody(req);
      return json(res, 503, { error: "swarm_not_configured", message: "Bee isn't configured on this publisher (dev stub)." });
    }
    if (req.method !== "GET" && req.method !== "HEAD") return json(res, 405, { error: "method" });

    const rel = PAGES[p] || normalize(decodeURIComponent(p)).replace(/^([/\\])+/, "");
    const file = resolve(WEB, rel);
    if (!file.startsWith(WEB + sep) || file.startsWith(DEV + sep)) return json(res, 404, { error: "not_found" });
    const data = await readFile(file);
    res.writeHead(200, { "Content-Type": TYPES[extname(file)] || "application/octet-stream", "Cache-Control": "no-store" });
    res.end(req.method === "HEAD" ? undefined : data);
  } catch (e) {
    if (e.code === "ENOENT" || e.code === "EISDIR") return json(res, 404, { error: "not_found" });
    json(res, 500, { error: String(e.message || e) });
  }
}).listen(PORT, "127.0.0.1", () => console.log(`DEV fixture server: http://127.0.0.1:${PORT}/dashboard  /console  /verify?token=demo`));
