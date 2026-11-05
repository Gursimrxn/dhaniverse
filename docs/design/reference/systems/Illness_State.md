Illness represents a **severe physical condition** that occurs when the player's body is pushed beyond sustainable limits.  
It is distinct from the Critical Health State — Illness is not triggered by health percentage alone, but by a combination of **lifestyle abuse, stress, and neglect** over time.

Illness interacts with:
• [[Health]]  
• [[Stress]]  
• [[Energy]]  
• [[Healthcare System]]  
• [[Food]]

---

## What Triggers Illness

Illness is triggered by **one of the following conditions**:

**Trigger 1 — Stress + Fast Food Abuse**  
As defined in [[Stress]] Rule S4:  
High Stress + consuming Fast Food constantly (×5) → Player becomes **Ill**.

**Trigger 2 — Prolonged Critical Health**  
If the player remains in **Critical Health State (health <= 10%) for more than 30 real-world minutes** without seeking treatment → Player becomes **Ill**. (Critical = <=10% everywhere; no auto-hospitalization intervenes — see Canonical Rules §3.1.)

**Trigger 3 — Missed Medication Plan**  
If the player receives a Medication Plan from the [[Healthcare System]] and misses **more than 50% of scheduled doses** → Player becomes **Ill** at the end of the recovery period.

---

## Illness Effects

When the player is Ill, the following apply simultaneously:

**E1 — Health Lock**  
Health cannot recover through any natural means while Ill.  
Natural food, idle recovery, and low-stress recovery are all **suspended**.  
Health can only be restored through **medical treatment**.

---

**E2 — Energy Cap**  
The player's maximum usable energy is reduced to **3 energy bars** (from 5).  
The remaining 2 bars are greyed out and inaccessible until Illness is cured.

---

**E3 — Movement Penalty**  
Movement speed decreases by **30%** while Ill.

---

**E4 — Work Restriction**  
The player **cannot perform any job** while Ill.  
This includes all workplace types — street stall, farm, factory, shop, and office.

---

**E5 — Stress Acceleration**  
While Ill, Stress increases by **+1 level every 15 real-world minutes** automatically.  
This reflects the compounding mental burden of being sick and unable to work.

---

**E6 — Food Absorption Penalty**  
Natural food still provides energy while Ill, but **health benefits from natural food are suspended**.  
Fast food penalties (health decay) still apply normally.

---

## How to Cure Illness

Illness **cannot be cured passively**. The player must take active steps.

**Step 1 — Hospital Visit Required**  
The player must visit a **Hospital** and receive at minimum **Advanced Treatment** (700 coins) or **Full Treatment** (1200 coins).  
Basic Treatment (300 coins) **does not cure Illness** — it only partially restores health while Ill.

---

**Step 2 — Complete the Medication Plan**  
After hospital treatment, the player receives an **Illness-specific Medication Plan**.  
This plan must be completed in full.  
Missing even **one dose** extends the Illness duration by **10 real-world minutes**.

### Illness Medication Plan

Recovery Tablets  
Quantity: 5 | Interval: every 5 minutes

Antibiotics  
Quantity: 5 | Interval: every 8 minutes

Vitamin Supplements  
Quantity: 4 | Interval: every 10 minutes

Stress Relief Tablets  
Quantity: 3 | Interval: every 15 minutes

Recovery Duration: **40 real-world minutes**

Completion Reward: Illness cured + Health restored to **50%** + Stress reduced by **−2 levels**

---

**Step 3 — Recovery Period**  
After completing the medication plan, the player enters a **Post-Illness Recovery Period** of **20 real-world minutes**.  
During this period:
- Energy cap remains at **3 bars** (slowly returning to 5 over the 20 minutes)
- Work is still restricted for the first **10 minutes**
- Health regenerates at **5% every 5 minutes** until reaching 60%

---

## Illness and Insurance

Illness treatment is expensive. [[Insurance System]] coverage applies normally:

| Plan     | Hospital Coverage | Out-of-Pocket (Advanced Treatment) |
|----------|-------------------|--------------------------------------|
| None     | 0%                | 700 coins                            |
| Basic    | 40%               | 420 coins                            |
| Standard | 60%               | 280 coins                            |
| Premium  | 80%               | 140 coins                            |

Players without insurance who are Ill face a severe financial and physical double-penalty.

---

## Illness Frequency Cap

A player cannot become Ill more than **once every 10 in-game days**.  
If the triggers are met again within that window, the game instead applies a **Warning State**:
- Stress increases by +1 level
- Health decay accelerates by 20% for 5 in-game days
- A notification warns the player they are approaching Illness again

---

## Why Illness Exists

Illness is the **consequence ceiling** for ignoring all other systems simultaneously.  
It is what happens when the player treats Stress, Food, and Health as optional — the systems stop being a slow drag and become an acute crisis.  
The work restriction is the critical mechanic: Illness stops income entirely, meaning every day spent Ill is a day of rent, loan repayments, and premiums still due but no coins coming in.  
It is designed to be **recoverable but genuinely punishing**.

---

## Connections

- **[[Health]]** — Illness locks health recovery and is triggered by prolonged critical health
- **[[Stress]]** — Illness accelerates stress gain; completing recovery reduces stress
- **[[Energy]]** — Illness caps maximum energy at 3 bars
- **[[Work System]]** — Work is fully blocked during Illness
- **[[Healthcare System]]** — Hospital and full medication plan are the only cure path
- **[[Insurance]]** — Coverage dramatically reduces the financial cost of Illness treatment
