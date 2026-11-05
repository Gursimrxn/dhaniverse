---
tags: [gdd, overview, vision, pillars]
date: 2026-11-05
version: 2.1
aliases: [Game Overview, Project Vision]
---

# Game Overview

> **Current direction — 2026-11-05:** Build the full game through a shared
> neighborhood with meaningful choices, independent permitted action order and
> verified recovery. [Choice design](14_Player_Choices_And_Consequences.md) and
> [development scope](12_Product_Direction.md) refine the milestone. Branding

## Elevator Pitch
**Dhaniverse** is a multiplayer life simulation game where players navigate a realistic economic world — earning income, managing expenses, building businesses, and learning financial literacy through consequence-driven gameplay. Every financial decision ripples through a shared economy shaped by all players.

**Founder clarification — 5 November 2026:** Players come to enjoy minigames,
tasks, grind, progression and life with other players. Budgeting and personal
finance are learned indirectly through decisions about what they earn, spend,
save and pursue. The activities must be enjoyable in their own right; economic
simulation and management interfaces alone do not fulfill the game idea.


---

## Game Pillars

The [lore and repeatable-play proposal](16_Lore_And_Repeatable_Play.md) connects
the existing river-and-rail history to activity mastery, personal ambitions and
shared economic life beyond initial upgrades. New narrative details remain
proposals; qualification, clock and reward rules retain their owners.

### 1. Real Economic Simulation
The economy is not cosmetic. Prices emerge from supply and demand. Loans use the canonical flat-term rate and repayment schedule; savings interest follows its own cycle. Default has cascading consequences. Player actions — buying, selling, producing, hoarding — visibly shift market conditions.

### 2. Consequence-Driven Learning
Players learn financial literacy not through tutorials but through outcomes. Skip rent → eviction. Ignore health → illness → cannot work → cannot pay bills. The systems teach through experience.

### 3. Social Economics
Finance is social. Players lend to each other, form self-help groups, hire employees, build reputation. Trust and reliability are measurable assets that affect access to opportunities.

---

## Genre & Platform
- **Genre:** Multiplayer Life Simulation / Economic Strategy / Serious Game
- **Platform:** Web-based (browser)
- **Perspective:** Walkable 3D city. The founder's 13 October direction is medium, angled third-person with a visible character, avoiding steep overhead framing. The current `game/` comparison still uses its earlier first-person controller; the new camera and browser acceptance remain implementation work.
- **Target Player Count:** 50-500 concurrent players per persistent world long term; not a rendering budget or measured capacity. Full-game shared economic interaction is the target; event-specific cuts do not restrict this vision.

---

## Target Audience

### Primary: Young Adults (16-25)
- Students and early-career individuals
- Limited real-world financial experience
- Familiar with simulation and multiplayer games
- Need: Practical financial concepts in engaging format

### Secondary: Educators & Institutions
- Schools, colleges, financial literacy programs
- Need: Measurable learning outcomes, classroom integration
- Use case: Supplement to financial education curriculum

### Tertiary: General Gamers
- Fans of simulation, strategy, and economy games
- Need: Deep, engaging systems with meaningful choices
- Attracted by: Emergent gameplay, player-driven economy

---

## Experience Goals

### Player Should Feel:
- **Empowered** — Their choices matter and have visible consequences
- **Challenged** — Resources are limited, trade-offs are real
- **Connected** — Other players are part of their economic reality
- **Curious** — Systems interact in discoverable ways
- **Competent** — Financial concepts become intuitive through play

### Player Should NOT Feel:
- Overwhelmed — Systems unlock gradually
- Punished unfairly — Recovery paths always exist
- Isolated — Economy is shared, not solitary
- Lectured — Learning is implicit, not didactic

---

## Core Differentiators

### vs. Traditional Life Sims
- Real economic simulation, not fixed prices
- Multiplayer economy, not single-player
- Explicit financial literacy layer

### vs. Stock Market Simulators
- Full life simulation, not just trading
- Social and reputation systems
- Consequence mechanics (health, stress, housing)

### vs. Educational Games
- Game-first design, not lesson-first
- Emergent complexity, not scripted scenarios
- Persistent multiplayer world

---

## Success Metrics

### Player Metrics
- Financial Health Score improvement over 30 days
- Savings rate increase
- Debt-to-income ratio management
- Business creation and sustainability

### Learning Metrics
- Demonstrated understanding of compound interest
- Risk management behavior (insurance adoption)
- Budget allocation skills
- Investment diversification

### Engagement Metrics
- Daily active users
- Session length (target: 30-60 minutes)
- Player-to-player transactions
- Community formation (SHG groups, business employment)

---

## Scope

### In Scope (Core)
- Complete economic simulation engine
- 24 interconnected game systems
- Multiplayer social layer
- Financial dashboard with advisor
- Player-driven market economy

### Out of Scope (Initial Release)
- Mobile native apps (web-first)
- Voice chat
- Ray-traced/Forward+-dependent graphics requirements or desktop-only effects that prevent the browser baseline; optional native builds do not replace web acceptance.
- Autonomous AI-driven NPC economies; deterministic baseline supply/demand and entry-level NPC work remain permitted economy safety nets.
- Public real-money deposits or cash-prize gameplay. The separate build demonstration uses explicitly labelled operator-funded demo funds; the simulation currency is not redeemable.

---

## References
- [[10_City_Art_Direction|City Art Direction]] — canonical production art plan: districts, materials, foliage, gates
- [[reference/00_INDEX|Research Index]] — Full system documentation
- [[02_Core_Gameplay|Core Gameplay Loop]]
- [[04_Economy_Design|Economy Design]]
