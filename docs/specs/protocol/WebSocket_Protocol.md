---
tags: [spec, protocol, websocket, real-time]
date: 2026-11-05
version: 2.1
aliases: [WebSocket Protocol, Real-time Protocol]
---

# WebSocket Protocol Specification

**Status 5 November 2026:** Proposed production transport and legacy reference.
The fresh runtime has no WebSocket listener or connected Godot economy.
Its local JSON-lines version is documented in runtime README.
Reconcile the production envelope, request identity, revisions and authentication
under OD13 before implementing this contract.

## Overview

This document defines the WebSocket protocol for real-time communication between the Dhaniverse backend (Rust/Actix-web) and the game client. WebSocket handles all real-time game events, state synchronization, and multiplayer interactions.

**Transport:** Dhaniverse's production design selects HTTPS/WSS and `WebSocketPeer`, shared by browser and desktop clients. This is a project decision, not a claim that WSS is Godot's only browser transport: Godot also documents HTTP and WebRTC, while low-level sockets are unavailable. [Godot web networking](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html#networking), [frontend transport design](../frontend/3D_Frontend_Production.md).

**WebSocket URL:** `wss://ws.dhaniverse.com/v1`
**Protocol Version:** 2.1 (major/minor in envelope, §Message Envelope)
**Message Format:** JSON
**Compression:** permessage-deflate when negotiated — browser clients may not negotiate it; every message shape must be valid uncompressed too (compression is an optimization, never a contract requirement).

---

## Connection Flow

### 1. Authentication

Client must authenticate immediately after connecting.

**Client → Server:**
```json
{
  "type": "auth",
  "token": "jwt_access_token",
  "client_version": "1.0.0",
  "protocol_version": 2
}
```

`protocol_version` is the contract major. The server rejects mismatched majors with `auth_error` code `UNSUPPORTED_PROTOCOL` — clients must not attempt to fall back to legacy field spellings (no ad hoc aliases; see [[../api/API_Contract.md|API Contract §Contract Versioning]]).

**Server → Client (Success):**
```json
{
  "type": "auth_success",
  "player_id": "uuid",
  "server_time": 1715085600000,
  "protocol_version": 2,
  "revision": 0
}
```

`server_time` is Unix milliseconds and the only time authority; the browser client maintains a presentation clock from it (backgrounded tabs cannot be trusted to keep time). `revision` seeds the session's monotonic write counter (§Message Envelope).


**Server → Client (Failure):**
```json
{
  "type": "auth_error",
  "error": "INVALID_TOKEN",
  "message": "Invalid or expired token"
}
```

**Connection closes on auth failure.**

---

### 2. Initial State Sync

After successful auth, server sends initial player state.

**Server → Client:**
```json
{
  "type": "state_sync",
  "data": {
    "player": {
      "player_id": "uuid",
      "username": "string",
      "energy_steps": 1000,
      "bonus_steps": 0,
      "health_basis_points": 10000,
      "stress_tenths": 10,
      "current_zone": "meadow",
      "position": { "x": 0.0, "y": 0.0, "z": 0.0 }
    },
    "wallet": {
      "balance_cents": 50000
    },
    "inventory": {
      "items": [
        {
          "id": "uuid",
          "item_id": "avocado_toast",
          "quantity": 2
        }
      ]
    },
    "nearby_players": [
      {
        "player_id": "uuid",
        "username": "string",
        "position": { "x": 10.0, "y": 0.0, "z": 20.0 },
        "yaw": 1.57
      }
    ]
  }
}
```

**Canonical field shapes.** Resources are fractional-safe integers per [Canonical Game Rules](../../design/11_Canonical_Game_Rules.md) (200 energy steps/bar + separate bonus pool, fractional food/health/stress effects): `energy_steps` (1/200 bar; full 5 bars = 1000), `bonus_steps` (temporary boosts, rules §3.4 cap 2 bars = 400 steps), `health_basis_points` (1/100 %; 100 % = 10000), `stress_tenths` (0.1 stress-band units; band 1 = 10). `energy_bars`/`health_percent` in UI are display roundings of these. Positions are **Y-up metres `{x, y, z}`** (Godot convention: x east, y height, z south) everywhere — client movement reports include `y` as an observation, but **height is server-authoritative**: the server validates against walkable surfaces and every ack/broadcast carries the corrected value. **Runtime drift (honesty):** the legacy Rust `packages/protocols` messages and `docker/migrations/001` still encode legacy integer-bars / 2D `position_x`/`position_y`; the shapes above are the contract to which code must be brought — design, not implemented, with no dual spelling on the wire (one cutover, API Contract §Contract Versioning).


---

### 3. Heartbeat

Both sides send periodic heartbeats to detect disconnections.

**Client → Server (every 30 seconds):**
```json
{
  "type": "heartbeat"
}
```

**Server → Client (every 30 seconds):**
```json
{
  "type": "heartbeat",
  "server_time": 1715085600000
}
```

**No heartbeat for 90 seconds → connection closed.**

---

## Message Types

### Client → Server Messages

#### Movement

```json
{
  "type": "movement",
  "position": { "x": 10.5, "y": 0.0, "z": 20.3 },
  "yaw": 0.78,
  "zone": "market"
}
```

`y` is an observation only; `yaw` (radians, avatar facing) exists so the 3D browser client can render remote avatars without extrapolating heading.

**Server Response:**
```json
{
  "type": "movement_ack",
  "position": { "x": 10.5, "y": 0.4, "z": 20.3 },
  "revision": 138,
  "server_time": 1715085600000
}
```

The ack's `y` is the server-corrected walkable-surface height; the client snaps toward it (interpolation rules: Multiplayer Architecture §Eventual Consistency).

---

#### Zone Enter/Exit

```json
{
  "type": "zone_enter",
  "zone": "market"
}
```

```json
{
  "type": "zone_exit",
  "zone": "market"
}
```

---

#### Consume Item

```json
{
  "type": "consume_item",
  "inventory_item_id": "uuid",
  "quantity": 1
}
```

**Server Response:**
```json
{
  "type": "consume_result",
  "success": true,
  "energy_steps_restored": 200,
  "health_basis_points_restored": 60,
  "stress_tenths_reduced": 0
}
```

---

#### Start Job Shift

```json
{
  "type": "job_start",
  "employer_id": "uuid",
  "job_type": "factory_worker"
}
```

**Server Response:**
```json
{
  "type": "job_start_result",
  "success": true,
  "shift_id": "uuid",
  "started_at": 1715085600000,
  "expected_end_at": 1715085800000,
  "wage_per_shift_cents": 8000
}
```

---

#### Complete Job Shift

```json
{
  "type": "job_complete",
  "shift_id": "uuid"
}
```

**Server Response:**
```json
{
  "type": "job_complete_result",
  "success": true,
  "base_wage_cents": 8000,
  "productivity_modifier": 1.0,
  "total_earned_cents": 8000
}
```

---

#### Chat Message

```json
{
  "type": "chat_send",
  "channel": "local",
  "message": "Hello!",
  "target_player_id": "uuid" // Optional, for DM
}
```

**Server Response:**
```json
{
  "type": "chat_ack",
  "message_id": "uuid",
  "channel": "local"
}
```

---

#### Trade Request

```json
{
  "type": "trade_request",
  "target_player_id": "uuid",
  "offer_items": [
    {
      "inventory_item_id": "uuid",
      "quantity": 2
    }
  ],
  "offer_coins": 1000,
  "request_items": [],
  "request_coins": 0
}
```

**Server Response:**
```json
{
  "type": "trade_request_result",
  "success": true,
  "trade_id": "uuid"
}
```

---

#### Trade Response (Accept/Decline)

```json
{
  "type": "trade_response",
  "trade_id": "uuid",
  "response": "accept" // or "decline"
}
```

**Server Response:**
```json
{
  "type": "trade_complete",
  "trade_id": "uuid",
  "status": "completed"
}
```

---

### Server → Client Messages

#### Player Movement (Broadcast)

Sent to all players in the same zone when a player moves.

```json
{
  "type": "player_moved",
  "player_id": "uuid",
  "username": "string",
  "position": { "x": 10.5, "y": 0.4, "z": 20.3 },
  "yaw": 0.78,
  "zone": "market"
}
```

---

#### Player Entered Zone (Broadcast)

```json
{
  "type": "player_entered_zone",
  "player_id": "uuid",
  "username": "string",
  "position": { "x": 10.0, "y": 0.0, "z": 20.0 },
  "yaw": 1.57,
  "zone": "market"
}
```

---

#### Player Exited Zone (Broadcast)

```json
{
  "type": "player_exited_zone",
  "player_id": "uuid",
  "username": "string",
  "zone": "market"
}
```

---

#### Chat Message (Broadcast)

```json
{
  "type": "chat_message",
  "message_id": "uuid",
  "channel": "local",
  "sender_id": "uuid",
  "sender_username": "string",
  "message": "Hello!",
  "timestamp": 1715085600000,
  "zone": "market"
}
```

---

#### State Update (Player-Specific)

Sent when player's state changes (energy, health, stress, wallet).

```json
{
  "type": "state_update",
  "updates": {
    "energy_steps": 800,
    "health_basis_points": 9500,
    "stress_tenths": 20,
    "wallet_balance_cents": 42000
  },
  "revision": 139
}
```

---

#### Inventory Update (Player-Specific)

```json
{
  "type": "inventory_update",
  "action": "added", // or "removed", "updated"
  "item": {
    "id": "uuid",
    "item_id": "avocado_toast",
    "quantity": 3
  }
}
```

---

#### Market Price Update (Broadcast)

Sent when market prices change (economy tick).

```json
{
  "type": "market_update",
  "items": [
    {
      "item_id": "avocado_toast",
      "market_price_cents": 198,
      "price_change_percent": 10.0,
      "trend": "up"
    }
  ]
}
```

---

#### Economic Event (Broadcast)

```json
{
  "type": "economic_event",
  "event_id": "uuid",
  "event_type": "drought",
  "severity": "major",
  "description": "A severe drought has struck the region",
  "affected_categories": ["food"],
  "started_at": 1715085600000,
  "ends_at": 1715344800000
}
```

---

#### Trade Request Received (Player-Specific)

```json
{
  "type": "trade_request_received",
  "trade_id": "uuid",
  "from_player_id": "uuid",
  "from_username": "string",
  "offer_items": [
    {
      "item_id": "avocado_toast",
      "quantity": 2
    }
  ],
  "offer_coins": 1000,
  "request_items": [],
  "request_coins": 0
}
```

---

#### Trade Request Response (Player-Specific)

```json
{
  "type": "trade_request_response",
  "trade_id": "uuid",
  "response": "accept", // or "decline"
  "from_player_id": "uuid"
}
```

---

#### Business Update (Broadcast)

Sent when business state changes (for employees/owners).

```json
{
  "type": "business_update",
  "business_id": "uuid",
  "business_name": "string",
  "update_type": "stock_changed",
  "details": {}
}
```

---

#### System Notification (Player-Specific)

```json
{
  "type": "notification",
  "level": "info", // or "warning", "error"
  "title": "Rent Due",
  "message": "Your rent is due in 12 hours",
  "timestamp": 1715085600000
}
```

---

#### Zone Players List (Player-Specific)

Sent when entering a new zone.

```json
{
  "type": "zone_players",
  "zone": "market",
  "players": [
    {
      "player_id": "uuid",
      "username": "string",
      "position": { "x": 10.0, "y": 0.0, "z": 20.0 },
      "yaw": 1.57
    }
  ]
}
```

---

## Message Envelope

All messages follow this envelope structure:

```json
{
  "type": "string",             // Message type identifier
  "id": "uuid",                 // Optional, for request-response correlation
  "protocol_version": 2,        // Contract major (auth handshake governs; informational per message)
  "request_seq": 42,            // Client writes only: monotonic per session, orders/intent-staleness ONLY
  "basis_revision": 138,        // Client writes (economic/actionable): the server state_revision the intent was computed against
  "revision": 139,              // Server messages: authoritative per-player counter (see note)
  "idempotency_key": "uuid",    // Economic actions only: server de-dupes replays within 24 h
  "timestamp": 1715085600000,   // Optional, server timestamp
  "data": {}                    // Optional, message-specific payload
}
```

**Separate counters:** `request_seq`, if adopted, orders transport messages;
`revision` identifies authoritative player state. A command names the state it
observed as `basis_revision`. Look up durable original receipts first. Reject a
fresh stale command with current state for resync; do not silently accept changed
prices or terms. Reconcile the production envelope with the fresh runtime under
OD13 rather than assuming the legacy `packages/protocols` shape is implemented.

**Replay/reconnect:** bounded per-session message caches can suppress transport
duplicates, but cannot supply economic idempotency after restart or eviction.
Economic commands require durable world/player/request-scoped original-result
replay, with changed-payload reuse rejected. Production key encoding and retention
remain OD13 decisions. Re-authenticate and resync after reconnect before new
actions; a receipt older than current state must not roll the client backward.

---

## Error Messages

```json
{
  "type": "error",
  "error_code": "string",
  "message": "string",
  "details": {}
}
```

**Common Error Codes:**
- `INVALID_MESSAGE` — Malformed message
- `UNAUTHORIZED` — Not authenticated
- `RATE_LIMITED` — Too many messages
- `INVALID_STATE` — Action not allowed in current state
- `NOT_FOUND` — Resource not found
- `INSUFFICIENT_RESOURCES` — Not enough coins, energy, etc.

---

## Rate Limiting

- **Movement:** 10 messages per second
- **Chat:** 5 messages per second
- **Other actions:** 20 messages per second
- **Browser courtesy:** the web client caps itself at 5 movement messages/s (positions interpolate client-side; see [[../frontend/3D_Frontend_Production.md|3D Frontend Production §8]]).

Exceeding limits → temporary throttling or connection close. These limits also replace the API contract's stale "WebSocket: no rate limit" line — the socket channel was always governed here.

---

## Reconnection Strategy

### Client Reconnection

1. **Detect disconnection** (heartbeat timeout or socket close)
2. **Wait exponential backoff** (1s, 2s, 4s, 8s, max 30s)
3. **Reconnect** with fresh auth token
4. **Request state resync** after auth:
   ```json
   {
     "type": "request_state_sync"
   }
   ```
5. **Server sends full state** as in initial sync

### Browser Tab Visibility (authoritative-time rules)

The browser pauses the game loop and eventually throttles timers when the tab is backgrounded; a socket may silently die. Contract consequences:

1. On `visibilitychange` → hidden, the client stops sending movement and marks local state provisional; **no action queue is buffered across suspension** (stale intents are dangerous, e.g. spending after rent auto-paid server-side).
2. On visible again: heartbeat-freshness check → if gap > 1 missed heartbeat, reconnect + `request_state_sync` before any input is accepted; the client re-derives all time-based UI from `server_time`, never elapsed wall time.
3. Offline consequences accrue on **server clock** (see Multiplayer Architecture §Persistent World); the client shows "what happened while away" from the resync diff, it does not simulate it.
4. Economic messages sent just before disconnection rely on `idempotency_key` replay (§Message Envelope), not on acks the client never received.

### State Reconciliation

- Server is authoritative
- Client accepts server state on reconnect
- Optimistic UI updates rolled back if server disagrees

### v2.1 Wire Additions (PROPOSED — design, not implemented)

Driven by the 3D browser client and canonical rules; each lands only with a server migration + protocol minor bump, never as an alias:

- Examples above already show the **canonical target shape** (`yaw`, `{x,y,z}` positions, step-based resources) even though the legacy `packages/protocols` messages still carry legacy fields; this document describes the contract, and the code cutover is implementation work (§Canonical field shapes note). `movement_ack`/`state_update` carry `revision`; consumers ignore updates with revision ≤ last applied.
- `zone` values are **logical gameplay zones** owned by the server (canonical game rules); render-chunk ids used for streaming in the browser client never appear in any message.
- Rest actions return progress fields per Canonical Game Rules (rate-based rest), replacing any notion of instant completion.

---

## Compression

Enable permessage-deflate compression for all messages > 1KB.

**Negotiation:**
```
Client: Sec-WebSocket-Extensions: permessage-deflate; client_max_window_bits=15
Server: Sec-WebSocket-Extensions: permessage-deflate; client_max_window_bits=15
```

---

## Security

1. **TLS only** — No plain WebSocket connections
2. **JWT authentication** — Token validated on connect
3. **Rate limiting** — Per-connection and per-player
4. **Input validation** — All messages validated server-side
5. **Message size limit** — Max 64KB per message
6. **Origin validation** — Verify client origin header

---

## Testing

### Connection Test

```bash
wscat -c wss://ws.dhaniverse.com/v1 \
  -H "Authorization: Bearer {token}"
```

### Message Flow Test

```json
// Send
{"type": "movement", "position": {"x": 10.5, "y": 0.0, "z": 20.3}, "yaw": 0.78, "zone": "market"}

// Expect
{"type": "movement_ack", "position": {"x": 10.5, "y": 0.4, "z": 20.3}, "revision": 138, "server_time": 1715085600000}
```

---

## References

- [[../api/API_Contract.md|API Contract]] — REST API endpoints
- [[../database/Schema.md|Database Schema]] — Data models
- [[../frontend/3D_Frontend_Production.md|3D Frontend Production]] — browser transport constraints behind the WSS-only rule
- [[../../specs/multiplayer/Multiplayer_Architecture.md|Multiplayer Architecture]] — Zone system, state sync
