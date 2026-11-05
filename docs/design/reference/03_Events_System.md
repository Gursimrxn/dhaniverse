# Events System

The Events System generates random occurrences that affect the game world, creating supply/demand fluctuations, presenting opportunities, and introducing challenges. Events make the economy dynamic and teach players to adapt to changing conditions.

It interacts with:
• [[Supply_Demand_System]]
• [[Commerce_System]]
• [[Work_System]]
• [[Healthcare System]]
• [[Government_Legal_System]]
• All economic systems

---

## Event Categories

### Supply Shocks
Events that reduce the availability of goods or services, driving prices up.

### Demand Spikes
Events that increase demand for specific goods or services, driving prices up.

### Supply Surges
Events that increase availability of goods, driving prices down.

### Infrastructure Failures
Events that disrupt transport, internet, or utilities.

### Health Crises
Events that affect population health, increasing demand for medical services.

### Economic Events
Events that affect employment, wages, or financial markets.

### Social Events
Festivals, celebrations, or community gatherings that affect behavior and spending.

---

## Event Mechanics

**E1 — Event Triggering**
Random events occur every 5–10 in-game days.
Each event affects the game world for a specified duration (1–5 in-game days).
Multiple events can occur simultaneously, compounding effects.

---

**E2 — Event Severity**
Events have three severity levels:
- **Minor:** Small price fluctuations (5–10%), limited geographic impact
- **Moderate:** Medium fluctuations (10–20%), city-wide impact
- **Major:** Large fluctuations (20–40%), region-wide impact

---

**E3 — Event Notification**
Players receive notifications when events begin:
- Event type and duration
- Affected categories (food, medicine, transport, etc.)
- Geographic scope (which zones are affected)
- Suggested player actions

---

**E4 — Event End**
When an event ends:
- Prices gradually return to baseline over 1–2 in-game days
- Notification confirms event conclusion
- Post-event summary shows impact on player's finances

---

## Event Catalog

### Supply Shock Events

| Event Name | Duration | Severity | Effect | Affected Categories |
|------------|----------|----------|--------|-------------------|
| Drought | 3 days | Major | Fresh produce supply drops 40% | Food (fruits, vegetables) |
| Flood | 3 days | Major | Fresh produce supply drops 40% | Food (fruits, vegetables) |
| Transport Strike | 2 days | Moderate | All supply drops 20% | All categories |
| Factory Fire | 2 days | Moderate | Manufactured goods supply drops 30% | Electronics, household items |
| Harvest Failure | 4 days | Major | Grain supply drops 50% | Packaged food, bread |
| Import Blockade | 3 days | Major | Imported goods supply drops 60% | Electronics, luxury items |

---

### Demand Spike Events

| Event Name | Duration | Severity | Effect | Affected Categories |
|------------|----------|----------|--------|-------------------|
| Disease Outbreak | 5 days | Major | Medicine demand spikes 60% | Medicine, healthcare |
| Heat Wave | 3 days | Moderate | Cold drinks demand spikes 40% | Beverages, ice cream |
| Cold Snap | 3 days | Moderate | Warm clothing demand spikes 35% | Clothing |
| Festival Season | 2 days | Moderate | Food and clothing demand spikes 30% | Food, clothing |
| School Semester Start | 2 days | Minor | Education materials demand spikes 20% | Books, stationery |
| Construction Boom | 4 days | Moderate | Building materials demand spikes 25% | Tools, raw materials |

---

### Supply Surge Events

| Event Name | Duration | Severity | Effect | Affected Categories |
|------------|----------|----------|--------|-------------------|
| Bumper Harvest | 2 days | Major | Fresh produce supply jumps 50% | Food (fruits, vegetables) |
| Import Surplus | 2 days | Moderate | Imported goods supply jumps 50% | Electronics, luxury items |
| Factory Overproduction | 2 days | Minor | Manufactured goods supply jumps 30% | Electronics, household items |
| Government Subsidy | 3 days | Moderate | Essential goods supply jumps 40% | Basic food items, medicine |

---

### Infrastructure Failure Events

| Event Name | Duration | Severity | Effect | Affected Systems |
|------------|----------|----------|--------|------------------|
| Power Cut | 1–3 hours | Minor | Electronics non-functional | Commerce, telecom |
| Internet Outage | 1–3 hours | Minor | Remote services unavailable | Banking, education, work |
| Bus Strike | 1 day | Moderate | Bus transport unavailable | Transport System |
| Train Delay | 2 hours | Minor | Train delays 5–10 minutes | Transport System |
| Water Shortage | 2 days | Moderate | Restaurant operations affected | Restaurant System |

---

### Health Crisis Events

| Event Name | Duration | Severity | Effect | Affected Systems |
|------------|----------|----------|--------|------------------|
| Flu Season | 5 days | Major | Hospital demand increases 40% | Healthcare System |
| Food Poisoning Alert | 3 days | Moderate | Street food demand drops 30% | Food System |
| Air Quality Warning | 4 days | Moderate | Outdoor activities discouraged | Work System (outdoor jobs) |

---

### Economic Events

| Event Name | Duration | Severity | Effect | Affected Systems |
|------------|----------|----------|--------|------------------|
| Job Fair | 1 day | Minor | Temporary job availability increase | Work System |
| Wage Increase | 7 days | Minor | All job wages increase 5% | Work System |
| Tax Holiday | 3 days | Moderate | Tax rate reduced by 50% | Government System |
| Interest Rate Cut | 7 days | Moderate | Bank loan interest reduced 1% | Banking System |
| Market Crash | 3 days | Major | Stock values drop 30% | Banking System (investments) |

---

### Social Events

| Event Name | Duration | Severity | Effect | Affected Systems |
|------------|----------|----------|--------|------------------|
| City Festival | 2 days | Moderate | Restaurant demand spikes 50% | Restaurant System |
| Charity Drive | 3 days | Minor | Welfare benefits increased 20% | Government System |
| Sports Championship | 2 days | Minor | Restaurant/bar demand spikes 30% | Restaurant System |
| Holiday Season | 3 days | Moderate | Gift demand spikes 40% | Commerce System |

---

## Event Interactions

### Compounding Events
When multiple events affect the same category:
- Effects stack multiplicatively, not additively
- Example: Drought (40% supply drop) + Transport Strike (20% supply drop) = 52% total supply drop (0.6 × 0.8 = 0.48)

### Conflicting Events
When events have opposite effects:
- Effects cancel partially
- Stronger event dominates
- Example: Bumper Harvest (+50% supply) × Flood (−40% supply) = 1.5 × 0.6 = 0.9 of baseline, or **10% less supply**. Multiplicative modifiers do not add their percentages.

---

## Player Strategies for Events

### Preparation Strategies
- Maintain emergency buffer (3–7 days of expenses)
- Keep diverse inventory (stock up on essentials)
- Purchase insurance before health crises
- Diversify income sources

### Reactive Strategies
- Buy before demand spikes (stock up during normal prices)
- Sell during supply surges (take advantage of low prices)
- Adjust work during infrastructure failures (remote work if internet available)
- Use alternative transport during strikes

### Learning Objectives
Events teach players:
- Markets are unpredictable
- Preparation reduces vulnerability
- Adaptability is a valuable skill
- Diversification mitigates risk
- Timing matters in economic decisions

---

## Event Frequency Tuning

**Early Game (Days 1–7):**
- Minor events only
- 5–10 day intervals between events
- Focus on teaching event mechanics without overwhelming

**Mid Game (Days 8–30):**
- Minor and moderate events
- 5–7 day intervals
- Introduce compounding events

**Late Game (Days 31+):**
- All event types including major
- 3–5 day intervals
- Complex event interactions
- Higher stakes and rewards

---

## Special Events

### Rare Events (1% chance per month)
These events have dramatic, game-changing effects:

| Event Name | Effect | Duration |
|------------|--------|----------|
| Economic Boom | All wages increase 20%, prices stable | 7 days |
| Recession | All wages decrease 15%, unemployment risk increases | 10 days |
| Natural Disaster | Regional devastation, massive supply shock, emergency aid available | 5 days |
| Policy Change | New tax rates, regulations, or subsidies introduced | Permanent |

Rare events are designed to be memorable and force major strategic adjustments.

---

## Why Events Exist

Events make Dhaniverse a **living, breathing economy** rather than a static simulation. They teach players that:
- External factors beyond individual control affect financial outcomes
- Preparation and resilience are as important as optimization
- Market timing and adaptability are valuable skills
- Diversification reduces vulnerability to specific shocks

Events also create **shared experiences** across the multiplayer world — all players respond to the same drought, festival, or crisis, creating conversation and community problem-solving.

---

## Connections

- [[Supply_Demand_System]] — Events are the primary driver of price movements
- [[Commerce_System]] — Events affect availability and prices of goods
- [[Work_System]] — Events can affect job availability and wages
- [[Healthcare System]] — Health crises increase demand
- [[Government_Legal_System]] — Some events trigger government responses
- [[Transport_Infrastructure_System]] — Infrastructure failures affect transport
- [[Banking_Finance_System]] — Economic events affect investments and loans
- All systems are affected by events in category-specific ways
