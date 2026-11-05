The Transport and Infrastructure System governs how players **move across the game map, manage connectivity, and navigate daily logistics** in Dhaniverse.  
Transport affects **energy consumption, time efficiency, and access** to key locations.  
Infrastructure services (telecom/internet) expand what the player can do without physically traveling.

This system interacts with:
• [[Energy]]  
• [[Work System]]  
• [[Stress]]  
• Economy  
• [[Commerce_System]]

---

## Transport Overview

Players can travel across the map in multiple ways:

| Mode              | Speed       | Energy Cost   | Coin Cost       |
|-------------------|-------------|---------------|-----------------|
| Walking           | 1× (base)   | Normal        | Free            |
| Bus               | 3× faster   | None          | 10 coins / trip |
| Train             | 6× faster   | None          | 25 coins / trip |
| Auto/Taxi (event) | 4× faster   | None          | 40 coins / trip |

---

## Transport Systems

#### Movement and Energy

**S1 — Walking Energy Cost**  
Walking is covered in the [[Energy]].  
Each energy bar supports **200 steps or 15 minutes**, whichever comes first.

---

**S2 — Vehicle Transport Saves Energy**  
Using a **Bus or Train** does not consume energy during transit.  
The player's energy bar timer is **paused** while in transit.  
This allows players to travel long distances without depleting energy needed for work.

---

**S3 — Transport and Time Efficiency**  
Since buses and trains are faster, players can reach distant locations (hospital, college, tax office) without spending excessive real-world time.  
This creates a **coin-vs-energy trade-off**: pay for transport and save energy, or walk for free and use energy.

---

## Bus Stop

Bus stops are located **throughout the map** at key intervals.  
They connect residential zones, market areas, work zones, and civic buildings.

### Bus Rules

**S4 — Bus Route Coverage**  
Each bus route connects a set of **predefined stops**.  
Players must walk to the nearest bus stop before boarding.

---

**S5 — Bus Wait Time**  
Buses arrive at each stop every **5 real-world minutes**.  
Players who arrive between buses must wait.  
Waiting does not consume energy but the idle timer (see [[Energy]] Rule S8) does apply during wait.

---

**S6 — Bus Pass**  
Players can purchase a **Bus Pass** for unlimited bus rides for 24 in-game hours.

| Pass Type     | Cost       | Duration         |
|---------------|------------|------------------|
| Single Ride   | 10 coins   | One trip         |
| Daily Pass    | 50 coins   | 24 in-game hours |
| Weekly Pass   | 250 coins  | 7 in-game days   |

A Weekly Pass is **economical if the player makes more than 4 bus trips per day**.

---

**S7 — Bus and Stress**  
Missing a bus during a **time-sensitive event** (e.g., a shift about to start, rent due) increases Stress by **+0.5 levels**.

---

## Railway Station

The Railway Station connects **distant zones on the map** that buses do not reach efficiently.  
It is the fastest mode of transport in Dhaniverse.

### Train Rules

**S8 — Train Route Coverage**  
Trains connect **major zones** only: city center, industrial zone, outer residential zones.  
Players must walk or take a bus to reach the railway station first.

---

**S9 — Train Ticket Cost**  
| Ticket Type   | Cost       | Duration              |
|---------------|------------|-----------------------|
| Single Ride   | 25 coins   | One trip              |
| Monthly Pass  | 400 coins  | 30 in-game days unlimited |

A Monthly Pass is **economical if the player commutes by train daily**.

---

**S10 — Train Delay Events**  
Random events may cause train delays of **5–10 real-world minutes**.  
Arriving late to a job shift due to a train delay does not trigger a pay penalty (a one-time grace rule per delay event).

---

**S11 — Train and Long Distance Jobs**  
Some high-paying jobs are **only accessible via train** (located in distant industrial or corporate zones).  
Players who invest in a Monthly Pass unlock these jobs effectively.

---

## Telecom / Internet Office

The Telecom Office provides **connectivity services** that allow players to perform tasks remotely.  
Having an active internet plan reduces the need to physically travel to certain locations.

### Telecom Plans

| Plan         | Cost                    | Data Limit     | Services Unlocked                   |
|--------------|-------------------------|----------------|-------------------------------------|
| Basic Plan   | 30 coins / 24 in-game hrs| Low           | Job alerts, bank balance check       |
| Standard Plan| 60 coins / 24 in-game hrs| Medium        | + Stock app, welfare portal access  |
| Premium Plan | 100 coins / 24 in-game hrs| Unlimited    | + Remote work, online education     |

### Telecom Rules

**S12 — Connectivity Requirement**  
Certain game actions require an **active internet plan**:
- Viewing stock portfolio (without visiting broker office)
- Receiving job alert bonuses (requires at least Basic Plan + Smartphone from [[Commerce_System]])
- Accessing online education courses (requires Premium Plan + Laptop)

---

**S13 — Remote Work**  
Players with a **Premium telecom plan and a Laptop** can perform **remote office shifts** without traveling to the office building.  
Remote shifts:
- Earn **90% of normal pay** (slight penalty for not being on-site)
- Consume **0.5 energy bars** instead of 1 (lower physical demand)
- Can be done from home, reducing transport costs

---

**S14 — Plan Interruption**  
If the player misses a telecom payment, the plan becomes **inactive** within **12 in-game hours**.  
All remote-access features are disabled until payment resumes.  
Stress increases by **+0.5 levels** if inactive plan causes a missed job alert.

---

**S15 — Power Cut Events**  
During infrastructure failure game events, internet connectivity may be **unavailable for 1–3 in-game hours**.  
Players with a **Premium Plan** are given **priority restoration** and experience **50% shorter outage duration**.

---

## Why Transport and Infrastructure Is Important

Transport turns **location on the map into a meaningful constraint**.  
Without fast transport, players lose energy reaching distant locations.  
Without internet, players must physically travel to do tasks that could be handled remotely.  
The system creates a **recurring cost vs. convenience** trade-off that mirrors real urban life:
- Walking is free but slow and energy-intensive
- Bus and train cost coins but preserve energy for work
- Internet costs coins but saves travel time and enables remote income

Investing in transport and connectivity is an **efficiency multiplier** — it doesn't earn money directly, but it makes earning money faster and cheaper.

---

## Connections

- **[[Energy]]** — Transport preserves energy by eliminating step-based consumption during travel
- **[[Work System]]** — Train access unlocks high-pay distant jobs; remote work enabled by telecom plan
- **[[Stress]]** — Missed buses during critical moments add stress; consistent transport reduces logistical pressure
- **[[Banking_Finance_System]]** — Investment app and bank access possible remotely with proper plan
- **[[Education_System]]** — Online courses require Premium telecom plan + Laptop
