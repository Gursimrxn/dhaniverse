Energy represents the player’s **physical capacity to move and perform activities**.  
Energy directly affects **movement speed and the ability to perform tasks**.

Energy is divided into **5 bars**, where:

- **1 bar = 20% of total energy**
![[../../../Images/Pasted image 20260309220659.png]]
---

## Energy Rules

**S1 — Movement Speed**
When the player has **full energy**, movement speed is **100%**.  
As energy decreases, **movement speed decreases proportionally**.

---

**S2 — Energy Recovery from [[Food]]**
Energy can be **recovered by consuming food items**. Different food items restore different amounts of energy depending on their type.

---

**S3 — Last Energy Bar Limitation**
When the player reaches the **last energy bar**, the player **cannot perform jobs or side quests**. The player must recover energy before continuing work activities.

---

**S4 — Energy Consumption by Movement**
Each **energy bar represents 200 steps**. When the player walks **200 steps**, one energy bar is consumed.

---

**S5 — Time-Based Energy Consumption**
Each energy bar lasts **15 minutes**.
If the player walks **200 steps before 15 minutes**, the energy bar is consumed immediately. 
If the player does **not reach 200 steps**, the energy bar is automatically consumed **after 15 minutes**.
Exceptions (canonical, see [11_Canonical_Game_Rules.md](../../11_Canonical_Game_Rules.md) §3.5/§2): the 15-minute drain does **not** run during an active work shift (shifts charge a flat 1 bar at completion), while riding bus/train (timer paused), or while the player is offline.

---
**S6 — [[Health]] Impact on Energy**
When the player has **100% [[Health]]**, one energy bar lasts **15 minutes**.
As **[[Health]] decreases**, energy consumption becomes faster: the bar
duration is multiplied by **0.9 per 10% of health lost** (e.g. at 50% health
the duration is 15 x 0.9^5 ≈ 8.8 minutes).

---
**S7 — Stress Impact on Energy**

If the player's **Stress level is High**, energy consumption becomes **20% faster**.
This means the **duration of each energy bar is reduced by 20%**.
Example:
Normal duration = 15 minutes  
High Stress duration = 12 minutes

**Stacking (canonical):** S6 (health) and S7 (stress) multipliers apply
**multiplicatively** to the 15-minute base duration; the inventory weight
penalty (Inventory S3, x1.1 consumption) applies to consumption, not
duration. No third hidden term exists.

---

**S8 — Idle Energy Recovery**

If the player remains **completely idle for 2 continuous minutes**, the player recovers **5% of total energy**.

Conditions:
- The player must not move or perform any actions during the 2-minute period.
- If the player moves or performs any activity before the 2 minutes are completed, the idle timer resets to 0 and no energy is recovered.
- Once energy is recovered, a new 2-minute idle timer begins if the player continues to remain idle.
---

**S9 — Temporary Energy Boost Items**
Some items can temporarily **add extra energy bars** beyond the normal limit.
Examples include:
- Energy Drinks (+2)
- Juice (+1)
- Energy Supplements (+1, pharmacy)
These bars live in a separate **bonus bar** pool above the 5-bar cap, are
spent before base bars, capped at 2 total, and expire on a timer
(Juice 30 min, Energy Drink / Energy Supplements 45 min [provisional]).
Full stack/precedence rules: [11_Canonical_Game_Rules.md](../../11_Canonical_Game_Rules.md) §3.4.
![[../../../Images/Pasted image 20260309222123.png]]

---
## Energy Conversion Rule

Food restores energy based on the **Full Energy value** listed for each item.

Full Energy = **5 Energy Bars**

Energy restored per item is calculated as:

Energy Bars Restored = 5 ÷ (items required for Full Energy)

Examples:

Vegetable Wrap  
5 items = Full Energy  
1 wrap = 1 Energy Bar

Fruits  
35 items = Full Energy  
1 fruit = 0.14 Energy Bars

Candy  
50 items = Full Energy  
1 candy = 0.10 Energy Bars

Avocado Toast  
1 item = Full Energy  
1 toast = 5 Energy Bars