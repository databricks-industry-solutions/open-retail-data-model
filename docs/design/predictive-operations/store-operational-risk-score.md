# Design — Store Operational Risk Score (Store Performance use case)

Design specification for the **Store Performance** use case in the
**Predictive Operations** outcome package. This is the spec-on-paper that the
`gold_store_operational_risk` view, the `store_risk_score` scored-output fact,
and the `mv_store_risk` metric view commit to. Settle it here before the SQL.

> Status: v1 — data-backed domains (Inventory, Supply-Chain, Sales/Margin,
> Equipment, Labor). The Customer-Experience sub-score is deferred (NULL) until a
> CX source lands. See [Deferred sub-scores](#deferred-sub-scores-v11v12).

## 1. What this is (and what it is not)

The **Store Operational Risk Score** estimates, for each store as of a given
date, how exposed that store is to near-term operational or financial
deterioration — the "which stores are becoming at-risk?" question. It composes
sub-scores that **already exist in other ORDM packages** into a single
store-grain triage surface plus a per-domain diagnostic breakdown.

**It is a transparent, expert-weighted heuristic index (0–100), not a
calibrated probability.** ORDM ships no trained model and no labeled outcome
history, so a "78% probability of stockout" claim is not defensible on synthetic
data. The column is named `operational_risk_score` (an index), never
`*_probability` or `*_pct`. A calibrated probability is a later, model-backed
deliverable that an adopter's notebook can populate (see
[Predictive honesty](#7-predictive-honesty-where-the-data-models-job-ends)).

This follows the discipline already set by
[`gold_procurement_risk`](../../../outcome-packages/early-risk-detection/gold/gold_procurement_risk.sql)
and [`gold_supplier_scorecard`](../../../outcome-packages/early-risk-detection/gold/gold_supplier_scorecard.sql):
per-input 0–100 normalization, visible weights summing to 100, a
non-compensatory escalator, and a self-explaining top-factors column.

## 2. Grain, layer, and placement

- **Grain:** one row per `store × as_of_date × score_method` (a daily snapshot; `score_method` lets a model row coexist with the heuristic row).
- **Layer:** gold + a scored-output extension fact + a UC Metric View, all in
  the `predictive_operations` schema — the package's single schema, which the
  equipment-maintenance objects were also consolidated into (see
  [ADR 0028](../../../governance/decisions/0028-predictive-operations-store-risk.md)).
  The composite reads other packages' gold views; no new canonical-core table is
  required for v1.
- **The score never lives on a master or dimension** (standards §A.9 forbids
  predictive scores on masters/dimensions). It lives only in the gold/metric
  layer and the append-only scored-output fact.

## 3. Sub-scores (the six domains)

Each domain contributes a raw sub-score on the **same 0–100 scale, higher =
riskier**. The six domains mirror the KPI framework's signal domains. Five are
data-backed in v1; one is deferred.

| # | Domain | v1 source (reuse, do not rebuild) | Roll-up to store grain |
|---|---|---|---|
| 1 | **Inventory** | `early_risk_detection.gold_inventory_risk` (product × store, `stockout_risk_score` 0–100) | Sales-velocity-weighted mean of `stockout_risk_score` (weight = `trailing_units_sold`; see §4 roll-up rule) |
| 2 | **Supply-Chain** | `early_risk_detection.gold_procurement_risk` (supplier grain, `risk_score` 0–100) | Spend-weighted mean over suppliers that ship to the store, via `purchase_order_line.store_sk`, spend bounded to a trailing 90-day window so the mix reflects current sourcing |
| 3 | **Sales/Margin** | `balancing_margin_and_volume.gold_sales_actuals` | Recent-vs-prior net-sales trend + discount-depth compression, normalized to 0–100 |
| 4 | **Equipment** | `predictive_operations.gold_equipment_health` (per-asset, `health_score` 0–100) | Worst-asset / criticality-weighted `100 − health_score` per store |
| 5 | **Labor** | `predictive_operations.gold_labor_risk` (store grain; unlocked by `canonical-core/labor`, ADR 0043) | Coverage-shortfall heuristic 0–100 |
| 6 | **Customer Experience** | _deferred_ — no CX/voice-of-customer source exists yet | NULL until CX source lands |

**Reuse boundary (do not re-model):** Inventory, Supply-Chain, and Sales/Margin
math is owned by their packages and only *referenced* here. Re-deriving stockout,
supplier, or margin risk under `predictive_operations` names would create
duplicate single-sources and re-implement prior work in `early-risk-detection`.

## 4. Scoring recipe (do it defensibly)

Mirrors `gold_procurement_risk.sql`. The rules below are the hard commitments.

1. **Normalize each raw signal to 0–100 before weighting**, against its realized
   distribution (observed p5/p95 or percentile), not a nominal ×100 clamp — a
   factor that only occupies the bottom third of its range would otherwise
   silently under-contribute versus its stated weight.
   - **Caveat — cross-store coupling (by design):** the discount-depth half of
     `sales_margin_risk` is normalized against a **cross-store p95** of discount
     rate computed per scoring run. That makes it a *relative* signal — a store's
     discount risk is expressed against its peers, so the same store on the same
     data can score differently if the peer set changes, and it is not reproducible
     for a single store scored in isolation. This is intentional for a fleet-wide
     **triage** index (the question is "which stores stand out?"), but a consumer
     must not read `sales_margin_risk` as a purely store-local signal. The sales-
     *trend* half is fully store-local; only the discount-depth half couples.
   - **Caveat — not stationary across dates:** because that p95 is recomputed each
     scoring run, the discount-depth normalizer can drift between snapshots. So the
     over-time measures in `mv_store_risk` (avg/max of `operational_risk_score`
     across `as_of_date`) mix a store-local trend signal with a fleet-relative,
     per-run-rebased discount signal — a rising `sales_margin_risk` across dates can
     reflect the store worsening **or** the fleet's discount distribution tightening.
     Read the score's *time trend* as directional triage, not a metrologically
     stable series; a stationary normalizer (a fixed reference p95, or per-store
     history) would be the v2 fix if strict cross-date comparability is needed.
2. **Visible weights in a single `w` CTE.** v1 weights over the five live
   domains (CX excluded from the denominator, not zero-weighted):

   | Domain | Weight |
   |---|---|
   | Inventory | 35 |
   | Supply-Chain | 25 |
   | Sales/Margin | 25 |
   | Equipment | 15 |
   | Labor | 15 |

   The composite is `SUM(weight_i × score_i) / SUM(weight_i over present domains)`.
3. **Missing means unknown, not safe.** A missing sub-score is `NULL` and is
   **excluded from the denominator** (as `gold_supplier_scorecard` does), never
   scored 0. This is why CX being NULL does not deflate the score —
   the denominator is the sum of *present* weights. `gold_procurement_risk`
   defaults missing inputs to 0, which understates risk; for a store score we do
   the opposite and exclude.
4. **Non-compensatory.** A plain weighted average is fully compensatory and
   reproduces the exact blind spot the framework exists to fix (the "102% of
   target, looks healthy" store that is stockout-critical). Two escalators, copied
   from `gold_procurement_risk`'s pattern:
   - **Worst-domain floor:** any single present domain going critical
     (sub-score ≥ `DOMAIN_CRITICAL`) forces the store to at least `HIGH`,
     regardless of the blend.
   - **Steep-trend force** on the Sales/Margin domain (sustained multi-period
     decline) forces at least `HIGH`.

   **Reconstructability limitation (v1):** the `store_risk_score` fact persists the
   tier and the per-domain sub-scores but not the *escalation reason*. A
   worst-domain-floor `HIGH` is reconstructable from the stored critical sub-score;
   a steep-trend `HIGH` is not, because `sales_trend_risk` is a gold-view
   intermediate and is not persisted. A pipeline that needs to explain every `HIGH`
   from the fact alone should add an `escalation_reason` column; v1 omits it.
5. **Do not double-count the availability→conversion pathway.** The causal chain
   is explicit that the domains are not independent: OSA/stockout feeds Inventory
   **and** drives Sales (via conversion). Each raw signal is assigned to exactly
   **one** sub-score (its proximate cause). The six sub-scores are the primary
   diagnostic profile; the single composite is a clearly-labeled **secondary
   triage roll-up**, not the headline that hides the diagnosis.
6. **State grain and roll-up rule per sub-score.** Inputs live at different grains
   (inventory is product × store, supplier risk is supplier-grain, equipment is
   per-asset). Each rolls up to store on the weight that matters for that domain:
   - **Inventory** — a **sales-velocity-weighted mean** of
     `gold_inventory_risk.stockout_risk_score` across the store's SKUs (weight =
     `trailing_units_sold`), so a stockout on a fast-moving SKU dominates a
     slow-mover; a store with no recorded velocity falls back to a plain mean.
   - **Supply-chain** — spend-weighted mean of supplier `risk_score`.
   - **Equipment** — criticality-weighted mean of `100 − health_score`.

   A plain mean would dilute a localized crisis and a raw MAX would let one item
   dominate — the weighted mean is the middle ground (the in-repo cautionary note
   in `gold_downtime_impact.sql`, use MAX not SUM per store/date, shows how a
   naive roll-up bites when left implicit).
7. **One declared horizon, per-domain observation windows.** Section 8 of the
   framework mixes 82@7-days with 91@14-days in one column, which is not
   comparable. v1 avoids that by pinning **one declared forward horizon**
   (`horizon_days = 7`) that the whole composite is interpreted against — every
   row in a snapshot carries the same horizon, so scores are comparable across
   stores and dates. `horizon_days` is that **assessment-horizon label, not a
   promise that every input is windowed to exactly 7 days** — the sub-scores read
   the trailing observation window that is diagnostic for each domain, and those
   windows differ by domain and are documented explicitly:

   | Domain | Observation window in v1 |
   |---|---|
   | Inventory | current-state (latest inventory snapshot + trailing sales velocity, from `gold_inventory_risk`) |
   | Supply-Chain | current supplier risk register (`gold_procurement_risk`), spend-weighted over a trailing 90-day PO-order window (`spend_window`) anchored to the latest `order_date` — a **procurement-local** clock, independent of sales freshness — so weights reflect current sourcing, not lifetime buys |
   | Sales/Margin | trailing **14-day** window vs the prior 14 days (recent-vs-prior net-sales trend + discount depth) |
   | Equipment | current-state health (`gold_equipment_health`: 7-day anomaly + 90-day work-order windows) |

   The reason windows differ is deliberate: a 7-day sales trend is too noisy to be
   a reliable decline signal, whereas inventory/equipment risk are point-in-time
   states. If a future version needs strictly horizon-matched windows or multiple
   horizons, emit them as **separate columns** (`risk_7d`, `risk_30d`), each with
   its inputs windowed to match — never mixed in one column.

### Outputs

- `operational_risk_score` DOUBLE (0–100, higher = riskier) — the composite.
- `operational_risk_tier` STRING — `UNKNOWN` / `LOW` / `MEDIUM` / `HIGH` /
  `CRITICAL`. `UNKNOWN` is emitted when `domains_scored = 0` (no present sub-score,
  so the score is NULL): the store is **unscored, not low-risk** — surfacing it as
  `LOW` would hide a store we have no signal for, contradicting the missing =
  unknown, not safe rule. The other four come from thresholds on the score plus the
  two escalators above.
- Per-domain sub-scores: `inventory_risk`, `supply_chain_risk`,
  `sales_margin_risk`, `equipment_risk`, `labor_risk` (each 0–100 or NULL),
  plus `cx_risk` (always NULL until a CX source lands).
- `top_risk_domains` STRING — the up-to-3 domains with the largest weighted
  contribution (the framework's **Diagnose** step, as `gold_procurement_risk`'s
  `top_risk_factors` does).
- `domains_scored` INT — how many of the six domains had a present (non-NULL)
  sub-score, so a consumer can see the composite's coverage.

## 5. Physical model — `store_risk_score` scored-output fact

Model the score physically as a **`store × as_of_date × score_method` snapshot
fact** (`dbx_data_type = transactional`), append-only, **no SCD2** (standards
§A.8: append-only facts carry only `record_source` + `load_timestamp`).
`as_of_date` conforms to `fiscal_calendar.date_key` and is the **scored-as-of**
date (the v1 gold view anchors it to `CURRENT_DATE()`, so the snapshot means "as
of when we scored," not "as far as any one input reaches"). `store_sk` carries the
**current** store version — the v1 view scores as-of today over current-state
inputs; a backfill pipeline scoring historical `as_of_date`s should resolve the
store version effective at that date. `score_method` is part of the grain so a model-backed row can sit
alongside the heuristic row for the same store/date without colliding — the
durable business key is `<store_id>|<as_of_date>|<score_method>`. This is the
durable, queryable history of scores a pipeline writes; the gold view is the live
computation. The scored-output columns follow the framework's Level-3/4 shape but
stay honest:

- `operational_risk_score` DOUBLE, `operational_risk_tier` STRING (CHECK enum).
- the six sub-score columns (Labor/CX NULL in v1).
- `horizon_days` INT (fixed 7 in v1).
- `score_method` STRING, CHECK `IN ('heuristic','model')` — v1 rows are
  `'heuristic'`; a model-backed pipeline writes `'model'` later.
- `predicted_impact_amount` DECIMAL(18,2) NULL + `currency_code` — reserved for a
  model/adopter to populate (the Estimate-Business-Impact step); NULL in the
  shipped heuristic.

Standards §A.9 forbids predictive scores on masters/dimensions, so the score
lives only in this gold/fact/metric layer, never on `store`.

## 6. Package boundary — `predictive-operations` vs `early-risk-detection`

Settle explicitly (logged in [ADR 0028](../../../governance/decisions/0028-predictive-operations-store-risk.md)):

- `early-risk-detection` owns **alert-grain, supply-chain-centric** triage
  (`gold_control_tower`: "which disruptions need action now?"). It is the
  event/alert plane.
- The **Store Operational Risk Score is store-grain and executive** ("which
  stores are becoming at-risk?"). It **consumes** `early-risk-detection`'s
  `gold_inventory_risk` and `gold_procurement_risk` outputs rather than competing
  with them. This is a bounded gold→gold read, legal under `LAYER-INTEGRITY`
  (which forbids only canonical-core FKs into a gold schema), precedent set by
  [ADR 0024](../../../governance/decisions/0024-gold-to-gold-coupling-acu-ucv.md).

Consequence accepted: `predictive-operations` does not deploy as a standalone
island — its composite needs `early-risk-detection` and `balancing-margin-and-volume`
gold views present. Deploy order is documented in the view header.

## 7. Predictive honesty — where the data model's job ends

The framework promises calibrated probabilities, dollar-impact predictions, and
Level-3/4 maturity. **ORDM is a data model plus gold/metric views; it trains and
serves no models.** So v1 ships:

- (a) conformed leading-indicator feature columns (the sub-scores),
- (b) a transparent heuristic composite index (0–100 + tier),
- (c) this documented scoring recipe,
- (d) a scored-output fact with `score_method` and a reserved
  `predicted_impact_amount` a pipeline can populate later.

Out of scope for the DDL: ML training, calibration, serving. A **Placeholder
Data** section in the package README names every NULL column and NULL KPI
(copying `balancing-margin-and-volume/README.md`'s honesty pattern). Where
prediction can honestly live: a worked notebook in `notebook-templates/` that
reads the feature views, trains/serves a model, and writes
`operational_risk_score` / `predicted_impact_amount` back with
`score_method = 'model'` — demonstrating the full Observe→Act loop as an adopter
example without claiming the DDL does the prediction.

## Deferred sub-scores (v1.1/v1.2)

- **Labor / Workforce** — **landed in ADR 0043** (`canonical-core/labor` +
  Workforce Optimization gold). `labor_risk` is populated from
  `gold_labor_risk` when present.
- **Customer Experience / voice-of-customer** (unlocks the CX sub-score): a small
  `feedback`/`survey_response` source (NPS/CSAT/complaints) + a `service_event`
  fact (wait time, abandoned transactions). Placement (new core domain vs outcome
  extension) is a working-group call. Return Rate already has a source
  (`returns_units` in BMV) and needs nothing new.

Sequencing: Labor is live; CX remains deferred and stays NULL in the composite
denominator until its source lands.
