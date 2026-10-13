# ADR 0029 — Aggregate-only sensing schema with policy-driven shared disclosure

**Status:** Accepted (2026-07-31) — all four scopes in the corrective-review approval record are signed off (CSS owner, CMN owner, Maintainers, Privacy).

## Context

Connected Store Signals models aggregated footfall, dwell, and occupancy. Aggregate data
can still enable record isolation, linkage, or inference when multiple small cells are
published together. ORDM, however, publishes a reusable schema and reference
implementation—not an adopter's data or a universal legal threshold. The model must
therefore separate complete operational truth from explicitly shared disclosure surfaces.

There is no regulator-set numeric threshold for footfall. A value of ten is a defensible
external-sharing default based on statistical-disclosure practice and analogous movement
data standards, but it is not a base-fact invariant and is not legal advice.

## Decision

1. **The published schema is aggregate-only.** Person-level or linkable sensing
   identifiers—including MAC addresses, face templates, person tracks, journey paths,
   per-person dwell, and demographic or emotion inference—are structurally forbidden
   across the package. Adopters needing consented person-level processing must operate a
   separate private tier with their own access, purpose, DPIA, and retention controls.
2. **Operational facts and operational gold views remain complete.** Valid measured zero
   and below-threshold observations are retained. The model does not null source facts at
   write time.
3. **Disclosure policy is effective-dated data.**
   `sensing_disclosure_policy` carries audience, `k_threshold`,
   `suppress_zero_flag`, and `minimum_interval_minutes`. A sensing-deployment version
   references the exact policy version used for external sharing.
4. **`external_default` uses k=10.** It suppresses measured zeros, requires
   same-cell dependent-measure suppression, and floors publishing at 15 minutes. An
   adopter may raise these controls. Lowering them requires a fresh privacy assessment.
   This reference implementation does not claim statistical complementary/secondary-cell
   suppression; a publication requiring that control needs a governed suppression
   lattice and reconstruction-risk design.
5. **Suppression is enforced only in explicit shared views.**
   `gold_store_traffic_daily_shared` and `gold_zone_traffic_shared` aggregate canonical
   intervals to a publishable window, then evaluate policy.
   `gold_zone_traffic_interval_shared` preserves only disclosure-approved canonical
   interval rows for governed compatibility use. When a daily primary cell is
   suppressed, all traffic-derived measures are NULL together; when an interval cell is
   suppressed, the complete row is omitted.
6. **Shared schemas omit reconstruction side channels.** They do not expose observed-zero
   flags, raw/expected observation counts, validity denominators, interval counts,
   raw/adjusted visitor components, or other fields that narrow a suppressed cell. A
   disclosure flag and policy id identify the governed outcome without revealing why a
   particular small value occurred.

## Consequences

- Operations and feed-health analytics remain truthful, including quiet periods.
- External and partner consumers must use the shared views; access control remains an
  adopter responsibility.
- Suppression controls can evolve by policy version without rewriting historical
  operational facts.
- CMN's exact-name compatibility view reads the CSS shared interval surface. New
  `opportunity_to_see` values remain NULL until a governed CMN derivation exists.
- Privacy review of `external_default` is required before release. This ADR and
  its reference configuration do not claim that any deployment is legally anonymous.
