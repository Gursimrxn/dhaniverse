The Multiplayer Social Layer is the **infrastructure through which players interact with each other** in Dhaniverse.
It governs how players find each other, form groups, hire and get hired, trade, lend, communicate, and compete.

Without this layer, all the multiplayer mechanics across other systems — SHG groups, business hiring, player lending, trade requests — have no interface to operate through.

It interacts with:
• [[Business_Ownership_System]]
• [[Player_Trade_System]]
• [[Banking_Finance_System]] (SHG / Microfinance)
• [[Social_Reputation_System]]
• [[Financial_Dashboard]]
• All player-facing systems

---

## Player Profile

Every player has a public profile visible to others.

| Field                  | Visible To         | Description                                  |
|------------------------|--------------------|----------------------------------------------|
| Username               | Everyone           | Player's chosen name                         |
| In-game days active    | Everyone           | How long they have been playing              |
| Reputation Tier        | Everyone           | Tier label only (Unknown to Distinguished)   |
| Housing Tier           | Everyone           | Tier label only                              |
| Current Employment     | Everyone           | Worker / Business Owner / Unemployed         |
| Business Name (if any) | Everyone           | Name of owned business                       |
| Financial Health Score | Friends only       | Only visible to mutual friends               |
| Debt details           | Private            | Never visible to others                      |
| Wallet/Bank balance    | Private            | Never visible to others                      |

Reputation Tier and employment status are public because they are the basis for trust in economic interactions.

---

## Social Connections

**S1 — Friend System**
Players can send friend requests to other players.
Accepted friends unlock:
- Viewing each other's Financial Health Score
- Priority in trade requests and job listings
- Direct messaging

**S2 — Blocking**
Players can block any other player.
Blocked players cannot initiate trades, send messages, or hire the blocking player.

---

## Communication

**S3 — Chat Channels**
Players can communicate through:

| Channel         | Scope                             | Use Case                              |
|-----------------|-----------------------------------|---------------------------------------|
| Local Chat      | Players in same map zone          | Real-time interaction, trading        |
| Direct Message  | Friends only                      | Private negotiation, lending terms    |
| Group Chat      | SHG groups, business teams        | Coordination                          |
| Trade Board     | Public (async)                    | Item listings (no direct chat needed) |

No open global chat — communication is zone and relationship based. This reduces noise and keeps interactions contextual.

---

## Job Board (Multiplayer Employment)

**S4 — Posting a Job**
Business owners post job listings through the Job Board.
A listing includes:
- Business name and type
- Role description
- Wage per shift
- Number of shifts available per day
- Location on map

Listings are visible to all players in the same map zone and to friends everywhere.

**S5 — Applying for a Job**
Players apply by sending a request to the business owner.
The owner sees the applicant's:
- Reputation Tier
- In-game days active
- Current health status (Healthy / Ill / Recovery — no percentages)
- Education level

The owner accepts or declines. No coin cost for either party.

**S6 — Shift Execution**
Once hired, the employee travels to the business location and checks in for their shift.
Shift rules follow the [[Work System]] with wages paid by the owner at end of shift rather than by the game directly.

**S7 — Rating After Employment**
After each shift, the business owner can rate the employee (1–5) and the employee can rate the business owner (1–5).
Ratings above 4 give both parties +0.3 Rep.
Ratings below 2 give no Rep penalty but are visible on the profile to future employers/employees.

---

## SHG Groups (Self-Help Groups)

**S8 — Forming an SHG**
A group of 3–6 players can form an SHG at the Microfinance Office.
One player nominates the group. Others confirm membership.
Once formed, the group is registered and can access group lending.

**S9 — SHG Savings Circle**
Each member contributes 50 coins every 24 in-game hours to the group pool.
Each cycle, one member receives the full pool (rotates in order agreed at formation).
Members can vote to skip a member's turn if they have missed contributions.
Missing a contribution: −1 Rep and Stress +0.5 levels.

**S10 — SHG Group Loan**
Any member can request a group-backed loan from the Microfinance Office.
All members see the request and vote to approve or deny.
If approved, all members are co-accountable for repayment.
If the borrower defaults, all members' Stress increases by +1 level and the group's microfinance borrowing is suspended for 5 in-game days.

This makes SHG membership a real decision with social stakes — not a free benefit.

**S11 — SHG Dissolution**
Any member can leave an SHG with 2 in-game days notice.
If a member leaves with an active group loan, they must settle their share before leaving.
The group can vote to dissolve entirely, which requires all loans to be cleared first.

---

## Leaderboard and Progress Visibility

**S12 — Leaderboard**
A public leaderboard tracks players across multiple dimensions:

| Category              | Metric                                |
|-----------------------|---------------------------------------|
| Wealthiest Players    | Net Worth (from [[Financial Dashboard]])|
| Most Reputable        | Social Reputation score               |
| Best Business         | Business revenue over last 7 days     |
| Most Financially Stable| Financial Health Score               |
| Fastest Climber       | Net worth growth rate over 7 days     |

The leaderboard shows the **top 10 players per category**.
Players below the top 10 see their own rank (e.g., "You are ranked 47th in Net Worth").

**S13 — Leaderboard and Teaching**
The leaderboard is designed to show multiple dimensions of success, not just who has the most coins.
A player ranked 1st in Net Worth but 80th in Financial Health Score illustrates that wealth without stability is fragile.
A player ranked 1st in Financial Health Score but 50th in Net Worth shows that stability can be maintained at any income level.

---

## Player Events and Challenges

**S14 — Community Challenges**
Periodic community challenges are issued to all players:

| Challenge Type            | Example                                        | Reward              |
|---------------------------|------------------------------------------------|---------------------|
| Savings Challenge         | Maintain 25%+ savings rate for 5 in-game days | +5 Rep, 100 coins   |
| Business Challenge        | Reach X revenue in 3 days (business owners)   | Business Rep boost  |
| Community Challenge       | SHG groups collectively clear X coins of debt | Group Stress relief |
| Market Challenge          | List and sell 10 items on Trade Board          | +3 Rep              |

Challenges are optional. Completing them rewards both coins and reputation.

---

## Why the Multiplayer Social Layer Exists

Personal finance is not learned in isolation. Real financial decisions are shaped by community — who you can borrow from, who trusts you, who you work for, who works for you.

The Multiplayer Social Layer makes the game's economy **feel inhabited**. Prices move because other players are buying and selling. Jobs exist because other players are running businesses. Loans are available because other players have saved.

It also creates **social accountability** for financial behavior — reputation is visible, lending defaults are public, employment ratings persist. This mirrors how financial reputation works in real communities and small economies.

---

## Connections

- **[[Business Ownership System]]** — Job Board is the hiring interface for businesses
- **[[Player-to-Player Trade System]]** — Trade requests and lending agreements initiated here
- **[[Banking & Finance System]]** — SHG groups access microfinance through this layer
- **[[Social Reputation System]]** — All player interactions feed into reputation
- **[[Financial Dashboard]]** — Leaderboard pulls data from the dashboard; comparison view is here
