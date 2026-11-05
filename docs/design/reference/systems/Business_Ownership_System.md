Business Ownership is the **late-game economic layer** of Dhaniverse.  
It represents the transition from earning income through labour to earning income through ownership — the most fundamental concept in personal finance and wealth building.

Players who build businesses employ other players, set prices, manage costs, take on risk, and generate profit beyond what any job can provide.

Business Ownership interacts with:
• [[Work System]]  
• [[Supply & Demand System]]  
• [[Banking & Finance System]]  
• [[Government & Legal System]]  
• [[Social Reputation System]]  
• [[Multiplayer Social Layer]]  
• Economy

---

Players who build businesses employ other players, set prices, manage costs, take on risk, and generate profit beyond what any job can provide. Revenue is player-driven — no business has a fixed daily payout; any "target revenue" figures elsewhere (07_Content_Design) are `[provisional]` design guidance, not mechanics ([11_Canonical_Game_Rules.md](../../11_Canonical_Game_Rules.md) §9 row 22).

| Requirement              | Details                                             |
|--------------------------|-----------------------------------------------------|
| Reputation               | Minimum Tier 3 — Established (41+ Rep points)       |
| Education                | Minimum School Diploma                              |
| Business Permit          | Purchased from City Hall (150 coins)                |
| Starting Capital         | Minimum 500 coins (varies by business type)         |
| No Active Loan Default   | Clean repayment record with the bank                |

---

## Business Types

| Business Type       | Min. Capital | Category       | Max Employees |
|---------------------|--------------|----------------|---------------|
| Street Stall        | 500 coins    | Food / goods   | 0             |
| Small Shop          | 1200 coins   | Retail         | 2             |
| Dhaba               | 1500 coins   | Food & dining  | 3             |
| Workshop / Factory  | 3000 coins   | Production     | 5             |
| Restaurant          | 5000 coins   | Dining         | 6             |
| Office / Consultancy| 4000 coins   | Services       | 4             |

---

## Business Systems

#### Setup

**S1 — Business Registration**  
All businesses must be registered at **City Hall**.  
Registration: 150 coins. Permits expire every **30 in-game days** and renew at 100 coins.  
Operating without a permit triggers fines and police inspections.

---

**S2 — Starting Capital Deployment**  
When opening a business, capital is committed as:

| Allocation         | Proportion |
|--------------------|------------|
| Inventory / Stock  | 50%        |
| Setup / Equipment  | 30%        |
| Operating Reserve  | 20%        |

The operating reserve buffers the first few days before revenue begins.

---

#### Revenue

**S3 — How Businesses Earn**  
Businesses earn when **other players purchase from them**.  
Revenue = Quantity Sold × Sale Price  
Sale price is set by the owner but constrained by the [[Supply & Demand System]].  
Pricing too far above Market Price means players buy from competitors.

---

**S4 — Footfall and Location**  
High-traffic map zones generate more customers.

| Zone Type     | Footfall Multiplier | Additional Lease Cost |
|---------------|---------------------|-----------------------|
| Residential   | 1×                  | Base rent             |
| Market/Bazaar | 1.8×                | +40% on base rent     |
| City Centre   | 2.5×                | +100% on base rent    |

---

**S5 — Operating Hours**  
Businesses earn **only while the owner is active OR employees are actively working**.  
An empty, unstaffed business earns nothing.  
This is the core incentive for hiring employees — they keep the business running when the owner is offline.

---

#### Costs

**S6 — Business Expenses**

| Expense              | Frequency           | Amount                          |
|----------------------|---------------------|---------------------------------|
| Stock replenishment  | Per item sold       | 60–70% of Base Price (wholesale)|
| Rent / Lease         | Every 24 in-game hrs| Zone-dependent                  |
| Employee wages       | Every 24 in-game hrs| Agreed rate per employee        |
| Permit renewal       | Every 30 in-game days| 100 coins                      |
| Business tax         | Every 7 in-game days | 10–15% of net profit           |

---

**S7 — Profit Calculation**  
Net Profit = Revenue − Stock Cost − Rent − Wages − Tax

Displayed daily in the **[[Financial Dashboard]]**.

---

#### Employees

**S8 — Hiring Players**  
Owners hire other players through a job listing in the **[[Multiplayer Social Layer]]**.  
Terms negotiated between owner and employee:
- Agreed wage per shift
- Shift duration (minimum 30 real-world minutes)
- Role: cashier, cook, vendor, factory worker, server

---

**S9 — Employee Performance**  
Employee output depends on their own [[Health System]], [[Energy System]], and [[Stress System]] stats.  
Healthy, low-stress employee = **100% productivity**  
Poor health or high stress = reduced productivity, reduced business revenue that shift.

This teaches owners that **employee wellbeing directly affects profit** — not just a moral concern.

---

**S10 — Dismissal and Quitting**  
Employees can quit at any time.  
Owners can dismiss employees freely, but dismissing someone with a formal Labor Office contract requires **1 in-game day notice** or **1 day's severance pay**.

---

#### Growth

**S11 — Business Upgrades**

| Upgrade              | Cost       | Effect                                      |
|----------------------|------------|---------------------------------------------|
| Additional Stock Slot| 300 coins  | +5 item types available for sale            |
| Improved Equipment   | 800 coins  | +15% production or service capacity         |
| Second Location      | Full setup cost | Branch opens (same business type)      |
| Brand Registration   | 500 coins  | Unlocks business reputation boost          |

---

**S12 — Business Reputation**  
Businesses have their own reputation score, separate from the owner's personal [[Social Reputation System]].

Increases when:
- Customers rate the business positively
- Stock is consistently available
- Prices are fair relative to Market Price

Decreases when:
- Stock runs out frequently
- Prices are above 150% of Market Price
- Employees have visible poor health or high stress

High business reputation increases footfall by **up to 30%** beyond the zone multiplier.

---

#### Failure and Closure

**S13 — Business Failure**  
Losses for **5 consecutive in-game days** → Warning Notification.  
Losses for **3 more days** after warning → Forced Closure:
- Stock liquidated at 40% of Market Price
- Equipment sold at 50% of cost
- Outstanding wages paid first
- Remaining coins return to owner's wallet
- Permit revoked

---

**S14 — Voluntary Closure**  
Owner can close at any time after:
- Paying all outstanding employee wages
- Settling unpaid business tax
- Returning permit to City Hall

---

## What Business Ownership Teaches

- Revenue minus costs equals profit — not all income is yours
- Location is a cost that must be justified by revenue
- Employees are a cost that must be justified by output
- Scaling too fast without capital reserve causes failure
- Market prices, not what you want to charge, determine what you can charge
- Business tax is proportional to success

The contrast between being an employee and being an owner is the **most important economic lesson** in Dhaniverse.

---

## Connections

- **[[Supply & Demand System]]** — Business output feeds supply; market prices cap viable sale price
- **[[Work System]]** — Employees are players from the work system; owners graduate from it
- **[[Banking & Finance System]]** — Business loans and separate business accounts
- **[[Government & Legal System]]** — Permits, business tax, and labor law apply
- **[[Social Reputation System]]** — Business and personal reputation linked but distinct
- **[[Financial Dashboard]]** — Daily profit/loss tracked here
- **[[Multiplayer Social Layer]]** — Hiring, job listings, and player interaction
