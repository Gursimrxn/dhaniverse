The Insurance Claim Center is the **physical location where players file, track, and resolve insurance claims** after receiving medical treatment.  
It is separate from the **Insurance Office** (where plans are purchased) and the **Hospital/Clinic** (where treatment is received).

The Claim Center is the operational bridge between treatment and reimbursement.

It interacts with:
• [[Insurance]]  
• [[Healthcare System]]  
• [[Stress]]  
• Economy  
• [[Banking_Finance_System]]

---

## How the Claim Process Works

After receiving treatment, the claim process follows a fixed sequence:

**Step 1 — Treatment Received**  
Player receives treatment at Hospital or Private Clinic.  
A **medical bill** is generated automatically.

**Step 2 — Claim Filing**  
Player visits the **Insurance Claim Center** and files a claim against their active insurance plan.  
Filing window: **within 12 in-game hours** of treatment.  
If the player misses this window, the claim is **void** and full bill must be paid.

**Step 3 — Claim Processing**  
The Claim Center processes the claim and calculates the payout.  
Processing takes **5 real-world minutes**.

**Step 4 — Payout and Patient Payment**  
Insurance pays its portion directly.  
The player pays the remaining balance.

---

## Claim Center Services

| Service                | Cost       | Description                                        |
|------------------------|------------|----------------------------------------------------|
| File a Claim           | Free       | Submit a medical claim for active insurance        |
| Check Claim Status     | Free       | View pending or processed claims                   |
| Appeal a Rejected Claim| 50 coins   | Contest a denied or underpaid claim                |
| Pharmacy Claim         | Free       | Submit a claim for pharmacy purchases              |
| Claim History Report   | 20 coins   | Full record of all past claims and payouts         |

---

## Claim Filing Rules

**S1 — Active Plan Required**  
A claim can only be filed if the player's insurance plan was **active at the time of treatment**.  
If the plan lapsed due to missed premium payment, the claim is automatically **rejected**.

---

**S2 — Filing Deadline**  
Claims must be filed within **12 in-game hours** of the treatment event.  
Late claims are rejected regardless of plan status.  
The player receives a **notification reminder** at the 10-hour mark.

---

**S3 — Claim Calculation**  
The Claim Center applies the coverage percentage defined in [[Insurance]]:

Insurance Payout = Medical Bill × Coverage Percentage  
Player Payment = Medical Bill − Insurance Payout

This is calculated automatically — no manual input required from the player.

---

**S4 — Pharmacy Claims**  
Pharmacy claims follow the same filing process but can be **batched**.  
Multiple pharmacy purchases within the same 24 in-game hours can be filed as a **single claim**.  
Pharmacy coverage is lower than treatment coverage (see [[Insurance]]).

---

## Claim Rejection

Claims can be rejected for the following reasons:

| Rejection Reason            | What Happens                                       |
|-----------------------------|----------------------------------------------------|
| Plan inactive at treatment  | Full bill must be paid by player                   |
| Filed after 12-hour deadline| Full bill must be paid by player                   |
| Treatment not covered       | Specific treatment type excluded from plan         |
| Duplicate claim             | Same treatment claimed twice; second is void       |

---

## Claim Appeal System

If a claim is rejected and the player believes the rejection is incorrect, they can **appeal**.

**S5 — Appeal Process**  
Cost: 50 coins, paid upfront. The fee is **not returned on denial** and is **refunded on approval** (canonical matrix row 29 — the two earlier phrasings "non-refundable" and "fee is refunded" stated this same rule partially).  
Duration: **10 real-world minutes** (review period; server timer, runs offline).

Possible outcomes:
- **Appeal Approved** — Original claim is paid out; appeal fee is refunded
- **Appeal Denied** — Rejection stands; appeal fee is lost
---

**S6 — Appeal Outcome Probability**  
Appeal success depends on the **rejection reason**:

| Rejection Reason            | Appeal Success Chance |
|-----------------------------|-----------------------|
| Plan inactive at treatment  | 0% (cannot appeal)    |
| Filed after deadline        | 10%                   |
| Treatment not covered       | 40%                   |
| Duplicate claim             | 0% (cannot appeal)    |

---

**S7 — Stress During Pending Claims**  
While a claim or appeal is pending, the **medical bill remains unpaid** —
but a claim **filed within its 12-hour window suspends the unpaid-bill
Stress (+1)** for as long as it is pending (canonical matrix row 28; bill
stress otherwise applies only once the bill's 24 in-game hour due time
passes). If the claim is approved, the bill settles; if it is rejected, the
bill's stress resumes from its due state.

---

## Claim Center and Fraud Prevention

**S8 — Claim Audit Events**  
Random **claim audit events** occur every 15 in-game days.  
During an audit, all recent claims are reviewed.  
Audits do not affect legitimate claims.  
(If a fraud mechanic is introduced in future: filing false claims triggers a legal event at the [[Court Building]].)

---

## Insurance Office vs. Claim Center

These are two separate physical locations with distinct functions:

| Location              | Function                                      |
|-----------------------|-----------------------------------------------|
| Insurance Office      | Purchase plans, upgrade/downgrade, pay premiums|
| Insurance Claim Center| File claims, check status, appeal rejections  |

Players who mistake one for the other will be redirected with a notification.

---

## Why the Claim Center Exists as a Separate Building

The Claim Center creates **friction in the reimbursement process** — intentionally.  
In real life, insurance does not pay automatically. You have to file, wait, and sometimes fight for your payout.  
This mechanic teaches players that insurance is not a passive shield — it requires active management.  
The 12-hour filing deadline creates urgency. The appeal system introduces uncertainty.  
Together, they make insurance feel like a real financial instrument rather than a flat discount.

---

## Connections

- **[[Insurance]]** — Coverage percentages and plan rules are defined here; Claim Center applies them
- **[[Healthcare System]]** — Medical bills are generated here; Claim Center settles them
- **[[Stress]]** — Pending unpaid bills from rejected or unprocessed claims raise stress
- **[[Banking_Finance_System]]** — Payout is deposited into the player's account or directly offsets the bill
