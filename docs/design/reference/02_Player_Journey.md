# Player Journey & Onboarding

This document describes the player's progression through Dhaniverse from first login to long-term engagement. It defines the onboarding experience, key milestones, and progression pathways.

**Current use:** a guided journey example, not a compulsory runtime queue.
[Choice design](../14_Player_Choices_And_Consequences.md) and
[interaction briefs](../15_Neighborhood_Interaction_Briefs.md) govern the next
playable milestone; players can skip hints and choose any eligible action.
Canonical prerequisites and values still apply.

---

## New Player Onboarding (First 30 Minutes)

### Step 1: Character Creation & Identity
**Duration:** 2 minutes

**Player Actions:**
- Choose username
- Receive temporary housing (Tier 1 - Room Rental, first 3 days free)
- Receive starting coins: 100 coins
- Receive basic clothing (Tier 1)

**System Interactions:**
- [[Multiplayer_Social_Layer]] - Profile creation
- [[Housing_System]] - Temporary housing assignment
- [[Inventory_System]] - Starting items

**Learning Objective:** Understand that housing and clothing are basic requirements.

---

### Step 2: Core Systems Introduction
**Duration:** 5 minutes

**Tutorial Flow:**
1. **Energy Tutorial**
   - Energy bar explained (5 bars total)
   - Walk 200 steps to see consumption
   - Eat starting food to see recovery
   - Message: "Energy is your capacity to act. Without it, you cannot work."

2. **Health Tutorial**
   - Health bar explained
   - Health decay demonstrated (5% every 2 hours)
   - Message: "Health declines over time. Poor choices accelerate decay."

3. **Stress Tutorial**
   - Stress meter explained (1-12 scale)
   - Stress reduction through rest shown
   - Message: "Stress affects everything. Keep it low to perform well."

**System Interactions:**
- [[Energy]] - Movement and recovery
- [[Health]] - Decay mechanics
- [[Stress]] - Pressure system
- [[Food]] - Energy recovery

**Learning Objective:** Understand the three core survival systems and their interdependence.

---

### Step 3: First Work Experience
**Duration:** 10 minutes

**Tutorial Flow:**
1. Visit Labor Office
2. View available jobs (Street Stall or Farm only - no education required)
3. Accept first job
4. Complete first shift (30 minutes real-time, accelerated for tutorial to 5 minutes)
5. Receive first payment
6. See Financial Dashboard for first time

**System Interactions:**
- [[Work_System]] - Job access and shifts
- [[Government_Legal_System]] - Labor Office
- [[Financial_Dashboard]] - Income tracking
- [[Banking_Finance_System]] - Wallet balance

**Learning Objective:** Work is the primary income source. Different jobs pay differently.

---

### Step 4: Basic Needs Management
**Duration:** 8 minutes

**Tutorial Flow:**
1. Rent payment notification (tutorial preview: "your 3 free days end on day 4; first rent will be due then" — the onboarding Tier 1 grant includes 3 free days, so no rent is actually due at 24h; canonical matrix row 31)
2. Visit Local Market to purchase food
3. Experience price fluctuation (scripted tutorial event: an **active supply modifier** that the price engine converts into >= +10% movement over at least 2 five-minute ticks — events never write prices directly; canonical matrix row 32)
4. Purchase food within budget
5. Return home and rest

**System Interactions:**
- [[Housing_System]] - Rent cycle
- [[Commerce_System]] - Market purchasing
- [[Supply_Demand_System]] - Price fluctuation
- [[Food]] - Nutrition
- [[Energy]] - Rest recovery

**Learning Objective:** Expenses are recurring. Market prices change. Budgeting is necessary.

---

### Step 5: Financial Planning Introduction
**Duration:** 5 minutes

**Tutorial Flow:**
1. Financial Dashboard highlights:
   - Savings rate (likely negative after first purchases)
   - Debt monitor (none yet)
   - Financial Health Score (likely 20-39 - Struggling)
2. Advisor character speaks: "Your savings rate is thin. A rate below 10% means you keep less than a tenth of what you earn — and a **negative** rate means you are spending more than you earn. Try to keep expenses below income."
3. Tutorial ends with goal: "Achieve Financial Health Score of 40+"

**System Interactions:**
- [[Financial_Dashboard]] - Score calculation
- [[Banking_Finance_System]] - Savings tracking

**Learning Objective:** Financial health is measurable. Goals provide direction.

---

## Early Game Progression (Days 1-7)

### Milestone 1: Stable Housing (Day 3)
**Goal:** Upgrade to Tier 2 housing (Small House) or maintain Tier 1 without eviction

**Player Actions Required:**
- Complete 10 work shifts consistently
- Pay rent on time
- Maintain health above 20%
- Keep stress below Level 8

**Reward:**
- Unlocks Home Storage (Tier 2+)
- Better energy recovery efficiency
- Stress reduction from stable housing

**Learning:** Consistency matters. Housing stability enables better resource management.

---

### Milestone 2: Basic Literacy (Day 5)
**Goal:** Complete Basic Literacy at Public Library

**Player Actions Required:**
- Visit Public Library
- Complete 10-minute Basic Literacy course
- Unlock Factory and Small Shop jobs

**Reward:**
- Access to higher-paying jobs
- +2 Social Reputation points

**Learning:** Education unlocks opportunities. Time investment in skills pays back.

---

### Milestone 3: First Savings (Day 7)
**Goal:** Achieve 50 coins in bank savings

**Player Actions Required:**
- Open bank account at Bank
- Deposit coins from wallet
- Maintain positive balance for 24 in-game hours

**Reward:**
- Interest accrual begins (0.5% per 24 in-game hours)
- Financial Health Score improves
- The account's 3-in-game-day age requirement for loan eligibility starts counting now — the deposit itself does not waive Banking S2's conditions (account >= 3 days, balance >= 100, clean record; canonical matrix row 34)

**Learning:** Savings provide security and growth. Banking is safer than carrying cash.

---

## Mid Game Progression (Days 8-30)

### Milestone 4: School Diploma (Day 14)
**Goal:** Complete School Diploma

**Player Actions Required:**
- Save 200 coins for tuition
- Enroll at School
- Complete 3 sessions (30 minutes total)
- Manage stress during study (+1 stress baseline)

**Reward:**
- Unlock Office entry-level jobs
- +5 Social Reputation points
- Significant pay increase potential

**Learning:** Education costs money upfront but pays back long-term. Stress management during pressure periods.

---

### Milestone 5: Insurance Coverage (Day 18)
**Goal:** Purchase Basic Insurance plan

**Player Actions Required:**
- Visit Insurance Office
- Select Basic Plan (60 coins/24 hrs)
- Pay first premium
- Understand coverage percentages

**Reward:**
- 40% coverage on hospital treatment
- 30% coverage on clinic treatment
- 10% coverage on pharmacy
- Financial security against health crises

**Learning:** Insurance converts unpredictable large costs into predictable small payments. Risk management.

---

### Milestone 6: Financial Health Score 60+ (Day 25)
**Goal:** Achieve "Managing" status on Financial Dashboard

**Requirements:**
- Savings rate above 10%
- Debt-to-income ratio below 30%
- Net worth trending upward
- Emergency buffer (3 days of expenses in bank)

**Reward:**
- Unlocks Business Ownership eligibility
- Better loan terms from bank
- Reduced stress from financial security

**Learning:** Financial health is multi-dimensional. Stability requires balance across multiple factors.

---

## Late Game Progression (Days 31+)

### Milestone 7: Business Ownership (Day 40)
**Goal:** Open first business (Street Stall or Small Shop)

**Player Actions Required:**
- Achieve Reputation Tier 3 (Established, 41+ Rep)
- Complete School Diploma
- Purchase Business Permit (150 coins)
- Save starting capital (500-1200 coins depending on business type)
- Choose business location

**Reward:**
- Passive income potential
- Hire other players
- Scale income beyond job limits
- Business reputation system

**Learning:** Ownership vs. employment. Risk and reward. Management responsibilities.

---

### Milestone 8: College Degree (Day 50)
**Goal:** Complete College Degree

**Player Actions Required:**
- Save 800 coins for tuition
- Enroll at College/University
- Complete 6 sessions (60 minutes total)
- Manage stress during intensive study

**Reward:**
- Unlock Manager and Senior Office jobs
- +10 Social Reputation points
- Access to specializations
- Maximum pay tier unlocked

**Learning:** Advanced education requires significant investment but unlocks highest-paying opportunities.

---

### Milestone 9: Property Ownership (Day 70)
**Goal:** Purchase first property

**Player Actions Required:**
- Save for down payment (20-50% of property price)
- Qualify for mortgage through Bank
- Choose property (Apartment, House, or Mansion)
- Commit to monthly payments

**Reward:**
- No rent payments
- Potential rental income
- Permanent stress reduction from housing security
- Asset appreciation potential

**Learning:** Property ownership is long-term wealth building. Mortgages are leverage but create obligation.

---

### Milestone 10: Financial Health Score 80+ (Day 90)
**Goal:** Achieve "Financially Stable" status

**Requirements:**
- Savings rate above 20%
- Debt-to-income ratio below 15%
- Net worth consistently upward
- Emergency buffer (7 days of expenses)
- Diverse expense categories (no single category > 40%)

**Reward:**
- Maximum loan ceiling unlocked
- Best interest rates
- Exclusive social events access
- Community recognition on leaderboard

**Learning:** True financial stability requires discipline across all systems. Wealth without stability is fragile.

---

## Alternative Pathways

### The Fast Track (Aggressive Progression)
**Player Type:** Risk-tolerant, time-intensive

**Path:**
- Focus on work immediately, minimal rest
- Take informal loans for quick capital
- Skip insurance initially (risk)
- Rush education
- Aggressive business expansion

**Risks:**
- High stress, frequent illness
- Debt spiral potential
- Vulnerable to random events
- Reputation damage from defaults

**Rewards:**
- Faster wealth accumulation
- Early business ownership
- Higher income ceiling sooner

---

### The Steady Track (Balanced Progression)
**Player Type:** Risk-averse, methodical

**Path:**
- Maintain health and stress carefully
- Save before spending
- Purchase insurance early
- Education at comfortable pace
- Conservative business growth

**Risks:**
- Slower progression
- May miss time-sensitive opportunities
- Lower income during education phase

**Rewards:**
- Stable, predictable growth
- Resilient to crises
- Strong reputation
- Lower stress overall

---

### The Social Track (Community-Focused)
**Player Type:** Collaborative, relationship-oriented

**Path:**
- Join SHG group early
- Focus on reputation building
- Player lending and trading
- Community challenges
- Social dining for reputation

**Risks:**
- Dependent on other players
- Group loan defaults affect everyone
- Time spent on social vs. income

**Rewards:**
- Social safety net
- Better lending terms
- Reputation advantages
- Community support during crises

---

## Retention Mechanics

### Daily Engagement Hooks
- Rent payment due
- Energy/health management needs
- Job shift availability
- Market price fluctuations
- Social reputation decay (if inactive)

### Weekly Engagement Hooks
- Tax filing deadline (every 30 days)
- Insurance premium payment
- Welfare benefit verification
- Education course sessions
- Community challenges

### Monthly Engagement Hooks
- Business permit renewal
- Property mortgage milestones
- Reputation tier advancement goals
- Financial Health Score improvement targets
- Seasonal events and festivals

---

## Failure Recovery

### Recovery from Bankruptcy
**If player loses all coins and housing:**
1. Automatic Tier 0 housing (street)
2. Welfare office access unlocked
3. Basic job access restored (Street Stall, Farm)
4. Debt forgiveness option (reputation penalty)
5. 7-day recovery period with reduced penalties

**Learning:** Failure is recoverable but has consequences. Safety nets exist but are limited.

---

## Connections

- [[01_Core_Gameplay_Loop]] - Moment-to-moment actions
- [[Financial_Dashboard]] - Progress tracking
- [[Education_System]] - Milestone requirements
- [[Work_System]] - Income progression
- [[Housing_System]] - Stability progression
- [[Social_Reputation_System]] - Social progression
- All systems contribute to player journey milestones
