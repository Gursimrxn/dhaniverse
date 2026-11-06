---
tags: [spec, implementation, roadmap, phases]
date: 2026-11-05
version: 2.1
aliases: [Implementation Order, Build Order]
---

# System Implementation Order

For the current task sequence and playable exit checks, use Implementation plan.
The phases below retain dependency context; they are not six completed releases
or a requirement to finish every system before exposing any player choice.

**Current gameplay milestone — 5 November 2026:** [Player choices and consequences](../../design/14_Player_Choices_And_Consequences.md) refines the pilot across these dependency phases. Demonstrate a shared neighborhood with different viable priorities, actions in any permitted order and complete recovery paths. Bring minimal literacy/qualified work, civic recovery and one shared trade method into that pilot rather than waiting for every advanced system. Routine walkthroughs remain correctness checks. Existing canonical mechanics and art/browser gates still apply; the historical planning notes do not determine the full-game build.

**Browser acceptance:** use [frontend production](../frontend/3D_Frontend_Production.md) for measured delivery checks. Authorized prototypes can precede those gates; they remain prototypes.

## Phase 0: Art and Toolchain Approval (precedes all client phases)

| Order | Item | Gate |
|-------|------|------|
| 0.1 | Blender gates G1–G6 — owner: [City Art Direction](../../design/10_City_Art_Direction.md) | Founder review before calling kits finished production art; authorized blockouts/imports can develop alongside them |
| 0.2 | Toolchain pin: exact Godot editor + web export templates, single-thread preset, headless export run | 3D Frontend Production gate 1 artifact |
| 0.3 | glTF pipeline dry run: one kit piece end-to-end (collider/socket suffixes, LOD import, VRAM compression, browser-rendered review) | 3D Frontend Production gate 2 with probe asset |
| 0.4 | Implement the founder's 13 October medium third-person direction at actual player scale, retaining the first-person comparison as a baseline | Readable character/interaction targets, camera collision and roof/canopy occlusion handling, clear input controls and measured target export; Blender views do not establish runtime behavior |

## Phase 1: Foundation (Core Survival)
**Goal:** Player can exist, move, consume resources, and see state changes.

| Order | System | Depends On | Deliverable |
|-------|--------|------------|-------------|
| 1.1 | Energy | None | Energy bar system, movement consumption, idle recovery |
| 1.2 | Health | None | Fractional-safe health, passive decay, canonical critical-state gate and health floor; ship required recovery alongside it |
| 1.3 | Stress | None | Stress levels, passive changes, event triggers |
| 1.4 | Food | Energy, Health | Food items, consumption, energy/health effects |
| 1.5 | Inventory | Food | Item storage, categories, capacity, stack limits |

**Phase 1 Test:** Player walks, energy depletes, eats food, energy recovers, health decays over time.
**Phase 1 Client Gate (browser):** Godot web export template pin + browser smoke (§11 of 3D Frontend Production) passes on the starter scene: Chromium desktop loads over HTTPS, audio-gesture start, WSS auth/resync round-trip. No movement/gameplay phase sign-off without it.

---

## Phase 2: Core Economy
**Goal:** Player can earn, spend, save, and see market prices.

| Order | System | Depends On | Deliverable |
|-------|--------|------------|-------------|
| 2.1 | Work System | Energy, Health, Stress | Job types, shifts, pay calculation, modifiers |
| 2.2 | Banking & Finance | Work | Accounts, deposits, withdrawals, basic loans |
| 2.3 | Commerce | Inventory, Supply/Demand | Shops, purchasing, price display |
| 2.4 | Supply & Demand | Commerce, Work | Price engine, supply/demand tracking, market ticks |
| 2.5 | Housing | Energy, Health, Stress, Banking | Housing tiers, rent, rest mechanics, storage |

**Phase 2 Test:** Player works shift, earns coins, buys food at market (price varies), pays rent, rests at home.
**Phase 2 Data Gate:** v2.1 schema delta (`housing_units`/`leases`/bounded storage, marked *proposed* in `Schema.md`) reconciled with Canonical Game Rules before 2.5 ships — housing/rent work must be built on lease rows, not `player_housing` drift. Rate-based rest (progress responses, no instant recharge) is the 2.5 acceptance wording.

---

## Phase 3: Advanced Economy
**Goal:** Player can plan long-term, manage risk, and access advanced features.

| Order | System | Depends On | Deliverable |
|-------|--------|------------|-------------|
| 3.1 | Education | Work, Banking | Education levels, courses, job unlocks |
| 3.2 | Government & Legal | Work, Banking, Housing | Taxes, welfare, permits, court, police |
| 3.3 | Insurance | Banking, Health | Plans, premiums, coverage calculation |
| 3.4 | Financial Dashboard | Banking, Work, Commerce | Health score, expense breakdown, advisor |
| 3.5 | Business Ownership | Banking, Work, Government | Business types, revenue, employees, growth |

**Phase 3 Test:** Player completes education, gets better job, buys insurance, sees financial health score, starts business.

---

## Phase 4: Multiplayer
**Goal:** Players can interact, trade, form groups, and see each other's impact.

| Order | System | Depends On | Deliverable |
|-------|--------|------------|-------------|
| 4.1 | Multiplayer Social | All economic systems | Profiles, friends, chat, job board, SHG |
| 4.2 | Social Reputation | Work, Education, Government | Reputation scale, gain/loss rules, tier effects |
| 4.3 | Player Trade | Inventory, Supply/Demand, Social | Direct trade, market listings, player lending |
| 4.4 | Events System | Supply/Demand, All systems | Event triggers, effects, catalog, resolution |

**Phase 4 Test:** Two players trade items, one hires the other, prices shift from collective behavior, event affects all.
**Phase 4 Network Gate:** durable idempotency and revision enforcement are part of shared-economy acceptance from its first transport integration; replay after browser reload must not double-spend. The archived async-only event plan is not this pilot's scope.

---

## Phase 5: Depth Systems
**Goal:** Full game experience with all support systems.

| Order | System | Depends On | Deliverable |
|-------|--------|------------|-------------|
| 5.1 | Healthcare | Health, Banking, Insurance | Hospitals, clinics, treatment, medication plans |
| 5.2 | Insurance Claims | Insurance, Healthcare | Claim filing, processing, appeals |
| 5.3 | Transport | Energy, Work | Bus, train, passes, telecom plans |
| 5.4 | Restaurants | Food, Stress, Reputation | Dining tiers, stress relief, reputation gain |
| 5.5 | Illness State | Health, Stress, Healthcare | Triggers, effects, cure path, frequency cap |

**Phase 5 Test:** Player gets ill, visits hospital, files insurance claim, uses transport to reach locations, dines out for stress relief.
**Phase 5 Client Gate:** full-district streaming inside §10 budgets — 60 s acceptance walk at 720p30 budget class with zero undeclared >100 ms frames; visual approval from the Compatibility browser build, never an offline render.

---

## Cross-Phase Dependencies

### Can Be Parallelized
- Phase 1 systems (Energy, Health, Stress) can be built simultaneously
- Phase 5 systems (Healthcare, Transport, Restaurants) are independent of each other
- Content creation (items, jobs, events) can happen alongside system development

### Must Be Sequential
- Supply & Demand requires Commerce and Work
- Business Ownership requires Banking and Government
- Player Trade requires Multiplayer Social Layer
- Insurance Claims requires Insurance and Healthcare
- City content follows Phase 0: kit library and district bundles (§6–§7 of 3D Frontend Production) are content deliverables parallel to system phases, not hidden inside them
- Client budget capture (profiler artifacts under `docs/reports/`) runs at **every** phase gate after Phase 0, not only at Phase 5

---

## References
- [[../../design/05_Systems_Map|Systems Map]]
- [[../../design/04_Economy_Design|Economy Design]]
- [[../../design/reference/00_INDEX|Research Index]]
- [[../frontend/3D_Frontend_Production.md|3D Frontend Production]] — budgets, gates, camera, export contract
- [[../../design/11_Canonical_Game_Rules|Canonical Game Rules]] — rule precedence over any older wording in these phases
