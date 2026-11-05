---
tags: [gdd, systems, architecture, dependencies]
date: 2026-05-07
version: 2.0
aliases: [Systems Map, System Architecture]
---

# Systems Map

## System Categories

### Core Survival Systems
Systems that govern player physical state. Must be implemented first.

| System | Purpose | Key Mechanics |
|--------|---------|---------------|
| [[reference/systems/Energy\|Energy]] | Physical capacity | 5 bars, 200 steps/bar, 15 min/bar, idle recovery |
| [[reference/systems/Health\|Health]] | Physical wellbeing | 0-100%, decays 5%/2 real hrs, affects work/productivity |
| [[reference/systems/Stress\|Stress]] | Mental pressure | 1-12 levels, accelerates decay, reduces pay |
| [[reference/systems/Food\|Food]] | Energy recovery | Natural vs Fast, energy values, health effects |

### Economic Systems
Systems that govern money, prices, and transactions.

| System | Purpose | Key Mechanics |
|--------|---------|---------------|
| [[reference/systems/Work_System\|Work System]] | Income generation | Job tiers, shifts, pay modifiers, education requirements |
| [[reference/systems/Banking_Finance_System\|Banking & Finance]] | Money management | Savings, loans, investments, pawn shop |
| [[reference/systems/Commerce_System\|Commerce]] | Purchasing | Retail locations, clothing tiers, electronics |
| [[reference/systems/Supply_Demand_System\|Supply & Demand]] | Price mechanics | Market prices, supply/demand ratio, price momentum |
| [[reference/systems/Business_Ownership_System\|Business Ownership]] | Entrepreneurship | Business types, revenue, employees, growth |
| [[reference/systems/Player_Trade_System\|Player Trade]] | Player exchange | Direct trade, market listings, player lending |
| [[reference/systems/Financial_Dashboard\|Financial Dashboard]] | Progress tracking | Health score, expense breakdown, net worth, advisor |

### Social Systems
Systems that govern player-to-player interactions.

| System | Purpose | Key Mechanics |
|--------|---------|---------------|
| [[reference/systems/Multiplayer_Social_Layer\|Multiplayer Social]] | Player infrastructure | Profiles, friends, chat, job board, SHG groups |
| [[reference/systems/Social_Reputation_System\|Social Reputation]] | Community standing | 0-100 scale, 5 tiers, affects access and rates |

### Support Systems
Systems that provide services and infrastructure.

| System | Purpose | Key Mechanics |
|--------|---------|---------------|
| [[reference/systems/Housing_System\|Housing]] | Living situation | 5 tiers, rent/mortgage, rest quality, storage |
| [[reference/systems/Healthcare System\|Healthcare]] | Medical treatment | Hospitals, clinics, pharmacy, medication plans |
| [[reference/systems/Insurance\|Insurance]] | Risk management | 3 plans, premiums, coverage, claims |
| [[reference/systems/Insurance_Claim_Center\|Insurance Claims]] | Claims processing | Filing, processing, appeals, fraud prevention |
| [[reference/systems/Education_System\|Education]] | Qualifications | 5 levels, sequential, unlocks jobs |
| [[reference/systems/Government_Legal_System\|Government & Legal]] | Civic systems | Taxes, welfare, permits, court, police |
| [[reference/systems/Transport_Infrastructure_System\|Transport]] | Movement | Walking, bus, train, telecom/internet |
| [[reference/systems/Inventory_System\|Inventory]] | Item management | 4 carry categories, 50 slots, expiry; home/locker storage bounded (see Canonical Rules §6) |
| [[reference/systems/Restaurant_Dhaba_System\|Restaurants]] | Dining | 4 tiers, stress relief, reputation gain |
| [[reference/systems/Illness_State\|Illness]] | Severe consequence | Triggers, effects, cure path, frequency cap |

---

## System Dependencies

### Dependency Graph
```
Energy ← Health, Stress, Food, Housing
Health ← Stress, Food, Healthcare, Illness
Stress ← Work, Housing, Events, Illness
Work ← Energy, Health, Stress, Education
Banking ← Work, Government, Reputation
Commerce ← Supply/Demand, Inventory
Supply/Demand ← Commerce, Work, Business, Events
Business ← Banking, Work, Reputation, Government
Multiplayer ← Business, Trade, Banking, Reputation
Reputation ← Work, Education, Commerce, Government
```

### Implementation Order

**Phase 1: Foundation (Must be first)**
1. Energy
2. Health
3. Stress
4. Food
5. Inventory

**Phase 2: Core Economy**
6. Work System
7. Banking & Finance
8. Commerce
9. Supply & Demand
10. Housing

**Phase 3: Advanced Economy**
11. Education
12. Government & Legal
13. Insurance
14. Financial Dashboard
15. Business Ownership

**Phase 4: Multiplayer**
16. Multiplayer Social Layer
17. Social Reputation
18. Player Trade
19. Events System

**Phase 5: Depth**
20. Healthcare
21. Insurance Claims
22. Transport
23. Restaurants
24. Illness State

---

## Cross-System Interactions

### Health Cascade
```
Poor Food → Low Energy → Can't Work → No Income → Can't Pay Rent → Eviction → No Rest → Health Decay → Illness → Can't Work → Debt Spiral
```

### Stress Cascade
```
High Stress → Fast Energy Drain → More Food Needed → More Spending → Financial Pressure → More Stress → Reduced Work Pay → Income Drop
```

### Reputation Cascade
```
Consistent Work → Reputation Gain → Better Loan Rates → Education Affordable → Better Job → Higher Income → More Consistency → More Reputation
```

### Market Cascade
```
Player Production → Supply Increase → Price Drop → More Buying → Demand Increase → Price Rise → More Production → Cycle
```

---

## System Rules Summary

### Universal Rules
- All systems operate on real-world time
- 1 in-game day = 24 real-world hours
- Actions consume real time (shifts: 30 min, education: 10-60 min)
- State persists across sessions

### Resource Rules
- Energy: 5 bars, consumed by movement/time, recovered by food/rest
- Health: 0-100%, passive decay, recovered by treatment/natural food
- Stress: 1-12, affected by events/lifestyle, reduced by rest/dining
- Coins: Primary currency, earned/spent/lent/saved

### Threshold Rules
- Work requires: 2+ energy bars (incl. bonus bars), health >10%, stress <9 (see Canonical Rules §3.5; Work S3 pay bands still apply)
- Education requires: sequential completion, upfront payment
- Business requires: Reputation 41+, School Diploma, Permit
- Property requires: Down payment, mortgage qualification

---

## References
- [11_Canonical_Game_Rules.md](11_Canonical_Game_Rules.md) — precedence and canonical tables
- [01_Game_Overview.md](01_Game_Overview.md)
- [04_Economy_Design.md](04_Economy_Design.md)
- [06_Multiplayer_Design.md](06_Multiplayer_Design.md)
- [Full Research Index](reference/00_INDEX.md)
