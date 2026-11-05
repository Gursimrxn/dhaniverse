## Health Insurance System

Health insurance protects the player from high medical expenses by covering a portion of healthcare costs.

Insurance works by paying a **regular premium**.  
In return, the insurance provider pays part of the player's **medical bills**.

Insurance interacts with:
• Hospital
• Private Clinic
• Pharmacy
• Medical Billing System

---
### Insurance Plans

Basic Plan

Premium: 60 coins every 24 in-game hours  
Coverage:
• Hospital treatment → 40% covered  
• Private clinic treatment → 30% covered  
• Medicines → 10% covered


Standard Plan

Premium: 100 coins every 24 in-game hours  
Coverage:
• Hospital treatment → 60% covered  
• Private clinic treatment → 45% covered  
• Medicines → 20% covered


Premium Plan

Premium: 150 coins every 24 in-game hours  
Coverage:
• Hospital treatment → 80% covered  
• Private clinic treatment → 60% covered  
• Medicines → 30% covered

---
### Premium Payment Rules

• Insurance remains active only if premiums are paid.
• Premiums are automatically deducted every 24 in-game hours.
• If the player cannot pay the premium, insurance becomes **inactive**.
• Coverage resumes only after the next premium payment.

--- 
### Insurance Claim Calculation

When a medical bill is generated, the insurance system calculates the coverage amount.

Formula:
Insurance Payout = Medical Bill × Coverage Percentage
Player Payment = Medical Bill − Insurance Payout

---
### Claim Processing Rules

• Claims are **manually filed** at the Insurance Claim Center within
**12 in-game hours** of treatment and process in **5 real minutes** —
payout is immediate upon processing. (The former "processed immediately
after treatment" line collapsed filing and settlement; the Claim Center
owns the process: see Insurance_Claim_Center.md and canonical matrix
row 28.)  
• Coverage applies only if the insurance plan is **active** at the time of
treatment.  
• Claims apply to:
  - hospital treatment
  - clinic treatment
  - pharmacy medicine purchases (batchable within a 24 in-game hour batch
    window; each purchase must still be inside its own 12-hour filing
    expiry)
---
### Plan Upgrade and Downgrade

Players may change insurance plans.

Rules:
• Plan changes take effect after the next premium cycle.
• Upgrading increases premium payments.
• Downgrading reduces coverage benefits.

---
### Insurance Activation Rule

Insurance must be purchased **before entering Critical Health State**.

Players cannot purchase insurance after health reaches 10%.

---
### Insurance Economic Role

Insurance converts large unpredictable medical costs into smaller predictable premium payments.

This creates strategic choices:

Pay small regular premiums for protection  
or  
Save money but risk paying large hospital bills.