The Government and Legal System represents the player's **interaction with civic institutions, taxation, welfare, and legal authority** in Dhaniverse.  
It governs mandatory obligations (taxes, laws), available support systems (welfare, subsidies), and consequences for non-compliance (fines, court).

This system interacts with:
• Economy  
• [[Work System]]  
• [[Stress]]  
• [[Housing_System]]  
• [[Banking_Finance_System]]

---

## Institutions Overview

| Institution              | Role                                              |
|--------------------------|---------------------------------------------------|
| City Hall / Municipal Office | Permits, registrations, civic services       |
| Tax Office               | Income tax collection and filing                  |
| Welfare / Benefit Office | Subsidies, ration card, government support        |
| Labor / Employment Office| Already covered in [[Work System]]               |
| Court Building           | Legal disputes, fines, and penalties              |
| Police Station           | Crime events, theft, reporting                    |

---

## City Hall / Municipal Office

The City Hall handles **permits, identity documents, and civic registrations** essential for accessing higher-level game features.

### Services

| Service                | Cost       | Description                                      |
|------------------------|------------|--------------------------------------------------|
| Identity Registration  | Free       | Creates the player's official in-game ID         |
| Business Permit        | 150 coins  | Required to run a legal street stall or shop     |
| Property Registration  | 200 coins  | Required to officially own property              |
| Complaint Filing       | Free       | File civic complaints (noise, sanitation, etc.)  |
| Birth/Death Certificate| 30 coins   | Required for certain welfare benefits            |

### City Hall Rules

**S1 — Identity Requirement**  
Players must have a registered **Identity** to:
- Open a bank account
- Access welfare benefits
- File tax returns
- Take formal employment above entry level

---

**S2 — Business Permit**  
Operating a street stall or small shop **without a permit** risks a **fine of 200 coins** during random inspection events.  
Permits are valid for **30 in-game days** and must be renewed.

---

## Tax Office

The Tax Office collects **income tax** from players earning above a minimum threshold.

### Tax Brackets

| Daily Income (coins)  | Tax Rate |
|-----------------------|----------|
| 0–100                 | 0%       |
| 101–200               | 5%       |
| 201–400               | 10%      |
| 401–700               | 15%      |
| 700+                  | 20%      |

### Tax Rules

**S3 — Tax Deduction Cycle**  
Taxes are calculated and deducted automatically every **7 in-game days** (tax week).  
The bracket table applies to **daily income**: each day's income is taxed at
its bracket rate, and the weekly deduction is the sum of the daily amounts;
the monthly S4 filing reconciles the record (canonical matrix row 24).
---

**S4 — Tax Filing**  
Players must file a **tax return** at the Tax Office every **30 in-game days**.  
Filing is **free** and takes **5 real-world minutes**.  
Failure to file:
- **Fine of 10% of weekly average income**
- Stress increases by **+1 level**

---

**S5 — Tax Deductions**  
Players can reduce their taxable income through legal deductions:

| Deduction Type       | Reduction         | Condition                           |
|----------------------|-------------------|-------------------------------------|
| Insurance Premium    | −5% taxable income| Active insurance plan               |
| Education Loan       | −3% taxable income| Active student loan repayment       |
| Medical Bills        | −5% taxable income| Hospital treatment in current period|
| Welfare Dependency   | 0% tax            | Player is registered for welfare    |

---

**S6 — Tax Evasion Risk**  
If the player attempts to under-report income (if this mechanic exists), random **tax audit events** occur every 15 in-game days.  
A failed audit results in:
- Fine of **30% of underpaid tax**
- Stress increases by **+2 levels**
- Bank account may be **temporarily frozen** for 3 in-game days

---

## Welfare / Benefit Office

The Welfare Office provides **government support to players in financial hardship**.  
It teaches players about real-world social safety nets and their limitations.

### Benefits Available

| Benefit             | Amount / Effect                     | Eligibility Condition                     |
|---------------------|-------------------------------------|-------------------------------------------|
| Ration Card         | 50% discount on basic food items    | Income below 100 coins/day                |
| Housing Subsidy     | 30 coins off rent every 24 in-game hrs| Tier 1 or 2 housing only               |
| Medical Subsidy     | 20% off hospital bills              | Income below 150 coins/day                |
| Unemployment Aid    | 20 coins / 24 in-game hrs           | Registered unemployed (see [[Work System]])|
| Education Scholarship | 50% off school fees               | Low income + no prior School Diploma      |

### Welfare Rules

**S7 — Eligibility Verification**  
Welfare benefits require **income verification** at the Welfare Office every **10 in-game days**.  
If the player's income has increased above the threshold, benefits are **automatically cancelled**.

---

**S8 — Welfare and Stress**  
Receiving welfare reduces financial stress.  
Active welfare benefits reduce Stress by **−0.5 levels** as long as they are active.

---

**S9 — Benefit Cap**  
Players cannot receive more than **3 welfare benefits simultaneously**.  
Applying for a fourth benefit automatically cancels the least valuable active benefit.

---

**S10 — Ration Card Usage**  
The Ration Card is used at the **Local Market / Bazaar** only.  
It cannot be used at the Supermarket or Restaurant.

---

## Court Building

The Court resolves **legal disputes, fines, and criminal cases** that arise from game events.

### Court Cases

| Case Type              | Trigger                                 | Possible Outcome                          |
|------------------------|-----------------------------------------|-------------------------------------------|
| Unpaid Fine            | Tax evasion, operating without permit   | Pay fine or face asset freeze             |
| Labor Dispute          | Unpaid wages complaint (from [[Work System]])| Recovery of owed wages              |
| Loan Default           | Bank blacklist appeal                   | Extended repayment terms or rejection     |
| Theft Victim Claim     | Filed after robbery event               | Partial coin recovery (if police filed)   |
| Eviction Dispute       | Filed against landlord                  | Temporary eviction halt (5 in-game days)  |

### Court Rules

**S11 — Court Fee**  
Filing any case at the Court costs **100 coins**.  
This fee is non-refundable regardless of outcome.

---

**S12 — Case Duration**  
Court cases take **3 in-game days** to resolve.  
During this period, the case outcome is pending.  
The player receives a **notification** when the verdict is delivered.

---

**S13 — Stress During Legal Proceedings**  
Having an open court case increases Stress by **+1 level** for the duration of the case.  
Winning a case reduces Stress by **−1 level**.  
Losing a case increases Stress by **+1 level**.

---

## Police Station

The Police Station handles **criminal events, theft, and safety** in Dhaniverse.

### Player Interactions

| Interaction          | Cost    | Description                                      |
|----------------------|---------|--------------------------------------------------|
| Report Theft         | Free    | File a report after a theft event                |
| File Complaint       | Free    | Report harassment or illegal activity            |
| Pay Bail             | Varies  | Release from detention after rule violation      |

### Police Events

**S14 — Theft Events**  
Random theft events occur in **unsafe map zones** (poorly lit areas, crowded markets at night).  
Theft removes **10–20% of coins carried** by the player (not coins in the bank).  
Filing a police report within **1 in-game hour** of the theft gives a **30% chance of partial coin recovery**.

---

**S15 — Rule Violations**  
If the player is caught violating game rules (no business permit, tax evasion discovered by audit):
- Police can **detain the player** for 10 real-world minutes
- During detention, the player cannot move, work, or perform actions
- Paying bail releases the player immediately

| Violation              | Detention Duration | Bail Cost |
|------------------------|--------------------|-----------|
| No Business Permit     | 10 minutes         | 100 coins |
| Tax Audit Failure      | 10 minutes         | 200 coins |
| Informal Loan Conflict | 5 minutes          | 80 coins  |

---

**S16 — Safe Zone vs. Unsafe Zone**  
The map is divided into **Safe Zones and Unsafe Zones**.  
Theft and crime events **only occur in Unsafe Zones**.  
Being in a Safe Zone near a Police Station reduces theft event probability by **50%**.

---

## Why Government and Legal Is Important

This system teaches the player that **civic institutions are both constraints and protections**:
- Taxes reduce income but fund welfare that helps during hardship
- Ignoring taxes or permits creates risk that can spiral out of control
- The court provides justice but costs time, money, and stress
- The police offer safety but the player must be proactive

The system simulates the **invisible infrastructure of economic life** — the rules that shape behavior even when the player isn't thinking about them.

---

## Connections

- **[[Work System]]** — Tax is calculated on work income; labor disputes go to court
- **[[Housing_System]]** — Property registration required at City Hall; eviction disputes resolved in court
- **[[Banking_Finance_System]]** — Tax defaults can freeze bank accounts; loan disputes handled by court
- **[[Stress]]** — Unpaid fines, legal cases, and detention all increase stress
- **[[Food]]** — Ration card applies discounts at local market
