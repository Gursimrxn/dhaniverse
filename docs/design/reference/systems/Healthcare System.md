Healthcare allows players to **restore health, recover from critical conditions, and maintain long-term physical well-being**.

Healthcare interacts with the following systems:

• [[Health]]  
• [[Energy]]
• [[Stress]] 
• [[Food]]  
• Economy

Healthcare services are provided through:

• Hospital  
• Private Clinic  
• Pharmacy / Medical Store

---

# Critical Health State

A player enters **Critical Health State** when health reaches **10%**.

### Effects

• Player receives a **notification recommending medical treatment**  
• Movement speed decreases by **20%**  
• Energy consumption increases by **20%**  
• Player **cannot take most jobs**

### Rule

Players must visit a **Hospital** to restore health beyond the critical level.

---

# Hospital System

Hospitals provide **major medical treatment** for players with severe health conditions.

### Services

Basic Treatment  
Cost: 300 coins  
Health Recovery: +30%

Advanced Treatment  
Cost: 700 coins  
Health Recovery: +60%

Full Treatment  
Cost: 1200 coins  
Health Recovery: Restore to 100%

### Rules

• Hospitals can treat players at **any health level**  
• Hospitals are **required for players in Critical Health State**  
• Treatment duration: **5 minutes**  
• Player **cannot move or perform actions during treatment**  
• After treatment, the player receives a **Medication Plan**

---

# Private Clinic System

Private clinics provide **preventive care and moderate treatment**.

### Services

Preventive Checkup  
Cost: 80 coins  
Health Recovery: +10%  
Stress −1

Basic Checkup  
Cost: 150 coins  
Health Recovery: +15%

Medical Treatment  
Cost: 350 coins  
Health Recovery: +35%

### Rules

• Clinics are available when health is **above 10%**  
• Clinics **cannot treat Critical Health State**  
• Treatment duration: **2 minutes**  
• Clinics also generate a **Medication Plan**

---

# Preventive Healthcare System

Preventive care helps players **maintain health before it becomes critical**.

### Preventive Checkup Effects

Health Recovery: +10%  
Stress Reduction: −1 level

### Health Stability State

Duration: **20 minutes**

Effects:

• Natural health decay reduced by **50%**  
• Stress-related health decay reduced by **50%**

---

# Medication Plan System

After treatment, the player receives a **Medication Plan** specifying medicines, quantities, and timing.

### Rules

• Medicines must be purchased from a **Pharmacy**  
• Medicines must be taken according to **scheduled intervals**  
• Completing the full medication plan provides **additional recovery benefits**

---

# Hospital Medication Plans

### Basic Treatment Plan

Recovery Tablets  
Quantity: 3  
Interval: every 5 minutes

Vitamin Supplements  
Quantity: 2  
Interval: every 10 minutes

Recovery Duration: **15 minutes**

Completion Reward  
+10% additional health recovery

---

### Advanced Treatment Plan

Recovery Tablets  
Quantity: 4  
Interval: every 5 minutes

Antibiotics  
Quantity: 3  
Interval: every 10 minutes

Vitamin Supplements  
Quantity: 3  
Interval: every 8 minutes

Recovery Duration: **25 minutes**

Completion Reward  
+15% additional health recovery

---

### Full Treatment Plan

Recovery Tablets  
Quantity: 5  
Interval: every 5 minutes

Antibiotics  
Quantity: 4  
Interval: every 8 minutes

Vitamin Supplements  
Quantity: 4  
Interval: every 10 minutes

Recovery Duration: **30 minutes**

Completion Reward  
Health remains above **90% for 30 minutes**

---

# Private Clinic Medication Plans

### Basic Checkup Plan

Vitamin Supplements  
Quantity: 2  
Interval: every 10 minutes

Recovery Tablets  
Quantity: 2  
Interval: every 8 minutes

Recovery Duration: **10 minutes**

---

### Medical Treatment Plan

Recovery Tablets  
Quantity: 3  
Interval: every 6 minutes

Vitamin Supplements  
Quantity: 2  
Interval: every 10 minutes

Recovery Duration: **15 minutes**

Completion Reward  
+5% additional health recovery

---

# Medication Compliance Rules

• Dosing convention: the **first dose is administered at t=0** (when the
plan starts), subsequent doses at k × interval; every published plan's
recovery duration is at least its last-dose time under this convention
([11_Canonical_Game_Rules.md](../../11_Canonical_Game_Rules.md) §9 row 30)  
• Medicines must be taken at the **scheduled time intervals**  
• Taking medicines early **does not accelerate recovery**  
• Missing a dose **adds 5 minutes to recovery time**

---

# Pharmacy / Medical Store System

Pharmacies sell medicines required for recovery.

### Medicine Inventory

Recovery Tablets  
Cost: 50 coins  
Effect: gradual health restoration

Antibiotics  
Cost: 120 coins  
Effect: stabilizes health after major treatment

Vitamin Supplements  
Cost: 80 coins  
Effect: improves recovery speed

Energy Supplements  
Cost: 80 coins  
Effect: +1 Energy Bar

Stress Relief Tablets  
Cost: 70 coins  
Effect: Stress −1 level

### Rules

• Medicines can be consumed **anywhere**  
• Some medicines are **required for medication plans**

---

# Recovery System

After treatment, the player enters a **Recovery State**.

### Recovery Effects

• Energy consumption increases by **10%**  
• Movement speed decreases by **5%**  
• High-effort jobs are **temporarily restricted**

### Recovery Duration

Private Clinic Treatment → **10 minutes**  
Hospital Treatment → **20 minutes**

### Health Regeneration

Health increases **5% every 5 minutes** until reaching **60% health**.

After reaching 60%, the normal **Health system rules resume**.

For insurance coverage details, see [[Insurance]].

---

# Medical Billing System

After treatment, the player receives a **medical bill**.

### Rules

• Bills must be paid within **24 in-game hours**. Unpaid-bill Stress (+1)
applies once that due time passes; a claim filed on time suspends bill
stress while pending ([11_Canonical_Game_Rules.md](../../11_Canonical_Game_Rules.md) §9 row 28).  
• Healthcare facilities may **refuse further non-emergency treatment until bills are cleared** — **Emergency Treatment on account is never refused**, so a critical player without coins is never softlocked (Canonical Rules §3.1)

---

# Healthcare Gameplay Loop

Health declines  
→ Preventive clinic visit OR health reaches 10%  
→ Hospital / Clinic treatment  
→ Medical bill generated  
→ Insurance covers part of the cost  
→ Medication plan issued  
→ Medicines purchased from pharmacy  
→ Recovery period begins  
→ Health stabilizes.
