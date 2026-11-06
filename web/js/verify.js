// Town Pass: World ID verification for one player.
// 1. GET /verify/session?token=… → {wallet, app_id, action, rp_context, …} (the server signs a fresh RP context).
// 2. IDKit 4 request (proof of human, signal = the player's wallet) → QR / World App deep link → poll for the proof.
// 3. POST /verify {token, result} → the server checks it with World ID's verify API and links the human to the player.
import qrcode from "https://unpkg.com/qrcode-generator@2.0.4/dist/qrcode.mjs";
import { $, getJSON, postJSON, loadCity, HttpError, initTheme, errText } from "./core.js";

initTheme();

const ACTION_DEFAULT = "tallyport-town-pass";
const POLL_EVERY_MS = 1500;
const POLL_TIMEOUT_MS = 10 * 60 * 1000;

// The one-time token arrives in ?token=. Keep it for this tab only (so a reload still works) and take it out of the
// address bar, so it doesn't sit in history or screenshots.
const token = (() => {
  const fromUrl = new URLSearchParams(location.search).get("token");
  try {
    if (fromUrl) sessionStorage.setItem("tallyport.verify.token", fromUrl);
    return fromUrl || sessionStorage.getItem("tallyport.verify.token") || "";
  } catch {
    return fromUrl || "";
  }
})();
if (new URLSearchParams(location.search).has("token") && history.replaceState) history.replaceState(null, "", location.pathname);

let session = null;
let abort = null;

const STATES = ["loading", "error", "ready", "sending", "done", "failed"];
function show(state) {
  for (const s of STATES) $(`#state-${s}`).hidden = s !== state;
  if (state === "done" || state === "failed") $(`#state-${state}`).focus();
}

function fail(title, text) {
  stopPolling();
  $("#failed-title").textContent = title;
  $("#failed-text").textContent = text;
  show("failed");
}

/** World App / bridge error codes → plain words. */
const IDKIT_ERRORS = {
  user_rejected: "You declined the request in the World App.",
  verification_rejected: "You declined the request in the World App.",
  credential_unavailable: "This World ID doesn't have the credential needed. An Orb-verified World ID is required.",
  max_verifications_reached: "This World ID has already been used for a Tallyport Town Pass.",
  nullifier_replayed: "This World ID has already been used for a Tallyport Town Pass.",
  connection_failed: "The World App couldn't connect. Check your connection and try again.",
  invalid_rp_signature: "The pass link's signature wasn't accepted. Open the Town Pass in the game again.",
  rp_signature_expired: "The pass link timed out. Try again.",
  timestamp_too_old: "The pass link timed out. Try again.",
  world_id_4_not_available: "Update the World App and try again.",
  inclusion_proof_pending: "Your World ID was issued very recently and isn't ready yet. Try again in a few hours.",
  timeout: "The World App didn't answer in time.",
  cancelled: "Cancelled.",
};

const SERVER_ERRORS = {
  already_verified: "This World ID is already linked to another Tallyport player. One human, one player.",
  human_taken: "This World ID is already linked to another Tallyport player. One human, one player.",
  token_expired: "This pass link has expired. Open the Town Pass in the game again.",
  token_used: "This pass link was already used. Open the Town Pass in the game again.",
  invalid_proof: "World ID didn't accept the proof.",
  verification_failed: "World ID didn't accept the proof.",
};

function serverMessage(e) {
  const b = e instanceof HttpError ? e.body : null;
  const code = b?.error || b?.code;
  return SERVER_ERRORS[code] || b?.message || (typeof code === "string" ? code : null) || errText(e);
}

// ---------------------------------------------------------------- session

async function loadSession() {
  if (!token) {
    $("#error-title").textContent = "This page needs a pass link";
    $("#error-text").textContent = "Open it from the Town Pass in the game: it adds a one-time token to the address.";
    show("error");
    return;
  }
  try {
    session = await getJSON(`/verify/session?token=${encodeURIComponent(token)}`);
  } catch (e) {
    const gone = e instanceof HttpError && [400, 404, 410].includes(e.status);
    $("#error-title").textContent = gone ? "This pass link has expired" : "We couldn't reach the town";
    $("#error-text").textContent = gone ? serverMessage(e) : `The game server didn't answer (${errText(e)}).`;
    show("error");
    return;
  }

  if (session.verified) return done({ human_id: session.human_id, ens: session.ens, rehearsal: session.rehearsal, already: true });

  if (!session.app_id) {
    // The app id is public; the server may expose it on /city instead of per session.
    try { session.app_id = (await loadCity())?.world_app_id || null; } catch { /* stays null */ }
  }

  $("#player-name").textContent = session.player || "—";
  $("#player-wallet").textContent = session.wallet || "—";
  $("#player-wallet").title = session.wallet || "";
  $("#action-id").textContent = session.action || ACTION_DEFAULT;
  if (session.environment && session.environment !== "production") {
    const pill = $("#env-pill");
    pill.hidden = false;
    pill.className = "pill alert";
    pill.textContent = `World ID ${session.environment}`;
  }

  $("#rehearsal").hidden = !session.rehearsal;
  const canIdkit = Boolean(session.app_id && session.rp_context && session.wallet);
  $("#idkit-area").hidden = !canIdkit;
  if (!canIdkit && !session.rehearsal) {
    $("#error-title").textContent = "World ID isn't set up on this server";
    $("#error-text").textContent = "The server didn't send a World ID app and signature for this pass. Tell the town's operator.";
    show("error");
    return;
  }
  show("ready");
}

/** RP signatures live a few minutes; fetch a fresh one when it's near expiry. */
async function freshSession() {
  const exp = Number(session?.rp_context?.expires_at || 0);
  if (exp - Date.now() / 1000 > 45) return session;
  const next = await getJSON(`/verify/session?token=${encodeURIComponent(token)}`);
  session = { ...session, ...next, app_id: next.app_id || session.app_id };
  return session;
}

// ---------------------------------------------------------------- IDKit

async function waitForIdkit(ms = 8000) {
  const t0 = Date.now();
  while (!window.IDKit) {
    if (Date.now() - t0 > ms) throw new Error("The World ID library didn't load. Check your connection or ad blocker and reload.");
    await new Promise((r) => setTimeout(r, 100));
  }
  return window.IDKit;
}

function drawQr(text) {
  const qr = qrcode(0, "M");
  qr.addData(text);
  qr.make();
  const n = qr.getModuleCount();
  let d = "";
  for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) if (qr.isDark(r, c)) d += `M${c} ${r}h1v1h-1z`;
  const pad = 2;
  $("#qr").innerHTML =
    `<svg viewBox="${-pad} ${-pad} ${n + 2 * pad} ${n + 2 * pad}" xmlns="http://www.w3.org/2000/svg" shape-rendering="crispEdges" aria-hidden="true">` +
    `<rect x="${-pad}" y="${-pad}" width="${n + 2 * pad}" height="${n + 2 * pad}" fill="#fff"/><path d="${d}" fill="#000"/></svg>`;
}

function stopPolling() {
  if (abort) abort.abort();
  abort = null;
}

async function start() {
  const btn = $("#start-btn");
  btn.disabled = true;
  try {
    const IDKit = await waitForIdkit();
    const s = await freshSession();
    const rp = s.rp_context;
    const request = await IDKit.request({
      app_id: s.app_id,
      action: s.action || ACTION_DEFAULT,
      rp_context: {
        rp_id: rp.rp_id,
        nonce: rp.nonce,
        created_at: Number(rp.created_at),
        expires_at: Number(rp.expires_at),
        signature: rp.signature,
      },
      // The server decides (WORLD_ALLOW_LEGACY_PROOFS, off by default) and enforces the same on POST /verify.
      allow_legacy_proofs: s.allow_legacy_proofs ?? false,
      environment: s.environment || "production",
      action_description: "Get your Tallyport Town Pass",
    }).preset(IDKit.proofOfHuman({ signal: s.wallet }));

    drawQr(request.connectorURI);
    $("#open-app").href = request.connectorURI;
    // Staging requests are answered by World's simulator, which takes the link pasted in, not a phone's camera.
    $("#simulator").hidden = s.environment !== "staging";
    $("#idkit-area").hidden = true;
    $("#connect").hidden = false;
    if (matchMedia("(pointer: coarse)").matches) $("#open-app").focus();
    await poll(request);
  } catch (e) {
    const code = e?.message;
    fail("Couldn't start World ID", IDKIT_ERRORS[code] || errText(e));
  } finally {
    btn.disabled = false;
  }
}

async function poll(request) {
  abort = new AbortController();
  const { signal } = abort;
  const t0 = Date.now();
  let misses = 0;
  while (!signal.aborted) {
    if (Date.now() - t0 > POLL_TIMEOUT_MS) return fail("Timed out", IDKIT_ERRORS.timeout);
    let status;
    try {
      status = await request.pollOnce({ signal, timeout: 15_000 });
      misses = 0;
    } catch (e) {
      if (signal.aborted) return;
      if (++misses > 6) return fail("Lost the connection to World ID", errText(e));
      await sleep(POLL_EVERY_MS * 2, signal);
      continue;
    }
    if (status.type === "awaiting_confirmation") {
      $("#poll-title").textContent = "Confirm in the World App";
      $("#poll-text").textContent = "The World App is open. Approve the Town Pass request there.";
    } else if (status.type === "confirmed" && status.result) {
      stopPolling();
      return submit(status.result);
    } else if (status.type === "failed") {
      return fail("World ID said no", IDKIT_ERRORS[status.error] || `World ID error: ${status.error || "unknown"}.`);
    }
    await sleep(POLL_EVERY_MS, signal);
  }
}

function sleep(ms, signal) {
  return new Promise((resolve) => {
    const t = setTimeout(resolve, ms);
    signal?.addEventListener("abort", () => { clearTimeout(t); resolve(); }, { once: true });
  });
}

// ---------------------------------------------------------------- server

async function submit(result) {
  show("sending");
  try {
    const res = await postJSON("/verify", { token, result });
    if (res?.ok === false) throw new HttpError(400, res, res.message || res.error);
    done(res || {});
  } catch (e) {
    fail("Verification didn't go through", serverMessage(e));
  }
}

function done(res) {
  stopPolling();
  if (res.rehearsal) {
    $("#done-kicker").textContent = "Rehearsal pass";
    $("#done-title").textContent = "Rehearsal verified";
    $("#done-text").textContent = "Go back to Tallyport. This was a rehearsal on an offline server: no real World ID check, no real payouts.";
  } else if (res.already) {
    $("#done-title").textContent = "You're already verified";
    $("#done-text").textContent = "This player already has its Town Pass. Go back to Tallyport.";
  }
  if (res.ens) {
    $("#done-ens").hidden = false;
    $("#done-ens").textContent = `Your town name: ${res.ens}`;
  }
  show("done");
}

// ---------------------------------------------------------------- wiring

$("#start-btn").addEventListener("click", start);
$("#cancel-btn").addEventListener("click", () => {
  stopPolling();
  $("#connect").hidden = true;
  $("#idkit-area").hidden = false;
  $("#poll-title").textContent = "Waiting for the World App…";
});
$("#retry-btn").addEventListener("click", () => {
  $("#connect").hidden = true;
  $("#idkit-area").hidden = !(session?.app_id && session?.rp_context);
  show(session ? "ready" : "loading");
  if (!session) loadSession();
});
$("#rehearse-btn").addEventListener("click", () => submit({ offline: true }));
$("#copy-link-btn").addEventListener("click", async () => {
  const btn = $("#copy-link-btn");
  const link = $("#open-app").href;
  try {
    await navigator.clipboard.writeText(link);
    btn.textContent = "Copied: paste it in the simulator";
  } catch {
    window.prompt("Copy this link into the simulator:", link);   // no clipboard access (an http page on another host)
  }
});

loadSession();
