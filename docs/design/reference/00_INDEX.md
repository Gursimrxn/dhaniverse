# Dhaniverse - Game Design Documentation Index

**Project:** Dhaniverse - A multiplayer financial literacy education game  
**Purpose:** This index provides structured navigation for AI agents and developers working on Dhaniverse systems.

---

## Quick Navigation for AI Agents

### Start Here for Implementation
- [[00_INDEX]] - This master index document
- [[01_Core_Gameplay_Loop]] - Moment-to-moment player experience
- [[02_Player_Journey]] - Onboarding, progression, and goals
- [[03_Events_System]] - Random events and world dynamics

### Core Systems (Implementation Priority)
1. [[Energy]] - Physical capacity and movement
2. [[Health]] - Physical well-being and decay
3. [[Stress]] - Mental pressure and consequences
4. [[Work_System]] - Primary income source
5. [[Banking_Finance_System]] - Savings, loans, investments

### Economic Systems
- [[Supply_Demand_System]] - Market price mechanics
- [[Commerce_System]] - Purchasing goods and services
- [[Business_Ownership_System]] - Running businesses
- [[Player_Trade_System]] - Player-to-player exchange
- [[Financial_Dashboard]] - Player financial tracking

### Social & Multiplayer
- [[Multiplayer_Social_Layer]] - Player interactions
- [[Social_Reputation_System]] - Community standing
- [[Education_System]] - Qualifications and skills

### Support Systems
- [[Housing_System]] - Living situation and rest
- [[Healthcare System]] - Medical treatment
- [[Insurance]] - Risk management
- [[Insurance_Claim_Center]] - Claims processing
- [[Government_Legal_System]] - Taxes, permits, legal
- [[Transport_Infrastructure_System]] - Movement and connectivity
- [[Inventory_System]] - Item management
- [[Food]] - Nutrition and energy recovery
- [[Restaurant_Dhaba_System]] - Dining establishments

### Canonical Authority
- [[../11_Canonical_Game_Rules]] - **Read first.** Precedence ladder, single time model, canonical tables, conflict matrix. Where any document below disagrees with it, the canonical file wins until that document is migrated.

### Housing Architecture
- [[notes/House - Player lobby]] - Concise canonical housing-architecture summary (replaces the former exploratory note; see its status header)

---

## System Interconnection Map

### Core Survival Loop
Energy ↔ Health ↔ Stress ↔ Work ↔ Housing
- All four core systems affect each other directly
- Disruption in one cascades to others

### Economic Flow
Work → Income → Banking/Finance → Spending → Commerce
- Income flows through financial systems
- Decisions in one affect capacity in others

### Social Layer
Multiplayer_Social_Layer ↔ Business_Ownership ↔ Player_Trade ↔ Social_Reputation
- All multiplayer features route through social layer
- Reputation affects access across all systems

---

## Implementation Order Recommendation

### Phase 1: Core Mechanics (Foundation)
1. Energy System - movement and capacity
2. Health System - decay and recovery
3. Stress System - pressure mechanics
4. Food System - basic energy recovery
5. Inventory System - item management

### Phase 2: Economic Engine
6. Work System - income generation
7. Banking_Finance_System - savings and basic loans
8. Commerce_System - purchasing
9. Supply_Demand_System - market prices
10. Housing_System - rest and rent

### Phase 3: Advanced Economics
11. Business_Ownership_System - entrepreneurship
12. Player_Trade_System - player exchange
13. Financial_Dashboard - tracking and education
14. Insurance - risk management
15. Government_Legal_System - taxes and permits

### Phase 4: Social & Multiplayer
16. Multiplayer_Social_Layer - player infrastructure
17. Social_Reputation_System - community standing
18. Education_System - qualifications
19. Events_System - world dynamics

### Phase 5: Support Systems
20. Healthcare System - medical treatment
21. Insurance_Claim_Center - claims processing
22. Transport_Infrastructure_System - connectivity
23. Restaurant_Dhaba_System - dining
24. Illness_State - severe consequences

---

## File Naming Convention

For Obsidian compatibility and AI readability:
- System files use underscore naming: `System_Name.md`
- Reference format: `[[System_Name]]`
- No spaces in filenames
- Consistent capitalization

---

## Known Issues & TODOs

### Documentation Gaps
- [x] Master index created
- [x] Core Gameplay Loop documented
- [x] Player Journey documented
- [x] Events System created
- [x] Canonical Game Rules created (conflict resolution + precedence)

### Content Cleanup
- [x] Healthcare_System.md carries no duplicate Insurance section (pointer only)
- [ ] Fix wiki-link inconsistencies (Energy vs Energy System, Insurance vs Insurance System, etc.) — cosmetic; canonical rules now resolve semantic conflicts
- [x] Operative-value standardization completed for: health/energy/stress/food/work/housing/inventory/supply-demand/banking/insurance/claims/healthcare/government/education/journey

### Architecture Notes
- House - Player lobby.md was rewritten as a short canonical summary; former contrary rates (120/300/700 rent, 48h lockout, 10s instant rest) are superseded per canonical matrix rows 16-18

---

## For AI Agents Reading This

When implementing a system:
1. Read the system's main document
2. Check "Connections" section for dependent systems
3. Verify referenced systems are implemented
4. Follow the implementation order when possible
5. Cross-reference with Core_Gameplay_Loop for context

All systems are designed to be modular but interconnected. Implement in phases to ensure each phase is functional before building on it.
