# ADR 0025 — SCD2 join contract in consuming views (SCD2-JOIN-CONTRACT mandate)

**Status:** Accepted (2026-07-24)

## Context

Gold and metric views consume SCD2 masters (effective_from_date / effective_to_date
/ is_current). A review of every gold/metric view found a class of defects that were
CI-invisible: the standards suite globbed only `canonical-core/*/tables` and
`outcome-packages/*/tables`, never `gold/` or `metric-views/`; and the synthetic
generators emit single-version masters, so `GROUP BY _sk` == `GROUP BY _id`, every
fact→history join is 1:1, and nothing fired. The defects (fan-out, reverse-drop,
GROUP BY / PARTITION BY / COUNT-DISTINCT on a version-specific `_sk`, and exposing a
bare SCD2 `_sk` as a metric-view dimension) are silently wrong in production while
green in CI.

The **non-obvious reframing** behind the fix, and the reason it is worth recording:
ORDM facts already carry an **ingest-resolved, version-specific `_sk`** (e.g.
`sales.product_sk` is "the product version in effect at the sale"). So a fact→
dimension join on the dimension's PK `_sk` is a plain 1:1 equi-join that is already
as-of-correct — **no range join is needed**, and adding a range/as-of predicate to
those joins would be a regression. A range/as-of predicate is reserved for the narrow
fact→history-table case (a price/cost history keyed on `product_price_sk`, not
`product_sk`), and even there it is portable ANSI SQL that auto-triggers the
Databricks range-join optimization, over a broadcastable dimension. This reframing
was worked out in the maintainer's local design notes; it belongs in the repo per
CONTRIBUTING §8 (a finalized convention decision gets an ADR + a decisions-log line),
mirroring the CLUSTER-KEY-TYPE precedent ([ADR 0023](0023-cluster-key-type-mandate.md)).

## Decision

1. **Add the standard mandate §A.16** ("SCD2 join contract in consuming views"):
   the default is an ingest-resolved PK-`_sk` equi-join; aggregate / partition /
   count-distinct on the durable `_id`, never a version-specific `_sk`; never equi-
   join `fact._sk = dim._sk` and also filter `is_current` (the reverse-drop); and do
   not expose a bare SCD2 `_sk` as a groupable metric-view dimension. The durable
   `_id`, not the `_sk`, is the portable cross-deployment key.

2. **Enforce it with `SCD2-JOIN-CONTRACT`** (`severity: error`, `status: static`),
   a cluster-free lint over `gold/*.sql` + `metric-views/*.sql` (+ the metric-view
   YAML `source:` and native `joins:` blocks). Five detectors: history-fanout,
   reverse-bug, frag-groupby, frag-partition, distinct-count-sk, plus the
   sk-dimension check. Reliable-from-DDL only; it is a strong regex-based guard over
   the known defect shapes, not a formal proof of SCD2-correctness.

3. **Ship green via a visible debt ledger.** The rule runs at error severity with the
   currently-known violations seeded into `standards/rules.yaml` `known_exceptions`
   (keyed `<relpath>::<kind>`), mirroring `FK-COMPLETENESS`. The suite stays green
   while the debt is enumerated; the fix-the-views PR removes each entry as its view
   is corrected. A liveness test forbids a dead exception; a per-detector positive
   test forbids silent detector rot.

4. **Make the defects testable.** Multi-version SCD2 generator helpers
   (`stamp_scd2_history` / `resolve_scd2_asof`, defaulted off so legacy output is
   unchanged) and a golden `test_price_actuals.py` (xfail-strict as a forcing
   function) so the class becomes observable once history lands.

The mandate cites `standard_section: "A.16"`.

## Consequences

- The SCD2 defect class is caught in CI before publish; the ledger only shrinks and,
  when empty, no view trips any detector.
- The reframing (equi-join, not range join) is recorded in the repo, so a future
  contributor is not pointed at notes that are not in the repo.
- Portability: the durable-`_id` contract is engine-neutral; the reserved range/as-of
  predicate is portable ANSI SQL (no Databricks-only hint in shipped SQL).
