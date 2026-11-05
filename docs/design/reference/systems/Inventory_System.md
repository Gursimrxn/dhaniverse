The Inventory represents **everything the player is currently carrying** in Dhaniverse.  
It defines how many items the player can hold, how items are organized, and the rules governing item usage, storage, and transfer.  
Without an inventory, systems like [[Food]], [[Healthcare System]], [[Commerce_System]], and the [[Pawn Shop]] have no physical basis to operate from.

The Inventory interacts with:
• [[Food]]  
• [[Healthcare System]]  
• [[Commerce_System]]  
• [[Banking_Finance_System]] (Pawn Shop)  
• [[Energy]]  
• [[Work System]]

---

## Inventory Structure

The inventory is divided into **four slots categories**, each with its own capacity:

| Category         | Capacity     | Contents                                       |
|------------------|--------------|------------------------------------------------|
| Food & Drinks    | 20 items     | All food items from [[Food]]            |
| Medicine         | 15 items     | All pharmacy items from [[Healthcare System]]  |
| Goods & Items    | 10 items     | Clothing, electronics, household items         |
| Equipment        | 5 items      | Work tools, energy drink stock, stall supplies |

**Total maximum inventory: 50 items**

---

## Inventory Systems

#### Capacity Rules

**S1 — Carry Limit**  
The player cannot carry more than the maximum capacity for each category.  
Attempting to purchase an item when the relevant category is full results in a **"Inventory Full" notification**.  
The player must consume, store, or discard items to make space.

---

**S2 — Stackable Items**  
Identical items stack within a single inventory slot.  
Stacking limits per item:

| Item Type             | Stack Limit |
|-----------------------|-------------|
| Food items (small)    | 10 per stack|
| Food items (large)    | 5 per stack |
| Medicine              | 10 per stack|
| Clothing              | 1 per slot  |
| Electronics           | 1 per slot  |

A single food item stack of 10 units counts as **1 inventory slot**.

---

**S3 — Inventory Weight and Energy**  
Carrying a **full inventory** increases energy consumption slightly.  
When the inventory is more than **80% full**, energy consumption increases by **10%**.  
This reflects the physical effort of carrying a heavy load.

---

#### Item Storage

**S4 — Home Storage**  
Players living in **Tier 2 housing or above** (Small House, Apartment, Owned)
have access to a **Home Storage container**. Storage is **bounded** — the
capacity is a per-tier unit budget, not unlimited (the earlier "unlimited
item storage" draft is retired; see section 6 of
[11_Canonical_Game_Rules.md](../../11_Canonical_Game_Rules.md)):

| Housing Tier  | Home Storage |
|---------------|--------------|
| Tier 0 (Street)| None |
| Tier 1 (Room) | None (room includes a landlord bed for Rest) |
| Tier 2 (Small House)| 150 units (provisional) |
| Tier 3 (Apartment)| 300 units (provisional) |
| Tier 4 (Owned)| 300 (apartment) / 600 (house) / 1200 (mansion) units (provisional) |

Items stored at home **cannot be used while away**. Furniture placed in the
home occupies **floor cells**, a budget independent of the storage-unit
capacity (bed 4, wardrobe 6, closet 3, kitchen set 8, sofa 4, desk 3 —
provisional, per-item authored values). A placed bed is the precondition for
Rest at Tier 2+; the room rental's landlord bed covers Tier 1.

---

**S5 — Bank Locker (Valuables)**  
The [[Banking_Finance_System]] Bank offers a **Safe Deposit Locker** service.  
Cost: 30 coins per 7 in-game days. Capacity: **30 goods-category units**
(provisional). Valuables stored in the bank locker **cannot be stolen**
during theft events (see [[Government_Legal_System]] Police rules).  
Only **Goods & Items category** items can be stored in the bank locker.

---

#### Item Usage Rules

**S6 — Food Consumption**  
Food items can be consumed **anywhere on the map** directly from the inventory.  
Consuming food applies the energy and health effects defined in [[Food]] immediately.  
Exception: Restaurant meals cannot be stored in inventory — they are consumed on-site.

---

**S7 — Medicine Usage**  
Medicines from the [[Healthcare System]] can be consumed anywhere.  
However, medicines taken **outside the scheduled Medication Plan intervals** do not accelerate recovery.  
Reference: [[Healthcare System]] Medication Compliance Rules.

---

**S8 — Item Expiry**  
Certain items degrade over time:

| Item Type         | Expiry Duration     | Effect on Expiry                  |
|-------------------|---------------------|-----------------------------------|
| Fresh Fruits      | 3 in-game days      | Disappears from inventory         |
| Cooked Food (dhaba, restaurant takeaway) | 1 in-game day | Cannot be consumed; must discard |
| Packaged Food     | No expiry           | No effect                         |
| Medicine          | No expiry           | No effect                         |
| Clothing          | Degrades (see [[Commerce_System]]) | Loses tier appearance  |

---

**S9 — Item Loss on Theft**  
During theft events (see [[Government_Legal_System]] Police rules), the thief takes **coins only** from the player's wallet.  
Inventory items are **not stolen** — only loose coins carried by the player.  
Items in Home Storage and Bank Locker are completely protected.

---

#### Coins vs. Inventory

**S10 — Coins Are Not Inventory Items**  
Coins are tracked separately from the inventory.  
They do not occupy inventory slots.  
Coins in the player's **wallet** (carried) can be stolen.  
Coins in the **bank account** cannot be stolen.

The distinction teaches the player to **keep coins in the bank** rather than carrying large amounts.

---

## Inventory Upgrades

Players can expand their inventory capacity through purchases:

| Upgrade             | Cost       | Effect                               |
|---------------------|------------|--------------------------------------|
| Backpack            | 150 coins  | +5 slots across all categories       |
| Large Backpack      | 350 coins  | +10 slots across all categories      |
| Insulated Food Bag  | 120 coins  | Doubles expiry time of perishable food|
| Medicine Organizer  | 80 coins   | +5 Medicine slots specifically       |

Upgrades are purchased at the **[[Commerce_System]]** Electronics/Goods shop.

---

## Inventory and the Pawn Shop

The [[Banking_Finance_System]] Pawn Shop operates on inventory items.  
Only items in the **Goods & Items** or **Equipment** category can be pawned.  
Food and medicine **cannot be pawned**.  
When an item is pledged to the pawn shop, it is **removed from inventory** immediately.  
If redeemed within 5 in-game days, it returns to inventory.  
If forfeited, it is permanently gone.

---

## Why the Inventory System Exists

The inventory is the **physical reality layer** of Dhaniverse.  
Without it, buying food means nothing — you need somewhere to hold it.  
Without it, the pawn shop has nothing to operate on.  
Without it, there is no difference between buying medicine and having medicine available when you need it.  

The carry limit and expiry rules create **planning decisions**:  
- Buy food in bulk to save trips to the market, but risk expiry and heavy carry  
- Keep medicine stocked for emergencies, but medicine takes slots away from food  
- Store valuables at home or bank to avoid loss, but then you can't use them in the field

These are small decisions that accumulate into a **resource management layer** underneath all the other systems.

---

## Connections

- **[[Food]]** — All food items are held and consumed through inventory
- **[[Healthcare System]]** — Medicines are carried and administered from inventory
- **[[Commerce_System]]** — All purchased goods enter inventory; clothing lives here
- **[[Banking_Finance_System]]** — Pawn shop operates on inventory items; bank locker secures them
- **[[Energy]]** — Full inventory increases energy consumption by 10%
- **[[Housing_System]]** — Tier 2+ housing unlocks Home Storage for overflow items
