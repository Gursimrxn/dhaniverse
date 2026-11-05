---
tags: [gdd, economy, simulation, core]
date: 2026-05-07
version: 2.0
aliases: [Economy Design, Economic Simulation]
---

# Economy Design

## Economic Philosophy
Dhaniverse's economy is a **player-driven simulation**, not a fixed-price shop system. Prices emerge from collective behavior. Supply comes from player production. Demand comes from player consumption. The economy is the game.

---

## Economic Architecture

### Core Economic Loop
```
Production → Supply → Market Price ← Demand ← Consumption
     ↑                                          ↓
   Players                                  Players
     ↑                                          ↓
   Income ←── Work/Business ──→ Spending
```

### Money Flow
```
NPC Jobs → Player Wallet → Player Spending → Other Players / NPC Sinks
                  ↑                              ↓
              Bank Loans ←── Bank Savings ←── Bank Deposits
```

**Money Sources (Injection):**
- NPC job payments (primary)
- Bank loan disbursements
- Welfare benefits
- Event rewards

**Money Sinks (Extraction):**
- Rent payments
- Tax payments
- NPC vendor purchases (base cost portion)
- Permit and license fees
- Court fines and penalties
- Insurance premiums (NPC portion)

---

## Supply & Demand Engine

### Price Model
Every tradeable item has:
- **Base Price** — The theoretical value at equilibrium
- **Market Price** — The actual price, driven by supply/demand ratio
- **Price Momentum** — Rate of change; prices drift, don't snap

### Supply Generation
Supply comes from:
- **Player Production:** Farm output, factory goods, business products
- **Player Listings:** Trade Board items for sale
- **NPC Baseline:** Minimum supply floor to prevent total scarcity

### Demand Generation
Demand comes from:
- **Player Consumption:** Food eaten, medicine used, items equipped
- **Player Purchases:** Market and shop buying
- **NPC Baseline:** Minimum demand floor for economic activity

### Price Movement Rules

The canonical deterministic model (windows, zero-supply floors, rounding,
explicit momentum) lives in
[11_Canonical_Game_Rules.md §4](11_Canonical_Game_Rules.md) and is mirrored by
[Economy_Engine_Spec.md](../specs/economy/Economy_Engine_Spec.md):

```
Market Price = Base Price × (Demand / max(Supply,1)) ^ Elasticity

Where:
- Elasticity varies by item category (food: 0.8, medicine: 0.3, luxury: 1.5)
- Price changes are smoothed (max 5% movement per tick)
- Momentum carries recent direction (60% weight to trend), realized as the
  explicit momentum recurrence in Canonical Rules §4
- Band: 50% floor (this chapter) to 3.0× ceiling (Engine Spec); the 1.3×
  intervention cap during Government Intervention Events is separate
```

### Market Ticks
- Economy recalculates every 5 real-world minutes
- Each tick: update supply, demand, prices for all items
- The daily supply-ratio tier table from the reference draft is retired;
  Supply_Demand_System.md links this model
- Players see price changes via market UI and notifications

---

## Item Categories & Elasticity

| Category | Elasticity | Volatility | Reason |
|----------|-----------|------------|--------|
| Basic Food | 0.8 | Medium | Essential, some substitution possible |
| Luxury Food | 1.5 | High | Discretionary, highly price-sensitive |
| Medicine | 0.3 | Low | Essential, inelastic demand |
| Clothing | 1.2 | Medium | Semi-discretionary, status-driven |
| Electronics | 1.8 | High | Luxury, highly elastic |
| Raw Materials | 1.0 | Medium | Production input, derived demand |

---

## Financial Instruments

### Banking (owner: [Banking_Finance_System.md](reference/systems/Banking_Finance_System.md))
- **Savings Accounts:** 0.5% applied once per in-game day, discrete, on the
  pre-mutation cycle-start balance — not continuous compounding
- **Fixed Deposits:** minimum 500 coins; 1% on a 7-day term, 2% on a 30-day
  term, paid at maturity (this chapter's 1-2% range resolves the older
  reference draft's 3%)
- **Loans:** flat-rate over term, fixed daily installment; personal 8%,
  mortgage 5%, microfinance 6%/10%
- **Credit Score:** Derived from repayment history, affects future rates

### Insurance (owner: [Insurance.md](reference/systems/Insurance.md))
- **Health Insurance:** 3 plan tiers (Basic/Standard/Premium)
- **Premiums:** 60/100/150 coins per in-game day
- **Coverage hospital/clinic/pharmacy:** 40/30/10, 60/45/20, 80/60/30 %
- **Claims:** Must file within 12 in-game hours of treatment

### Player Lending
- **Direct Loans:** Player-to-player, negotiated terms
- **Interest:** Unrestricted (market-determined)
- **Enforcement:** Reputation penalty + court system
- **Risk:** Default damages both parties differently

### Microfinance (SHG)
- **Group Formation:** 3-6 players
- **Savings Circle:** Rotating pool access
- **Group Loans:** Joint liability, peer pressure enforcement
- **Social Capital:** Trust built through participation

---

## Market Manipulation & Controls

### Detection Mechanisms
- **Hoarding Detection:** Single player buying >30% of item supply triggers flag
- **Price Gouging:** Listing items >200% of market price triggers review
- **Market Cornering:** Controlling >50% of item supply triggers intervention

### Government Intervention
- **Price Controls:** Temporary price caps during crisis events
- **Supply Release:** Government stock release during shortages
- **Fines:** Penalties for proven manipulation
- **Audits:** Random tax and market audits

---

## Economic Events

### Supply Shocks
- Drought: Food supply -40% for 3 days
- Transport Strike: All supply -20% for 2 days
- Factory Fire: Manufactured goods -30% for 2 days

### Demand Spikes
- Disease Outbreak: Medicine demand +60% for 5 days
- Festival: Food/clothing demand +30% for 2 days
- Heat Wave: Cold drinks demand +40% for 3 days

### Economic Policy
- Tax Holiday: Tax rate -50% for 3 days
- Interest Rate Cut: Loan rates -1% for 7 days
- Subsidy: Essential goods supply +40% for 3 days

---

## Macro-Economic Indicators

### Tracked Metrics
- **Money Supply (M0):** Total coins in circulation
- **Velocity of Money:** Transactions per coin per day
- **Inflation Rate:** Average price change across basket
- **Gini Coefficient:** Wealth inequality measure
- **Employment Rate:** % of players working vs. idle
- **GDP:** Total value of all transactions

### Dashboard
- Available to all players (transparency)
- Historical trends (7-day, 30-day)
- Event impact analysis
- Personal position vs. averages

---

## Economic Balance Rules

### Anti-Inflation Controls
- Money sinks must exceed money sources by 5-10%
- NPC job payments capped per player per day
- Loan interest extracts money from economy
- Tax system removes coins from circulation

### Anti-Deflation Controls
- Minimum price floor (50% of base price)
- NPC baseline demand prevents total collapse
- Welfare system injects money during hardship
- Event rewards add coins during special periods

### Wealth Inequality Management
- Progressive tax brackets (0-20%)
- Welfare benefits for low-income players
- Reputation advantages for consistent (not just wealthy) players
- Multiple success dimensions on leaderboard

---

## Implementation Architecture

### Economy Engine (Server-Side)
```
EconomyEngine
├── SupplyTracker — Tracks all item supply sources
├── DemandTracker — Tracks all item demand sources
├── PriceCalculator — Computes market prices each tick
├── EventManager — Triggers and resolves economic events
├── MarketMonitor — Detects manipulation patterns
└── IndicatorCalculator — Computes macro-economic metrics
```

### Data Flow
```
Player Actions → Action Log → Economy Engine → Price Updates → Player UI
                                     ↓
                              Macro Indicators → Dashboard
```

---

## References
- [11_Canonical_Game_Rules.md](11_Canonical_Game_Rules.md) — price model, precedence
- [01_Game_Overview.md](01_Game_Overview.md)
- [05_Systems_Map.md](05_Systems_Map.md)
- [Supply & Demand System](reference/systems/Supply_Demand_System.md)
- [Banking & Finance](reference/systems/Banking_Finance_System.md)
- [Player Trade](reference/systems/Player_Trade_System.md)
- [Events System](reference/03_Events_System.md)
