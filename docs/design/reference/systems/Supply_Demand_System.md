The Supply and Demand System governs how **market prices in Dhaniverse respond to collective player behavior**.  
Prices are not fixed — they move based on what players produce, sell, and consume across the game world.  
This is the economic engine that makes Dhaniverse a living multiplayer economy rather than a static single-player simulation.

It interacts with:
• [[Commerce System]]  
• [[Food]]  
• [[Work System]]  
• [[Business Ownership System]]  
• [[Player-to-Player Trade System]]  
• Economy

---

## Core Principle

Every tradeable item has two values:

**Base Price** — fixed reference price set at game launch (players pay the
live Market Price for these; the values in 07_Content_Design are base prices)  
**Market Price** — live price players actually pay, moves above or below
Base Price based on supply and demand

Players transact at **Market Price** at markets, stalls, businesses, and
the Trade Board. One intentional exception: the **Supermarket** sells at
fixed shelf prices set relative to Base Price (a premium for stability, see
Commerce_System S4); supermarket purchases still register as demand in the
engine, but shelf prices do not float.


---

## How Supply Is Generated

Supply increases when players **produce or sell** items into the market.

| Source                      | Items Added to Supply                        |
|-----------------------------|----------------------------------------------|
| Farm workers harvesting      | Fresh produce, fruits, grains               |
| Street stall vendors selling | Cooked food, packaged goods                 |
| Business owners stocking    | Any goods their business deals in            |
| Players selling to market   | Any item via [[Player-to-Player Trade System]]|
| Import events               | Bulk supply of specific items (temporary)    |

---

## How Demand Is Generated

Demand increases when players **purchase** items.

| Source                        | Demand Increased For           |
|-------------------------------|--------------------------------|
| Players buying food           | Food category items            |
| Players buying medicine       | Medicine category items        |
| Players buying clothing       | Clothing                       |
| Players buying electronics    | Electronics                    |
| Hospital treating players     | Medicine demand spike          |
| Game events (festivals, crises)| Specific item demand spikes   |

---

## Price Movement Rules

**S1 — Price Band**  
Market Price moves between **50% and 300% of Base Price**. Cannot go below
or above these bounds regardless of extremes. (Floor from 04_Economy_Design;
ceiling from the Economy Engine Spec — the earlier 200% ceiling is retired.
The 200% figure survives only as the price-gouging *listing review*
threshold. Government Intervention Events cap an item at 130% of Base for
5 in-game days; that cap is a separate mechanism layered on the band.)

---

**S2 — Price Calculation**  
The canonical deterministic model — the elasticity formula, the 5 real-minute
tick, supply/demand window definitions, zero-supply floor, 5%/tick movement
cap, and the explicit momentum recurrence — lives in
section 4 of [11_Canonical_Game_Rules.md](../../11_Canonical_Game_Rules.md)
and in [Economy_Engine_Spec.md](../../../specs/economy/Economy_Engine_Spec.md).
The former daily supply-ratio tier table (1.5x/-10% etc.) is **retired**:
prices now recompute every 5 real minutes from the continuous ratio, not
once per in-game day from discrete bands.

---

**S3 — Category Independence**  
Each item has its own supply/demand calculation.  
Food prices moving does not affect medicine prices.  
Example: Burger prices can fall while Avocado Toast prices rise simultaneously.

---

**S4 — Price Memory**  
"Momentum" is exactly the deterministic recurrence in Canonical Rules §4
(60% weight on prior trend direction, 5%-per-tick movement cap, 0.4 pull
toward the clamp target). There is no separate snap-back or
"consecutive balanced days" stabilization rule — both earlier phrasings are
retired as under-specified; the recurrence reproduces drift-and-return
behavior on its own.

## Market Visibility

**S5 — Price Board**  
Every market location displays a live **Price Board** showing:
- Current Market Price of all listed items
- Direction indicator: ↑ rising, ↓ falling, → stable
- % change from Base Price

Players use this to decide when to buy, when to sell, and what to produce.

---

**S6 — Price Alerts**  
Players with a Smartphone (see [[Commerce System]]) can set **price alerts**.  
When a tracked item crosses their set threshold, they receive a notification.  
Maximum **5 active alerts** per player.

---

## Supply Shocks and Demand Spikes

**S7 — Game Event Impact**

| Event                  | Effect                                          |
|------------------------|-------------------------------------------------|
| Drought / Flood        | Fresh produce supply drops 40% for 3 days      |
| Disease Outbreak       | Medicine demand spikes 60% for 5 days          |
| Festival Event         | Food and clothing demand spikes 30% for 2 days |
| Transport Strike       | All supply drops 20% (goods can't move)        |
| Import Surplus Event   | Specific category supply jumps 50% for 2 days  |

---
**S8 — Player-Driven Shortage**  
If players corner the supply of a specific item (buying all available stock), they can create an artificial shortage and sell at elevated prices.  
This is intentional — it teaches **monopoly behavior and price manipulation**.

Counter-mechanic (canonical thresholds, 04_Economy_Design): a single player
buying more than **30% of an item's supply** raises a hoarding flag/review;
a single entity controlling more than **50% of supply** triggers a
**Government Intervention Event**, capping that item's price at 130% of Base
Price for 5 in-game days. (This draft's 60% trigger is retired — intervene
before total cornering is possible.) Listing above 200% of Market Price
triggers a price-gouging review.
---

## What Players Learn

- Farming pays more when food is scarce
- Buying medicine before an outbreak is cheaper than buying during one
- Running a business requires reading the market, not just producing
- Hoarding creates short-term profit but triggers consequences

These are the core mechanics of **real commodity markets**, taught through gameplay decisions.

---

## Connections

- **[[Commerce System]]** — All retail prices are market prices, not fixed
- **[[Food System]]** — Food item prices fluctuate based on production and consumption
- **[[Work System]]** — Farm and factory output feeds supply
- **[[Business Ownership System]]** — Business owners are primary supply-side actors
- **[[Player-to-Player Trade System]]** — Direct trades at negotiated prices
- **[[03_Events_System]]** — Events create the most dramatic supply/demand swings
