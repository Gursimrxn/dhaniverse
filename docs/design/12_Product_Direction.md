# Dhaniverse development scope and open design questions

**Updated 2026-11-05.** This file organizes implementation and unresolved gaps. It does not replace the founder's game idea, introduce a tagline, or override [Canonical Game Rules](11_Canonical_Game_Rules.md).

**Gameplay direction accepted 2026-11-05:** [Player choices and consequences](14_Player_Choices_And_Consequences.md) refines the next milestone. Build several connected opportunities in a shared neighborhood, support actions in any permitted order and verify recovery after setbacks. The linear first routine remains one correctness scenario, not the complete player experience. The new research informs experiments; individual balance proposals do not override canon.

## Design authority

Dhaniverse remains the documented multiplayer economic life simulation: manage energy, health and stress; earn through work and businesses; spend on needs; save, borrow and invest; progress through education, reputation and ownership; participate in a shared, persistent economy. All 24 documented systems remain the full-game target. Implementing them in stages does not remove them.


Canonical rules and system owners remain authoritative: one UTC server clock, 30-minute normal shifts, the documented five-minute tutorial shift, offline financial obligations and health decay, 12-hour rent grace/eviction, education programs and documented housing/recovery rules. Any alternative requires an explicit founder decision; research recommendations are not authorization.

## Work authorized now

Build the 3D models/environment and game together in reviewable slices. Reuse the liked DV-01 arrival, DV-03 market and DV-05 housing models, retain the bank and Common Table, and assemble the starter district using the measured map. Keep stable site and housing-unit identities.

The first slice needs actual routes, entrances, interiors, terrain joins and a controllable player. Build service anchors for the documented job, market, banking, food and housing interactions. A marker or menu is not a claim that its backend system has been implemented.

The earlier DV-06 supermarket, DV-07 clothing/laundry and DV-08 electronics/telecom were rejected. Their v3 replacements are review candidates, not approved production assets. Judge them against purpose, references and their place in the town; three generic shells do not pass merely because they were exported.

## Gaps to fill without changing the idea

- Define the actual activity inside a work shift, its attendance, partial-pay, disconnect and completion-evidence rules. Do not substitute a shorter normal shift by changing a prototype constant.
- Reconcile code, API and schema with fractional energy/health/stress values, canonical prices, stable leases and atomic monetary operations.
- Define how rest interacts with time drain, course-specific energy exceptions, simultaneous obligation priority and NPC supply/demand floors.
- Complete Financial Health Score normalization and zero-income behavior.
- Verify critical-state, illness, welfare and emergency treatment paths together so a player can recover under the documented rules.
- Measure public routes, energy/travel costs, physical housing capacity and browser performance rather than inferring them from renders.
- Record conflicting consumer examples and fix them against their owner tables.

## Research and possible experiments

Retention research informs questions and playtests. Shorter shifts, different offline penalties, different education formats, cosmetic monetization, AI guides and onchain achievements are proposals, not adopted game rules. Retention percentages are internal experiment ideas, not product guarantees or investment requirements.

AI/Jev and Web3 are potential later integrations. They cannot change game money, prices, leases, rewards or progression outside the authoritative command path. No model, chain, revenue model or financial product is selected by this file.

## Implementation order

1. Preserve design authority and correct overreaching doc changes.
2. Assemble/export existing starter models and author connecting terrain, streets and paths. Validate them in a playable Godot scene.
3. Implement durable server commands for work, income, food, bank, housing and rest. Connect them through independent eligibility and activity rules rather than a compulsory next-task queue; verify the documented routine as one possible order.
4. Add minimal learning with an actual qualified role, shared stock and one consent-based trade method to demonstrate distinct priorities. Ship recovery alongside the pressures that need it, then extend through documented progression and dependencies.
5. Playtest, measure and present proposed balance changes separately for a founder decision. Expand art and systems without moving owned unit identities.

See world plan and gap audit, [implementation order](../specs/systems/Implementation_Order.md) and [runtime architecture](../specs/systems/Runtime_Architecture.md).
