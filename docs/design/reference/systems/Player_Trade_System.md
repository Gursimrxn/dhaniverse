The Player-to-Player Trade System allows players to **directly exchange items, goods, and services with each other** outside of NPC vendors and fixed market prices.

It interacts with:
• [[Inventory_System]]
• [[Supply_Demand_System]]
• [[Business_Ownership_System]]
• [[Banking_Finance_System]]
• [[Social_Reputation_System]]
• [[Multiplayer_Social_Layer]]

---

## Trade Methods

| Method         | Location            | Price                | Speed    |
|----------------|---------------------|----------------------|----------|
| Direct Trade   | Face-to-face on map | Negotiated           | Instant  |
| Market Listing | Public trade board  | Listed price         | Async    |
| Player Lending | Any location        | Interest rate agreed | Deferred |

---

## Direct Trade

**S1 — How Direct Trade Works**
Two players must be at the same map location. One initiates a trade request. Both see a window showing what each offers. Both must confirm before any exchange occurs.

**S2 — What Can Be Traded**
Tradeable: Goods & Items, Food & Drinks, Medicine from [[Inventory_System]], and Coins.
Not tradeable: active business stock, documents (permits, medication plans, ID papers), clothing currently being worn.

**S3 — Trade and Reputation**
Completing a trade: +0.2 Rep for both.
Cancelling after agreeing: −0.5 Rep for the cancelling player.

**S4 — Scam Protection**
Once both players confirm, the trade cannot be reversed. Complaints go to the Police Station but the game does not auto-reverse trades. Players learn: verify before confirming.

---

## Market Listing (Trade Board)

**S5 — Listing Items**
Players list items on a public Trade Board at any market location. Listing is free. Seller sets the price. Any player can purchase remotely — coins transfer immediately, item enters buyer's inventory.

**S6 — Listing Duration**
Listings stay active for 5 in-game days. Unsold listings expire and items return to seller. Sellers can cancel any time before purchase.

**S7 — Trade Board and Market Price**
Trade Board listings contribute to the [[Supply_Demand_System]]. Items listed below Market Price increase supply pressure. Items listed above Market Price don't affect supply until purchased.

**S8 — Trade Fee**
Trade Board charges 2% of sale price on successful sale. Direct trades have no fee.

---

## Player Lending

**S9 — How Player Lending Works**
Any player can lend coins to another. Both agree on: loan amount, interest rate (no restriction), repayment period and schedule. Terms confirmed through the [[Multiplayer Social Layer]]. The game automatically deducts repayments from the borrower's wallet on schedule.

**S10 — Repayment Enforcement**
If the borrower's wallet is insufficient, the deduction is marked overdue.

| Overdue Stage              | Consequence                                   |
|----------------------------|-----------------------------------------------|
| Immediately overdue        | Borrower loses −3 Rep; lender notified        |
| After 1 in-game day grace  | Lender can file at Court Building             |
| Court judgment             | Repayment enforced or penalty on borrower     |

**S11 — Lending and Reputation**
Repaying on time: +1 Rep for borrower.
Defaulting: −5 Rep (more punishing than missing a bank payment — it damages a public personal relationship).
Lender recovering successfully: +0.5 Rep.

**S12 — Player Lending vs. Bank**
Player lending can offer lower rates for trusted relationships or higher rates for strangers who cannot access bank credit. This creates a natural informal credit market between real players with real social stakes.

---

## What Player Trade Teaches

**Direct Trade** — Negotiation, verification before committing, opportunity cost
**Market Listing** — Pricing strategy, market timing, commission costs
**Player Lending** — Interest is the cost of borrowed capital, trust-based lending has different rates, default has social consequences, lending is an investment with risk

---

## Connections

- **[[Inventory_System]]** — All traded items come from and go to inventory
- **[[Supply_Demand_System]]** — Trade Board listings affect market supply
- **[[Social_Reputation_System]]** — Trades, defaults, cancellations affect reputation
- **[[Banking_Finance_System]]** — Player lending complements and competes with bank loans
- **[[Government_Legal_System]]** — Court resolves lending disputes
- **[[Multiplayer_Social_Layer]]** — Trade requests and lending agreements initiated here
