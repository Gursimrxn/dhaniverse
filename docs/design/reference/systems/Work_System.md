Work represents the player's **primary source of income** in Dhaniverse.  
Players earn coins by performing jobs at different workplaces. The type of work available depends on the player's **education level, health, energy, and stress condition**.

Work interacts with:
• [[Health]]  
• [[Energy]]  
• [[Stress]]  
• [[Education System]]  
• Economy

---

## Workplace Types

Pay bands are canonical per 07_Content_Design §Job Catalog (see
../../07_Content_Design.md — this draft's wider bands are superseded).
Every shift charges a flat **1 energy bar at completion** (Canonical Rules
§3.5); the per-workplace energy figures later in this document
(0.5/1.5/2 bars) are superseded.

| Workplace         | Job Type            | Skill Required | Pay (per shift)  |
|-------------------|---------------------|----------------|------------------|
| Street Stall      | Vendor / Hawker     | None           | 30-50 coins      |
| Farm              | Farm Worker         | None           | 40-60 coins      |
| Factory/Workshop  | Factory Worker      | Basic          | 60-80 coins      |
| Small Shop        | Shop Assistant      | Basic          | 50-70 coins      |
| Office Building   | Office Clerk / Bank Teller | Intermediate | 80-120 / 90-130 coins |
| Office Building   | Manager / Senior Officer   | Advanced     | 150-200 / 180-250 coins |

---

## Work Systems

#### Job Availability

**S1 — Energy Requirement for Jobs**  
To start a shift the player needs **at least 2 spendable energy bars**
(base + bonus bars), **health above 10%**, and **Stress below 9**
(universal gate, per 05_Systems_Map and Canonical Rules §3.5).  
If the player drops to the **last energy bar** during a shift, the shift is
paused until spendable energy recovers.  
Reference: [[Energy System]] Rule S3.

---

**S2 — Health Impact on Work**  
Health affects the player's productivity during work.

| Health Level | Productivity Modifier |
|--------------|-----------------------|
| 75–100%      | 100% pay              |
| 50–74%       | 80% pay               |
| 25–49%       | 60% pay               |
| 10–24%       | 40% pay               |
| Below 10%    | Cannot work           |

---

**S3 — Stress Impact on Work**  
High stress reduces work efficiency.

| Stress Level | Effect                        |
|--------------|-------------------------------|
| Low (1–4)    | Normal pay                    |
| Moderate (5–8)| Pay reduced by 10%           |
| High (9–12)  | Shifts cannot be started (gate S1); within Moderate-plus-higher eligible range the 10% reduction applies — High itself is blocked by the gate |

---

**S4 — Education Requirement**  
Higher-tier jobs require minimum education levels.

| Education Level | Jobs Unlocked                       |
|-----------------|-------------------------------------|
| No Education    | Street Stall, Farm                  |
| Basic Literacy  | Factory, Small Shop                 |
| School Diploma  | Office (entry-level)                |
| College Degree  | Office (senior), Manager            |

Education is obtained through the **[[Education System]]**.

---

#### Shifts and Scheduling

**S5 — Shift Duration**  
Each job shift lasts **30 minutes (real-world time)**.  
The player must remain at the workplace for the duration of the shift.  
Leaving early results in **partial pay proportional to time completed**.

---

**S6 — Shift Availability**  
Each workplace has a **maximum number of shifts per 24 in-game hours**.

| Workplace      | Max Shifts / Day |
|----------------|------------------|
| Street Stall   | 4                |
| Farm           | 3                |
| Factory        | 3                |
| Small Shop     | 3                |
| Office         | 2                |

---

**S7 — Energy Consumed by Work**  
Each completed shift costs a flat **1 energy bar**, charged at completion,
regardless of workplace or steps taken (canonical; supersedes this draft's
1.5-bar figure and the per-workplace 0.5/1.5/2 notes below). The normal
15-minute drain and step drain are suspended during the shift.

---

#### Income and Growth

**S8 — Performance Bonus**  
If the player completes a shift at **100% health and Low stress**, they receive a **+15% pay bonus** for that shift.

---

**S9 — Job Progression**  
Players who complete a certain number of shifts at the same workplace unlock a **pay raise**.

| Shifts Completed | Pay Raise |
|------------------|-----------|
| 10 shifts        | +10%      |
| 25 shifts        | +20%      |
| 50 shifts        | +35%      |

---

## Street Stall

Street stalls are **the most accessible entry point** for players with no skills or education.

### Rules

- No education or skill required
- Player sets up a stall and earns income passively while present
- Income depends on **foot traffic** in the area (varies by location on map)
- Canonical shift energy cost is 1 bar (S7); the stall's low physical demand is reflected instead in its 4-shifts-per-day cap
- Players can purchase stall goods from the **[[Commerce System]]** (local market) to sell at markup

---

## Farm

Farms provide work in exchange for physical labor.

### Rules

- No education required
- Canonical shift energy cost is 1 bar (S7); farm's high physical demand is reflected instead in its 3-shifts-per-day cap
- Farm work during poor weather (game events) may reduce output by **20%**
- After 25 farm shifts, player can unlock a **Small Farm Plot** as personal passive income

---

## Factory / Workshop

Factories and workshops provide **steady, moderate-paying work**.

### Rules

- Requires Basic literacy (from [[Education System]])
- Canonical shift energy cost is 1 bar (S7)
- Working in a factory at **Moderate Stress** increases injury risk:
  - 10% chance per shift of a **minor injury event** (health −5%, forced break). (High stress cannot occur during a shift — the work gate blocks starting at 9+.)

---

## Small Shop

Small shops require basic people skills and literacy.

### Rules

- Requires Basic literacy
- Pay depends on the type of shop (food shop pays slightly more than general goods)
- Players gain a **social reputation score** slowly over time

---

## Office Building

Offices offer the **highest pay ceiling** but require education and stable health.

### Rules

- Entry-level office work requires a School Diploma
- Senior/manager roles require a College Degree
- Office jobs keep the standard 1-bar shift cost; their advantage is pay and the lowest physical context (no injury events)
- Missing 3 consecutive office shifts causes a **job termination event**
- After termination, player must reapply (costs 1 in-game day waiting period)

---

## Labor / Employment Office

The Labor Office helps players **find work, register for jobs, and resolve labor disputes**.

### Services

| Service               | Cost      | Description                                      |
|-----------------------|-----------|--------------------------------------------------|
| Job Board Access      | Free      | Lists all currently available jobs               |
| Job Registration      | 20 coins  | Official registration for formal employment      |
| Skill Assessment      | 50 coins  | Identifies which jobs the player qualifies for   |
| Dispute Filing        | 30 coins  | File a complaint about unpaid wages              |
| Unemployment Benefit  | Free      | Receive coins if unemployed for 48+ in-game hrs  |

### Unemployment Benefit Rules

- Player must be registered at the Labor Office
- Benefit: **20 coins every 24 in-game hours**
- Benefit stops when the player accepts a new job
- Maximum benefit period: **5 in-game days**

---

## Why Work Is Important

Work is the **engine of the player's economy**. Every other system — housing, food, healthcare, insurance — depends on income. The work system creates meaningful trade-offs:
- High-pay jobs require investment in education and health maintenance
- Low-pay jobs are accessible but cannot sustain a comfortable lifestyle
- Health and stress directly reduce earnings, punishing neglect of other systems

---

## Connections

- **[[Energy]]** — Energy is consumed during shifts; low energy stops work
- **[[Health]]** — Health directly scales pay; poor health can bar certain jobs
- **[[Stress]]** — High stress reduces pay and restricts high-tier jobs
- **[[Education System]]** — Education unlocks higher-paying job tiers
- **[[Housing System]]** — Income from work pays rent and mortgage
