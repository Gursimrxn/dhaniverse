Education represents the player's **knowledge level and formal qualifications** in Dhaniverse.  
It determines which jobs are accessible, how fast the player learns skills, and unlocks advanced systems in the game.

Education interacts with:
• [[Work System]]  
• [[Stress]]  
• Economy  
• [[Banking_Finance_System]]

---

## Education Levels

Education is a **progressive ladder**. Each level unlocks higher-tier work and additional game mechanics.

| Level | Qualification        | Institution     | Duration (real-world) | Cost        |
|-------|----------------------|-----------------|-----------------------|-------------|
| 0     | No Formal Education  | —               | —                     | Free        |
| 1     | Basic Literacy       | Public Library  | 10 minutes (1 session)| Free        |
| 2     | School Diploma       | School          | 30 minutes (3 sessions)| 200 coins   |
| 3     | College Degree       | College/Uni     | 60 minutes (6 sessions)| 800 coins   |
| 4     | Postgraduate / Skill | College/Uni     | 45 minutes (5 sessions, provisional) | 1200 coins  |

Level 4 (Postgraduate/Skill) is distinct from the **specialization
programs** below (Finance/Healthcare/Business, 400 coins, 3 sessions): only
specializations carry pay effects. All sessions are 10 real minutes
(1200/45 row: Canonical Rules matrix row 26).

---

## Education Systems

#### Progression Rules

**S1 — Sequential Requirement**  
Education must be completed **in order**.  
A player cannot enroll in College without completing a **School Diploma** first.

---

**S2 — Enrollment Fee**  
Fees must be **paid upfront** before education begins.  
Players who cannot afford fees may apply for a **Student Loan** through the [[Banking & Finance System]].

Student Loan Terms:
- Interest: 4% flat on total fee
- Repayment: automatic deduction of 20 coins every 24 in-game hours after graduation
- Defaulting on the loan adds **Stress +1 level** per missed payment

---

**S3 — Education and Energy**  
Attending school or college consumes **1 energy bar per session**.  
Players must have at least **2 energy bars** before starting a session.

---

**S4 — Stress During Study**  
Enrolling in education increases the player's **baseline Stress by +1 level** for the duration of the course.  
This reflects academic pressure.  
On completion (or dropout processing), **exactly the +1 applied at enrollment is removed** (floor 1). Stress changes caused by events during the course (bills, dining, illness, etc.) **persist** — enrollment does not snapshot and restore the whole stress state ([11_Canonical_Game_Rules.md](../../11_Canonical_Game_Rules.md) §9 row 27).

---

**S5 — Dropout Rule**  
If the player misses **3 consecutive sessions** at a school or college, they are **dropped from the program**.  
They must re-enroll and pay the **enrollment fee again**.  
Dropping out increases Stress by **+1 level**.

---

## School

Schools provide the **foundational qualification** (School Diploma) required to access office-level employment.

### Services

| Service              | Cost       | Duration  | Outcome                   |
|----------------------|------------|-----------|---------------------------|
| Basic Literacy Course| Free       | 10 mins   | Unlocks Factory, Shop jobs|
| School Diploma       | 200 coins  | 30 mins   | Unlocks Office entry-level|

### School Rules

- School sessions run in **fixed time windows** (e.g., every 2 in-game hours)
- Players must **arrive at the school building** to attend a session
- Each session lasts **10 real-world minutes**
- The School Diploma requires **3 completed sessions**

---

## College / University

The College/University provides **advanced qualifications** that unlock high-paying jobs, senior roles, and postgraduate specializations.

### Programs

| Program              | Cost       | Sessions Required | Outcome                        |
|----------------------|------------|-------------------|--------------------------------|
| College Degree       | 800 coins  | 6 sessions        | Unlocks Manager/Senior Office  |
| Finance Specialization| 400 coins | 3 sessions        | +20% pay at Investment Office  |
| Healthcare Track     | 400 coins  | 3 sessions        | Reduces clinic costs by 15%    |
| Business Management  | 400 coins  | 3 sessions        | +15% income from owned business|

### College Rules

**S6 — Specialization Requirement**  
Specializations can only be taken **after completing a College Degree**.  
Players may hold a maximum of **2 specializations** simultaneously.

---

**S7 — Degree Value Decay**  
If a player does not use their College Degree qualification for **30 in-game days** (i.e., they do not work an office job), their **skill level decreases by 1 tier**.  
They must attend a **refresher course (200 coins, 2 sessions)** to restore it.

---

## Public Library

The Public Library provides **free access to basic literacy and low-cost skill courses**.  
It is the most accessible education resource in the game.

### Services

| Service              | Cost  | Duration  | Outcome                           |
|----------------------|-------|-----------|-----------------------------------|
| Basic Literacy       | Free  | 10 mins   | Level 1 Education                 |
| Financial Literacy   | Free  | 15 mins   | Reduces Stress from financial events by 10%|
| Health Awareness     | Free  | 10 mins   | Reduces health decay by 2% permanently|
| Job Skills Booklet   | Free  | 10 mins   | +5% productivity in current job for 3 in-game days|

### Library Rules

- The library is **always open** (no time windows)
- Library courses do not consume energy (passive, self-paced)
- Players can only benefit from each library course **once per 5 in-game days**

---

**S8 — Library and Stress Relief**  
Spending time at the library (any course) reduces Stress by **−0.5 levels** per session.  
This reflects the calming effect of focused, low-pressure learning.

---

## Why Education Is Important

Education is the **primary unlock mechanism** for economic mobility in Dhaniverse.  
Without investing in education, the player is permanently confined to low-pay, high-effort jobs.  
The system teaches real-world concepts:
- Education costs money upfront but pays back through higher income
- Student debt is manageable if income grows after graduation
- Skipping education means slower financial progress
- Specialization increases pay in targeted fields

---

## Connections

- **[[Work System]]** — Education tier directly determines which jobs are available and pay scales
- **[[Stress]]** — Studying adds stress; library visits reduce it
- **[[Banking_Finance_System]]** — Student loans fund education; investment specialization increases returns
- **[[Health]]** — Health awareness course from library reduces passive health decay
