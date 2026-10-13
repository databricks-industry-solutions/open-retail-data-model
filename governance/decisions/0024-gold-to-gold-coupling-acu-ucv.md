# ADR 0024 — ACU and UCV gold views may read each other (bounded gold↔gold coupling)

**Status:** Accepted (2026-07-23)

## Context

Behavioral segmentation spans two outcome packages by design:

- **ACU** (Actionable Customer Understanding) owns the behavioral primitives:
  `segment_membership` (append-only per-segment membership feed) and the
  `segment_performance` metric view.
- **UCV** (Unified Customer View) owns activation: `gold_activatable_audience_current`
  applies the net consent + preference + reachability gate to produce the
  activatable audience.

This creates a mutual gold↔gold read across the two packages:

- UCV's `gold_activatable_audience_current` reads ACU's `segment_membership` (the
  TARGETING plane: current-as-of, minus exited).
- ACU's `segment_performance` metric view reads UCV's
  `gold_activatable_audience_current` (to report activatable penetration — UCV owns
  the net gate, so ACU consumes it rather than re-deriving it).

`§0` frames each outcome package as a self-contained bundle, so this coupling is
worth recording explicitly rather than leaving implicit in the SQL.

## Decision

Accept the bounded gold↔gold coupling between ACU and UCV. It is legal and safe:

- **LAYER-INTEGRITY holds** — the rule forbids canonical-core FKs into an outcome
  schema; it does not forbid one gold view reading another gold/append-only object.
  No canonical-core table depends on either package.
- **Deploy-resolvable** — both are views over already-deployed tables; there is no
  circular *table* dependency, only a view-read relationship resolved at query time.
- **Single source of truth is preserved** — the net activation gate lives in exactly
  one place (UCV), and membership lives in exactly one place (ACU). The coupling
  exists precisely so neither is re-derived; duplicating either would be worse.

Consequence accepted: neither package deploys as a fully standalone island — UCV's
activation view needs ACU's `segment_membership` present, and ACU's
`segment_performance` needs UCV's `gold_activatable_audience_current` present (it
reads it directly, so without UCV the metric view does not resolve — deploy the
unified-customer-view package before it, as `segment_performance.sql`'s header
states). This is the intended shape for a cross-package behavioral-activation
capability, not a defect. If a future consumer needs ACU's size/behavior metrics
without UCV, split the activatable-reach measures into a separate view gated on
UCV's presence; the size/behavior measures over `segment_membership` alone do not
depend on UCV.

## Consequences

- The relationship is documented once here instead of being inferred from the SQL.
- The duplicated "latest membership, minus exited" CTE in both views is kept in
  sync via cross-reference comments (there is no shared-SQL include mechanism).
- Revisit if a third package needs the activatable audience, at which point the gate
  may warrant promotion to a shared location.
