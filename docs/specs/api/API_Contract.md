---
tags: [spec, api, rest, contract]
date: 2026-11-05
version: 2.1
aliases: [API Contract, REST API]
---

# API Contract Specification

**Status 5 November 2026:** Proposed production REST contract and legacy
reference, not a deployed interface for the fresh runtime. The current
executable is a local JSON-lines harness documented in
runtime README. URLs and responses below are
design examples. Reconcile transport DTOs, authentication and migrations before
implementing endpoints; see open decisions OD13.

## Overview

This document proposes the REST API contract for production non-real-time operations such as authentication, account management and administrative functions.

**Base URL:** `https://api.dhaniverse.com/v1`
**Authentication:** JWT Bearer tokens
**Content-Type:** `application/json`

---

## Contract Versioning and Client Compatibility

This contract is **versioned for both client and server**; the browser (Godot web export) and the Next.js shell are separate consumers with independent release cadence.

- `protocol_version` (integer major) is declared by the client on WebSocket `auth` (`client_version` follows semver for build identity) and pinned in every REST call path (`/v1`). The server **rejects incompatible majors at handshake** (`auth_error` / `426 Upgrade Required`) instead of partially accepting.
- **No ad hoc compatible aliases.** When a field is renamed or moved, v-current keeps exactly one spelling. Aliases are permitted only as a documented, time-boxed dual-serve with a removal ticket, and never introduced silently by a client hotfix. Breaking field changes roll forward on a major bump only.
- Every state-mutating economic `POST` requires stable request identity and durable original-result replay. Header encoding and production retention are transport decisions under OD13, not the local JSON-lines request format. The earlier 24-hour retention idea is not permission to replay a financial mutation after its receipt expires.
- `request_seq`, when used for transport ordering, is distinct from authoritative player state revision. Check a durable original receipt before checking the basis of a new action. A fresh command with stale `basis_revision` is rejected with current state for resync; do not silently accept changed terms. Production wire fields must be reconciled with the runtime command boundary before implementation.
- Design deltas proposed against canonical rules are collected in **§v2.1 Design Deltas**. Both deltas and endpoint examples are target design, not evidence of deployed behavior. Current user instructions, canonical mechanics and the runtime authority boundary take precedence over conflicting legacy examples.

## Authentication

### Register Player

Create a new player account.

**POST** `/auth/register`

**Request Body:**
```json
{
  "username": "string (3-32 chars, alphanumeric)",
  "email": "string (valid email, optional)",
  "password": "string (min 8 chars)"
}
```

**Response (201 Created):**
```json
{
  "player_id": "uuid",
  "username": "string",
  "access_token": "jwt_token",
  "refresh_token": "jwt_token"
}
```

**Errors:**
- `400 Bad Request` — Invalid username/password
- `409 Conflict` — Username already exists

---

### Login Player

Authenticate and receive tokens.

**POST** `/auth/login`

**Request Body:**
```json
{
  "username": "string",
  "password": "string"
}
```

**Response (200 OK):**
```json
{
  "player_id": "uuid",
  "username": "string",
  "access_token": "jwt_token",
  "refresh_token": "jwt_token"
}
```

**Errors:**
- `401 Unauthorized` — Invalid credentials

---

### Refresh Token

Refresh access token using refresh token.

**POST** `/auth/refresh`

**Request Body:**
```json
{
  "refresh_token": "jwt_token"
}
```

**Response (200 OK):**
```json
{
  "access_token": "jwt_token",
  "refresh_token": "jwt_token"
}
```

**Errors:**
- `401 Unauthorized` — Invalid/expired refresh token

---

## Player Endpoints

### Get Player Profile

Retrieve current player's profile and core state.

**GET** `/players/profile`

**Headers:** `Authorization: Bearer {access_token}`

**Response (200 OK):**
```json
{
  "player_id": "uuid",
  "username": "string",
  "created_at": "iso8601",
  "last_login_at": "iso8601",
  
  "energy_steps": 1000,
  "bonus_steps": 0,
  "energy_last_tick_at": "iso8601",
  "health_basis_points": 10000,
  "health_last_decay_at": "iso8601",
  "stress_tenths": 10,
  
  "current_zone": "meadow",
  "position": { "x": 0.0, "y": 0.0, "z": 0.0 },
  
  "is_online": true,
  "last_heartbeat_at": "iso8601"
}
```

Canonical field semantics (see §v2.1 Design Deltas 7–8; [Canonical Game Rules](../../design/11_Canonical_Game_Rules.md) IN-2/3.3/3.4): energy = 1/200-bar steps (5 full bars = 1000) with `bonus_steps` as the separate temporary-boost pool; health = 1/100 %; stress = 0.1-band units; `position` is Y-up metres `{x, y, z}` (x east, y server-computed height, z south). **Runtime drift:** the legacy Actix handlers + SQLx models use whole-bar integers and 2D `position_x/position_y` — these payloads are the contract the code is being brought to; **design, not implemented**.

---

### Update Player Location

Update player's position (called by game client periodically).

**POST** `/players/location`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "zone": "string",
  "position": { "x": 10.5, "y": 0.0, "z": 20.3 },
  "request_seq": 51
}
```

**Response (200 OK):**
```json
{
  "zone": "string",
  "position": { "x": 10.5, "y": 0.4, "z": 20.3 },
  "state_revision": 138
}
```

`y` in the request is the client's observation; the response's `y` is the server-authoritative walkable-surface height (movement authority: Multiplayer Architecture §Eventual Consistency). REST is the fallback for this update when the WebSocket is down; the socket channel (§WebSocket Protocol) is the normal path.

---

## Wallet Endpoints

### Get Wallet Balance

Retrieve current wallet balance.

**GET** `/wallet/balance`

**Headers:** `Authorization: Bearer {access_token}`

**Response (200 OK):**
```json
{
  "balance_cents": 50000,
  "balance_display": "500.00"
}
```

---

### Transfer Coins

Transfer coins to another player.

**POST** `/wallet/transfer`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "to_player_id": "uuid",
  "amount_cents": 1000,
  "note": "string (optional)"
}
```

**Response (200 OK):**
```json
{
  "transaction_id": "uuid",
  "from_player_id": "uuid",
  "to_player_id": "uuid",
  "amount_cents": 1000,
  "created_at": "iso8601"
}
```

**Errors:**
- `400 Bad Request` — Insufficient balance
- `404 Not Found` — Recipient not found

---

## Bank Endpoints

### Get Bank Accounts

List all bank accounts for current player.

**GET** `/bank/accounts`

**Headers:** `Authorization: Bearer {access_token}`

**Response (200 OK):**
```json
{
  "accounts": [
    {
      "id": "uuid",
      "account_type": "savings",
      "balance_cents": 100000,
      "interest_rate": 0.0050,
      "last_interest_applied_at": "iso8601",
      "created_at": "iso8601"
    }
  ]
}
```

---

### Create Savings Account

Open a new savings account.

**POST** `/bank/accounts/savings`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "initial_deposit_cents": 10000
}
```

**Response (201 Created):**
```json
{
  "id": "uuid",
  "account_type": "savings",
  "balance_cents": 10000,
  "interest_rate": 0.0050,
  "created_at": "iso8601"
}
```

**Errors:**
- `400 Bad Request` — Minimum deposit not met
- `409 Conflict` — Savings account already exists

---

### Create Fixed Deposit

Create a fixed deposit account.

**POST** `/bank/accounts/fixed-deposit`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "amount_cents": 50000,
  "duration_days": 7
}
```

**Response (201 Created):**
```json
{
  "id": "uuid",
  "account_type": "fixed_deposit",
  "balance_cents": 50000,
  "interest_rate": 0.01,
  "locked_until": "iso8601",
  "maturity_amount_cents": 50500,
  "created_at": "iso8601"
}
```

---

### Apply for Loan

Apply for a bank loan.

**POST** `/bank/loans`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "amount_cents": 100000,
  "term_days": 30
}
```

**Response (201 Created):**
```json
{
  "id": "uuid",
  "principal_cents": 100000,
  "remaining_cents": 100000,
  "interest_rate": 0.08,
  "term_days": 30,
  "monthly_payment_cents": 3600,
  "started_at": "iso8601",
  "next_payment_at": "iso8601",
  "status": "active"
}
```

**Errors:**
- `400 Bad Request` — Loan eligibility requirements not met
- `409 Conflict` — Active loan already exists

---

## Inventory Endpoints

### Get Inventory

Retrieve current player's inventory.

**GET** `/inventory`

**Headers:** `Authorization: Bearer {access_token}`

**Response (200 OK):**
```json
{
  "items": [
    {
      "id": "uuid",
      "item_id": "avocado_toast",
      "item_name": "Avocado Toast",
      "category": "food",
      "quantity": 2,
      "expiry_at": "iso8601"
    }
  ],
  "capacity_by_category": {
    "food": 20,
    "medicine": 15,
    "goods": 10,
    "equipment": 5
  }
}
```

---

### Consume Item

Consume a food or medicine item.

**POST** `/inventory/consume`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "inventory_item_id": "uuid",
  "quantity": 1
}
```

**Response (200 OK):**
```json
{
  "consumed": true,
  "energy_steps_restored": 200,
  "health_basis_points_restored": 60,
  "stress_tenths_reduced": 0
}
```

**Errors:**
- `400 Bad Request` — Item not consumable, insufficient quantity
- `404 Not Found` — Item not in inventory

---

## Market Endpoints

### Get Market Prices

Retrieve current market prices for all items.

**GET** `/market/prices`

**Response (200 OK):**
```json
{
  "items": [
    {
      "item_id": "avocado_toast",
      "name": "Avocado Toast",
      "base_price_cents": 180,
      "market_price_cents": 198,
      "price_change_percent": 10.0,
      "supply": 150,
      "demand": 100,
      "trend": "up"
    }
  ]
}
```

---

### Get Item Details

Get detailed information about a specific item.

**GET** `/market/items/{item_id}`

**Response (200 OK):**
```json
{
  "item_id": "avocado_toast",
  "name": "Avocado Toast",
  "category": "food",
  "base_price_cents": 180,
  "market_price_cents": 198,
  "elasticity": 1.0,
  "is_perishable": true,
  "shelf_life_days": 1
}
```

**Errors:**
- `404 Not Found` — Item not found

---

### Purchase Item

Purchase an item from an NPC vendor.

**POST** `/market/purchase`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "item_id": "avocado_toast",
  "quantity": 5,
  "vendor_type": "local_market"
}
```

**Response (200 OK):**
```json
{
  "transaction_id": "uuid",
  "item_id": "avocado_toast",
  "quantity": 5,
  "price_per_unit_cents": 198,
  "total_cents": 990,
  "created_at": "iso8601"
}
```

**Errors:**
- `400 Bad Request` — Insufficient balance, inventory full
- `404 Not Found` — Item not available at vendor

---

### Buy Clothing

Purchase clothing items.

**POST** `/commerce/clothing`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "clothing_type": "formal_shirt",
  "quantity": 1
}
```

**Response (200 OK):**
```json
{
  "transaction_id": "uuid",
  "clothing_type": "formal_shirt",
  "quantity": 1,
  "total_cents": 5000,
  "purchased_at": "iso8601"
}
```

---

### Buy Electronics

Purchase electronic items.

**POST** `/commerce/electronics`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "item_type": "smartphone",
  "quantity": 1
}
```

**Response (200 OK):**
```json
{
  "transaction_id": "uuid",
  "item_type": "smartphone",
  "quantity": 1,
  "total_cents": 25000,
  "purchased_at": "iso8601"
}
```

---

## Housing Endpoints

### Get Housing Info

Retrieve current housing information.

**GET** `/housing`

**Headers:** `Authorization: Bearer {access_token}`

**Response (200 OK):**
```json
{
  "housing_tier": 2,
  "housing_type": "small_house",
  "rent_cents_per_day": 8000,
  "last_rent_paid_at": "iso8601",
  "rent_due_at": "iso8601",
  "is_owned": false,
  "storage_items": {}
}
```

---

### Pay Rent

Pay rent for current housing.

**POST** `/housing/rent`

**Headers:** `Authorization: Bearer {access_token}`

**Response (200 OK):**
```json
{
  "paid_cents": 8000,
  "paid_at": "iso8601",
  "next_due_at": "iso8601"
}
```

**Errors:**
- `400 Bad Request` — Insufficient balance, rent not due
- `404 Not Found` — No active housing

---

### Upgrade Housing

Upgrade to a higher housing tier.

**POST** `/housing/upgrade`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "target_tier": 3
}
```

**Response (200 OK):**
```json
{
  "previous_tier": 2,
  "new_tier": 3,
  "housing_type": "apartment",
  "rent_cents_per_day": 15000,
  "updated_at": "iso8601"
}
```

**Errors:**
- `400 Bad Request` — Insufficient balance, already at target tier
- `404 Not Found` — Property broker visit required

---

## Employment Endpoints

### Get Employment Status

Retrieve current employment information.

**GET** `/employment/status`

**Headers:** `Authorization: Bearer {access_token}`

**Response (200 OK):**
```json
{
  "current_employer_id": "uuid",
  "current_job_type": "factory_worker",
  "current_wage_per_shift_cents": 8000,
  "shifts_completed": 15,
  "consecutive_shifts": 5,
  "last_shift_completed_at": "iso8601",
  "unemployment_benefit_eligible": false
}
```

---

### Start Job Shift

Begin a job shift.

**POST** `/employment/shift/start`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "employer_id": "uuid",
  "job_type": "factory_worker"
}
```

**Response (200 OK):**
```json
{
  "shift_id": "uuid",
  "started_at": "iso8601",
  "expected_end_at": "iso8601",
  "wage_per_shift_cents": 8000
}
```

**Errors:**
- `400 Bad Request` — Insufficient energy, already on shift
- `404 Not Found` — Employer not found

---

### Complete Job Shift

Complete a job shift and receive payment.

**POST** `/employment/shift/complete`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "shift_id": "uuid"
}
```

**Response (200 OK):**
```json
{
  "shift_id": "uuid",
  "completed_at": "iso8601",
  "base_wage_cents": 8000,
  "productivity_modifier": 1.0,
  "stress_modifier": 1.0,
  "performance_bonus_cents": 0,
  "total_earned_cents": 8000
}
```

**Errors:**
- `400 Bad Request` — Shift not found, shift not started by player
- `409 Conflict` — Shift already completed

---

## Business Endpoints

### Create Business

Register a new business.

**POST** `/businesses`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "business_name": "string",
  "business_type": "small_shop",
  "zone": "market",
  "location_id": "mw.stall.017",
  "position": { "x": 100.0, "y": 0.0, "z": 200.0 },
  "capital_cents": 120000
}
```

**Response (201 Created):**
```json
{
  "id": "uuid",
  "business_name": "string",
  "business_type": "small_shop",
  "zone": "market",
  "capital_cents": 120000,
  "is_active": true,
  "permit_expires_at": "iso8601",
  "created_at": "iso8601"
}
```

**Errors:**
- `400 Bad Request` — Insufficient capital, reputation too low
- `409 Conflict` — Business name already exists

---

### Get Business

Retrieve business details.

**GET** `/businesses/{business_id}`

**Response (200 OK):**
```json
{
  "id": "uuid",
  "owner_id": "uuid",
  "business_name": "string",
  "business_type": "small_shop",
  "zone": "market",
  "capital_cents": 120000,
  "daily_revenue_cents": 5000,
  "daily_expenses_cents": 3000,
  "max_employees": 2,
  "is_active": true,
  "business_reputation_score": 50
}
```

**Errors:**
- `404 Not Found` — Business not found

---

### Hire Employee

Hire a player for the business.

**POST** `/businesses/{business_id}/employees`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "employee_id": "uuid",
  "wage_per_shift_cents": 7000,
  "role": "cashier"
}
```

**Response (201 Created):**
```json
{
  "id": "uuid",
  "business_id": "uuid",
  "employee_id": "uuid",
  "wage_per_shift_cents": 7000,
  "role": "cashier",
  "hired_at": "iso8601"
}
```

**Errors:**
- `400 Bad Request` — Not business owner, max employees reached
- `404 Not Found` — Business or employee not found

---

## Dashboard Endpoints

### Get Financial Health Score

Retrieve financial health score and recommendations.

**GET** `/dashboard/health`

**Headers:** `Authorization: Bearer {access_token}`

**Response (200 OK):**
```json
{
  "health_score": 65,
  "status": "managing",
  "recommendations": [
    "Reduce food spend by switching to market purchases",
    "Defer clothing purchase until rent is secured"
  ]
}
```

---

### Get Expense Breakdown

Retrieve expense breakdown by category.

**GET** `/dashboard/expenses`

**Headers:** `Authorization: Bearer {access_token}`

**Response (200 OK):**
```json
{
  "expenses": [
    {
      "category": "food",
      "amount_cents": 15000,
      "percent_of_income": 30
    },
    {
      "category": "housing",
      "amount_cents": 8000,
      "percent_of_income": 16
    }
  ]
}
```

---

### Get Net Worth

Retrieve current net worth calculation.

**GET** `/dashboard/net-worth`

**Headers:** `Authorization: Bearer {access_token}`

**Response (200 OK):**
```json
{
  "net_worth_cents": 45000,
  "assets_cents": 120000,
  "liabilities_cents": 75000,
  "calculated_at": "iso8601"
}
```

---

## Multiplayer Endpoints

### Get Player Profile (Public)

Get public profile of another player.

**GET** `/players/{player_id}/profile`

**Response (200 OK):**
```json
{
  "player_id": "uuid",
  "username": "string",
  "in_game_days_active": 45,
  "reputation_tier": "established",
  "housing_tier": 2,
  "current_employment": "worker",
  "business_name": null
}
```

**Errors:**
- `404 Not Found` — Player not found

---

### Send Friend Request

Send a friend request to another player.

**POST** `/players/{player_id}/friend-request`

**Headers:** `Authorization: Bearer {access_token}`

**Response (201 Created):**
```json
{
  "request_id": "uuid",
  "from_player_id": "uuid",
  "to_player_id": "uuid",
  "status": "pending",
  "created_at": "iso8601"
}
```

**Errors:**
- `400 Bad Request` — Already friends, request already sent
- `404 Not Found` — Player not found

---

### Block Player

Block another player.

**POST** `/players/{player_id}/block`

**Headers:** `Authorization: Bearer {access_token}`

**Response (201 Created):**
```json
{
  "relationship_id": "uuid",
  "player_id": "uuid",
  "related_player_id": "uuid",
  "relationship_type": "blocked",
  "created_at": "iso8601"
}
```

**Errors:**
- `404 Not Found` — Player not found

---

### List Trade Listings

Browse public trade listings.

**GET** `/trade/listings`

**Query Parameters:**
- `item_id` (optional) — Filter by item
- `zone` (optional) — Filter by zone
- `limit` (optional, default 50) — Max results

**Response (200 OK):**
```json
{
  "listings": [
    {
      "id": "uuid",
      "seller_id": "uuid",
      "seller_username": "string",
      "item_id": "avocado_toast",
      "item_name": "Avocado Toast",
      "quantity": 10,
      "price_per_unit_cents": 170,
      "total_cents": 1700,
      "listed_at": "iso8601",
      "expires_at": "iso8601"
    }
  ]
}
```

---

### Create Trade Listing

List an item for sale on the trade board.

**POST** `/trade/listings`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "inventory_item_id": "uuid",
  "quantity": 5,
  "price_per_unit_cents": 170
}
```

**Response (201 Created):**
```json
{
  "id": "uuid",
  "seller_id": "uuid",
  "item_id": "avocado_toast",
  "quantity": 5,
  "price_per_unit_cents": 170,
  "total_cents": 850,
  "listed_at": "iso8601",
  "expires_at": "iso8601"
}
```

**Errors:**
- `400 Bad Request` — Insufficient inventory, invalid price
- `404 Not Found` — Inventory item not found

---

### Purchase from Trade Listing

Buy an item from a trade listing.

**POST** `/trade/listings/{listing_id}/purchase`

**Headers:** `Authorization: Bearer {access_token}`

**Response (200 OK):**
```json
{
  "transaction_id": "uuid",
  "listing_id": "uuid",
  "buyer_id": "uuid",
  "seller_id": "uuid",
  "item_id": "avocado_toast",
  "quantity": 5,
  "price_per_unit_cents": 170,
  "total_cents": 850,
  "sold_at": "iso8601"
}
```

**Errors:**
- `400 Bad Request` — Insufficient balance, inventory full, buying own listing
- `404 Not Found` — Listing not found or expired
- `409 Conflict` — Listing already sold

---

### Create Player Loan

Create a peer-to-peer loan.

**POST** `/trade/loans`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "to_player_id": "uuid",
  "amount_cents": 10000,
  "interest_rate": 0.05,
  "term_days": 30
}
```

**Response (201 Created):**
```json
{
  "loan_id": "uuid",
  "from_player_id": "uuid",
  "to_player_id": "uuid",
  "amount_cents": 10000,
  "interest_rate": 0.05,
  "due_at": "iso8601",
  "status": "active"
}
```

---

## Government Endpoints

### Get Tax Records

Retrieve tax payment history.

**GET** `/government/tax/records`

**Headers:** `Authorization: Bearer {access_token}`

**Query Parameters:**
- `limit` (optional, default 10) — Max results

**Response (200 OK):**
```json
{
  "records": [
    {
      "id": "uuid",
      "tax_week_start": "iso8601",
      "tax_week_end": "iso8601",
      "income_cents": 50000,
      "tax_rate": 0.10,
      "tax_cents": 5000,
      "paid_at": "iso8601",
      "status": "paid"
    }
  ]
}
```

---

### Pay Tax

Pay outstanding tax.

**POST** `/government/tax/pay`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "tax_record_id": "uuid"
}
```

**Response (200 OK):**
```json
{
  "tax_record_id": "uuid",
  "paid_cents": 5000,
  "paid_at": "iso8601",
  "status": "paid"
}
```

**Errors:**
- `400 Bad Request` — Insufficient balance, tax already paid
- `404 Not Found` — Tax record not found

---

### File Court Case

File a legal dispute.

**POST** `/government/court/case`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "defendant_id": "uuid",
  "case_type": "labor_dispute",
  "description": "string"
}
```

**Response (201 Created):**
```json
{
  "id": "uuid",
  "plaintiff_id": "uuid",
  "defendant_id": "uuid",
  "case_type": "labor_dispute",
  "description": "string",
  "filed_at": "iso8601",
  "status": "pending"
}
```

**Errors:**
- `400 Bad Request` — Court fee not paid, invalid case type

---

### Get Welfare Benefits

Check welfare benefit eligibility and status.

**GET** `/government/welfare`

**Headers:** `Authorization: Bearer {access_token}`

**Response (200 OK):**
```json
{
  "is_eligible": true,
  "active_benefits": [
    {
      "benefit_type": "food_subsidy",
      "amount_cents": 5000,
      "next_payment_at": "iso8601"
    }
  ],
  "verification_required": false
}
```

---

## Insurance Endpoints

### Get Insurance Policies

Retrieve active insurance policies.

**GET** `/insurance/policies`

**Headers:** `Authorization: Bearer {access_token}`

**Response (200 OK):**
```json
{
  "policies": [
    {
      "id": "uuid",
      "plan_type": "standard",
      "hospital_coverage_percent": 60,
      "clinic_coverage_percent": 45,
      "pharmacy_coverage_percent": 20,
      "premium_cents_per_day": 10000,
      "started_at": "iso8601",
      "last_premium_paid_at": "iso8601",
      "next_premium_at": "iso8601",
      "is_active": true
    }
  ]
}
```

---

### Purchase Insurance

Purchase an insurance plan.

**POST** `/insurance/policies`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "plan_type": "standard"
}
```

**Response (201 Created):**
```json
{
  "id": "uuid",
  "plan_type": "standard",
  "hospital_coverage_percent": 60,
  "clinic_coverage_percent": 45,
  "pharmacy_coverage_percent": 20,
  "premium_cents_per_day": 10000,
  "started_at": "iso8601",
  "next_premium_at": "iso8601",
  "is_active": true
}
```

**Errors:**
- `400 Bad Request` — Health below 10%, plan already active
- `402 Payment Required` — Insufficient balance for first premium

---

### File Insurance Claim

File an insurance claim for medical treatment.

**POST** `/insurance/claims`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "policy_id": "uuid",
  "medical_bill_cents": 70000,
  "treatment_type": "hospital_advanced"
}
```

**Response (201 Created):**
```json
{
  "id": "uuid",
  "policy_id": "uuid",
  "player_id": "uuid",
  "medical_bill_cents": 70000,
  "coverage_amount_cents": 42000,
  "player_payment_cents": 28000,
  "treatment_type": "hospital_advanced",
  "filed_at": "iso8601",
  "status": "pending"
}
```

**Errors:**
- `400 Bad Request` — Policy inactive, treatment not covered
- `404 Not Found` — Policy not found

---

### Appeal Insurance Claim

Appeal a rejected or underpaid insurance claim.

**POST** `/insurance/claims/appeal`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "claim_id": "uuid",
  "appeal_reason": "string"
}
```

**Response (200 OK):**
```json
{
  "appeal_id": "uuid",
  "claim_id": "uuid",
  "status": "pending_review",
  "submitted_at": "iso8601"
}
```

**Errors:**
- `400 Bad Request` — Claim not eligible for appeal
- `404 Not Found` — Claim not found

---

## Admin Endpoints

### Get System State

Retrieve global system state (admin only).

**GET** `/admin/system/state`

**Headers:** `Authorization: Bearer {admin_token}`

**Response (200 OK):**
```json
{
  "active_player_count": 127,
  "economy_tick_interval_minutes": 5,
  "world_start_time": "iso8601",
  "total_transactions_today": 15420
}
```

**Errors:**
- `403 Forbidden` — Not an admin

---

### Trigger Economic Event

Manually trigger an economic event (admin only).

**POST** `/admin/economy/events`

**Headers:** `Authorization: Bearer {admin_token}`

**Request Body:**
```json
{
  "event_type": "drought",
  "severity": "major",
  "affected_categories": ["food"],
  "supply_modifier": -0.4,
  "duration_hours": 72
}
```

**Response (201 Created):**
```json
{
  "event_id": "uuid",
  "event_type": "drought",
  "severity": "major",
  "started_at": "iso8601",
  "ends_at": "iso8601",
  "status": "active"
}
```

**Errors:**
- `403 Forbidden` — Not an admin

---

## Healthcare Endpoints

### Hospital Treatment

Receive hospital treatment.

**POST** `/healthcare/hospital`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "treatment_type": "advanced"
}
```

**Response (200 OK):**
```json
{
  "treatment_id": "uuid",
  "health_basis_points_restored": 8000,
  "cost_cents": 70000,
  "treated_at": "iso8601"
}
```

---

### Clinic Treatment

Receive clinic treatment.

**POST** `/healthcare/clinic`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "treatment_type": "basic"
}
```

**Response (200 OK):**
```json
{
  "treatment_id": "uuid",
  "health_basis_points_restored": 3000,
  "cost_cents": 15000,
  "treated_at": "iso8601"
}
```

---

### Buy Medicine

Purchase medicine from pharmacy.

**POST** `/healthcare/pharmacy`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "medicine_type": "antibiotics",
  "quantity": 5
}
```

**Response (200 OK):**
```json
{
  "transaction_id": "uuid",
  "medicine_type": "antibiotics",
  "quantity": 5,
  "total_cents": 5000,
  "purchased_at": "iso8601"
}
```

---

## Transport Endpoints

### Use Transport

Use transport to travel.

**POST** `/transport/use`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "transport_type": "bus",
  "destination_zone": "market"
}
```

**Response (200 OK):**
```json
{
  "trip_id": "uuid",
  "transport_type": "bus",
  "cost_cents": 200,
  "energy_saved": 2,
  "arrived_at": "iso8601"
}
```

---

### Buy Transport Pass

Purchase a transport pass.

**POST** `/transport/pass`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "pass_type": "monthly",
  "transport_mode": "bus"
}
```

**Response (200 OK):**
```json
{
  "pass_id": "uuid",
  "pass_type": "monthly",
  "valid_until": "iso8601",
  "cost_cents": 3000
}
```

---

### Subscribe to Telecom

Subscribe to a telecom plan.

**POST** `/transport/telecom`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "plan_type": "standard"
}
```

**Response (200 OK):**
```json
{
  "subscription_id": "uuid",
  "plan_type": "standard",
  "daily_cost_cents": 60,
  "started_at": "iso8601"
}
```

---

## Restaurant Endpoints

### Dine at Restaurant

Dine at a restaurant.

**POST** `/restaurant/dine`

**Headers:** `Authorization: Bearer {access_token}`

**Request Body:**
```json
{
  "restaurant_type": "restaurant",
  "meal_type": "full_course"
}
```

**Response (200 OK):**
```json
{
  "dining_id": "uuid",
  "energy_steps_restored": 1000,
  "health_basis_points_restored": 1000,
  "stress_tenths_reduced": 20,
  "cost_cents": 8000,
  "dined_at": "iso8601"
}
```

---

## Leaderboard Endpoint

### Get Leaderboard

Retrieve leaderboard by category.

**GET** `/leaderboard/{category}`

**Response (200 OK):**
```json
{
  "category": "net_worth",
  "entries": [
    {
      "rank": 1,
      "player_id": "uuid",
      "username": "string",
      "score": 50000.0
    }
  ]
}
```

---

## Events Endpoint

### Get Active Events

Retrieve active economic events.

**GET** `/events`

**Response (200 OK):**
```json
{
  "events": [
    {
      "id": "uuid",
      "event_type": "drought",
      "severity": "major",
      "description": "Fresh produce supply drops 40%",
      "affected_categories": ["food"],
      "supply_modifier": -0.4,
      "demand_modifier": 0.0,
      "started_at": "iso8601",
      "ends_at": "iso8601",
      "status": "active"
    }
  ]
}
```

---

## Stats Endpoint

### Get Player Stats

Retrieve player statistics.

**GET** `/stats`

**Headers:** `Authorization: Bearer {access_token}`

**Response (200 OK):**
```json
{
  "total_earnings_cents": 500000,
  "total_spent_cents": 350000,
  "shifts_completed": 50,
  "days_played": 30
}
```

---

## Error Response Format

All error responses follow this format:

```json
{
  "error": {
    "code": "string",
    "message": "string",
    "details": {}
  }
}
```

**Common Error Codes:**
- `INVALID_REQUEST` — Malformed request body
- `UNAUTHORIZED` — Invalid or missing authentication
- `FORBIDDEN` — Insufficient permissions
- `NOT_FOUND` — Resource not found
- `CONFLICT` — Resource already exists or state conflict
- `INSUFFICIENT_BALANCE` — Not enough coins
- `INVENTORY_FULL` — Inventory capacity reached
- `INSUFFICIENT_ENERGY` — Not enough energy bars

---

## Rate Limiting

- **Unauthenticated:** 10 requests per minute per IP
- **Authenticated:** 100 requests per minute per player
- **WebSocket:** governed by the per-message-type limits in [[../protocol/WebSocket_Protocol.md|WebSocket Protocol §Rate Limiting]] (movement 10/s, chat 5/s, other actions 20/s). "No rate limit" was never true for the socket channel; corrected for contract consistency.

Rate limit headers:
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1715085600
```

---

## v2.1 Design Deltas (PROPOSED — not implemented)

Canonical target semantics below require implementation and migrations in the fresh backend. Some examples already reflect the target; none establishes a deployed service. Correct conflicting examples against their owner before using them as a DTO specification.

1. **Bounded home storage.** `storage_capacity_units` and `storage_used_units` account for stored item quantities: one quantity is one storage unit. Separate placed-furniture floor cells use their own budget. `storage_items` moves from unbounded JSONB to quantity-accounted rows (see `Schema.md` deltas and canonical rules §6); inventory overflow cannot silently discard or duplicate goods.
2. **Rate-based rest.** Any rest action (`/housing/rest` when implemented, and the WS equivalent) returns **progress deltas** (`energy_gained`, `rested_until`, next-tick timestamps) — never instant full bars. The retired 10-second instant-recharge behavior must not reappear in any response shape.
3. **Eviction grace = 12 in-game hours** in rent-due notifications and `next_due_at` semantics; older 48 h notes are retired.
4. **Server-authoritative housing units.** Multi-unit structures expose persistent unit/address IDs; clients never infer or fabricate vacancy/stock counts — availability comes from server entities (`Schema.md` `housing_units`).
5. **Price model.** The continuous elasticity model on 5-minute ticks with **0.5×–3.0×** base clamp is canonical (`specs/economy/Economy_Engine_Spec.md`, aligned by canonical rules); the retired daily ratio-tier table must not be re-exposed. The 2× listing gouging threshold is a separate rule. `economy_tick_interval_minutes` stays `5`.
6. **Insurance tiers (applied to examples).** Canonical magnitudes (rules §9 row 10): premiums **60/100/150** coins per day; coverage hospital **40/60/80**, clinic **30/45/60**, pharmacy **10/20/30** for Basic/Standard/Premium. The `/insurance` examples above show the Standard plan at the canonical 10000-cents / 60-45-20; backend seed data must use the same table (Insurance.md is being updated to match — same cutover, one spelling).
7. **Positions are full 3D, right-handed Y-up (Godot convention), metres:** `position: {x, y, z}` everywhere — REST, WS, persistence. x = world X (east), y = height (**server-computed** from walkable surfaces; client reports include it as an observation but it is never trusted), z = world Z (south). The examples above already use this shape; the legacy Actix/SQLx types still carry 2D fields, so the **code cutover is implementation work** (design, not implemented). One spelling; no 2D/3D aliases.
8. **Fractional resource magnitudes.** Canonical consumption/decay is fractional (fruits 0.14 bars; health 5 pts/2 h; stress 0.5-band effects), so the wire uses fixed-point integers: `energy_steps` (1/200 bar; 5-bar cap = 1000; IN-3's `bonus_steps` boost pool capped at 400), `health_basis_points` (1/100 %), `stress_tenths` (0.1 band units, 10–120). Display fields (`energy_bars`, `health_percent`) are renderings of these, never authority. Payload examples above are converted; the legacy Rust/Postgres columns (`SMALLINT` bars/percent/level) need the matching migration + type cutover — design, not implemented.

---

## References

- [[../../design/05_Systems_Map|Systems Map]] — System architecture
- [[../database/Schema.md|Database Schema]] — Data models
- [[../protocol/WebSocket_Protocol.md|WebSocket Protocol]] — Real-time communication
- [[../../design/11_Canonical_Game_Rules|Canonical Game Rules]] — ownership, stock, price, rest, and lease constants
- [[../frontend/3D_Frontend_Production.md|3D Frontend Production]] — browser client contract (idempotency/revision rationale)
