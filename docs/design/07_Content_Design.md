---
tags: [gdd, content, catalog, balancing]
date: 2026-11-05
version: 2.1
aliases: [Content Design, Game Content]
---

# Content Design

This chapter is a consumer catalog. Precedence rules are in
[11_Canonical_Game_Rules.md](11_Canonical_Game_Rules.md); its section 9 names
the owner of each value family and its matrix records where this chapter's
numbers beat older reference drafts (jobs, food, insurance) and where an
owner document's table was adopted instead (clothing, healthcare, housing
mechanics). Prices are BASE prices — players transact at Market Price per
the canonical price model (Canonical Rules §4).

## Job Catalog

This table is canonical for pay and energy (Canonical Rules §9 rows 11-12;
the Work_System draft's wider bands and per-workplace energy costs are
superseded). Pay is before health/stress/clothing/reputation modifiers and
the +15% performance bonus.

| Tier | Job | Location | Pay/Shift | Energy | Requirements |
|------|-----|----------|-----------|--------|--------------|
| 0 | Street Stall Helper | Market | 30-50 coins | 1 bar | None |
| 0 | Farm Laborer | Farm | 40-60 coins | 1 bar | None |
| 1 | Factory Worker | Factory | 60-80 coins | 1 bar | Basic Literacy |
| 1 | Small Shop Assistant | Shop | 50-70 coins | 1 bar | Basic Literacy |
| 2 | Office Clerk | Office | 80-120 coins | 1 bar | School Diploma |
| 2 | Bank Teller | Bank | 90-130 coins | 1 bar | School Diploma |
| 3 | Manager | Office | 150-200 coins | 1 bar | College Degree |
| 3 | Senior Officer | Bank/Govt | 180-250 coins | 1 bar | College Degree |

Work gating (Canonical Rules §3.5): >= 2 spendable bars (base + bonus),
health > 10%, stress < 9; shifts are 30 real minutes with 1 bar charged at
completion; the 15-minute energy time-drain does not run during a shift.
Per-day shift caps and pay raises: Work_System S6/S9.

### Specializations
| Specialization | Pay Bonus | Requirements |
|----------------|-----------|--------------|
| Finance | +20% at Investment Office | Finance Specialization |
| Healthcare | -15% clinic costs | Healthcare Track |
| Business | +15% business income | Business Management |

---

## Food Catalog

This table is canonical for base prices and per-item health effects
(Canonical Rules §9 row 14; Food.md's blanket +0.6%/-0.7% values apply only
as fallback to items unique to that document, whose prices there stand).
Energy per item = 5 bars / items-for-full-energy (both catalogs use the same
conversion rule).

### Natural Food
| Item | Energy Restored | Health Effect | Cost (Base) | Source |
|------|----------------|---------------|-------------|--------|
| Fruits | 0.14 bars | +1% health | 3 coins | Market |
| Vegetable Wrap | 1 bar | +2% health | 8 coins | Market/Stall |
| Avocado Toast | 5 bars (full) | +5% health | 25 coins | Cafe |
| Full Meal (cooked takeaway) | 3 bars | +8% health | 40 coins | Dhaba/stall takeaway (1-day expiry, Inventory S8) |

### Fast Food
| Item | Energy Restored | Health Effect | Cost (Base) | Source |
|------|----------------|---------------|-------------|--------|
| Candy | 0.10 bars | -0.5% health | 2 coins | Market |
| Packaged Snacks | 0.5 bars | No effect | 5 coins | Supermarket |
| Street Food | 1 bar | No effect | 10 coins | Street Stall |

Food.md-only items (Burger 30, Cheetos 20, Donut 80, Boba Tea 120, Juice
100, Ramen 180, Energy Drink 100) keep their Food.md prices and conversion
values with health effect Natural +0.6% / Fast -0.7% per Health.md.

---

## Housing Catalog

Owner: [Housing_System.md](reference/systems/Housing_System.md); mechanics
per Canonical Rules (12-hour real-time rent grace; rate-based rest at a bed;
bounded home storage with furniture floor footprint independent of storage
units — Tier 1 rooms include a landlord bed but no storage).

| Tier | Type | Cost | Rest Quality | Home Storage |
|------|------|------|--------------|--------------|
| 0 | No Housing | Free | None | None |
| 1 | Room Rental | 40 coins/day | Low (50% recovery) | None (bed provided) |
| 2 | Small House | 80 coins/day | Moderate (100% recovery) | 150 units (provisional) |
| 3 | Apartment | 150 coins/day | High (100% + health bonus) | 300 units (provisional) |
| 4 | Owned Property | Mortgage, then maintenance | High + stress reduction | 300/600/1200 units by property type (provisional) |

### Property Purchase
| Type | Price | Down Payment | Mortgage Term | Maintenance/Day |
|------|-------|--------------|---------------|-----------------|
| Apartment | 2,500 coins | 20-50% | 10-30 days | 30 coins |
| House | 7,000 coins | 20-50% | 10-30 days | 80 coins |
| Mansion | 20,000 coins | 20-50% | 10-30 days | 200 coins |

Housing units are persistent server-assigned addresses inside multi-unit
structures (Canonical Rules §7); availability is server stock, never a
client-side illusion.

---

## Clothing Catalog

Owner: [Commerce_System.md](reference/systems/Commerce_System.md) — adopted
over this chapter's older sketch (Canonical Rules §9 row 19), because
Commerce carries the full durability/laundry/dress-code mechanic.

| Tier | Type | Cost | Durability | Effect |
|------|------|------|------------|--------|
| 0 | None/Basic | Free | Infinite | -10% office pay, -1 Rep/day |
| 1 | Basic clothes | 100 coins | 10 days | No bonus or penalty |
| 2 | Smart casuals | 300 coins | 20 days | +5% office pay |
| 3 | Formal wear | 600 coins | 30 days | +10% office pay, +social rep |
| 4 | Premium attire | 1200 coins | 45 days | +15% office pay, major social rep |

---

## Insurance Plans

Canonical values (agreement of 04 and 07 over the older draft; Canonical
Rules §9 row 10). Owner mirror: [Insurance.md](reference/systems/Insurance.md).

| Plan | Premium (24hrs) | Hospital | Clinic | Pharmacy |
|------|-----------------|----------|--------|----------|
| Basic | 60 coins | 40% | 30% | 10% |
| Standard | 100 coins | 60% | 45% | 20% |
| Premium | 150 coins | 80% | 60% | 30% |

---

## Healthcare Services

Owner: [Healthcare System.md](reference/systems/Healthcare%20System.md);
canonical values are the owner's (Canonical Rules §9 row 35), and
this chapter's older merged table is superseded.

| Treatment | Cost | Duration | Health Restored |
|-----------|------|----------|-----------------|
| Clinic preventive checkup | 80 coins | 2 min | +10%, stress -1 |
| Clinic basic checkup | 150 coins | 2 min | +15% |
| Clinic medical treatment | 350 coins | 2 min | +35% |
| Hospital basic | 300 coins | 5 min | +30% |
| Hospital advanced | 700 coins | 5 min | +60% |
| Hospital full | 1,200 coins | 5 min | Restore to 100% |

Critical state is health <= 10% everywhere: clinics refuse, hospitals treat
(including Emergency Treatment on account so an unpaid player is never
softlocked); the game does not auto-hospitalize.

---

## Transport Options

| Mode | Speed | Cost | Energy Cost |
|------|-------|------|-------------|
| Walking | 1× | Free | Normal |
| Bus | 3× | 10 coins/trip | None (timer paused) |
| Train | 6× | 25 coins/trip | None (timer paused) |
| Auto/Taxi | 4× | 40 coins/trip | None |

### Pass Options
| Pass | Cost | Duration |
|------|------|----------|
| Bus Daily | 50 coins | 24 hours |
| Bus Weekly | 250 coins | 7 days |
| Train Monthly | 400 coins | 30 days |

---

## Telecom Plans

| Plan | Cost (24hrs) | Services |
|------|-------------|----------|
| Basic | 30 coins | Job alerts, bank balance |
| Standard | 60 coins | + Stock app, welfare portal |
| Premium | 100 coins | + Remote work, online education |

---

## Education Programs

Owner: [Education_System.md](reference/systems/Education_System.md). Costs
are upfront fees; each session is 10 real minutes, 1 energy bar per session,
+1 baseline stress while enrolled.

| Level | Cost | Duration | Sessions |
|-------|------|----------|----------|
| Basic Literacy | Free | 10 min | 1 |
| School Diploma | 200 coins | 30 min | 3 |
| College Degree | 800 coins | 60 min | 6 |
| Specialization | 400 coins | 30 min | 3 |
| Postgraduate / Skill | 1200 coins | 45 min | 5 (provisional) |

---

## Business Types

Owner: [Business_Ownership_System.md](reference/systems/Business_Ownership_System.md).
Revenue is player-driven (footfall x price x stock), not a fixed daily
payout; the targets below are design guidance `[provisional]` and are not
mechanics.

| Type | Min. Capital | Max Employees | Target Revenue/Day |
|------|-------------|---------------|--------------------|
| Street Stall | 500 coins | 0 | 80-150 coins |
| Small Shop | 1,200 coins | 2 | 200-400 coins |
| Dhaba | 1,500 coins | 3 | 250-500 coins |
| Office / Consultancy | 4,000 coins | 4 | 400-800 coins |
| Workshop / Factory | 3,000 coins | 5 | 600-1,200 coins |
| Restaurant | 5,000 coins | 6 | 500-1,000 coins |

Hard eligibility: Reputation Tier 3 (41+), School Diploma, Business Permit
(150 coins, 30-day term), capital, clean loan record. Financial Health 60+
is pacing guidance, not a gate (Canonical Rules §9 row 23).

---

## Event Catalog

See [Events System](reference/03_Events_System.md) for the full catalog:
supply shocks, demand spikes, infrastructure failures, economic and social
events. Event magnitudes apply as modifiers inside the canonical price model.

---

## References
- [11_Canonical_Game_Rules.md](11_Canonical_Game_Rules.md) — precedence, ownership map, conflict matrix
- [04_Economy_Design.md](04_Economy_Design.md)
- [05_Systems_Map.md](05_Systems_Map.md)
- [Work System](reference/systems/Work_System.md)
- [Food System](reference/systems/Food.md)
- [Housing System](reference/systems/Housing_System.md)
- [Events System](reference/03_Events_System.md)
