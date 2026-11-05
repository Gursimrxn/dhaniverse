Health represents the player’s **overall physical condition and well-being** in Dhaniverse.  
It reflects how well the player is taking care of their lifestyle, including food choices, stress levels, and medical care. Health gradually changes over time depending on the player’s actions and life conditions.

---
#### How Health Appears in the Game
Health is displayed as a **Health Bar** visible in the player interface. The bar represents the player's current physical condition and ranges from **very low health to full health**. As the bar decreases, the player’s physical capability also decreases. When the bar increases, the player becomes healthier and more efficient.

![[../../../Images/Pasted image 20260309194554.png]]

---
## Health Systems:
#### Health Decay

#### Health Decay

**S1 — Time**
Health decreases by **5% every 2 hours (real-world time)** on the single server wall clock. (1 in-game day = 24 real hours; see [11_Canonical_Game_Rules.md](../../11_Canonical_Game_Rules.md) §2 — the earlier "2h = 1 in-game day" note was an error and is deleted; the 5%/2h magnitude stands.)

---

**S2 — Fast Food Consumption**
Each food item labeled **FAST FOOD** decreases health by **0.7% per item consumed**.

---

**S3 — High Stress**
If the **Stress Meter is at High**, health decreases by **2% every 15 minutes (real-world time)** until health reaches **10%**.

---

**S4 — Moderate Stress**
If the **Stress Meter is at Moderate**, health decreases by **1% every 15 minutes (real-world time)** until health reaches **10%**.

---
#### Health Recovery

**S1 — Low Stress Recovery**
If the **Stress Meter remains Low for 15 minutes (real-world time)**, health increases by **2% every 5 minutes** until it reaches **50% of the player's current health capacity**.

---

**S2 — Natural Food Consumption**
Each food item labeled **NATURAL FOOD** increases health by **0.6% per item consumed** (fallback value; items whose entry in [07_Content_Design.md](../../07_Content_Design.md) §Food Catalog lists a specific per-item effect use that value instead — see Canonical Rules §3.3).

---
#### System Rules
- Health **cannot drop below 5%**.
- At health **10% or below** the player enters the Critical Health State
  (movement -20%, energy use +20%, clinics refuse, shifts cannot be started,
  insurance cannot be purchased). The player must travel to the Hospital
  themselves — there is **no automatic hospitalization**; hospitals accept
  critical patients on Emergency Treatment on account (see
  [11_Canonical_Game_Rules.md](../../11_Canonical_Game_Rules.md) §3.1) so an
  unpaid player is never softlocked. Remaining critical >30 real minutes
  triggers Illness (see Illness_State).
---
## Why Health Is Important
Health exists to create **real-life pressure and responsibility** in the game. Without health decay, players would not need to manage their lifestyle or make meaningful decisions about food, stress, and healthcare. The health system ensures that players must:
- maintain a healthy lifestyle
- consume proper food
- manage stress
- plan for healthcare
Ignoring these responsibilities leads to lower performance and higher risks.

---
#### Concepts Health Connects With
Health is connected to several other core systems in Dhaniverse:

##### 1. Food System
Food directly affects health. Healthy food improves health, while unhealthy food can reduce it.

---
##### 2. Stress System
Stress influences how fast health decreases or recovers. Higher stress can accelerate health decay.

---
##### 3. Energy System
Health affects the player’s **energy consumption and efficiency**. Lower health causes energy to drain faster and reduces physical performance.

---
##### 4. Healthcare System
Medical treatment can restore health when it becomes too low.

---
##### 5.Economy System
Health indirectly affects the player's finances because poor health can:
- increase medical expenses
- reduce productivity
- slow down work efficiency

---
#### Design Purpose
The health system exists to simulate **real-world physical well-being inside the game economy**.
It connects lifestyle choices with economic consequences, making players responsible for maintaining their condition while managing their finances.
