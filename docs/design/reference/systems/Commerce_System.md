The Commerce System governs how players **purchase goods, manage their inventory, and access everyday necessities** in Dhaniverse.  
It covers all non-food retail — clothing, electronics, groceries — as well as the markets where food ingredients and general goods are sold.

Commerce interacts with:
• [[Food]]  
• [[Health]]  
• [[Energy]]  
• [[Work System]]  
• [[Stress]]  
• Economy

---

## Retail Locations Overview

| Location              | Category              | Price Level | Variety |
|-----------------------|-----------------------|-------------|---------|
| Street Stall          | Food / small goods    | Cheapest    | Low     |
| Local Market / Bazaar | Food, groceries, misc | Low         | High    |
| Supermarket           | Groceries, household  | Medium      | Very High|
| Clothing Shop         | Apparel               | Medium-High | High    |
| Electronics Shop      | Devices, accessories  | High        | Medium  |

---

## Local Market / Bazaar

The Local Market is the **most accessible shopping hub** in Dhaniverse.  
It sells food items, raw groceries, household goods, and miscellaneous items at **lower prices than the supermarket** but with **less variety and consistency**.

### Available Goods

| Category         | Examples                             | Notes                              |
|------------------|--------------------------------------|------------------------------------|
| Fresh produce    | Vegetables, fruits, grains           | Price fluctuates with game events  |
| Cooked street food| Wraps, snacks, juice               | Same as [[Food System]] items      |
| Household items  | Soap, basic tools                    | Required for some daily tasks      |
| Raw materials    | Goods that Street Stall vendors resell| Useful for the [[Work System]]   |

### Market Rules

**S1 — Price Fluctuation**  
Market prices fluctuate based on **random supply events** every 3–5 in-game days.  
Events such as floods or shortages may increase prices by **up to 30%**.  
Surplus events may reduce prices by **up to 20%**.

---

**S2 — Bargaining**  
Players can attempt to bargain at the market.  
Successful bargaining reduces the price by **5–15%**.  
Bargaining has a **cooldown of 1 in-game hour per vendor**.

---

**S3 — Bulk Purchase Discount**  
Purchasing **10 or more units** of the same item provides a **10% discount**.

---

## Supermarket / Grocery Store

The Supermarket provides **consistent pricing and wider product variety** than the local market.  
It is more expensive but never runs out of stock and prices do not fluctuate.

### Available Goods

| Category           | Examples                         | Notes                             |
|--------------------|----------------------------------|-----------------------------------|
| Packaged food      | All [[Food System]] items        | Fixed prices; no bargaining       |
| Household supplies | Cleaning products, toiletries    | Required for maintenance tasks    |
| Pharmacy basics    | Basic OTC medicine               | Minor overlap with [[Healthcare System]] |
| Baby/care products | Specialized goods                | Premium-priced                    |

### Supermarket Rules

**S4 — No Price Fluctuation**  
Supermarket prices are **fixed and stable** regardless of market events.  
This makes it reliable but more expensive than the local market.

---

**S5 — Loyalty Card**  
Players can apply for a **Supermarket Loyalty Card** (cost: 50 coins one-time).  
After every **10 purchases**, the player receives a **5% cashback** on the next purchase.

---

**S6 — Bulk Packs**  
The supermarket sells **bulk packs** (e.g., 10-item bundles) at a **15% discount** compared to buying individually.

---

## Clothing Shop

Clothing represents the player's **presentation and social capital** in Dhaniverse.  
Wearing better clothing improves performance in **office jobs and social interactions**.

### Clothing Tiers

The table below is canonical for clothing costs/durability/effects
([11_Canonical_Game_Rules.md](../../11_Canonical_Game_Rules.md) §9 rows 19;
07_Content_Design's early sketch was aligned to it).

| Tier | Type           | Cost       | Effect                                  |
| ---- | -------------- | ---------- | --------------------------------------- |
| 0    | No clothing    | Free       | −10% pay at office jobs; social penalty |
| 1    | Basic clothes  | 100 coins  | No bonus or penalty                     |
| 2    | Smart casuals  | 300 coins  | +5% pay at office jobs                  |
| 3    | Formal wear    | 600 coins  | +10% pay at office jobs; +social rep    |
| 4    | Premium attire | 1200 coins | +15% pay; major social rep boost        |

### Clothing Rules

**S7 — Clothing Durability**  
Clothes degrade over time.  
Each clothing tier lasts a set number of **in-game days** before becoming worn out.

| Tier | Durability       |
|------|------------------|
| 1    | 10 in-game days  |
| 2    | 20 in-game days  |
| 3    | 30 in-game days  |
| 4    | 45 in-game days  |

When clothing becomes worn out, it drops **one tier in appearance**.

---

**S8 — Stress and Appearance**  
If the player's clothing is worn out and they have **High Stress**, they receive an additional **−5% pay penalty** at office jobs (reflecting loss of professional presentation).

---

**S9 — Laundry Maintenance**  
Players can maintain clothing by paying a **laundry fee of 20 coins every 5 in-game days**.  
Laundry extends durability by **+3 in-game days** per wash.  
Not doing laundry causes clothing to degrade **1 day faster** per missed wash cycle.

---

## Electronics / Mobile Shop

Electronics provide **tools that improve player efficiency** across multiple systems.

### Available Electronics

| Item           | Cost       | Effect                                              |
|----------------|------------|-----------------------------------------------------|
| Basic Phone    | 400 coins  | Access to job alerts, bank notifications            |
| Smartphone     | 900 coins  | All basic phone features + investment app access    |
| Laptop         | 1500 coins | Required for online jobs and some education courses |
| Earphones      | 150 coins  | Stress reduction: −0.5 levels while using           |
| Power Bank     | 200 coins  | Keeps phone operational during power cut events     |

### Electronics Rules

**S10 — Device Durability**  
Electronics have a durability measured in **in-game days**.

| Item        | Durability     |
|-------------|----------------|
| Basic Phone | 30 in-game days|
| Smartphone  | 45 in-game days|
| Laptop      | 60 in-game days|

When durability expires, the device needs **repair (50% of original cost) or replacement**.

---

**S11 — Job Alert Bonus**  
Players with a **Smartphone** receive notifications when high-pay jobs become available.  
Responding within **5 real-world minutes** of a notification gives a **+10% pay bonus** for that shift.

---

**S12 — Investment App**  
A Smartphone unlocks access to the **investment app**, allowing the player to monitor and trade stocks without visiting the **[[Banking & Finance System]]** Investment Office in person.  
This saves travel time and energy.

---

**S13 — Power Cut Events**  
During game events (storms, infrastructure failures), electronics may become non-functional for **1–3 in-game hours** unless the player has a **Power Bank**.

---

## Why Commerce Is Important

Commerce is the **everyday expenditure layer** of Dhaniverse. It forces the player to make constant micro-decisions:
- Buy cheap food at the market (price risk) or expensive food at the supermarket (price stability)?
- Invest in formal clothing to earn more at office jobs, or save coins short-term?
- Buy a smartphone to access better jobs and investments, or stay low-tech and save?

These choices accumulate into a lifestyle that determines the player's long-term financial trajectory.

---

## Connections

- **[[Food]]** — Markets and supermarkets are the primary source of food items
- **[[Work System]]** — Clothing tier directly affects pay at office jobs
- **[[Stress]]** — Poor clothing and worn-out equipment cause minor stress increases
- **[[Banking & Finance System]]** — Electronics unlock investment access without travel
- **[[Health]]** — Purchasing natural food from markets supports health recovery
