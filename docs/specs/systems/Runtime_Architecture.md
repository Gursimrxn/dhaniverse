# Dhaniverse runtime architecture

**Scope.** The code is in this repository: `server/crates/rules` holds the pure domain, `server/crates/server` the transport and `game/` the client. The initial executable is a headless rules foundation, not a deployed multiplayer game.

**Implementation update 5 November 2026:** The pure domain and a durable local
SQLite command store now exist. The JSON-lines executable exposes food and
savings to a fixed local guest; earning remains withheld pending attendance and
eligibility work. There is no network transport or Godot connection. PostgreSQL
remains the production decision. See the [server README](../../../server/README.md).
The next gameplay milestone follows [player choices](../../design/14_Player_Choices_And_Consequences.md),
with independent eligible actions rather than a compulsory tutorial sequence.

## Structure and boundaries

Use a modular monolith: one Rust application, PostgreSQL as durable authority, a thin Godot presentation client, and the existing Next.js shell for public pages/auth handoff. One deployment is easier to operate and change while learning the right boundaries. Extract a service only when measurement shows a need and its ownership is clear.

```text
Godot / web shell
        │ typed intents and state revisions
        ▼
Authenticated command service
        │ validate presence, version and current state
        ▼
Pure domain transition
        │ resulting state and events
        ▼
PostgreSQL transaction: state + ledger/events + receipt + outbox
        │ committed outbox only
        ├── WSS state updates
        ├── analytics
        └── optional AI / achievement adapter
```

The independent Cargo workspace contains `dhaniverse-domain` and `dhaniverse-local-server`. Rules and data types remain separate from adapters. Production transport, PostgreSQL storage and protocol DTOs will be added alongside them. Domain code imports no database, engine, HTTP or AI SDK. Do not create 24 empty crates or a general plugin framework in anticipation of possible systems.

## Command handling

1. Authenticate the player/world and validate access/presence. Never accept a player ID, bank visit or clock as authority merely because a client sent it.
2. Begin the transaction. Lock the affected player and relevant stock/unit rows using a consistent lock order.
3. Look up the unique `(world_id, player_id, request_id)` receipt before evaluating a changed state revision. The same semantic command returns the original receipt; different payload reuse is rejected.
4. Check the client's `basis_revision`; reject stale new commands and return current state for resync.
5. Evaluate the pure transition against current state, trusted server time and versioned catalog.
6. Commit player state, monetary ledger entries, stock/unit changes, events, receipt and outbox together. Constraints enforce nonnegative balances and unique active allocations.
7. Publish committed events after commit. Consumers deduplicate by event ID; a lost acknowledgment reuses the request ID.

The original bounded memory adapter remains ephemeral. The new local SQLite
store retains committed receipts across restart without eviction and compares
typed semantic intents. Its protocol bounds requests at 4096 bytes. Production
retention, migration and deployed identity still need policies; local durability
does not establish a production-ready service.

## Invariants worth testing

- All money is integer cents, with checked arithmetic and a defined maximum that fits the database/wire contract. Bank transfers preserve total player money; wages/purchases are explicitly categorized source/sink events.
- Resource precision survives client/server round trips. The pilot uses 200 energy steps per bar and a 1000-step cap.
- The client cannot provide price, reward or outcomes. Accepted timed contracts snapshot terms so balance updates do not rewrite in-flight rewards.
- New commands consume a current revision; successful retries return their earlier result without a second payout/purchase.
- Rejections leave the player, ledger, stock and receipts unchanged.
- Activities require server-validated evidence and attendance/disconnect semantics before shipping. A completion timestamp alone is insufficient. This remains pending in the first foundation.
- Leases and businesses have stable authored world/unit IDs. Cosmetic geometry, load chunks and NPC dialogue never allocate ownership.
- AI cannot author authoritative mutations. Chain/provider failure cannot block the simulation.

Use focused behavior tests and end-to-end transaction tests, including concurrent last-item buying, duplicate payouts, stale revisions, interrupted requests and reconnect. Avoid tests that merely repeat constants or accept an in-memory success as proof of database safety.

## Clocks and lifecycle

One trusted UTC server clock timestamps events and activities. Tests inject explicit time. Canonical offline obligations, health decay, grace and eviction remain part of the design; energy does not drain offline. These other systems are not implemented by the foundation, which cannot claim an alternative policy.

Normal work uses the canonical 1800 seconds; the documented tutorial exception uses 300 seconds. Tests advance injected time without changing live rules. Completion evidence and canonical attendance/partial-pay/disconnect behavior remain to be implemented.

## Browser client

Godot 4.7.2 is the locally observed editor candidate. Verify matching export templates and a clean web build before calling it browser-ready. Use GDScript and Compatibility for the browser baseline, preserving the existing art masters. Reuse a model only after its materials/collision/performance survive the real target camera.

One network dispatcher owns intents, receipt IDs, revision application and resync. UI displays authoritative data; it may show pending actions clearly. On tab suspension/offline, stop intents. On return, resync before new spending. Profile loading, frame time and stalls from the first neighborhood; keep the existing browser specification's budgets as provisional targets until measured.

## Scaling path

Initially operate one pilot world and one server instance. Include world identity in durable keys and service ownership now; it does not imply multiple gameplay economies are already built. Prioritize correctness and measurable latency over million-player promises.

Stateless HTTP processes can scale after all authority/receipts are durable. WSS delivery can use the outbox to distribute updates. Rendering visibility areas limit avatar traffic; they do not change leases or market truth. Add Redis/pub-sub only when multiple instances or measured load need it. Server partitioning preserves the documented single persistent world. Separate player worlds or instanced homes are not an approved shortcut.

Load tests must record concurrent actions, tick duration, p95/p99 latency, connection/reconnect bursts, transaction conflicts and CPU/memory. Split economy or real-time delivery services only when a clear bottleneck and stable interface justify the operational cost.

## AI and Web3 interfaces

After the core loop works, define a decision-policy interface over a bounded list of authored actions and a minimal trusted state summary. Start with rules; compare models offline on recorded cases. Dialogue generation is separate from action selection. No live model calls are made by the foundation.

An optional achievement adapter subscribes to committed milestones. It uses a versioned claim schema, explicit opt-in and retryable receipts; ownership and economy remain in PostgreSQL. Chain-specific addresses never become core player IDs. Test signed offchain verification before paying chain/onboarding complexity.

## Next implementation task

Add the production command transport/authentication, PostgreSQL transaction
adapter and versioned DTOs, reusing the local store's failure/concurrency
scenarios. Connect independent eligible Godot activities and authoritative state
resync; neither the memory adapter nor the fixed-guest SQLite harness is a public
multiplayer server. Use the choice chapter's pilot sequence rather than treating
the executable first-session scenario as the player's required itinerary.

Architecture sources: [Fowler on starting with a monolith](https://martinfowler.com/bliki/MonolithFirst.html), [PostgreSQL transaction isolation](https://www.postgresql.org/docs/current/transaction-iso.html), [Godot browser export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html). These support constraints and trade-offs, not an unmeasured capacity guarantee.
