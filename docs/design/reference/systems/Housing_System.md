Housing represents the player's **living situation and residential stability** in Dhaniverse.  
It directly affects **[[Stress]], [[Health]], [[Energy]] recovery, and financial outflow**.  
Where the player lives determines how well they rest, how fast they recover, and how much of their income goes toward rent or mortgage payments.

Housing interacts with:
• [[Health]]  
• [[Energy]]  
• [[Stress]]  
• Economy  
• [[Banking_Finance_System]]

---

## Housing Tiers

Players can live in one of five housing situations, ranging from no shelter to owned property.

| Tier | Type              | Cost                        | Rest Quality | Home Storage |
|------|-------------------|-----------------------------|--------------|--------------|
| 0    | No Housing        | Free                        | None         | None         |
| 1    | Room Rental       | 40 coins / 24 in-game hours | Low          | None (bed provided) |
| 2    | Small House       | 80 coins / 24 in-game hours | Moderate     | 150 units (provisional) |
| 3    | Apartment         | 150 coins / 24 in-game hours| High         | 300 units (provisional) |
| 4    | Owned Property    | Mortgage payment (see below)| High         | 300/600/1200 units by type (provisional) |

Home storage is **bounded** per the canonical storage model
(see 11_Canonical_Game_Rules.md §6); "unlimited home storage" (Inventory
draft) is retired. Furniture occupies floor cells, which never consume
storage units.

---

## Housing Systems

#### Rest and Recovery

**S1 — No Housing Penalty**  
If the player has **no housing**, they sleep on the street.  
Effects:
- [[Energy]] idle recovery is **disabled**
- [[Health]] decay rate increases by **10%**
- Stress increases by **+1 level every 24 in-game hours**

---

**S2 — Room Rental Recovery**  
Living in a **Room Rental** provides basic shelter.  
Effects:
- [[Energy]] idle recovery functions at **50% efficiency**
- No health bonus or penalty from housing
- No stress modification from housing alone
- The room includes a **landlord-provided bed** (rest is available at 50%
  efficiency without the player owning furniture), but **no home storage**
- Room rentals are rooms inside multi-unit buildings with persistent
  server-assigned unit addresses — see
  [11_Canonical_Game_Rules.md](../../11_Canonical_Game_Rules.md) §7
---

**S3 — Small House Recovery**  
Living in a **Small House** provides stable shelter.  
Effects:
- [[Energy]] idle recovery functions at **100% efficiency**
- [[Health]] decay rate decreases by **5%**
- Stress is reduced by **−0.5 levels every 24 in-game hours** if rent is paid on time

---

**S4 — Apartment Recovery**  
Living in an **Apartment** provides comfortable shelter.  
Effects:
- [[Energy]] idle recovery functions at **100% efficiency**
- [[Health]] decay rate decreases by **10%**
- Stress is reduced by **−1 level every 24 in-game hours** if rent is paid on time

---

#### Rent and Payment Rules

**S5 — Rent Due Cycle**  
Rent is automatically deducted every **24 in-game hours**.  
If the player does not have sufficient coins when rent is due:
- Rent is marked as **unpaid**
- [[Stress]] increases by **+1 level**
- Player has a **grace period of 12 in-game hours** (= 12 real hours; canonical, [11_Canonical_Game_Rules.md](../../11_Canonical_Game_Rules.md) §5) to pay

---

**S6 — Eviction Rule**  
If the player fails to pay rent within the **grace period**:
- Player is **evicted** and moved to Tier 0 (No Housing)
- Stress increases by **+2 levels**
- Player must find new housing through a **Property Broker**

---

**S7 — Advance Rent Option**  
Players may pay rent **up to 7 days in advance** to avoid payment stress.  
Paying in advance provides:
- No late-payment risk for the prepaid period
- Stress reduction of **−1 level** (one-time, for financial security)

---

## Property Broker

The Property Broker facilitates **finding, renting, and purchasing** housing.

### Services

| Service             | Cost       | Description                                      |
|---------------------|------------|--------------------------------------------------|
| Rental Listing      | Free       | Browse available rental properties               |
| Lease Agreement     | 50 coins   | Official rental contract (required for Tier 2+) |
| Property Purchase   | 200 coins  | Broker fee for buying a property                 |
| Property Valuation  | 80 coins   | Get current market value of a property           |

### Rules

- Players must visit a **Property Broker** to change housing tiers
- Moving to a higher tier requires signing a **Lease Agreement**
- Players cannot purchase property without visiting the broker first

---

## Housing Finance / Mortgage Office

Players who cannot pay the full cost of a property upfront can take a **mortgage**.

### Mortgage Plans

| Plan         | Down Payment | Monthly Installment         | Loan Term       |
|--------------|--------------|-----------------------------|-----------------|
| Basic Loan   | 20% of price | Fixed coins / 24 in-game hrs| 30 in-game days |
| Standard Loan| 30% of price | Fixed coins / 24 in-game hrs| 20 in-game days |
| Fast Loan    | 50% of price | Fixed coins / 24 in-game hrs| 10 in-game days |

### Rules

- Mortgage payments are automatically deducted every **24 in-game hours**
- Missing a mortgage payment increases **Stress by +1 level**
- Missing **3 consecutive payments** results in **property repossession**
- Repossession moves the player back to **Tier 0 (No Housing)**
- Players must have a minimum income history to qualify (see [[Work System]])
- Mortgage is obtained through the **[[Banking & Finance System]]**

---

## Owned Property Benefits

Once a property is fully paid off, the player **owns it outright**.

Effects:
- No recurring housing payment
- [[Stress]] permanently reduced by **−1 level** from housing security
- Player can **rent out the property** to earn passive income
- Property can be sold through the **Property Broker**

---

## Why Housing Is Important

Housing creates **long-term financial planning pressure**. Without housing stability, the player suffers compounding penalties — poor energy recovery leads to lower work efficiency, which leads to lower income, which threatens rent payment. Players must balance:
- Short-term cash flow for rent
- Long-term investment in property ownership
- Risk of eviction vs. over-committing to mortgage payments

---

## Connections

- **[[Energy]]** — Housing quality directly controls idle recovery efficiency
- **[[Health]]** — Housing tier affects daily health decay rate
- **[[Stress]]** — Unpaid rent and eviction spike stress; stable housing reduces it
- **[[Banking_Finance_System]]** — Mortgages are issued through the bank
- **[[Work System]]** — Income from jobs funds rent; owned property can generate passive rent income
