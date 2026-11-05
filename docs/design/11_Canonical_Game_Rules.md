---
tags: [gdd, canonical, rules, precedence, balance]
date: 2026-11-05
version: 1.1
aliases: [Canonical Game Rules, Rule Precedence, Balance Authority]
---

# Canonical Game Rules

> **Design authority confirmed - 2026-11-05:** These rules remain authoritative.
> [Development scope](12_Product_Direction.md) records implementation and gaps;
> it does not override shifts, offline decay, obligations, eviction, education or
> the full-game systems. Retention alternatives remain proposals until explicitly
> approved by the founder. The archived planning deadline no longer applies;

This document arbitrates gameplay-rule conflicts across the design corpus
(docs/design/01-09, docs/design/reference/**, docs/specs/economy/). Where two
documents disagree on an operative number, threshold, or formula, the value
here wins; any remaining contradictory consumer must be corrected against it.
Unresolved policies are tracked in Open decisions.
Values marked
`[provisional]` are placeholder capacities/counts that keep systems solvable
without a balance pass; they are **not** tuned and not verified for shipping.

## 1. Precedence Ladder

1. Current user direction and established authorization. [Product direction](12_Product_Direction.md)
   and [player choices](14_Player_Choices_And_Consequences.md) record the current
   full-game milestone without changing mechanical values. Chapter 08 is an
   applies only to its requested scope and eligibility.
2. This document: precedence, single time model, price model, storage model,
   world-persistence invariants, and every conflict resolution in section 9.
3. The **numbered main GDD chapters (01-07)** are preferred for conflicting
   magnitudes between a chapter and an older reference draft. Detail in a
   reference draft does not by itself promote it over the chapter.
4. The reference/systems document that owns a mechanic (section 10) is the
   authority for *rules, mechanics, gating, and timing structure* of that
   mechanic.
5. `reference/notes/` is design archaeology only; its housing content has
   been replaced by a concise canonical note that defers to this file.

Rationale: the reference drafts are the oldest documents; the 2.0 chapters
are the current product intent. Where both speak to the same magnitude, the
chapter wins; where only a reference document defines a mechanic's structure,
it keeps ownership.

## 2. Single Time Model

There is exactly **one server wall clock (UTC)**. There is no separate
simulated-time clock. "1 in-game day" means a 24 real-hour UTC day boundary.

Activity eligibility on that shared clock:

| Process | Runs while offline / tab hidden? | Notes |
|---|---|---|
| Economy ticks (5 min) | Yes | server-authoritative, continues at zero players |
| Rent, premiums, loan installments, interest cycles, taxes | Yes | day-clock boundaries |
| Health decay (5% / 2 real hours), stress-driven health decay | Yes | biological drift is wall-clock, per Health.md |
| Item expiry, reputation decay | Yes | day clock |
| Energy bars (200 steps / 15 min per bar) | No | energy is consumed by live activity; offline idle does not drain energy below the last online value |
| Idle energy recovery (5% / 2 min idle) | Only while connected and idle | paused offline entirely |
| Work shifts (30 real min) | Only while connected at workplace | disconnect mid-shift = partial pay at time completed |
| Treatment, dining, claim processing timers | Yes (server) | these are server timers; a hidden tab does not freeze them, the client just catches up on reconnect |

- **CR-1 (Day):** 1 in-game day = 24 real hours everywhere. The parenthetical
  in Health.md equating 2 real hours with "1 in-game day" was an error and
  has been deleted; health decay remains **5 percentage points every 2 real
  hours** on the shared clock.
- **CR-2 (Grace/due units):** every "per 24 in-game hours" obligation = every
  24 real hours; "12 in-game hours grace" = 12 real hours.
- **CR-3 (Recovery paths stay explicit):** energy recovers (food, idle, rest,
  transport-pause, remote-work discount); stress recovers (library -0.5,
  dhaba refuge, insurance/stability relief, advance-rent -1, housing daily
  -0.5/-1); cash recovers (unemployment benefit 20/day, welfare benefits,
  bankruptcy path to Tier 0 + welfare). These channels are load-bearing and
  must not be removed by later tuning.

## 3. Canonical Cross-System Constants

### 3.1 Critical health state (unified threshold: health <= 10%)

| Rule | Value |
|---|---|
| Movement speed | -20% |
| Energy consumption | +20% |
| Work | cannot start shifts (also already fails the >10% work gate) |
| Clinics | refuse treatment |
| Insurance purchase | forbidden (prevents adverse selection) |
| Hospital | accessible; see no-softlock rule |
| Illness trigger | remaining <=10% for >30 real minutes untreated |

- Health floor: never below 5%.
- **No automatic hospital teleport.** The archived Health.md rule that
  auto-sends players below 10% to hospital is retired: it silently pays the
  crisis lesson and breaks the insurance activation rule.
- **No softlock:** when a player in critical state cannot pay, the hospital
  must offer **Emergency Treatment on account** — a medical bill recorded
  like any other (24-hour payment window, stress +1 if unpaid, healthcare
  facilities may refuse *future non-emergency* service until cleared, court
  debt path exists). Welfare Medical Subsidy (20% off hospital bills) and
  bankruptcy recovery remain available. Emergency-on-account cannot be
  refused for any reason.

### 3.2 Stress bands and named levels

Stress 1-12: **Low = 1-4, Moderate = 5-8, High = 9-12.** Every reference to
"High/Moderate Stress" (health decay, energy x1.2, pay penalties, factory
injury risk) keys off these bands.

### 3.3 Food catalog (07 magnitudes canonical; energy conversion from Food.md)

Energy per item = `5 bars / (items required for Full Energy)`. Items present
in 07_Content_Design use 07's base price and per-item health effect exactly.
Items that exist only in Food.md keep Food.md's base price and the per-item
health fallback (**Natural +0.6% / Fast -0.7%**).

| Item | Class | Base price | Full-energy items | Per item | Health/item |
|---|---|---|---|---|---|
| Fruits | Natural | 3 coins | 35 | 0.14 bars | +1% |
| Vegetable Wrap | Natural | 8 coins | 5 | 1 bar | +2% |
| Avocado Toast | Natural | 25 coins | 1 | 5 bars | +5% |
| Full Meal (cooked takeaway) | Natural | 40 coins | explicit override: fixed restore | 3 bars | +8% |
| Candy | Fast | 2 coins | 50 | 0.10 bars | -0.5% |
| Packaged Snacks | Fast | 5 coins | 10 | 0.5 bars | none (07) |
| Street Food | Fast | 10 coins | 5 | 1 bar | none (07) |
| Burger | Fast | 30 coins | 25 | 0.2 bars | -0.7% fallback |
| Cheetos | Fast | 20 coins | 30 | 0.17 bars | -0.7% fallback |
| Donut | Fast | 80 coins | 5 | 1 bar | -0.7% fallback |
| Juice | Natural | 100 coins | 5 | 1 bar | +0.6% fallback; +1 temp bar, +10% speed |
| Ramen | Natural | 180 coins | 1 | 5 bars | +0.6% fallback |
| Boba Tea | Fast | 120 coins | 1 | 5 bars | -0.7% fallback; -10% speed 1 min |
| Energy Drink | Fast | 100 coins | 1 | 5 bars | -0.7% fallback; +2 temp bars, +30% speed |

Exactly **one** per-item health effect applies per consumption: the 07
value where listed; otherwise the Health.md fallback by class. Effects never
double-apply.

### 3.4 Temporary energy boosts (duration and stack precedence)

Food grants of "extra bars" (Juice +1, Energy Drink +2, Energy Supplements
+1) enter a separate **bonus_bars** pool above the 5-bar cap:

- Consumed **first** by all energy drains; base bars never drop while
  bonus_bars > 0.
- Total bonus_bars capped at 2. Grant while a boost is active:
  `bonus = min(2, max(existing_bonus, grant))` (no addition); the grant
  replaces the timer only if `grant >= existing`, otherwise timer untouched.
- Duration: Juice 30 real minutes; Energy Drink 45 real minutes; Energy
  Supplements 45 real minutes `[provisional]`. Expiry removes unused bonus
  bars only.
- Bonus bars do **not** satisfy "at least 2 bars to start a shift" unless
  `energy_bars + bonus_bars >= 2` — the check reads the combined pool
  (canonical: combined pool is spendable energy).

### 3.5 Work gating and shift energy (05 gate, 07 pay/energy magnitudes)

- Start a shift requires: **education tier, >= 2 bars spendable energy,
  health > 10%, stress < 9.** (05_Systems_Map threshold; retained. The
  pay-reduction bands in Work S3 still apply when eligible.)
- Every shift costs **1 energy bar** (07 magnitude), charged at completion;
  the **15-min time drain does not run during a shift** (step drain also
  does not apply). Work_System's per-workplace overrides (0.5/1.5/2 bars)
  are superseded by the flat 1 bar.
- Dropping to the last spendable bar mid-shift pauses the shift; pay accrues
  for time worked and settles proportionally if abandoned (Work S5).
- Pay bands, productivity table, raises, caps: per 07 (adopted) and
  Work_System structure.

## 4. Canonical Market Price Model (deterministic)

The 04_Economy formula is canonical (08 mandates it exactly); the daily
supply-ratio tier table in Supply_Demand_System.md is retired. Constants
from 04: 5% max movement per tick, momentum trend weight 60%, price floor
50% of base. 04 states no ceiling, so the Engine Spec's 3.0x ceiling is
adopted. Government intervention cap (1.3x during intervention events) is a
separate mechanism layered above the band, not part of it.

Per tick (every 5 real minutes, server-side, offline-inclusive):

```
S_raw = market-available supply units      (window/state below)
D_raw = units demanded in trailing window  (window below)
S = max(S_raw, 1)                          # zero-supply floor: math is total
D = max(D_raw, 0)

raw    = base_price * (D / S) ^ elasticity
target = clamp(raw, 0.5 * base_price, 3.0 * base_price)

# explicit deterministic momentum (60% prior trend weight):
dir_t  = +1 if target >  P * 1.01
         -1 if target <  P * 0.99
          0 otherwise
M      = clamp(0.6 * M_prev + 0.4 * dir_t, -1, 1)

step     = target - P  if dir_t != 0
           0.02 * M * P  otherwise          # trend drift when balanced
capped   = clamp(step, -0.05 * P, +0.05 * P)
P_next   = clamp(floor_cent(P + capped), 0.5 * base, 3.0 * base)
```

- **Rounding (fixed monetary rule):** all derived money is computed in
  integer cents and **floor-rounded to the cent** exactly once at the final
  assignment; intermediate arithmetic stays unrounded. No banker's rounding
  anywhere.
- **Supply window (state, not flow):** `S_raw` = NPC baseline stock floor +
  active trade-board listing quantities + unsold business shelf stock +
  unsold player stall stock, sampled at tick time.
- **Demand window (flow):** `D_raw` = units purchased or consumed in the
  trailing **24 real hours** (144 ticks), each event counted **exactly
  once**: a market/business/board purchase counts at sale; consuming stored
  inventory does *not* re-count; direct player-to-player trades count once
  as demand for the sold item; NPC baseline adds a fixed demand floor.
- Zero supply cannot persist for any listed item because the NPC baseline
  floor keeps S_raw >= 1; with D = 0 the ratio path drives price to the 0.5x
  floor. Both branches are defined; no NaN/inf possible.
- **Manipulation thresholds (04 values canonical):** single buyer >30% of an
  item's supply = hoarding flag/review; single entity >50% = Government
  Intervention Event capping that item at **130% of base for 5 in-game
  days**; listing >200% of current market price = gouging review.
  Supply_Demand's 60% cornering figure is superseded (intervene earlier).

## 5. Financial Instrument Mechanics

- **Savings interest (0.5%/cycle):** applied once per 24 h cycle at the
  boundary. **Basis:** the balance *at cycle start*, before any accrual or
  in-cycle mutation; credited amount = `floor_cent(B_start * 0.0050)`. If
  the balance fell below B_start at any time in the cycle, the cycle earns
  nothing (Banking S1 forfeit rule). Accrual is recorded pre-mutation so
  interest never compounds on a partially-updated balance.
- **Loans:** flat rate over term; daily installment =
  `floor_cent(principal * (1 + rate) / term_days)`; last installment absorbs
  the remainder so total repaid is exact. No continuous exponent formula
  (Engine Spec's `(1+r)^(h/24)` is retired — contradicted the player-facing
  flat-rate rules).
- **Fixed deposits:** term/rate from 04's published range: 7-day FD at
  **1%**, 30-day FD at **2%**, paid at maturity on the deposit principal
  (`floor_cent`); early withdrawal: penalty 1%, no interest. (Resolves
  04 "1-2%" vs Banking "3% on 7-day maturity" in favor of the chapter.)
- **Rent grace:** 12 real hours past due; unpaid after grace = eviction to
  Tier 0, +2 stress, -5 Rep, re-let via Property Broker.
- **Insurance premium lapse:** coverage inactive until next paid cycle
  (Insurance.md rules unchanged).

## 6. Storage Model: three independent containers

All three are bounded; none is unlimited. Capacities marked `[provisional]`.

| Container | What it holds | Capacity |
|---|---|---|
| Carried inventory | portable items on the player | 20 food / 15 medicine / 10 goods / 5 equipment slots, stacks per Inventory S2, backpack upgrades per list. **Unchanged.** |
| Home storage container | portable items stored inside a home | **Tier 2: 150 units; Tier 3 (apartment): 300; Tier 4 owned apartment/house/mansion: 300/600/1200 units** `[provisional]` (1 unit = 1 item quantity; unlimited stacking within unit budget). Tier 0/1: none. |
| Bank locker | goods-category items only | **30 units** `[provisional]`, 30 coins / 7 in-game days |

- **Floor footprint is independent of storage capacity.** Large furniture is
  house-bound and occupies *floor cells* of the home; placing furniture
  never consumes storage units. Cell budgets `[provisional]`: Tier 2: 24,
  Tier 3: 40, owned apartment: 40, house: 80, mansion: 160. Bed: 4 cells,
  wardrobe: 6, closet: 3, kitchen set: 8, sofa: 4, desk: 3. No fractional or
  ranged footprints are allowed in item data (the earlier "appliances
  10-25" is replaced by per-item cell counts authored per item).
- **Rest requires a bed in the home. Tier 1 Room Rentals include a
  landlord-provided bed** (rest available at 50% recovery efficiency, no
  storage) — consistent with Housing S2. Tier 2+ players must place a bed
  themselves (purchase, furniture, footprint applies). Rest is **rate-based**
  (idle recovery 5% energy per 2 real minutes x tier efficiency); the
  archived note's 10-second instant recharge is retired — instant full
  recharge would delete the food/energy economy.
- "Unlimited home storage" (Inventory S4) is retired: it made carry limits,
  the pawn shop, and locker fees decorative.

## 7. World Persistence and Ownership Invariants

Per approved direction and shared with
[../specs/frontend/3D_Frontend_Production.md](../specs/frontend/3D_Frontend_Production.md):

- **WP-1 (Single shared world):** one persistent world; no instanced
  personal lobbies. Interiors (homes, shops, hospitals) are shared world
  spaces linked to a physical location. Server partitioning for rendering
  ("render chunks") is an implementation detail and must never fragment
  gameplay identity, ownership, prices, or economy state.
- **WP-2 (Persistent addresses):** every housing/business unit has a stable
  server-assigned address and unit ID (district -> lot -> building -> unit),
  independent of any cosmetic world seed; art reworks restyle facades and
  never re-number ownership. The city is finite and author-expandable;
  districts and lots are curated content, not procedural stock.
- **WP-3 (Housing supply is physical):** enough housing exists through
  multi-unit structures (apartment buildings with per-unit leases); room
  rentals are rooms inside buildings. No private copy of a house per player.
- **WP-4 (No fake stock):** the client never renders or claims an
  ownership, lease, availability, or stock state the server has not
  granted; optimistic UI previews must be marked as such and revalidated.
- **WP-5 (Finite harvestable resources):** natural resource nodes (timber,
  clay, fiber, forage) carry finite server-side stocks. Harvest decrements
  server stock; **regeneration happens only via server growth ticks** at a
  fixed per-node-type rate. Decorative and protected trees (parks, street
  trees, authored landmarks) are **not harvestable at all**. Rendered node
  state derives from server stock; stock 0 shows the server depleted state.
- **WP-6 (Authoritative leases):** rent obligations, 12 h grace, eviction,
  deposits, and transfers are server facts with event logs; the frontend
  displays them and cannot create them.

## 8. Implementation Invariants

- **IN-1:** all quantities (coins, energy, health, stress, reputation,
  prices, stocks, leases, container contents) are server-computed and
  persisted; clients submit intents.
- **IN-2:** money is integer cents internally (1 coin = 100 cents in
  examples); floor-cent rounding per section 4.
- **IN-3:** `players.energy_bars` keeps its 0-5 CHECK; temporary boosts live
  in a separate `bonus_bars` column (section 3.4) — never stored in
  `energy_bars`.
- **IN-4:** purchases, lease payments, claims, and harvests carry
  client-generated idempotency keys; retries never double-apply.
- **IN-5:** tick order is the Engine Spec's order; every formula in this
  file is total over all legal states (floors/caps defined at every
  boundary: zero supply, zero demand, clamp collisions, final-installment
  remainder).
- **IN-6:** all day-clock boundaries are UTC `TIMESTAMPTZ` arithmetic, not
  per-player local days.

## 9. Conflict Resolution Matrix

| # | Conflict | Competing sources | Canonical resolution | Rationale |
|---|---|---|---|---|
| 1 | Day length | 05 "1 day = 24 real h" vs Health.md "(2h real) (1 in game day)" | One wall clock; day = 24 h; **health decay stays 5% per 2 real hours** — the erroneous day-equivalence is deleted, not converted | 05 is the v2.0 universal rule; Health's rate was a parenthetical labeling error; magnitude preserved exactly |
| 2 | Price cadence + formula | 04/Spec "5-min tick + elasticity formula" vs S&D "daily tier table" | Section 4 formula, 5-min tick; tier table retired | 08 mandates 04's constants "exactly as specified"; one continuous model with defined windows |
| 3 | Momentum | 04 "max 5%/tick, 60% trend weight" (vague) vs Spec "0.4 smoothing" | Explicit momentum recurrence in section 4: 60% prior direction retained; smoothing realized as 5%/tick cap; 0.4 pull inside `target-P` step | Deterministic reading of 04's intent; no silent numeric drift |
| 4 | Price ceiling | S&D 2.0x band vs Spec 3.0x; 04 silent on ceiling | 0.5x floor (04) .. 3.0x ceiling (Spec); intervention cap 1.3x separate | User directive: 04 has no ceiling, so Spec's 3.0x; S&D's 200% retained only as the gouging-review listing threshold |
| 5 | Zero supply/demand | formula undefined at S=0 | S floor 1 unit; D floor 0; NPC baseline keeps real supply >= 1 | Totality of the model |
| 6 | Supply/demand windows | S&D "last period"; spec "track by item"; unspecified 24h EMA | Supply = tick-time market-available stock state; demand = trailing 24 real hours, each event counted once; consumption of already-purchased goods never re-counts | Removes double-counting and undefined windows |
| 7 | Rounding | unspecified everywhere | integer cents, single floor-round at final assignment | Fixed monetary rounding |
| 8 | Interest math | Spec `(1+r)^(h/24)` vs Banking daily discrete | Discrete daily, basis = pre-mutation cycle-start balance, floor-cent | Banking rules are the player-facing promise; continuous form broke the forfeit rule |
| 9 | FD rate | 04 "1-2%" vs Banking "3% on maturity" | 1% (7-day) / 2% (30-day) per 04 range | Numbered chapter preference for magnitudes |
| 10 | Insurance premiums/coverage | Insurance.md 60/120/200, 30/40/60, 10/20/40 vs 04+07 60/100/150, 30/45/60, 10/20/30 | **60/100/150; hospital 40/60/80; clinic 30/45/60; pharmacy 10/20/30** | 04 and 07 agree with each other (2 sources, newer); Insurance.md updated to match |
| 11 | Job pay bands | Work doc 30-60..250-500 vs 07 30-50..180-250 | 07 bands | Chapter preference for magnitudes |
| 12 | Shift energy | Work S7 "1.5 flat" vs per-workplace 0.5/1.5/2 vs 07 "1 bar" | Flat 1 bar/shift at completion; no time/step drain during shift | Chapter magnitude; per-workplace overrides retired |
| 13 | Work stress gate | 05 "stress <9" vs Work S3 (pay cut + office block only) | **Gate retained: stress <9 to start shifts** (with S3 pay bands applying below 9 too); recovery channels (dhaba refuge, library, meds) keep it escapable | User directive; S3 reductions are the in-band pressure, the gate is the wall; 02/05 state it |
| 14 | Food prices/effects | Food.md (40-180, blanket +0.6/-0.7) vs 07 (2-40, per-item +1..+8/-0.5) | 07 table exactly for shared items incl. their per-item effects; Food.md-only items keep Food.md prices with +0.6/-0.7 fallback (section 3.3) | Chapter preference; Food.md's blanket values survive only as fallback. Conversion rule 5/items is consistent in both |
| 15 | Auto-hospitalization | Health.md "<10% auto-sent to hospital" vs Healthcare critical state + Illness trigger + insurance activation rule | Retired; player acts; emergency-on-account + welfare prevent softlock | Auto-rescue breaks the lesson and the insurance gate |
| 16 | Housing rents / eviction clock | Housing_System 40/80/150 + 12 h grace vs note 120/300/700 + 48 h lockout | Housing_System values (match 05/07); grace 12 real hours | Owner + chapter agreement; note replaced |
| 17 | Rest | note "10 s fixed restore by type" vs idle-recovery efficiency model | Rate-based rest at a bed (section 6); tier 1 has landlord bed | Instant recharge deletes the energy/food economy |
| 18 | Home storage | Inventory S4 "unlimited" vs note space-based capacity | Bounded containers + independent floor cells (section 6) | Preserves pawn/locker/carry economics; realizes note's space idea without unbounded value |
| 19 | Clothing costs/durability | 07 50/150/300/600, 15-30 days vs Commerce 100/300/600/1200, 10-45 days | **Commerce table** | The two tables share no row names (cost overlap coincidental); Commerce is the item-economy owner with the full mechanic (durability, laundry, entry dress codes); 07 aligned to it |
| 20 | Manipulation thresholds | 04 30%/50% vs S&D 60% | 30% flag, 50% intervention @ 1.3x/5 days | 04 preference; earlier trigger keeps event reachable |
| 21 | SHG size | Banking "group of 5" vs 06 + social layer "3-6" | 3-6 | Chapter + owner agree; exactly-5 makes formation brittle |
| 22 | Business revenue | 07 fixed "Daily Revenue" vs Business doc player-driven revenue | Player-driven; 07 column is design-target only | Fixed revenue contradicts the core pillar and the owner's mechanics |
| 23 | Business eligibility | 03 milestone "FHS 60+ unlocks business" vs prereq table | Prereq table is the hard gate; FHS 60+ is pacing guidance | Owner table is the gate; 03 aligned |
| 24 | Tax scale | Gov brackets "daily income" vs weekly settlement vs monthly filing | Brackets evaluated on daily income; weekly deduction = sum of daily bracketed tax; monthly filing | Only reading where both tables stay true; deterministic |
| 25 | Temporary bars vs schema | Food +1/+2 bars vs `energy_bars BETWEEN 0 AND 5` | `bonus_bars` column (IN-3), rules in 3.4 | Preserves both |
| 26 | Postgraduate vs specialization rows | Education ladder level 4 "1200/45 min" vs College table specializations "400/3 sessions" | Two distinct programs: **Postgraduate/Skill** (ladder level 4) = 1200 coins, 45 min, 5 sessions `[provisional]`; **Specializations** (Finance/Healthcare/Business, post-degree) = 400 coins, 3 sessions; only specializations carry pay effects. 07 lists both | Table label collision, not a value conflict |
| 27 | Enrollment stress restore | Education S4 "returns to pre-enrollment level" | Completion removes exactly the +1 applied at enrollment (floor 1); stress changes incurred during the course persist | Whole-state restore would silently erase events (bills, dining, illness) that happened mid-course |
| 28 | Claim processing | Insurance.md "processed immediately" vs Claim Center "file within 12 h, process 5 min" | Claim Center owns the process: manual filing, 12 h window, 5 real-min processing. Medical-bill stress applies when the **bill** passes its 24 h due time, not while a timely filed claim is pending. Batched pharmacy claims share the 24 h batch window, but a batch is only valid if every purchase in it is still within its own 12 h expiry | Owner detail beats the summary line; pending-claim stress would punish exactly the compliant player |
| 29 | Appeal fee | "non-refundable" vs "refunded on approval" | Fee paid upfront; **not returned on denial; refunded on approval** — same rule stated identically in both places | Consistent reading of the two sentences |
| 30 | Medication plan durations | Plans' "recovery duration" vs implied last-dose times | Dosing convention: **first dose at t=0** (at plan start), then every interval; plan duration >= max last-dose time. Published plans are consistent under this convention (hospital full: antibiotics last at 24 min, tablets at 20 < 30) | t=0 is the only convention where every listed duration holds |
| 31 | Tutorial rent timing | 02_Journey "first rent due in 24 h" vs "3 days free" | Free trial: rent starts accruing after day 3; the tutorial notification is an informational preview ("first rent will be due on day 4") | Removes contradiction, keeps the teaching beat |
| 32 | Tutorial price spike | 02_Journey scripted "+10% market prices" vs 5%/tick cap | Scripted tutorial events are supply/demand modifiers entering the price engine — never direct price writes; a +10% target is reached over >= 2 ticks | Preserves the single model (§4, IN-5) |
| 33 | Advisor savings-rate line | 02_Journey "savings rate below 10% means spending more than you earn" | Savings rate 0-10% = thin margin; only a **negative** rate means spending exceeds income | Arithmetic correctness |
| 34 | Day-7 milestone vs loan rules | 02_Journey "deposit 50 coins: unlocks loan eligibility" vs Banking S2 (account >= 3 days, balance >= 100) | The milestone grants interest accrual and starts the 3-day account clock; loan eligibility remains Banking S2's conditions | A tutorial milestone cannot waive the owner's gate |
| 35 | Healthcare price/restore table | 07's merged 3-row table (clinic 300/10 min/+30%, hospital +50%/+70%, 20/30 min) vs Healthcare System.md (clinic 80/150/350 at 2 min, +10/15/35%; hospital 300/700/1200 at 5 min, +30/60%/to-100) | Healthcare System.md owns treatment services; 07 aligned to the owner. Durations are server timers that run offline (§2) | Owner defines the full medication-plan mechanics these prices feed; 07's rows collapsed two distinct facility catalogs |
| 36 | Crisis trigger wording | 02 "Health < 10%", 01_Loop "below 10%", Health/Healthcare/Illness various | Critical state is **health <= 10%** everywhere; work gate remains **health > 10%** (i.e. blocked at <=10) | Single boundary convention; no value change |

## 10. Balance-Table Ownership Map

| Value family | Owner (live table) | Consumers (link, never restate differently) |
|---|---|---|
| Time model, eligibility | **this file** | all |
| Price model + windows + rounding | **this file** + Economy_Engine_Spec (implementation mirror) | 04, Supply_Demand_System, 08 |
| Survival drift rates | Health.md / Stress.md / Energy.md (within this file's constants) | 02, 05, 01_Core_Gameplay_Loop, 02_Player_Journey |
| Food items | **this file 3.3** (07 magnitudes) with Food.md structure | 07, Energy.md, Commerce |
| Insurance plans | **this file 9#10** mirrored in Insurance.md | 04, 07, Illness_State, Claim Center, API spec |
| Jobs/wages/shifts | 07 bands + Work_System structure | 02, 03, 05, Multiplayer job board |
| Education ladder | Education_System.md | 03, 07 |
| Housing economics | Housing_System.md (rents/grace/rest per this file) | 05, 07, 03, Banking |
| Storage capacities | Inventory_System.md + **this file 6** | 05, 07 |
| Reputation scale | Social_Reputation_System.md | all |
| Tax/welfare | Government_Legal_System.md | 04, 07 |
| Event catalog | reference/03_Events_System.md | 04, 07 |

A change to an owned number happens in the owner first; consumer documents
are updated in the same change set.

## 11. Status and Scope Separation

- Full simulation (this rule set, 24 systems, single persistent world)
  remains the product target.
  shared 5-min market ticks, trade board, one job ladder, bank + loans,
  graduation attestation; no real-time co-presence. The demo reads the same
  canonical tables; nothing here blocks the subset.
- `[provisional]` values (home/locker capacities, floor cells, boost
  durations, postgrad session count) require a balance pass and carry no
  shipping verification claim.

### Truly open ambiguities (no source answers; flagged, not decided)

1. Exact NPC baseline supply/demand floors per item (04 requires floors but
   publishes none).
2. Interest/rounding of sub-cent installment remainders is defined (last
   installment absorbs), but the **order of daily deductions** when rent,
   premium, loan, and telecom all fall due in the same hour is unspecified;
   proposed: fixed priority rent > loan > premium > telecom > other
   `[decision-needed]`.

## References
- [02_Core_Gameplay.md](02_Core_Gameplay.md) - verbs (08-mandated)
- [04_Economy_Design.md](04_Economy_Design.md) - price constants source
- [05_Systems_Map.md](05_Systems_Map.md) - day rule + thresholds
- [07_Content_Design.md](07_Content_Design.md) - magnitude tables
- [../specs/economy/Economy_Engine_Spec.md](../specs/economy/Economy_Engine_Spec.md) - implementation mirror
- [reference/00_INDEX.md](reference/00_INDEX.md) - navigation
