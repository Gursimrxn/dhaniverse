Food is the primary way players **recover energy** and influence their **health and performance**. Players can **purchase food items from food vendors** in the game world.
Food items are divided into two categories:
- **Natural Food**
- **Fast Food**
Each food item restores a certain amount of **energy** and may also apply **temporary effects** on the player.

**Price/effect precedence:** for items that also appear in the canonical food
catalog ([07_Content_Design.md](../../07_Content_Design.md) §Food Catalog,
mirrored in [11_Canonical_Game_Rules.md](../../11_Canonical_Game_Rules.md)
§3.3), that catalog's base price and per-item health effect win; this table
keeps structure (conversion rule, classes, boosts) and prices for items
unique to it. Where no per-item health effect is listed, the Health.md
fallback applies (Natural +0.6% / Fast -0.7% per item).
# Natural Food
Natural foods are generally **healthier options** that restore energy with fewer negative effects.

| Item           | Price     | Energy Recovery        | Additional Effect                           |
| -------------- | --------- | ---------------------- | ------------------------------------------- |
| Avocado Toast  | 25 coins  | 1 item = Full Energy   | +5% health (07)                           |
| Vegetable Wrap | 8 coins   | 5 items = Full Energy  | +2% health (07)                           |
| Ramen          | 180 coins | 1 item = Full Energy   | +0.6% health (fallback)                   |
| Juice          | 100 coins | 5 items = Full Energy  | +1 bonus bar (30 min), +10% speed         |
| Fruits         | 3 coins   | 35 items = Full Energy | +1% health (07)                           |

---

# Fast Food
Fast foods are generally **cheaper and restore energy faster**, but they may have **negative effects on health or performance**.

| Item         | Price     | Energy Recovery        | Additional Effect                         |
| ------------ | --------- | ---------------------- | ----------------------------------------- |
| Candy        | 2 coins   | 50 items = Full Energy | -0.5% health (07)                       |
| Burger       | 30 coins  | 25 items = Full Energy | -0.7% health (fallback)                 |
| Cheetos      | 20 coins  | 30 items = Full Energy | -0.7% health (fallback)                 |
| Donut        | 80 coins  | 5 items = Full Energy  | -0.7% health (fallback)                 |
| Boba Tea     | 120 coins | 1 item = Full Energy   | -0.7% health; speed -10% for 1 minute   |
| Energy Drink | 100 coins | 1 item = Full Energy   | -0.7% health; +2 bonus bars (45 min), +30% speed |

---

# Food Effects
Food affects multiple systems in the game:
- **[[Energy]] Recovery** – primary purpose of food
- **Movement Speed Modifiers** – temporary boosts or reductions
- **[[Health]] Impact** – certain food types may influence long-term health

