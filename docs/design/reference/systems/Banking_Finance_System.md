The Banking and Finance System represents the player's **relationship with formal and informal financial institutions** in Dhaniverse.  
It governs how players **save, borrow, invest, and access emergency funds** when their income is insufficient.

This system interacts with:
• Economy  
• [[Housing System]]  
• [[Work System]]  
• [[Stress System]]  
• [[Insurance System]]

---

## Institutions Overview

| Institution              | Role                                     | Risk Level  |
| ------------------------ | ---------------------------------------- | ----------- |
| Bank / Branch            | Savings, fixed deposits, formal loans    | Low         |
| ATM Kiosk                | Cash withdrawal and balance check        | None        |
| Microfinance / SHG       | Small group-backed loans, no collateral  | Low-Medium  |
| Investment/Broker Office | Stocks, mutual funds, market instruments | Medium-High |
| Pawn Shop                | Instant cash against items               | Medium      |
| Informal Lender          | Unregulated high-interest loans          | High        |

---

## Bank System

The Bank is the **primary formal financial institution** in Dhaniverse.  
Players can store money safely, earn interest, and access credit.

### Bank Services

| Service             | Cost / Rate                    | Description                                    |
|---------------------|--------------------------------|------------------------------------------------|
| Savings Account     | Free to open                   | Stores coins; earns 0.5% interest / 24 in-game hrs |
| Fixed Deposit       | Minimum 500 coins              | Locked for 7 or 30 in-game days; earns 1% (7-day) / 2% (30-day) on maturity|
| Personal Loan       | 8% interest over loan term     | Borrow up to 3× average daily income           |
| Mortgage Loan       | 5% interest over loan term     | Long-term loan for property purchase           |
| Bank Statement      | Free                           | View transaction history                       |

### Bank Rules

**S1 — Savings Account Interest**  
Interest is added automatically every **24 in-game hours**.  
Coins must remain in the account for the full cycle to earn interest.  
Withdrawing early cancels that cycle's interest.

---

**S2 — Loan Eligibility**  
To take a loan, the player must:
- Have had a Savings Account for at least **3 in-game days**
- Have a minimum balance of **100 coins**
- Not have any existing **unpaid loan with the bank**

---

**S3 — Loan Repayment**  
Loan repayments are automatically deducted every **24 in-game hours**.  
Missing a repayment:
- Incurs a **late fee of 5% of the installment**
- Stress increases by **+1 level**

Missing **3 consecutive repayments**:
- Loan is declared **defaulted**
- Player is **blacklisted** from bank loans for 10 in-game days
- Stress increases by **+2 levels**

---

**S4 — Fixed Deposit Lock**  
Once a Fixed Deposit is created, coins cannot be withdrawn until maturity.  
Early withdrawal cancels the interest and incurs a **penalty of 1% of the deposit**.

---

## ATM Kiosk

ATMs allow players to **withdraw cash or check their bank balance** without visiting a branch.

### Services

| Service           | Cost    | Description                         |
|-------------------|---------|-------------------------------------|
| Cash Withdrawal   | Free    | Withdraw coins from savings account |
| Balance Check     | Free    | View current savings balance        |
| Mini Statement    | 5 coins | View last 5 transactions            |

### ATM Rules

- ATMs are located at **multiple points on the map**
- Players can only withdraw coins that exist in their **savings account**
- If an ATM is vandalized during a game event, it may be **temporarily out of service**

---

## Microfinance Office / SHG Center

The Microfinance Office provides **small loans to players who do not qualify for bank credit**.  
It operates through **Self-Help Groups (SHGs)** — small groups of players who vouch for each other.

### Microfinance Services

| Service         | Cost         | Description                                      |
| --------------- | ------------ | ------------------------------------------------ |
| Join SHG        | Free         | Join a group of 3-6 players; enables group lending |
| Group Loan      | 6% interest  | Loan backed by the SHG; no collateral needed     |
| Individual Loan | 10% interest | Small loan without group membership              |
| Savings Circle  | Free         | Pool savings with group; rotate payouts          |

### Microfinance Rules

**S5 — Group Loan Accountability**  
If a player takes a **Group Loan** and defaults, the **other group members' Stress increases by +1 level**.  
The group collectively owes the remaining balance.

---

**S6 — SHG Savings Circle**  
- Each member contributes **50 coins every 24 in-game hours**
- One member receives the full pool each cycle (rotates)
- This creates a **lump-sum payout** without bank interest

---

**S7 — Loan Ceiling**  
Microfinance loans are capped at **500 coins per player**.  
To access larger loans, the player must use the **Bank**.

---

## Investment / Broker Office

The Investment Office allows players to **grow wealth through financial instruments**.

### Investment Products

| Product         | Min. Amount | Risk   | Return                                 |
| --------------- | ----------- | ------ | -------------------------------------- |
| Mutual Fund     | 200 coins   | Low    | 2–4% every 7 in-game days              |
| Stock Market    | 100 coins   | Medium | −15% to +25% every 3 in-game days      |
| Government Bond | 300 coins   | None   | 1.5% every 7 in-game days (guaranteed) |

### Investment Rules

**S8 — Market Volatility Events**  
The game generates **random market events** every 5–10 in-game days.  
Events can cause stock values to rise or fall by up to **30%**.

---

**S9 — Investment Lock Period**  
Mutual funds and bonds have a **minimum holding period**.

| Product         | Lock Period           |
| --------------- | --------------------- |
| Mutual Fund     | 3 in-game days        |
| Government Bond | 7 in-game days        |
| Stocks          | No lock; sell anytime |

Selling before the lock period incurs a **penalty of 2% of the invested amount**.

---

**S10 — Broker Fee**  
Each stock transaction (buy or sell) incurs a **broker fee of 2 coins or 1% of transaction value**, whichever is higher.

---

## Pawn Shop

The Pawn Shop allows players to **get instant cash by pledging items** from their inventory.

### Rules

**S11 — Pledge and Redemption**  
The player hands over an item and receives **40–60% of the item's market value** immediately.  
The player can reclaim the item by paying back the amount plus a **15% fee within 5 in-game days**.

---

**S12 — Forfeiture Rule**  
If the player does not redeem the item within **5 in-game days**, the item is **permanently forfeited** and sold by the pawn shop.

---

**S13 — Stress Effect**  
Using the Pawn Shop increases Stress by **+0.5 levels** (reflects financial desperation).

---

## Informal Lender (Moneylender)

The Informal Lender provides **instant cash with no eligibility check** but at very high interest rates.  
This is the **last resort** option when the player cannot access any other credit.

### Loan Terms

| Loan Amount     | Interest Rate | Repayment Period |
|-----------------|---------------|------------------|
| Up to 200 coins | 25% flat      | 3 in-game days   |
| 200–500 coins   | 30% flat      | 5 in-game days   |

### Informal Lender Rules

**S14 — No Eligibility Check**  
The Informal Lender gives loans to any player regardless of credit history or bank blacklist status.

---

**S15 — Threatening Consequences**  
Missing a repayment to the Informal Lender:
- Stress increases by **+2 levels** immediately
- The lender may send **collection events** that reduce the player's inventory coins by a small amount each day until debt is cleared

---

**S16 — Debt Trap Risk**  
If the player cannot repay within the repayment period, interest compounds at **10% per additional in-game day**.  
This can quickly make the debt unrepayable through normal income alone.

---

## Why Banking and Finance Is Important

The banking and finance system creates a **realistic financial risk ladder**. Players learn through gameplay that:
- Saving in a bank is safe but slow
- Investments offer growth but carry risk
- Informal lenders offer speed but can trap the player in a debt spiral
- Microfinance is community-based and creates social accountability

Poor financial decisions compound — unpaid loans increase stress, which reduces work productivity, which reduces income, which makes repayment harder. This mirrors real-world financial pressure.

---

## Connections

- **[[Housing System]]** — Mortgages are issued through the Bank
- **[[Stress System]]** — Missed repayments and informal loans spike stress
- **[[Work System]]** — Income determines loan eligibility and repayment capacity
- **[[Insurance System]]** — Insurance premiums are a financial commitment that must be balanced against savings
