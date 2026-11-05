# Housing Architecture (Canonical Summary)

**Status:** operative summary; all values defer to
[../../11_Canonical_Game_Rules.md](../../11_Canonical_Game_Rules.md) and
[Housing_System.md](../systems/Housing_System.md). This file replaces the
former 364-line design exploration, whose contrary rent table
(120/300/700), 48-hour lockout, 10-second instant rest, per-type fixed bar
restore, and mansion stress-reset were superseded by the canonical rules
(see matrix rows 16-18, 36). Ideas that survived into canon are marked
below; nothing here is independently operative.

## World and unit identity

- One persistent shared world; interiors are shared world spaces linked to a
  physical location, never instanced personal lobbies (Canonical WP-1).
- Every home is a unit at a persistent server-assigned address
  (district -> lot -> building -> unit), stable across cosmetic reworks
  (WP-2). Multi-unit buildings provide supply; room rentals are rooms inside
  buildings (WP-3). Availability/ownership is server-authoritative; the
  client never fakes stock (WP-4).

## Space and capacity

- Home storage is a bounded unit budget by tier (150/300/300-600-1200,
  provisional) — the note's "space, not slots" idea, realized as server
  units (Canonical §6).
- Furniture occupies floor cells, a budget **independent** of storage
  units; items inside furniture remain portable (adopted idea).
- Large items (furniture, appliances) are house-bound; small items portable
  (adopted).

## Rest

- Rest requires a placed bed (4 cells); Tier 1 rooms include a
  landlord-provided bed (adopted bed-gating).
- Rest is rate-based idle recovery (5% energy / 2 real min x tier
  efficiency), not a fixed instant restore (rejected: 10-second recharge).
- Housing modifies recovery efficiency and stress; it never restores
  health directly or replaces healthcare (adopted constraint).

## Money

- Rents 40/80/150; ownership adds maintenance 30/80/200 per property type
  (rent table adopted from the owner doc, maintenance from this note).
- Rent auto-deducts per 24 real hours; unpaid: stress +1, **12-hour grace**,
  then eviction to Tier 0 (rejected: 48-hour lockout).

## Progression framing (non-operative)

Small apartment -> basic survival; house -> stable lifestyle; mansion ->
optimized efficiency, with visible status. Status is flavor; all mechanical
effects come exclusively from the canonical housing tables.
