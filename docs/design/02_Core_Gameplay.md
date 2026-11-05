---
tags: [gdd, gameplay, core-loop, ux]
date: 2026-05-07
version: 2.0
aliases: [Core Gameplay, Game Loop]
---

# Core Gameplay

The loops and session structure below describe recurring decisions, not a
mandatory task sequence. [Player choices and consequences](14_Player_Choices_And_Consequences.md)
defines the next milestone: independent eligible actions, different priorities
and connected outcomes with feasible recovery.

## Primary Loop

Moment-to-moment play comes from enjoyable minigames and tasks within the shared
world. Repetition supports skill, earnings and self-chosen progression goals.
Decisions about the resulting resources connect that play to budgeting, personal
finance and later opportunities. Design the activity, its progression and its
economic connections together; actual rewards still follow their rule owners.

```
MANAGE → EARN → SPEND → PLAN → (repeat)
```

### MANAGE: Survival Layer
Monitor and maintain three core resources:
- **Energy** (5 bars) — Capacity to move and work. Consumed by walking (200 steps/bar) or time (15 min/bar)
- **Health** (0-100%) — Decays 5% every 2 real hours (shared wall clock; 1 in-game day = 24 real hours). Affects work productivity and energy efficiency
- **Stress** (1-12 levels) — Increases from pressure events. Reduces work pay, accelerates energy drain

**Player Actions:**
- Eat food to restore energy
- Rest at home to recover energy and reduce stress
- Visit hospital/clinic to restore health
- Manage lifestyle to control stress

### EARN: Income Generation
Convert energy and time into coins through work:
- **Job Types:** Street Stall → Farm → Factory → Shop → Office → Manager
- **Requirements:** Education level, >= 2 spendable energy bars, health >10%, stress <9 (Canonical Rules §3.5)
- **Pay Modifiers:** Health level, stress level, clothing tier, reputation

**Player Actions:**
- Choose job based on qualifications and current state
- Complete shifts (30 min real-time)
- Improve qualifications through education
- Build reputation for pay bonuses

### SPEND: Resource Allocation
Distribute earned coins across competing needs:
- **Essential:** Food, rent, medicine
- **Protective:** Insurance premiums, savings
- **Investment:** Education, business capital, property
- **Optional:** Better clothing, dining out, electronics

**Player Actions:**
- Purchase goods at markets (prices fluctuate with supply/demand)
- Pay recurring obligations (rent, insurance, loans)
- Make trade-off decisions between immediate needs and long-term goals

### PLAN: Strategic Decisions
Make forward-looking choices that shape long-term trajectory:
- Save vs. spend vs. invest
- Pursue education vs. maximize current income
- Rent vs. buy property
- Employment vs. business ownership
- Individual vs. group (SHG) financial strategy

**Player Actions:**
- Review Financial Dashboard for health score and trends
- Set savings and investment goals
- Evaluate risk (insurance coverage, emergency buffer)
- Form or join economic groups

---

## Secondary Loops

### Crisis Loop
```
Crisis → Seek Help → Pay Cost → Recover → Return to Normal
```
Triggered by: Health <= 10% (Critical State), Stress >= 9 (shifts blocked; >= 9 also triggers crisis pressure), Illness, Eviction, Loan Default

### Social Loop
```
Find Players → Interact (Trade/Hire/Lend) → Build Reputation → Better Opportunities
```
Triggered by: Player choice to engage multiplayer features

### Business Loop
```
Start Business → Hire/Produce → Sell → Profit → Reinvest/Expand
```
Unlocked at: Reputation 41+, School Diploma, Business Permit

---

## Session Structure

### Typical Session (30-60 minutes)

**Opening (5 min): Assessment**
- Check energy, health, stress
- Review Financial Dashboard
- Note pending obligations (rent due, loan payment, tax deadline)

**Core (20-40 min): Action**
- Complete 1-2 work shifts
- Purchase necessities
- Handle crisis if any
- Optional: social interaction, dining, market trading

**Closing (5-10 min): Planning**
- Deposit coins in bank
- Review financial health changes
- Set goals for next session
- Ensure housing secured (rent paid) before going offline; obligations run on the shared clock, energy does not drain offline

---

## Key Decisions & Trade-offs

| Decision | Option A | Option B | Trade-off |
|----------|----------|----------|-----------|
| Transport | Walk (free, slow, uses energy) | Bus (costs coins, fast, saves energy) | Money vs. Energy |
| Food | Street stall (cheap, energy only) | Restaurant (expensive, +stress relief +rep) | Money vs. Wellbeing |
| Housing | Rent (lower upfront, ongoing cost) | Buy (high upfront, no rent, asset) | Short-term vs. Long-term |
| Work | Job (stable, limited upside) | Business (risky, unlimited upside) | Security vs. Potential |
| Lending | Bank (formal, credit check) | Player (informal, trust-based) | Process vs. Relationship |
| Health | Ignore (save money now) | Treat (cost now, prevent crisis) | Present vs. Future |

---

## Player Agency

### What Players Control
- Job selection and work frequency
- Spending allocation across categories
- Savings rate and investment choices
- Education pursuit and timing
- Housing tier and location
- Social connections and reputation building
- Business creation and management
- Risk management (insurance, emergency funds)

### What Players Don't Control
- Market prices (emerge from collective behavior)
- Random events (drought, disease, festival)
- Other players' decisions
- Government policies (tax rates, welfare rules)
- Time-based decay (health, energy, item expiry)

---

## Feedback Systems

### Immediate Feedback
- Energy bar depletes visibly with movement
- Coin balance updates on transaction
- Health bar shows decay in real-time
- Stress meter changes with events

### Short-Term Feedback
- Pay received after shift completion
- Rent due notification
- Market price change alerts
- Reputation change notifications

### Long-Term Feedback
- Financial Health Score trends (daily/weekly)
- Net worth tracking over time
- Reputation tier advancement
- Leaderboard position changes

---

## References

Operative numbers in this chapter are summaries. The canonical authority for
every value, clock, and threshold is
[11_Canonical_Game_Rules.md](11_Canonical_Game_Rules.md); system owners are
listed in its ownership map.

- [01_Game_Overview.md](01_Game_Overview.md)
- [03_Player_Progression.md](03_Player_Progression.md)
- [Energy](reference/systems/Energy.md)
- [Work System](reference/systems/Work_System.md)
- [Financial Dashboard](reference/systems/Financial_Dashboard.md)
