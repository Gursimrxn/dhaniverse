---
tags: [protocol, attestation, schema, reputation]
date: 2026-11-05
version: 0.1-draft
status: historical draft; no implementation selected or deployed
aliases: [Reputation Schema, Financial Capability Attestation]
---

# Reputation Schema v0.1 — Financial Capability Attestations

This is an earlier Solana-oriented proposal, not the current game's identity,
economic authority or a committed integration. Optional milestone proofs
must be voluntary. Do not equate simulation performance with validated real-world
creditworthiness or expose private balances/debt by default.

**Purpose:** machine-readable, portable proof of demonstrated financial behavior. Signed by our on-chain program, verifiable by any Solana app, EAS-aligned field semantics for future cross-chain portability.

## Attestation record

```
{
  schema_version: "0.1",
  subject_wallet: <pubkey>,           // non-transferable; re-attestation replaces
  issued_at: <unix>,
  issuer: <our program id>,
  fields: { ... }                     // subset always present: defined below
  proof_context: {                    // provenance per field class
    sim: "server-signed action log (Postgres) + merkle root anchoring",
    real: "observed on-chain tx + program CPI receipt"
  }
}
```

## v0.1 fields

| Field | Type | Source class | Definition |
|---|---|---|---|
| `graduation_level` | int 0–3 | sim | 0 none → 1 first loan repaid → 2 Financial Health Score ≥70 sustained 30d → 3 ≥85 + real deposit event |
| `compound_interest_mastery` | bool | sim | Completed savings + loan cycles with correct optimization (dashboard-measured) |
| `loan_repaid_ratio` | float 0–1 | sim | Repaid principal / originated, all-time |
| `on_time_repayment_rate` | float 0–1 | sim | On-time installments / due installments |
| `savings_streak_days` | int | sim+real | Consecutive days with net-positive savings (real deposits extend ×2 weight) |
| `real_deposit_events` | int | real | Count of actual USDC vault deposits ≥ $1 |
| `real_saved_usd_cents` | int | real | Current verified vault balance |
| `market_participation` | int | sim | Trade-board executions (economic activity proof) |

## Guardrails (design law — from a16z reward-systems + Superteam reputation lessons)

1. **Non-transferable, non-sellable** — bound to subject wallet + identity attestation chain.
2. **Sybil resistance:** real-money events weighted > simulated events; sim-only score capped at level 2; velocity limits on sim field growth (see 04_Economy_Design rate tables).
3. **Decay:** fields half-life 90 days of inactivity; profiles show last-verified timestamp.
4. **No pay-to-win:** money can never buy score; only behavior.
5. **Privacy-by-default:** per-field share toggles; verify endpoint only reveals what subject enabled; anonymized aggregates go to research flywheel only with opt-in.

## Verify contract (consumer-facing)

`verify.<domain>/<wallet>` → renders enabled fields, issuer signature check, and a **lender view**: mock rate quote computed from fields (e.g. APR = base + spread(loan_repaid_ratio, savings_streak)). The quote formula is a published, versioned artifact too — schema changes get changelog + major-version bump.

## Roadmap

- v0.1 (build): our program signs; our verify page reads.
- v0.2 (post-build): open SDK — any Solana lending market queries attestations as extra collateral signal; EAS/Attestation Service bridge.
- v1.0: standardized field set with named external consumers ≥2 (the metric that proves L3 to investors — see design/09_Business_Roadmap.md §Scale Ladder).

## References
- [[09_Business_Roadmap|Business Roadmap]] — why this is the venture layer
- [[04_Economy_Design|Economy Design]] — in-game sources for sim fields
- Galaxy "The New Age in Onchain Credit Markets"; a16z "Reputation Travels With You" (archive corpus)
