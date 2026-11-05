---
tags: [gdd, multiplayer, social, networking]
date: 2026-05-07
version: 2.0
aliases: [Multiplayer Design, Social Layer]
---

# Multiplayer Design

## Multiplayer Philosophy
Dhaniverse is not a single-player game with multiplayer features. The economy is inherently multiplayer — prices, supply, demand, jobs, and reputation all depend on other players. The social layer is the economy's nervous system.

---

## World Model

### Single Persistent World
- One world, all players coexist
- No instances, no shards, no lobbies
- Economy is shared across all players
- Player actions affect everyone

### Player Visibility
- Players visible on map in real-time
- Interaction possible when in same zone
- Profile visible to all (limited info)
- Detailed info only for friends

---

## Social Infrastructure

### Player Profile
**Public (All Players):**
- Username
- Days active
- Reputation tier (label only)
- Housing tier (label only)
- Employment status
- Business name (if owner)

**Friends Only:**
- Financial Health Score
- Recent activity

**Private (Never Visible):**
- Wallet/bank balance
- Debt details
- Health/stress specifics

### Friend System
- Send/accept friend requests
- Friends see extended profile
- Priority in trade and job listings
- Direct messaging unlocked

### Blocking
- Block any player
- Blocked players cannot: trade, message, hire
- Blocks are unilateral and immediate

---

## Communication

### Chat Channels

| Channel | Scope | Use Case |
|---------|-------|----------|
| Local Chat | Same map zone | Casual interaction, trade negotiation |
| Direct Message | Friends only | Private deals, lending terms |
| Group Chat | SHG, business teams | Coordination, planning |
| Trade Board | Public, async | Item listings, no chat needed |

### Design Rules
- No global chat (reduces noise)
- Communication is zone and relationship based
- Trade Board is async (no real-time negotiation required)
- All chat is text-based (no voice in initial release)

---

## Economic Interactions

### Player-to-Player Trade
**Direct Trade:**
- Face-to-face at same location
- Both players confirm before exchange
- No fees, instant transfer
- Irreversible after confirmation

**Market Listings:**
- List items on public Trade Board
- Set price, 5-day duration
- 2% fee on successful sale
- Affects supply/demand metrics

**Player Lending:**
- Negotiated amount, rate, schedule
- Auto-deducted from borrower wallet
- Default: reputation penalty + court option
- Creates informal credit market

### Employment
**Job Board:**
- Business owners post job listings
- Wage, shifts, location specified
- Applicants show: reputation, days active, education
- Owner accepts/declines

**Shift Execution:**
- Employee travels to business
- Completes shift per Work System rules
- Owner pays wages (not NPC)
- Post-shift rating (1-5) affects reputation

---

## Group Economics

### Self-Help Groups (SHG)

**Formation:**
- 3-6 players
- Register at Microfinance Office
- One nominates, others confirm

**Savings Circle:**
- Each member contributes 50 coins/24hrs
- Rotating pool access
- Vote to skip non-contributors
- Missed contribution: -1 Rep, +0.5 Stress

**Group Loans:**
- Any member can request
- All members vote to approve
- Joint liability for repayment
- Default: all members +1 Stress, group suspended 5 days

**Dissolution:**
- Leave with 2-day notice
- Must settle share if active loan
- Group vote to dissolve (loans cleared first)

---

## Reputation & Trust

### Reputation as Social Currency
- Visible to all (tier only)
- Affects: loan rates, job access, social events
- Gained: consistency, education, financial reliability
- Lost: defaults, legal issues, public illness

### Trust Mechanics
- Reputation is earned, not bought
- Two players with same coins can have different access
- Trust enables: better rates, priority hiring, exclusive events
- Trust is fragile: defaults hurt more than gains help

---

## Competition & Cooperation

### Leaderboard
**Categories:**
- Wealthiest (Net Worth)
- Most Reputable (Reputation Score)
- Best Business (7-day Revenue)
- Most Stable (Financial Health Score)
- Fastest Climber (Net Worth Growth Rate)

**Design:**
- Top 10 per category shown
- Personal rank always visible
- Multiple dimensions of success
- Wealth ≠ Stability (intentionally visible)

### Community Challenges
- Periodic, optional events
- Examples: savings challenge, business challenge, market challenge
- Rewards: coins + reputation
- Creates shared goals without forced cooperation

---

## Anti-Griefing Design

### Prevention
- Blocking system (immediate, unilateral)
- Trade confirmation required (no auto-accept)
- Reputation cost for cancellations
- No PvP or direct harm mechanics

### Detection
- Trade pattern monitoring
- Lending abuse detection
- Chat harassment reporting

### Response
- Reputation penalties for bad behavior
- Court system for disputes
- Temporary restrictions for repeat offenders
- Permanent bans as last resort

---

## Social Dynamics

### Emergent Behaviors (Designed For)
- Informal credit markets (player lending rates vary by trust)
- Labor markets (business owners compete for good employees)
- Reputation economies (high-rep players become hubs)
- Community support networks (SHG groups as safety nets)
- Market specialization (players find economic niches)

### Social Learning
- Observing successful players' strategies
- Reputation as visible track record
- Leaderboard showing multiple success paths
- Community challenges teaching cooperation

---

## References
- [11_Canonical_Game_Rules.md](11_Canonical_Game_Rules.md) — §7 world-persistence and ownership invariants (single shared world, persistent unit addresses, no instanced lobbies)
- [01_Game_Overview.md](01_Game_Overview.md)
- [04_Economy_Design.md](04_Economy_Design.md)
- [05_Systems_Map.md](05_Systems_Map.md)
- [Multiplayer Social Layer](reference/systems/Multiplayer_Social_Layer.md)
- [Social Reputation](reference/systems/Social_Reputation_System.md)
- [Player Trade](reference/systems/Player_Trade_System.md)
