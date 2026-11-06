---
tags: [spec, economy, engine, backend]
date: 2026-05-07
version: 2.0
aliases: [Economy Engine, Backend Spec]
---

# Economy Engine Specification

## Overview
The Economy Engine is the server-side system that simulates the game's economy. It processes player actions, calculates market prices, manages financial instruments, and tracks macro-economic indicators.

---

## Core Responsibilities

### 1. Price Calculation
- Compute market prices for all tradeable items every 5 minutes (single
  shared server clock; ticks run while players are offline)
- Apply the canonical elasticity model with defined supply/demand windows
  and zero-supply floors (see section below and
  [11_Canonical_Game_Rules.md §4](../../design/11_Canonical_Game_Rules.md))
- Smooth price changes with the explicit momentum recurrence (max 5% per tick)
- Maintain price history for trend analysis

### 2. Supply Tracking
- Aggregate supply from: player production, trade listings, NPC baseline
- Track supply by item, zone, and source
- Detect supply anomalies (hoarding, cornering)

### 3. Demand Tracking
- Aggregate demand from: player purchases, consumption, NPC baseline
- Track demand by item, zone, and consumer type
- Detect demand anomalies (spikes, manipulation)

### 4. Financial Processing
- Process all transactions (purchases, sales, transfers)
- Calculate and apply interest (savings, loans)
- Manage loan lifecycle (issuance, repayment, default)
- Process insurance claims and payouts

### 5. Event Management
- Trigger random economic events on schedule
- Apply event effects to supply/demand
- Resolve events and restore baseline
- Track event history and impact

### 6. Macro Tracking
- Calculate money supply, velocity, inflation
- Track wealth distribution (Gini coefficient)
- Monitor employment and GDP
- Generate economic reports

---

## Data Models

### Item
```
id, name, category, base_price, elasticity, current_supply, current_demand, market_price, price_momentum, last_updated
```

### Transaction
```
id, type (buy/sell/transfer/interest/fee), from_player, to_player, item_id, quantity, price_per_unit, total, timestamp
```

### Loan
```
id, borrower, lender (player or bank), principal, interest_rate, term, remaining, status (active/paid/defaulted), payment_schedule, missed_payments
```

### EconomicEvent
```
id, type, severity, start_time, duration, affected_categories, supply_modifier, demand_modifier, status (active/resolved)
```

### MacroSnapshot
```
timestamp, money_supply, velocity, inflation_rate, gini_coefficient, employment_rate, gdp, active_players
```

---

## Calculation Formulas

Canonical source: [11_Canonical_Game_Rules.md §4-5](../../design/11_Canonical_Game_Rules.md). Implementation mirrors it exactly.

### Market Price
```
S = max(current_supply, 1)                 # zero-supply floor; NPC baseline
                                           # keeps real supply >= 1 anyway
D = current_demand                         # units purchased/consumed in the
                                           # trailing 24 real hours, each
                                           # event counted exactly once
target = clamp(base_price * (D / S) ^ elasticity, 0.5 * base_price, 3.0 * base_price)

dir  = +1 if target > price * 1.01
       -1 if target < price * 0.99
        0 otherwise
M    = clamp(0.6 * M_prev + 0.4 * dir, -1, 1)     # momentum, 60% trend weight

step   = target - price    if dir != 0
         0.02 * M * price  otherwise
step   = clamp(step, -0.05 * price, +0.05 * price) # max 5% per tick
price  = clamp(floor_cent(price + step), 0.5 * base_price, 3.0 * base_price)
```
- Rounding: integer cents; floor-to-cent exactly once at final assignment.
- The former `new = old + (calc - old) * 0.4` smoothing line is superseded
  by the recurrence above (same intent, now deterministic at the bounds);
  the 2.0x band from the reference draft was retired in favor of
  0.5x-3.0x (floor from Economy Design, ceiling from this spec); the 1.3x
  Government Intervention cap is a separate event mechanism.

### Financial Processing
```
Savings (0.5%/cycle): at each 24h boundary, if balance never dropped below
  the cycle-start balance B: credit floor_cent(B * 0.0050); basis is
  pre-mutation B. Partial or drawn-down cycles earn nothing (S1 forfeit).
Loans: flat rate over term; daily installment =
  floor_cent(principal * (1 + rate) / term_days); final installment absorbs
  the remainder. (Continuous (1+r)^(h/24) compounding is retired — it
  contradicted the player-facing flat-rate and forfeit rules.)
Insurance payout: payout = medical_bill * coverage_percentage
                  player_pays = medical_bill - payout
                  (both floored to cent at settlement)
```

### Tax Calculation
```
daily_tax(d)  = bracketed_tax(income_on_day_d)   # 0-20% bracket table
weekly_deduct = sum(daily_tax over 7 days)       # automatic deduction
monthly filing reconciles the record (Government_Legal_System S3/S4)
```

---

## Tick Processing Order

1. Collect all player actions since last tick
2. Update supply levels (production, listings, expiry)
3. Update demand levels (consumption, purchases)
4. Calculate new market prices
5. Process financial transactions (interest, payments)
6. Check for market manipulation
7. Trigger/update/resolve events
8. Calculate macro indicators
9. Broadcast updates to clients

---


## Performance Requirements
- Tick processing: < 500ms for 500 players (design target, unmeasured)
- Price updates: broadcast within 1 second
- Transaction processing: atomic, immediate confirmation
- Event triggering: scheduled, no drift
---

## References
- [[../../design/04_Economy_Design|Economy Design]]
- [[../../design/reference/systems/Supply_Demand_System|Supply & Demand]]
- [[../../design/reference/systems/Banking_Finance_System|Banking & Finance]]
