# Core Gameplay Loop

The core gameplay loop defines what players actually do moment-to-moment in Dhaniverse. This document describes the fundamental cycle of actions that drive player engagement and learning.

---

## The Primary Loop

```
Manage Energy & Health → Work to Earn Income → Spend on Needs → Plan for Future → Repeat
```

### Step 1: Manage Energy & Health
**Player Action:** Monitor energy bars and health percentage. Consume food, rest at home, visit healthcare if needed.

**System Interactions:**
- [[Energy]] - Movement and work capacity
- [[Health]] - Physical well-being affecting all actions
- [[Stress]] - Mental pressure accelerating decay
- [[Food]] - Energy recovery
- [[Housing_System]] - Rest and recovery efficiency

**Player Decision:** "Do I have enough energy to work? Is my health stable enough to risk a shift?"

---

### Step 2: Work to Earn Income
**Player Action:** Choose a job based on education level, health, and energy. Complete shifts to earn coins.

**System Interactions:**
- [[Work_System]] - Job availability and pay
- [[Education_System]] - Job tier requirements
- [[Energy]] - Consumed during work
- [[Health]] - Affects pay rate and job eligibility
- [[Stress]] - Reduces efficiency and blocks high-tier jobs

**Player Decision:** "Which job can I do? Will the pay justify the energy cost?"

---

### Step 3: Spend on Needs
**Player Action:** Purchase food, pay rent, buy medicine, pay insurance premiums, handle daily expenses.

**System Interactions:**
- [[Commerce_System]] - Purchasing goods
- [[Food]] - Nutrition
- [[Housing_System]] - Rent payments
- [[Healthcare System]] - Medical treatment
- [[Insurance]] - Premium payments
- [[Banking_Finance_System]] - Payment processing

**Player Decision:** "What do I need right now vs. what can I afford? Should I save or spend?"

---

### Step 4: Plan for Future
**Player Action:** Save money, invest in education, purchase insurance, consider business ownership, build reputation.

**System Interactions:**
- [[Banking_Finance_System]] - Savings, investments, loans
- [[Education_System]] - Long-term skill investment
- [[Insurance]] - Risk management
- [[Business_Ownership_System]] - Entrepreneurship
- [[Social_Reputation_System]] - Community standing
- [[Financial_Dashboard]] - Tracking and reflection

**Player Decision:** "Should I invest in education now? Can I afford insurance? Is this the right time to start a business?"

---

## Secondary Loops

### Crisis Recovery Loop
Triggered when health reaches 10% or below (Critical State), stress reaches high levels, or illness occurs.

```
Crisis State → Seek Healthcare → Pay Medical Bills → Recover at Home → Return to Normal Loop
```

**Purpose:** Teaches consequence of neglect and recovery process.

### Social Interaction Loop
Triggered by player choice to engage with multiplayer features.

```
Find Players → Trade/Lend/Hire → Build Reputation → Unlock Opportunities → Repeat
```

**Purpose:** Teaches social capital and community-based economics.

### Business Management Loop
Unlocked after establishing financial stability and reputation.

```
Hire Employees → Manage Operations → Track Profit → Reinvest or Expand → Repeat
```

**Purpose:** Teaches ownership vs. employment economics.

---

## Session Structure

### Typical Play Session (30-60 minutes)

**First 10 minutes: Assessment**
- Check energy, health, stress levels
- Review financial dashboard
- Plan immediate priorities

**Next 20-40 minutes: Action**
- Complete work shifts
- Handle necessary purchases
- Manage inventory
- Engage in social activities (optional)

**Final 10 minutes: Planning**
- Review financial health score
- Make savings/investment decisions
- Set goals for next session
- Secure housing/rest

### Daily In-Game Rhythm
Players typically repeat the core loop 2-3 times per in-game day:
1. Morning: Assess, work first shift
2. Midday: Handle needs, second shift if energy allows
3. Evening: Rest, plan, prepare for next day

---

## Engagement Hooks

### Short-Term Hooks (Per Session)
- Energy management urgency ("I need to eat before I can work")
- Rent payment deadline ("Rent is due in 2 hours")
- Shift availability ("Job posting expires soon")
- Market price fluctuations ("Food prices are low today")

### Medium-Term Hooks (Per Week)
- Education course completion
- Loan repayment milestones
- Reputation tier advancement
- Business profit targets

### Long-Term Hooks (Per Month)
- Home ownership goal
- Business expansion
- Financial health score improvement
- Education degree completion

---

## Failure States

### Soft Failure (Recoverable)
- Eviction from housing → Find new housing, pay penalties
- Job termination → Reapply, wait period
- Loan default → Repay with interest, reputation damage
- Illness → Expensive treatment, work interruption

### Hard Failure (Game Over / Reset)
- (None designed - game focuses on learning through consequence, not permanent failure)

**Design Philosophy:** Players should always have a path to recovery, even if difficult. This encourages learning from mistakes rather than restarting.

---

## Player Agency

### Meaningful Choices
Players make decisions that have real consequences:
- **Time vs. Money:** Walk (free, slow, energy-intensive) vs. Bus (costs coins, fast, saves energy)
- **Short-term vs. Long-term:** Spend now on food vs. save for education
- **Risk vs. Security:** Informal lender (fast, expensive) vs. Bank loan (slower, cheaper)
- **Individual vs. Social:** Work alone vs. join SHG group

### Trade-Offs
Every advantage has a cost:
- Higher education → Higher pay but tuition cost and time investment
- Better housing → Better recovery but higher rent/mortgage
- Insurance → Security but ongoing premium cost
- Business ownership → Unlimited income potential but risk and management burden

---

## Learning Through Gameplay

### Implicit Learning
Players absorb concepts through gameplay without explicit instruction:
- Compound interest (through loan interest accumulation)
- Supply and demand (through market price fluctuations)
- Risk management (through insurance decisions)
- Social capital (through reputation mechanics)

### Explicit Learning
The [[Financial_Dashboard]] and system "Why X Is Important" sections make learning explicit:
- Savings rate visualization
- Debt cost tracking
- Financial health scoring
- Advisor character feedback

---

## Pacing

### Early Game (Days 1-7)
- Focus: Survival, basic needs
- Systems: Energy, Health, Work, Food, Housing
- Goal: Achieve stable housing and consistent income

### Mid Game (Days 8-30)
- Focus: Financial stability, education
- Systems: Banking, Education, Insurance, Commerce
- Goal: Improve job tier, build savings, establish reputation

### Late Game (Days 31+)
- Focus: Wealth building, ownership
- Systems: Business Ownership, Investments, Multiplayer
- Goal: Own property, run business, achieve financial health score 80+

---

## Connections

- [[Energy]] - Capacity for all actions
- [[Health]] - Foundation for work and survival
- [[Stress]] - Accelerator of problems
- [[Work_System]] - Income generation
- [[Banking_Finance_System]] - Financial management
- [[Financial_Dashboard]] - Reflection and tracking
- All systems feed into and are affected by the core loop
