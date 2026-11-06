---
tags: [spec, database, schema, postgresql]
date: 2026-11-05
version: 2.1
aliases: [Database Schema, PostgreSQL Schema]
---

# Database Schema Specification

## Overview

This document defines the PostgreSQL database schema for Dhaniverse v2.0+. The database stores all persistent player data, economic state, and multiplayer information.

**Technology:** PostgreSQL 15+
**ORM:** SQLx (compile-time checked queries)
**Migration Tool:** sqlx-cli or similar

**Status 5 November 2026:** Tables below are a proposed PostgreSQL production
contract. `docker/migrations/` belongs to the legacy backend and is not verified
as deployed here. The fresh local runtime uses
`runtime/crates/local-server/src/schema.sql`.
Its durable SQLite tables are a narrow development adapter, not this complete
schema. Reconcile the proposed tables, canonical rules, domain types and actual
production migrations together before referring to them as implemented.
---

## Core Design Principles

1. **All money stored as integers** (cents) to avoid floating-point precision issues
2. **Timestamps in UTC** using `TIMESTAMPTZ`
3. **Soft deletes** for audit trails (deleted_at instead of DELETE)
4. **JSONB for flexible data** (inventory, event history, etc.)
5. **Indexes on frequently queried columns** (player_id, timestamps, status)
6. **Foreign key constraints** for referential integrity
7. **Stable identity:** every addressable world entity (district, parcel, housing unit, business premises, resource site) has an immutable primary key assigned by authored content or server provisioning. Cosmetic generation seeds change *placement decoration only*; they must never renumber or repurpose an ID (canonical rules).
8. **Mutable stocks are server rows, not files:** resource availability, housing vacancy, and lease state live in these tables and only in these tables. Nothing in this schema stores anything that a client (browser cache, PCK manifest, local save) is allowed to be authoritative about.

---

## Core Tables

### players

Stores player account information and core state.

```sql
CREATE TABLE players (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(32) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_login_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    
    -- Core Survival Systems (fractional-safe fixed-point integers; canonical per
    -- 11_Canonical_Game_Rules 3.1/3.3/3.4 + IN-3: foods act at 0.14-bar granularity,
    -- health drifts 5 pts / 2 h, stress moves in 0.5-band steps — SMALLINT bar/percent
    -- counters cannot round-trip these, so storage uses steps/basis-points/tenths.)
    energy_steps SMALLINT NOT NULL DEFAULT 1000 CHECK (energy_steps BETWEEN 0 AND 1000),
    bonus_steps SMALLINT NOT NULL DEFAULT 0 CHECK (bonus_steps BETWEEN 0 AND 400), -- rules 3.4 boost pool, separate column, IN-3
    energy_last_tick_at TIMESTAMPTZ DEFAULT NOW(),
    health_basis_points INTEGER NOT NULL DEFAULT 10000 CHECK (health_basis_points BETWEEN 500 AND 10000), -- 1/100 %
    health_last_decay_at TIMESTAMPTZ DEFAULT NOW(),
    stress_tenths SMALLINT NOT NULL DEFAULT 10 CHECK (stress_tenths BETWEEN 10 AND 120), -- 0.1 per band unit
    
    -- Location (Y-up metres; x east, y server-computed height, z south — Godot convention.
    -- y is authoritative server data (walkable surface), never a client assertion.)
    current_zone VARCHAR(50) NOT NULL DEFAULT 'meadow',
    position_x DOUBLE PRECISION NOT NULL DEFAULT 0,
    position_y DOUBLE PRECISION NOT NULL DEFAULT 0,
    position_z DOUBLE PRECISION NOT NULL DEFAULT 0,
    
    -- Session state (in-memory, persisted for recovery)
    is_online BOOLEAN DEFAULT false,
    last_heartbeat_at TIMESTAMPTZ
);

CREATE INDEX idx_players_username ON players(username);
CREATE INDEX idx_players_online ON players(is_online) WHERE is_online = true;
CREATE INDEX idx_players_zone ON players(current_zone);
```

### player_wallets

Stores immediate cash balance.

```sql
CREATE TABLE player_wallets (
    player_id UUID PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
    balance_cents BIGINT NOT NULL DEFAULT 0 CHECK (balance_cents >= 0),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### player_bank_accounts

Stores bank account information including savings, fixed deposits, and loans.

```sql
CREATE TABLE player_bank_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    account_type VARCHAR(20) NOT NULL CHECK (account_type IN ('savings', 'fixed_deposit', 'loan')),
    
    -- For savings and fixed deposits
    balance_cents BIGINT NOT NULL DEFAULT 0 CHECK (balance_cents >= 0),
    interest_rate DECIMAL(5, 4) NOT NULL DEFAULT 0.0050, -- 0.5% per 24h
    last_interest_applied_at TIMESTAMPTZ,
    
    -- For fixed deposits
    locked_until TIMESTAMPTZ,
    maturity_amount_cents BIGINT,
    
    -- For loans
    principal_cents BIGINT NOT NULL DEFAULT 0,
    remaining_cents BIGINT NOT NULL DEFAULT 0,
    interest_rate_loan DECIMAL(5, 4) NOT NULL,
    term_days SMALLINT,
    started_at TIMESTAMPTZ,
    next_payment_at TIMESTAMPTZ,
    missed_payments SMALLINT DEFAULT 0,
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paid', 'defaulted')),
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_bank_accounts_player ON player_bank_accounts(player_id);
CREATE INDEX idx_bank_accounts_type ON player_bank_accounts(account_type);
CREATE INDEX idx_bank_accounts_status ON player_bank_accounts(status);
```

### player_inventory

Stores player inventory items with stacking and expiry.

```sql
CREATE TABLE player_inventory (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    item_id VARCHAR(100) NOT NULL,
    item_name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL CHECK (category IN ('food', 'medicine', 'goods', 'equipment')),
    quantity SMALLINT NOT NULL DEFAULT 1 CHECK (quantity > 0),
    expiry_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_inventory_player ON player_inventory(player_id);
CREATE INDEX idx_inventory_category ON player_inventory(category);
CREATE INDEX idx_inventory_expiry ON player_inventory(expiry_at) WHERE expiry_at IS NOT NULL;
```

### player_housing

Stores housing information including rent and mortgages.

```sql
CREATE TABLE player_housing (
    player_id UUID PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
    housing_tier SMALLINT NOT NULL DEFAULT 0 CHECK (housing_tier BETWEEN 0 AND 4),
    housing_type VARCHAR(50),
    rent_cents_per_day BIGINT,
    last_rent_paid_at TIMESTAMPTZ,
    rent_due_at TIMESTAMPTZ,
    
    -- For owned property
    is_owned BOOLEAN DEFAULT false,
    purchase_price_cents BIGINT,
    mortgage_remaining_cents BIGINT,
    mortgage_monthly_cents BIGINT,
    mortgage_next_payment_at TIMESTAMPTZ,
    
    -- Home storage (items stored at home)
    storage_items JSONB DEFAULT '{}',
    
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### player_education

Stores education progress and qualifications.

```sql
CREATE TABLE player_education (
    player_id UUID PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
    education_level SMALLINT NOT NULL DEFAULT 0 CHECK (education_level BETWEEN 0 AND 4),
    current_course VARCHAR(100),
    course_progress SMALLINT DEFAULT 0,
    course_total_sessions SMALLINT,
    course_started_at TIMESTAMPTZ,
    student_loan_cents BIGINT DEFAULT 0,
    student_loan_next_payment_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### player_reputation

Stores social reputation score and tier.

```sql
CREATE TABLE player_reputation (
    player_id UUID PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
    reputation_score SMALLINT NOT NULL DEFAULT 0 CHECK (reputation_score BETWEEN 0 AND 100),
    reputation_tier SMALLINT NOT NULL DEFAULT 1 CHECK (reputation_tier BETWEEN 1 AND 5),
    last_decay_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### player_employment

Stores current job information and work history.

```sql
CREATE TABLE player_employment (
    player_id UUID PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
    current_employer_id UUID, -- NULL if unemployed
    current_job_type VARCHAR(50),
    current_wage_per_shift_cents BIGINT,
    shifts_completed SMALLINT DEFAULT 0,
    consecutive_shifts SMALLINT DEFAULT 0,
    last_shift_completed_at TIMESTAMPTZ,
    unemployment_benefit_eligible BOOLEAN DEFAULT false,
    unemployment_benefit_started_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

---

## Economic Tables

### items

Catalog of all tradeable items with base prices and properties.

```sql
CREATE TABLE items (
    id VARCHAR(100) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL,
    base_price_cents BIGINT NOT NULL,
    elasticity DECIMAL(3, 2) NOT NULL DEFAULT 1.0,
    is_perishable BOOLEAN DEFAULT false,
    shelf_life_days SMALLINT,
    energy_recovery_steps SMALLINT NOT NULL DEFAULT 200,  -- 1/200 bar (rules 3.3: fruits 0.14 bars = 28 steps)
    health_impact_basis_points SMALLINT NOT NULL DEFAULT 0, -- 1/100 % per item (rules 3.3: +1% = 100)
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_items_category ON items(category);
```

### market_state

Stores current market prices, supply, and demand for all items.

```sql
CREATE TABLE market_state (
    item_id VARCHAR(100) PRIMARY KEY REFERENCES items(id),
    current_supply BIGINT NOT NULL DEFAULT 0,
    current_demand BIGINT NOT NULL DEFAULT 0,
    market_price_cents BIGINT NOT NULL,
    price_momentum DECIMAL(5, 4) DEFAULT 0,
    last_updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Price history (last 7 days as JSON array)
    price_history JSONB DEFAULT '[]'
);
```

### transactions

Transaction ledger for all financial transactions.

```sql
CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_player_id UUID REFERENCES players(id) ON DELETE SET NULL,
    to_player_id UUID REFERENCES players(id) ON DELETE SET NULL,
    item_id VARCHAR(100) REFERENCES items(id) ON DELETE SET NULL,
    
    transaction_type VARCHAR(50) NOT NULL CHECK (transaction_type IN (
        'purchase', 'sale', 'transfer', 'interest', 'fee', 'wage', 
        'rent', 'tax', 'loan_disbursement', 'loan_repayment', 'insurance_premium', 'insurance_payout'
    )),
    
    quantity SMALLINT DEFAULT 1,
    price_per_unit_cents BIGINT,
    total_cents BIGINT NOT NULL,
    
    category VARCHAR(50), -- For financial dashboard breakdown
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_transactions_from_player ON transactions(from_player_id);
CREATE INDEX idx_transactions_to_player ON transactions(to_player_id);
CREATE INDEX idx_transactions_type ON transactions(transaction_type);
CREATE INDEX idx_transactions_created_at ON transactions(created_at);
```

### businesses

Stores business information for player-owned businesses.

```sql
CREATE TABLE businesses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    business_name VARCHAR(100) NOT NULL,
    business_type VARCHAR(50) NOT NULL,
    
    -- Location
    location_id VARCHAR(64) REFERENCES world_entities(id), -- stable parcel/premises identity (proposed table below)
    position_x DOUBLE PRECISION, -- presentation coords, derived from location placement
    position_y DOUBLE PRECISION,
    position_z DOUBLE PRECISION,
    
    -- Financials
    capital_cents BIGINT NOT NULL,
    daily_revenue_cents BIGINT DEFAULT 0,
    daily_expenses_cents BIGINT DEFAULT 0,
    
    -- Employees
    max_employees SMALLINT DEFAULT 0,
    
    -- Status
    is_active BOOLEAN DEFAULT true,
    permit_expires_at TIMESTAMPTZ,
    
    -- Reputation
    business_reputation_score SMALLINT DEFAULT 50,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_businesses_owner ON businesses(owner_id);
CREATE INDEX idx_businesses_zone ON businesses(zone);
CREATE INDEX idx_businesses_active ON businesses(is_active) WHERE is_active = true;
```

### business_employees

Stores employee relationships for businesses.

```sql
CREATE TABLE business_employees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    
    wage_per_shift_cents BIGINT NOT NULL,
    role VARCHAR(50),
    hired_at TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT true,
    
    UNIQUE(business_id, employee_id, is_active)
);

CREATE INDEX idx_employees_business ON business_employees(business_id);
CREATE INDEX idx_employees_employee ON business_employees(employee_id);
```

---

## Multiplayer Tables

### player_relationships

Stores friend connections and blocks.

```sql
CREATE TABLE player_relationships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    related_player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    relationship_type VARCHAR(20) NOT NULL CHECK (relationship_type IN ('friend', 'blocked')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(player_id, related_player_id)
);

CREATE INDEX idx_relationships_player ON player_relationships(player_id);
CREATE INDEX idx_relationships_related ON player_relationships(related_player_id);
```

### shg_groups

Self-Help Groups for microfinance.

```sql
CREATE TABLE shg_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_name VARCHAR(100) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT true
);

CREATE INDEX idx_shg_active ON shg_groups(is_active) WHERE is_active = true;
```

### shg_members

SHG group membership.

```sql
CREATE TABLE shg_members (
    group_id UUID NOT NULL REFERENCES shg_groups(id) ON DELETE CASCADE,
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    contribution_cents BIGINT DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    
    PRIMARY KEY (group_id, player_id)
);

CREATE INDEX idx_shg_members_player ON shg_members(player_id);
```

### shg_loans

Group-backed loans.

```sql
CREATE TABLE shg_loans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES shg_groups(id) ON DELETE CASCADE,
    borrower_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    
    principal_cents BIGINT NOT NULL,
    remaining_cents BIGINT NOT NULL,
    interest_rate DECIMAL(5, 4) NOT NULL,
    
    started_at TIMESTAMPTZ DEFAULT NOW(),
    next_payment_at TIMESTAMPTZ,
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paid', 'defaulted'))
);

CREATE INDEX idx_shg_loans_group ON shg_loans(group_id);
CREATE INDEX idx_shg_loans_borrower ON shg_loans(borrower_id);
```

### player_loans

Direct player-to-player loans.

```sql
CREATE TABLE player_loans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lender_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    borrower_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    
    principal_cents BIGINT NOT NULL,
    remaining_cents BIGINT NOT NULL,
    interest_rate DECIMAL(5, 4) NOT NULL,
    repayment_period_days SMALLINT,
    
    started_at TIMESTAMPTZ DEFAULT NOW(),
    next_payment_at TIMESTAMPTZ,
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paid', 'defaulted', 'in_dispute'))
);

CREATE INDEX idx_player_loans_lender ON player_loans(lender_id);
CREATE INDEX idx_player_loans_borrower ON player_loans(borrower_id);
```

### trade_listings

Market listings for player-to-player trade.

```sql
CREATE TABLE trade_listings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    item_id VARCHAR(100) NOT NULL REFERENCES items(id),
    quantity SMALLINT NOT NULL,
    price_per_unit_cents BIGINT NOT NULL,
    
    listed_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    is_active BOOLEAN DEFAULT true,
    buyer_id UUID REFERENCES players(id) ON DELETE SET NULL,
    sold_at TIMESTAMPTZ
);

CREATE INDEX idx_trade_listings_seller ON trade_listings(seller_id);
CREATE INDEX idx_trade_listings_item ON trade_listings(item_id);
CREATE INDEX idx_trade_listings_active ON trade_listings(is_active) WHERE is_active = true;
CREATE INDEX idx_trade_listings_expires ON trade_listings(expires_at);
```

---

## Government & Legal Tables

### tax_records

Tax payment records.

```sql
CREATE TABLE tax_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    
    tax_week_start TIMESTAMPTZ NOT NULL,
    tax_week_end TIMESTAMPTZ NOT NULL,
    income_cents BIGINT NOT NULL,
    tax_rate DECIMAL(5, 4) NOT NULL,
    tax_cents BIGINT NOT NULL,
    
    paid_at TIMESTAMPTZ,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'overdue', 'fine_applied')),
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_tax_records_player ON tax_records(player_id);
CREATE INDEX idx_tax_records_week ON tax_records(tax_week_start);
```

### welfare_benefits

Welfare benefit records.

```sql
CREATE TABLE welfare_benefits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    benefit_type VARCHAR(50) NOT NULL,
    amount_cents BIGINT NOT NULL,
    
    started_at TIMESTAMPTZ DEFAULT NOW(),
    next_verification_at TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT true,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_welfare_player ON welfare_benefits(player_id);
CREATE INDEX idx_welfare_active ON welfare_benefits(is_active) WHERE is_active = true;
```

### court_cases

Legal disputes and court proceedings.

```sql
CREATE TABLE court_cases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plaintiff_id UUID REFERENCES players(id) ON DELETE SET NULL,
    defendant_id UUID REFERENCES players(id) ON DELETE SET NULL,
    
    case_type VARCHAR(50) NOT NULL,
    description TEXT,
    
    filed_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ,
    verdict VARCHAR(50),
    penalty_cents BIGINT,
    
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'resolved', 'dismissed'))
);

CREATE INDEX idx_court_plaintiff ON court_cases(plaintiff_id);
CREATE INDEX idx_court_defendant ON court_cases(defendant_id);
CREATE INDEX idx_court_status ON court_cases(status);
```

---

## Insurance Tables

### insurance_policies

Active insurance policies.

```sql
CREATE TABLE insurance_policies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    plan_type VARCHAR(20) NOT NULL CHECK (plan_type IN ('basic', 'standard', 'premium')),
    
    hospital_coverage_percent SMALLINT NOT NULL,
    clinic_coverage_percent SMALLINT NOT NULL,
    pharmacy_coverage_percent SMALLINT NOT NULL,
    premium_cents_per_day BIGINT NOT NULL,  -- canonical seed: Basic 6000 / Standard 10000 / Premium 15000 (rules §9 row 10)
    
    started_at TIMESTAMPTZ DEFAULT NOW(),
    last_premium_paid_at TIMESTAMPTZ,
    next_premium_at TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT true
);

CREATE INDEX idx_insurance_player ON insurance_policies(player_id);
CREATE INDEX idx_insurance_active ON insurance_policies(is_active) WHERE is_active = true;
```

### insurance_claims

Insurance claim records.

```sql
CREATE TABLE insurance_claims (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_id UUID NOT NULL REFERENCES insurance_policies(id) ON DELETE CASCADE,
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    
    medical_bill_cents BIGINT NOT NULL,
    coverage_amount_cents BIGINT NOT NULL,
    player_payment_cents BIGINT NOT NULL,
    
    treatment_type VARCHAR(50),
    treatment_at TIMESTAMPTZ,
    
    filed_at TIMESTAMPTZ DEFAULT NOW(),
    processed_at TIMESTAMPTZ,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'under_appeal'))
);

CREATE INDEX idx_claims_player ON insurance_claims(player_id);
CREATE INDEX idx_claims_policy ON insurance_claims(policy_id);
CREATE INDEX idx_claims_status ON insurance_claims(status);
```

---

## Events System Tables

### economic_events

Active and resolved economic events.

```sql
CREATE TABLE economic_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type VARCHAR(50) NOT NULL,
    severity VARCHAR(20) NOT NULL CHECK (severity IN ('minor', 'moderate', 'major')),
    
    description TEXT,
    affected_categories JSONB, -- Array of affected item categories
    supply_modifier DECIMAL(5, 2),
    demand_modifier DECIMAL(5, 2),
    
    started_at TIMESTAMPTZ DEFAULT NOW(),
    ends_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'resolved'))
);

CREATE INDEX idx_events_active ON economic_events(status) WHERE status = 'active';
CREATE INDEX idx_events_ends_at ON economic_events(ends_at);
```

---

## System Tables

### system_state

Global system configuration and state.

```sql
CREATE TABLE system_state (
    key VARCHAR(100) PRIMARY KEY,
    value JSONB NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Initial values:
-- economy_tick_interval_minutes: 5
-- world_start_time: timestamp
-- active_player_count: integer
```

### audit_log

Audit trail for sensitive operations.

```sql
CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID REFERENCES players(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    details JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_audit_player ON audit_log(player_id);
CREATE INDEX idx_audit_action ON audit_log(action);
CREATE INDEX idx_audit_created_at ON audit_log(created_at);
```

---

## Indexes Summary

**Performance-critical indexes:**
- `players.username` — Login queries
- `players.is_online` — Online player list
- `players.current_zone` — Zone-based queries
- `player_bank_accounts.player_id` — Financial queries
- `transactions.from_player_id`, `transactions.to_player_id` — Transaction history
- `transactions.created_at` — Time-based queries
- `trade_listings.item_id` — Market browsing
- `trade_listings.expires_at` — Cleanup job

**Composite indexes to consider:**
- `transactions(player_id, created_at)` — Player transaction history
- `market_state(item_id, last_updated_at)` — Price updates

---

## Migration Strategy

1. **Initial migration:** Create all tables with initial schema
2. **Seed data:** Populate items catalog, system_state
3. **Index creation:** Create indexes after data load for performance
4. **Future migrations:** Version-controlled migrations using SQLx
5. **Forward-only contract:** no column is renamed in place without a major-bump migration plan (rename + dual-read window + removal ticket); clients resolve field names per `protocol_version` (API Contract §Contract Versioning), and there are no undocumented compatibility aliases.

---

## v2.1 Proposed Delta (design — NOT implemented; see Overview status note)

Reconciles the schema with [Canonical Game Rules](../../design/11_Canonical_Game_Rules.md) and the browser client ([3D Frontend Production](../frontend/3D_Frontend_Production.md)). These statements ship only with numbered migrations (`003_…`+); until then every one is a promise about the future, and no running system exhibits them.

### 1. Server-authoritative housing units and leases

```sql
-- PROPOSED
CREATE TABLE housing_units (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),          -- stable address ID, independent of seed
    structure_id UUID NOT NULL REFERENCES structures(id),    -- multi-unit building (kit-placed parcel)
    unit_label VARCHAR(20) NOT NULL,                         -- "2B" style; display-only, never identity
    district_id VARCHAR(50) NOT NULL,                        -- content district (City Art Direction)
    bedrooms SMALLINT NOT NULL CHECK (bedrooms BETWEEN 0 AND 6),
    storage_capacity_units SMALLINT NOT NULL,                -- bounded home storage (rule: tier-derived)
    base_rent_cents_per_day BIGINT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'vacant'
        CHECK (status IN ('vacant','leased','reserved','retired')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (structure_id, unit_label)
);

CREATE TABLE leases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    unit_id UUID NOT NULL REFERENCES housing_units(id),
    player_id UUID NOT NULL REFERENCES players(id),
    started_at TIMESTAMPTZ NOT NULL,
    rent_cents_per_day BIGINT NOT NULL,
    last_rent_paid_at TIMESTAMPTZ,
    rent_due_at TIMESTAMPTZ NOT NULL,
    grace_hours SMALLINT NOT NULL DEFAULT 12,                -- canonical eviction grace: 12 in-game h
    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','grace','evicted','terminated')),
    ends_at TIMESTAMPTZ
);
```

`player_housing` (above) is then **replaced by** lease-derived state rather than being a second source of truth; migration copies rows and drops the table only after services read leases. Vacancy visible to the client = count of `status='vacant'` rows the server chose to publish — clients never compute or fake stock (browser client rule §7).

### 2. Bounded storage accounting

```sql
-- PROPOSED
CREATE TABLE home_storage_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lease_id UUID NOT NULL REFERENCES leases(id) ON DELETE CASCADE,
    item_id VARCHAR(100) NOT NULL REFERENCES items(id),
    quantity SMALLINT NOT NULL CHECK (quantity > 0),
    stored_at TIMESTAMPTZ DEFAULT NOW()
);
```

Replaces free-form `player_housing.storage_items JSONB`; sum(`quantity`) per
lease must fit the unit's `storage_capacity_units`, enforced inside the same
transaction as additions/transfers. One item quantity consumes one storage unit
under canonical rules §6. Placed furniture uses a separate floor-cell budget and
must not be stored or charged through these portable-item capacity rows. Its
placement schema is separate implementation design, not supplied by this draft.

### 3. World content identity

```sql
-- PROPOSED
CREATE TABLE world_entities (
    id VARCHAR(64) PRIMARY KEY,              -- stable authored ID, e.g. "fq.bank", "mw.stall.014"
    kind VARCHAR(32) NOT NULL,               -- service_anchor | parcel | resource_site | structure
    district_id VARCHAR(50) NOT NULL,
    chunk_x SMALLINT, chunk_y SMALLINT,      -- cosmetic streaming hint ONLY (mutable re-layout)
    manifest_version INT NOT NULL,           -- which published WorldManifest revision placed this
    properties JSONB NOT NULL DEFAULT '{}'
);
```

Rules embedded by shape: `chunk_x/chunk_y` are nullable presentation hints (a re-grid of render chunks updates them; nothing else changes); `id` and `district_id` never move due to cosmetic seed changes; resource-site stocks live in a dedicated server table keyed by this ID (`resource_sites` — PROPOSED sibling table: `site_id FK, item_id, stock_units, regen_per_tick, last_tick_at`) — a protected/decorative tree (City Art Direction §Vegetation) simply has **no** resource-site row, so nothing harvestable is implied by rendering.

### 4. Idempotency and revision support

```sql
-- PROPOSED
CREATE TABLE idempotency_keys (
    key UUID PRIMARY KEY,
    player_id UUID NOT NULL REFERENCES players(id),
    request_hash VARCHAR(64) NOT NULL,       -- sha256 of canonical request body
    response JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()     -- retention 24 h (cleanup job), matches API contract
);
```

Plus `players.state_revision BIGINT NOT NULL DEFAULT 0` bumped inside every authoritative state transaction — the number the WebSocket envelope's `revision` compares against, and the value a browser resync diffs from.

### 5. Rest semantics

No new table: rest becomes a **rate evaluation** — `last_rested_at TIMESTAMPTZ` + server tick arithmetic (5%/2 min × housing efficiency, requires bed access per canonical rules). The retired instant-recharge behavior needs no column; anything storing "rested = full bars" is removed by design.

### 6. Positions

`players.position_x/y/z` (and the businesses trio) are **Y-up metres** matching the contract in [API Contract delta 7](../api/API_Contract.md): DECIMAL(10,2) was replaced by `DOUBLE PRECISION` in the table above so SQL storage, wire JSON, and Godot doubles share one precision story; `position_y` is server-written only. **Legacy drift:** `docker/migrations/001_initial_schema.sql` still has the legacy `SMALLINT` bars + 2D `DECIMAL(10,2)` columns — this schema text is the target the migration `003` must implement (design, not implemented).

### 7. Migration hygiene (retirements)

- `player_housing` → superseded by `leases` join (drop after services cut over)
- `businesses` float coords remain for rendering; `location_id` FK (proposed above) becomes placement truth (parcel identity beats coordinates)
- `energy_bars`/`health_percent`/`stress_level` columns → converted to steps/basis-points/tenths by `003_…` scaling existing rows (bars×200, pct×100, level×10); game is pre-launch, no external consumers to alias

---

## Data Retention

- **Audit logs:** 90 days
- **Transaction history:** 365 days (archive older to cold storage)
- **Trade listings:** Auto-delete after expiry + 7 days
- **Court cases:** Keep resolved cases for 180 days
- **Economic events:** Keep resolved events for 30 days

---

## References

- [[../../design/04_Economy_Design|Economy Design]] — Economic architecture
- [[../../design/05_Systems_Map|Systems Map]] — System dependencies
- [[../../specs/economy/Economy_Engine_Spec|Economy Engine Spec]] — Backend economic logic
- [[../../design/11_Canonical_Game_Rules|Canonical Game Rules]] — source of lease/stock/rest/identity semantics
- [[../frontend/3D_Frontend_Production.md|3D Frontend Production]] — why chunks are cosmetic hints, not ownership
