# The Town Pass: World ID flow, end to end

How a Tallyport player proves they are one real person with World ID 4.0 (IDKit 4), and what the server does with it.
I checked this against World's current docs (links at the end) and against the code. Endpoint and field names here
are the real ones.

## Who is who

| Thing | Value | Where it's set |
|---|---|---|
| App id | `app_eca8340a4f71973c608bbaa31a7af47e` (default) | `WORLD_APP_ID` or `--world-app-id` |
| RP id | `rp_f24fbbc28154fb5c` (default) | `WORLD_RP_ID` or `--world-rp-id` (the tallyport binary only) |
| Action | `tallyport-town-pass` (default) | `WORLD_ACTION` |
| Environment | `production` (default) | `WORLD_ENVIRONMENT` (`production`, `staging` for the simulator, `sandbox`) |
| Legacy 3.0 proofs | off (default) | `WORLD_ALLOW_LEGACY_PROOFS=true` |
| RP signing key | secret, from the Developer Portal | `RP_SIGNING_KEY` (World ID is off without it) |

Rules about the ids: if `WORLD_APP_ID` is set and `WORLD_RP_ID` isn't, proofs are verified under the app id. World's
API still accepts an app id there. Otherwise the founder's RP id is used. Flags win over the environment. I checked
from outside that the founder's app and RP are registered and migrated to World ID 4.0: the verify API took both and
ran the proof check. An unknown RP id gets `app_not_migrated` instead.

Why legacy proofs are off: with `allow_legacy_proofs: true`, a person could prove once with a 3.0 credential and again
after upgrading to 4.0. The two nullifiers can't be linked, so one person could hold two players. World's own docs
say to track both kinds of nullifier when legacy proofs are on, and new apps start 4.0-only. Turning it on lets people
who haven't upgraded the World App in, at that cost.

## The flow

```
Game (Godot)                 Server (hub + http.rs)                    World
-----------                  ----------------------                    -----
hello / ClaimName  ───────▶  player created, Intent::EnsureWallet
                   ◀───────  you{wallet: null} ... later you{wallet: "0x…"}
command TownPass   ───────▶  town_pass_check: has wallet, not yet human
                   ◀───────  result{ok, url: <public>/verify?token=<48 hex>}   (link works once, 15 min)
open url / embed IDKit
GET /verify/session?token ─▶ signs a fresh RP context (nonce bound to
                   ◀───────  this wallet, 300 s, single use)
IDKit.request(...).preset(proofOfHuman({signal: wallet}))  ─────────────▶  World App proves
                   ◀────────────────────────────────────────────────────── result (nullifier, signal_hash, proof)
POST /verify {token, result} ▶ checks, then forwards result unchanged ──▶ POST /api/v4/verify/{rp_id}
                                                                  ◀──── success, nullifier, environment
                             ToCity::Verified → rules.verify_human
                   ◀───────  event HumanVerified; NameRegistered (ENS); held payouts paid
                   ◀───────  HTTP {ok, human_id, ens}
```

### 1. The player needs a wallet first

`ClaimName` creates the player and asks the chain for a wallet (`Intent::EnsureWallet`). The wallet comes back on a
later `you` (`you.wallet` changes from `null` to an address). Until then `TownPass` is refused with `NoWallet`. The
gangway gate should wait for `you.wallet` before it offers World ID. On the offline server the wallet arrives at once.

### 2. Ask for a link

WebSocket: `{"type":"command","ref":"<unique>","command":{"type":"TownPass"}}`

- OK: `{"type":"result","ref":…,"ok":true,"url":"https://<public-url>/verify?token=<48 hex>"}`. The link works once,
  for 15 minutes, and is held in memory only. After a restart the player just asks again.
- Refused: `AlreadyHuman`, `NoWallet`, or `TryAgain`.
- The token is the `token` query parameter of `url`. Nothing is logged: a link isn't game state.

### 3. Get the IDKit settings

`GET /verify/session?token=<token>` answers with:

```json
{ "player": "asha", "wallet": "0x…", "expires_at": 1762…, "verified": false, "human_id": null, "ens": null,
  "app_id": "app_eca8…", "action": "tallyport-town-pass", "environment": "production",
  "allow_legacy_proofs": false, "rehearsal": false,
  "rp_context": { "rp_id": "rp_f24f…", "nonce": "0x00…", "created_at": 1762…, "expires_at": 1762…,
                  "signature": "0x…(65 bytes)" } }
```

Every call signs a new RP context. The nonce is `hashToField(32 random bytes)`. The signature is EIP-191 over
`0x01 ‖ nonce ‖ created_at (u64 BE) ‖ expires_at (u64 BE) ‖ hashToField(action)`. That is World's algorithm, and a
unit test checks our output against World's published test vector. The nonce is remembered for this wallet, works
once, and expires with the context (300 s). Ask for a fresh context if `rp_context.expires_at` is less than about
45 s away, as `web/js/verify.js` does.

Errors: `404 token_unknown`, `410 token_used`, `410 token_expired`, `503 verifier_unavailable`.

### 4. Run IDKit

IDKit core 4.6.0 (the latest 4.x on npm) is the browser global `IDKit`:

```js
const request = await IDKit.request({
  app_id, action, rp_context, allow_legacy_proofs, environment,
  action_description: "Get your Tallyport Town Pass",
}).preset(IDKit.proofOfHuman({ signal: wallet }));   // signal = the player's wallet, exactly as the server gave it
// show request.connectorURI as a QR code / deep link, then poll:
const status = await request.pollOnce();               // waiting_for_connection | awaiting_confirmation | confirmed | failed
```

`proofOfHuman` is World's preset for 4.0 Proof of Human. With legacy proofs off, only 4.0 proofs come back.

### 5. Send the result

`POST /verify` with `{"token": "<token>", "result": <IDKit result, unchanged>}`.

Before it calls World, the server checks:

1. the result's `nonce` is one this server issued, unused, unexpired, for this player's wallet. The nonce is spent
   whatever happens next, so a result is tried once;
2. `protocol_version` is `4.0` (`3.0` only when legacy proofs are on);
3. `action` is present and equals our action. A session proof has no action, so it's refused;
4. the result's `environment`, if present, equals ours, as World's docs ask;
5. every response's `signal_hash` is `hashToField` of this wallet (address bytes, checksummed text or lowercase
   text), and every response has a `nullifier` (a uniqueness proof, not a session proof).

Then it forwards the result unchanged to `POST https://developer.world.org/api/v4/verify/{rp_id}`. It needs
`success: true`, the same `environment`, the same `action` if one is returned, and a nullifier that matches the one
sent. The nullifier, as 32-byte lowercase `0x` hex, becomes the player's human id.

### 6. One person, one player

The city thread runs `rules::State::verify_human`. It refuses `AlreadyHuman` (409, "you already have the Town Pass")
and `HumanTaken` (409: this nullifier already holds another player). Otherwise it records nullifier → player in the
replayed state (`chain.humans`), so the rule survives restarts. Then it emits `HumanVerified`, asks for
`RegisterName` (`<name>.tallyport.eth`) if the player has no name, finishes any Town Pass quest step, pays everything
held for the Town Pass (`retry_owed`), and checks the referral. The page gets
`{"ok": true, "human_id": "0x…", "ens": "<name>.tallyport.eth" | null}`. The game sees `HumanVerified` and later
`NameRegistered` on its WebSocket.

Replay protection, layer by layer: a single-use link token, a single-use nonce bound to the wallet and the action, an
RP signature that expires in 300 s, a signal bound to the wallet, and a persisted nullifier → player map.

## For the Godot gate

- **Web build** (`/play` on dhaniverse.com, iframe): load IDKit 4.6.0 with SRI, as `web/verify.html` does, and drive
  steps 3 to 5 through `JavaScriptBridge`, the same calls `web/js/verify.js` makes. The game server is another origin.
  `GET /verify/session` and the JSON answers carry `Access-Control-Allow-Origin: *`. The server doesn't answer CORS
  preflight (`OPTIONS`), so send the POST with `Content-Type: text/plain`. The body is still the JSON above, and the
  server parses the body whatever the content type, so the browser makes no preflight.
- **Desktop build**: IDKit is JavaScript, so open `url` in the system browser (`OS.shell_open`) as
  `world/town_pass_desk.gd` does today, and wait for `HumanVerified` on the WebSocket.
- Either way, wait for `you.wallet` after `ClaimName` before sending `TownPass`. Show `HumanVerified` as the stamp
  and `NameRegistered` as the name landing.
- A "sign in with World" that creates the account from the proof doesn't exist. The proof is bound to a wallet,
  so the account and wallet must exist first. A new device still can't recover an account (Code_Map 8.1).

## Rehearsal

On a server without `RP_SIGNING_KEY`, started with `--debug`, the page shows "Run rehearsal verify", which posts
`{"offline": true}`. The human id is `keccak256("offline:" + wallet)`, and the page and game say "rehearsal".

## Sources (read for this audit)

- IDKit integration: https://docs.world.org/world-id/idkit/integrate
- Verify API (`POST /api/v4/verify/{rp_id}`): https://docs.world.org/api-reference/developer-portal/verify
- RP signatures and test vectors: https://docs.world.org/world-id/idkit/signatures
- Presets and request config: https://docs.world.org/world-id/idkit/credentials
- 4.0 migration, legacy proofs and nullifiers: https://docs.world.org/world-id/4-0-migration
- IDKit core on npm (latest 4.6.0): https://www.npmjs.com/package/@worldcoin/idkit-core
