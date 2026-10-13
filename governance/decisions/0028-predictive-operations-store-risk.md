# ADR 0028 — Store Operational Risk Score: a `predictive_operations` schema, store-grain composite, and the boundary with `early-risk-detection`

**Status:** Accepted (2026-07-27)

## Context

The **Predictive Operations** outcome package owns three use cases: In-Store
Equipment Maintenance (done), Store Performance (this ADR), and Workforce
Optimization (deferred). The Store Performance use case delivers a **Store
Operational Risk Score** — a store-grain, executive-facing index of near-term
operational/financial deterioration risk ("which stores are becoming at-risk?").

Building it raised the decisions this ADR records — the three placement/boundary
questions below, plus the honesty framing of the score itself (Decision §4):

1. **Schema placement.** The package's existing (done) equipment objects deploy
   into the `in_store_equipment_maintenance` schema, which is named for that *use
   case*, not the package. The naming standard (§D) says an outcome-package schema
   is the full outcome slug (`predictive_operations`), so `in_store_equipment_maintenance`
   is pre-existing naming drift from when equipment-maintenance was folded in as
   the package's only use case (PR #83). The new store-grain composite is the
   first genuinely package-level object, so it surfaces the mismatch rather than
   creating it — and needs a home.

2. **The composite reads other packages' gold views.** The score reuses
   `early_risk_detection.gold_inventory_risk`, `early_risk_detection.gold_procurement_risk`,
   `balancing_margin_and_volume.gold_sales_actuals`, and its own
   `gold_equipment_health`. This is a gold→gold cross-package read.

3. **Overlap with `early-risk-detection`.** That package already ships a "single
   pane of glass" (`gold_control_tower`). The distinction between the two must be
   stated so they do not compete.

## Decision

### 1. One `predictive_operations` schema for the whole package

The package deploys **all** its objects — both use cases — into a single schema
named for the package, `predictive_operations`, matching standards §D (an
outcome-package schema is the full package slug). Concretely:

- The `predictive_operations` schema token is wired through `databricks.yml`, the
  config resolver, and the deploy bootstrap; it is the package's one schema.
- Store Performance objects (`gold_store_operational_risk`, `store_risk_score`,
  `mv_store_risk`) deploy into it.
- The **equipment-maintenance objects are moved** into it too — the earlier
  `in_store_equipment_maintenance` schema token and its per-use-case schema are
  removed. The single synthetic generator (`predictive_operations.py`) writes all
  four extension tables there.

We fixed the drift at its root rather than add a second schema and carry the split
as a standing exception. Pre-publication timing made the rename safe — no external
consumer was pinned to the old schema name, and the cost would only grow the longer
it sat. The package now has one clean home matching §D, the store-risk composite no
longer lands in a schema literally named "equipment maintenance," and there is no
schema-placement exception to carry forward.

### 2. The score is a store × as_of_date gold composite + append-only scored-output fact — no new core

v1 needs **no new canonical-core table**. It composes four sub-scores that already
exist (Inventory, Supply-Chain, Sales/Margin, Equipment). The gold→gold read is
legal under `LAYER-INTEGRITY` (which forbids only canonical-core FKs into a gold
schema; a view reading another gold view is fine), with precedent in
[ADR 0024](0024-gold-to-gold-coupling-acu-ucv.md). Supply-Chain risk maps to store
grain via `purchase_order_line.store_sk` (the ship-to location), so no supplier↔store
bridge table is needed.

The score is physically a **`store × as_of_date` snapshot fact**, append-only, no
SCD2 (§A.8), tagged `dbx_data_type = transactional`. Standards §A.9 forbids
predictive scores on masters/dimensions, so it lives only in the gold/fact/metric
layer, never on `store`.

### 3. Boundary with `early-risk-detection`

- `early-risk-detection` is the **alert/event plane** — alert-grain,
  supply-chain-centric ("which disruptions need action now?", `gold_control_tower`).
- The Store Operational Risk Score is the **store/executive plane** — store-grain
  ("which stores are becoming at-risk?"). It **consumes** early-risk-detection's
  outputs rather than re-deriving them.

Re-owning inventory/supplier/margin risk under `predictive_operations` names would
create duplicate single-sources and re-implement prior `early-risk-detection` work.
The consolidate-avoid-sprawl principle wins: reference, do not rebuild.

### 4. It is a heuristic index, not a calibrated probability

ORDM trains and serves no models. The score is a transparent, expert-weighted
0–100 index with a documented recipe (per-input normalization, visible weights
summing to 100, non-compensatory escalators, `top_risk_domains` diagnosis, a fixed
7-day horizon). The column is `operational_risk_score`, never `*_probability`. The
scored-output fact carries `score_method IN ('heuristic','model')` and a reserved
NULL `predicted_impact_amount` so a model-backed pipeline can populate calibrated
values later. A README **Placeholder Data** section names every NULL column/KPI
(the `balancing-margin-and-volume` honesty pattern).

## Consequences

- The `in_store_equipment_maintenance` schema token no longer exists; anything that
  referenced it (a downstream query, dashboard, or grant) must use
  `predictive_operations`. This is the one-time cost of the rename, paid while
  pre-publication.
- `predictive-operations` does not deploy as a standalone island: the composite
  reads `early-risk-detection` and `balancing-margin-and-volume` gold views, so
  those packages must be present first (deploy order is stated in the view header).
  A future third consumer of these sub-scores would be the trigger to revisit the
  gold→gold coupling.
- Labor and Customer-Experience sub-scores are **NULL columns** in v1, excluded from
  the composite denominator (missing = unknown, not safe), so they light up once
  their source domains land **without reworking the composite**. Those domains — a
  `canonical-core/labor` domain (employee/labor_schedule/labor_actuals) and a
  CX/voice-of-customer source — remain **separate working-group-gated core proposals**
  (the standards §C open call on employee v1 vs v1.x); they gate the Workforce
  Optimization use case and the CX sub-score respectively.
- The full scoring recipe lives in the design spec,
  [`docs/design/predictive-operations/store-operational-risk-score.md`](../../docs/design/predictive-operations/store-operational-risk-score.md).
