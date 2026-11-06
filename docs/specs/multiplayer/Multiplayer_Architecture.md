---
tags: [spec, multiplayer, architecture, networking]
date: 2026-11-05
version: 2.1
aliases: [Multiplayer Architecture, Network Spec]
---

# Multiplayer Architecture Specification

## Overview
The production design targets a persistent shared world where players coexist, interact and collectively drive the economy. The intended browser client uses Godot web export and project-selected HTTPS/WSS transport; low-level native ENet/UDP is not a browser path. Wire details live in [WebSocket Protocol](../protocol/WebSocket_Protocol.md), with delivery constraints in [frontend production](../frontend/3D_Frontend_Production.md). This is a target, not a shipped client.

**Status 5 November 2026:** This is a production design contract, not a shipped
networked game. The active implementation is the fresh [runtime architecture](../systems/Runtime_Architecture.md).
The [choice-based pilot](../../design/14_Player_Choices_And_Consequences.md) needs
shared economic truth and a narrow consent-based trade method. Real-time
presence/chat is implemented as its scope requires; see the
[runtime architecture](../systems/Runtime_Architecture.md) for actual transport and integration status.

---

## Architecture Principles

### 1. Authoritative Server
- All game state is server-authoritative
- Clients send actions, server validates and executes
- No client-side trust for economic transactions
- Server is single source of truth

### 2. Persistent World
- World state persists 24/7 on the **server clock**
- Economy continues ticking even with zero players
- Player state saved on disconnect
- Offline consequences apply (rent due, health decay)
- Browser corollary: tabs suspend and clients reload at any time; "offline" is the normal state of a browser player, so every consequence must be reconstructible from server timestamps + resync diff, never from client elapsed time.

### 3. Zone-Based Interaction
- Map divided into **logical gameplay zones** owned by the server
- Players in same zone can interact
- Zone-based chat and visibility
- Cross-zone: Trade Board, Job Board (async)
- Zones are *not* render chunks: the browser streams cosmetic chunks for GPU-budget reasons; chunk ids never appear in protocol, ownership, or zone identity (canonical rules; [[../frontend/3D_Frontend_Production.md|3D Frontend Production §7]]).

### 4. Eventual Consistency
- Clients may be slightly behind server
- State syncs at regular intervals
- Critical actions (trades, payments) are synchronous request/response with idempotency keys — the browser may reload mid-request (§Message replay, WebSocket Protocol)
- Non-critical (position, animations) are interpolated client-side between server updates; movement authority is server range-checked

---

## Core Components

### Server Components
```
GameServer
├── WorldState — Current state of all entities
├── EconomyEngine — Price calculation, transactions
├── PlayerManager — Connections, authentication, state
├── ZoneManager — Zone partitioning, visibility
├── ChatServer — Message routing
└── EventScheduler — Timed events, economy ticks
```

### Client Components

The Godot browser client implements the component contract in [[../frontend/3D_Frontend_Production.md|3D Frontend Production §7]] (WorldManifest / ChunkStream / KitLibrary / Presentation / Interaction / NetworkState). The legacy sketch maps onto it as: Renderer → Presentation+ChunkStream, InputHandler → Interaction, StateManager → NetworkState mirror, NetworkClient → NetworkState transport, UIManager → Presentation HUD.

### Wallet/Shell Side (Next.js)

Auth session, wallet connect, profile/verify pages live in the Next.js shell, not the game client; the shell hands the game a short-lived access token (§API Contract). Game and shell share one account session but never share trust: the server re-validates every mutation regardless of origin.

---

## Communication Patterns

### Synchronous (Request-Response)
- Login/Authentication
- Trade confirmation
- Purchase transactions
- Loan applications
- Claim filing

### Asynchronous (Server Push)
- Price updates (every 5 min)
- Event notifications
- Rent/payment due alerts
- Chat messages
- Player join/leave zone

### State Sync
- Full sync on connect
- Delta sync every 1 second
- Critical state: immediate
- Non-critical: batched
- Browser reality: a second-tick delta channel plus visibility-triggered resync (§Browser Tab Visibility, WebSocket Protocol); the client renders interpolated movement between deltas and never extrapolates authority.

---

## Zone System

### Zone Definition
- Map divided into logical zones (server-owned gameplay grouping)
- Each zone: ~20-50 players visible
- Illustrative gameplay groupings: Residential, Market, Industrial, Civic, Entertainment. **Content districts** (Founders' Quay, Market Ward, Cedar Quarter, …) are the authored identity layer from [[../../design/10_City_Art_Direction|City Art Direction]]; a zone may span several adjacent districts. The final zone↔district partition is an open design item tracked in [[../../design/11_Canonical_Game_Rules|Canonical Game Rules]].

### Zone Transitions
- Player moves between zones seamlessly
- Zone change triggers: visibility update, chat channel switch
- Economy is global (not per-zone)

---

## Player State

### Persistent State (Saved to DB)
- Profile (username, join date)
- Resources (energy, health, stress)
- Inventory (items, quantities)
- Finances (wallet, bank, loans)
- Progression (education, reputation, housing)
- Relationships (friends, blocks, SHG membership)

### Session State (In-Memory)
- Position on map
- Current zone
- Active shift (if working)
- Pending trade offers
- Chat connection

---

## Security Considerations

### Anti-Cheat
- Server validates all economic actions
- Rate limiting on transactions
- Anomaly detection on earning/spending patterns
- Trade pattern monitoring

### Anti-Griefing
- Block system
- Trade confirmation required
- Reputation cost for bad behavior
- Chat filtering and reporting

---

## Scalability

### Target Capacity
- 50-500 concurrent players per world
- Economy ticks: < 500ms
- State sync: < 100ms latency
- Zone capacity: 50 players per zone

**Latency honesty:** < 100 ms is the *server-processing* target. Browser clients traverse HTTPS/WSS round-trips (typically 60–250 ms RTT) and TCP head-of-line blocking — WebSocket is documented as "good for reliability but not for latency". The design therefore stays event/state-level (this sim never needs 60 Hz authority over movement; positions interpolate, actions confirm). No claim here implies measured end-to-end latency; that happens at the frontend validation gates.

### Scaling Strategy
- Vertical scaling for initial release
- Horizontal: zone servers if needed
- Database: separate read/write instances
- Economy engine: dedicated compute
- Browser caveat for any scaling claim: capacity above is server-side; browser-tab suspension (§Persistent World) means concurrent *sockets* overestimate concurrent *attention* — connection pooling should size for reconnection storms (deploy windows, popular-hour returns), not steady state.

---

## References
- [[../../design/06_Multiplayer_Design|Multiplayer Design]]
- [[../../design/04_Economy_Design|Economy Design]]
- [[../../design/11_Canonical_Game_Rules|Canonical Game Rules]] — authoritative ownership/stock/lease semantics
- [[../frontend/3D_Frontend_Production.md|3D Frontend Production]] — browser transport and budget constraints
- [[../../design/reference/systems/Multiplayer_Social_Layer|Multiplayer Social Layer]]
