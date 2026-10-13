# ADR 0023 — Clustering keys: order-independence, and a narrow enforced CLUSTER-KEY-TYPE mandate

**Status:** Accepted (2026-07-23)

## Context

The standard's physical-layout guidance (§B "Clustering key selection") originally
carried Z-ORDER-era ordering folklore: "lead with the high-cardinality column,"
"put a date last," and "do not lead a clustering key with a low-cardinality enum."
§C also routes physical-layout calls to "the working group and the decisions log,
not standards to harden now," so any hardening of this surface needs a record here.

Two things prompted a change. First, a contributor PR clustered a table on
`service_level_pct` — a `DECIMAL(6,5)` percentage that is only ever selected, never
filtered or joined — which earns no data-skipping and wastes one of the max-four
key slots. Second, a review of the Databricks Liquid Clustering docs and internal
field guidance established that Liquid Clustering is **multi-dimensional and
order-independent** (Hilbert-curve based): key order does not matter, and
low-cardinality or enum keys skip fine and combine well. The "lead with / date
last / don't lead with an enum" advice is Z-ORDER-era and does not apply to the
plain `CLUSTER BY (...)` ORDM ships.

## Decision

1. **Retire the ordering folklore in §B.** State that Liquid Clustering is
   order-independent and that low-cardinality/enum keys are fine and combine well.
   Keep one soft caution: a mutable low-cardinality lifecycle enum as the *sole*
   key can churn the layout, so pair it with a stable key. This reverses the prior
   §B "lead with high-cardinality / date last / no enum-led key" guidance.

2. **Add one narrow enforced mandate, `CLUSTER-KEY-TYPE`** (`severity: error`,
   `status: static`), scoped to only what is reliably provable from DDL alone
   (near-zero false positives):
   - FAIL a cluster key whose type is FLOAT/DOUBLE/DECIMAL **and** whose name is a
     percentage/rate/ratio/score or money word — a continuous measure is never a
     filter/join predicate. Type **and** name must both match, so a legitimately
     range-filtered `DOUBLE` (latitude/longitude) is not flagged; a `_sk`/`_id`
     key is always exempt (a join key, never a measure); on a gold view, whose
     cluster keys are SELECT-output aliases with no parseable type, the name alone
     decides, with a categorical-suffix carve-out (`_band`/`_tier`/`_center`…).
   - FAIL a clause with more than four keys (Databricks rejects >4 at CREATE; a
     pre-deploy guard).
   - FAIL a cluster key that is not a column declared in the same CREATE TABLE
     (typo / dropped column; tables only).

   The rule deliberately does **not** enforce key cardinality, key order, or the
   general "column is only selected, never filtered" case — the last is not
   statically provable (it needs query telemetry) and is left to review.

The mandate cites `standard_section: "B"` (a design principle) rather than an §A
mandate, matching its "recommended, with one narrow exception" status; §C records
the exception explicitly.

## Consequences

- The single continuous-measure clustering mistake is now caught in CI before
  deploy; it is a forward guard (green on `main` today, zero `known_exceptions`).
- Contributors are no longer nudged toward the retired ordering rules by the
  standard, CONTRIBUTING, the review skill, or the canonical-core table comments
  (all synced in the same PR).
- Portability note: `CLUSTER BY` / Liquid Clustering is Databricks/Delta-native and
  does not port to non-Delta engines; that is by charter, and the rule operates on
  ORDM's own DDL, so portability is not affected.
