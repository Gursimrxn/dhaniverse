---
tags: [business, roadmap, moat, fundraising, reputation]
date: 2026-11-05
version: 1.0
aliases: [Business Roadmap, Path to Scale]
---

# Business Roadmap — From Game to Fundable Company

> **Historical hypothesis — 2026-11-05:** This ladder is not the current build
> mandate. [Product direction](12_Product_Direction.md) prioritizes a retained
> consumer game; AI, onchain achievements, vaults and institutional products each
> require separate evidence. No token, vault or portable credit claim is required
> for the pilot.

**Archived thesis, not an adopted company direction:** The game and the vault were proposed as acquisition and monetization features for a portable financial-behavior layer. The following market claims, scale ladder and vault timelines are historical hypotheses, not verified results or current implementation instructions. Current game development follows [player choices and consequences](14_Player_Choices_And_Consequences.md).

## Why this is the millions-scale asset (evidence, as of 2026-11-05)

- **Twyne** raised $2.5M seed (Aug 2026; Cyber Fund + Ethereal Ventures) for attestation-based credit delegation — VCs pay for reputation→credit rails now; they have no consumer funnel. Wildcat Labs: $3.5M for undercollateralized lending. Teller: multi-year category incumbent.
- **Galaxy Research — "The New Age in Onchain Credit Markets"**: on-chain credit's binding constraint is verified borrower history; thin-file young adults are the unserved majority.
- **a16z — "Decentralized Identity: Your Reputation Travels With You" / "A Novel Framework for Reputation-Based Systems"**: portable, earned, non-transferable reputation as foundational design — our attestation schema implements it.
- Colosseum corpus: reputation/profile tools (`webtag`, `solana-reputation-scorer`, `repaye`, `certifyonchain`) are all infra without consumer acquisition; credit-lane winners (`yumi-finance` — 1st Place DeFi, Cypherpunk; `legasi` — 3rd Place RWAs, Cypherpunk) show judges fund credit. We are the intersection.
- **Behavioral moat:** score credibility = proof-of-behavior under real stakes (repayment history + actual savings streaks), not vanity badges. Retention science: Duolingo streak mechanics; PLOS One leaderboard-savings study; CEPR "Gamification Can Help Consumers Reach Their Saving Goals."
- **Geography:** India ~27% literacy vs 67.0 inclusion index (RBI FY25); CoinSwitch Q3-2025: India's Gen Z already out-invests millennials in crypto. USDC-on-Solana = sub-cent cross-border savings rail for exactly them. US: 30-state personal-finance mandates (NGPF, Apr-2026) → B2B licensing beachhead (Zogo→Peak6 exit precedent).

## Scale Ladder

1. **L1 — Game (now):** consumer acquisition engine, CAC≈0 via flex factor (public profiles, achievements, shareable score). Playable vertical slice.
2. **L2 — Vault (W+1):** real USDC savings + yield; 10–20% take on ~4–6% routed yield. First real-money behavior events feed the score.
3. **L3 — Open attestation standard (the venture layer):** published, versioned schema (EAS/VC-compatible) others can verify: lenders price our score, wallets display it, employers check it. Revenue: verification/licensing fees on third-party consumption. This is the Twyne-grade asset, built on a funnel they don't have.
4. **L4 — B2B:** sim-as-curriculum licensing to schools/neobanks (NGPF-mandated US states; RBI literacy push). Margin layer, not the moat.

## What must change in the build

1. **Attestation schema is a spec, not an implementation detail.** Publish `specs/protocol/Reputation_Schema.md`: versioned fields (savings_streak_days, loan_repaid_ratio, compound_interest_mastery, real_deposit_events…), each signed by our program, EAS-aligned so any Solana app can verify.
2. **Third-party verify page in the demo:** `verify.<domain>/<wallet>` showing an attestation + how a mock lender would price a loan off it. Costs ~1 day; converts our story from "game" to "credit data layer" in readers' heads.
3. **Score design guardrails** (from a16z reward-systems doc): non-transferable, sybil-resistant (real-money events weigh > in-game events), decays over time, no pay-to-win. Documented in the schema.
4. **Regulatory posture for scale:** stay the *data/attestation layer* (not a lender, not a custodian) → custody lives with wallet rails (Phantom/Privy-style embedded), deposits demo-only until an MSB/bank/EMI partner signs. The data layer is the defensible, licensable piece.
5. **Open economy data flywheel:** aggregate (anonymized) sim behavior → published "financial capability" research → PR + LP trust for L3. Nobody else has behavioral ground-truth at scale.

## Team & fundraising notes

- Team of 4 meets Colosseum's winning-team profile (avg 3+). Gap: **credit/fintech BD** — add a lending-background advisor before accelerator interviews, not after.
- VC pitch line: "We are the GitHub for financial capability — a consumer economy sim that manufactures verified credit histories for the 3.5B financially illiterate, starting with Gen Z on stablecoin rails."
- Traction sequence investors want: 500 MAU sim with ≥50 real vault conversions → 1 external protocol verifying attestations → pre-seed.

## References
- [[04_Economy_Design|Economy Design]] — credit-score system = L3 data source
- `specs/protocol/Reputation_Schema.md` — first artifact of L3 (drafted)

## Regulatory reality annex (as of 5 Nov 2026 — the fence the ladder lives inside)

- **FCRA (US consumer credit):** third parties using our attestations to decide *individual consumer* credit eligibility ⇒ we'd be a Consumer Reporting Agency (permissible purpose, adverse action, disputes). **Avoided by design:** L3 ships to (a) on-chain/protocol and (b) **business-entity** credit first — neither is a "consumer report"; user-disclosed wallet credentials also shift the analysis.
- **GENIUS Act (PL 119-27):** issuers can't pay stablecoin interest; third-party yield routing is pending-rule gray (CRS IF13174; OCC NPRM Mar-2026) — we route to existing DeFi venues as software, never issue; watch the final rules.
- **Deposits/custody:** real user funds require partner rails (Circle/Fireblocks/Transak BaaS; India: NBFC partner or nothing). Until then: demo funds only, and **India = B2B education-only (Zogo model), no money handling**.
- **Gaming law:** game never has cash prizes (state public-gaming acts). Minors: 18+ for any money feature; under-18 engagement is curriculum-only.
- Investor posture: this gray is fundable (Twyne $2.5M, Wildcat $3.5M, both Aug 2026) but every deck carries this slide. We are the data layer *outside* the regulated perimeter, partnering at the edges.
