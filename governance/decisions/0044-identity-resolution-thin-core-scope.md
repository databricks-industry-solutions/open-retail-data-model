# ADR 0044 — Identity Resolution is delivered by the thin identity core; the identity graph is deferred

**Status:** Accepted (2026-10-08) by the maintainer, @Tagar.

## Context

The Unified Customer View package lists an "Identity Resolution" use case. Identity resolution in
commerce combines deterministic matching, probabilistic linkage, survivorship, householding, consent
enforcement and auditability. The research behind ORDM's customer core
([docs/design/customer-identity/identity-resolution-notes.md](../../docs/design/customer-identity/identity-resolution-notes.md))
describes a full graph-first model for it: identity nodes and edges with confidence, a match-rule catalog
for survivorship, a merge/split event log, replayable graph snapshots, and an erasure-surviving
identifier suppression ledger.

ORDM already ships the thin projection of that model and states, in the `identity_link` table header and
the design note, that the graph is "design-only until a dedicated identity-resolution outcome package
needs them". The use case stayed `in-progress` because that scope was never recorded as the definition of
done for it.

What ships and is populated today:

- `customer.identity_link`: one row per source-system identifier assertion resolved to a profile, per
  SCD2 version, with `identifier_type`, a pseudonymized `identifier_value_hash`, `match_method`,
  `match_confidence` and `link_status`. A current active identifier resolves to exactly one profile
  (`identity_link_single_active_profile_per_identifier`).
- `customer.household` and the profile-to-household link.
- v1 suppression: the do-not-contact overlay on `customer.consent`
  ([ADR 0027](0027-consent-suppression-overlay.md)), served as `gold_person_do_not_target_current`
  ([ADR 0028, cross-plane do-not-target](0028-cross-plane-do-not-target-and-multi-purpose-gate.md)), plus `identity_link.link_status = 'suppressed'` for a
  suppressed identifier.
- `gold_unified_customer_360_current`, which surfaces the resolution per profile as
  `active_identifier_count` and `resolved_identity_confidence` (the highest `match_confidence` across the
  profile's current active links).

## Decision

1. For v1, the Identity Resolution use case is the **resolved-identity surface**: the conformed
   "resolved key plus match confidence" in `identity_link`, householding, and their per-profile
   projection in `gold_unified_customer_360_current`. On that scope the use case is done.
2. The graph-first machinery (`identity_node`, `identity_edge`, `identity_event`,
   `identity_graph_snapshot`, `ref_match_rule`, `ref_identifier_type`, the erasure-surviving,
   identifier-hash-keyed `identifier_suppression` ledger, and current-state resolution read models) is
   **not** part of v1. It is deferred to a future
   identity-resolution outcome package, built when a consumer needs merge/split auditability or
   survivorship rules in the model.
3. ORDM models the **output** of identity resolution, not the resolution engine. Adopters run their own
   matching (a CDP, an identity service, or their own pipeline) and land its result in `identity_link`.

## Consequences

- The use case can be marked `done` with this scope, and its `tables:` mapping names
  `gold_unified_customer_360_current`.
- Consumers that need explainable merges, survivorship precedence or point-in-time identity state must
  wait for the deferred package or model it in their private layer; the design note keeps the full
  research so nothing is lost.
- Promoting a deferred object later is intended to be additive (extending `identity_link` rather than
  changing its grain or keys); the future package's design decides that.
