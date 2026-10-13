# Real-Time Data Access — Architecture & Runbook

## Business problem

Associates need a unified, trustworthy view of store operational context while helping customers. The data must be **governed**, **freshness-aware**, and **least-privilege** — suitable as the foundation for a future AI assistant, mobile companion, POS overlay, or AI/BI dashboard.

## Non-goals

- No generic consumer chatbot or unbounded LLM agent.
- No ORDM-owned ingestion pipelines (bronze/CDC jobs stay in the adopter workspace).
- No write-back of prices, inventory adjustments, or order changes.
- No exposure of customer PII, employee personal data, margins, or loss-prevention signals.

## Architecture

```
Canonical core (product, inventory_position, product_price, promotion, store, equipment_reading)
        + promote_with_purpose.promotion_scope
        + aasa.associate_context_event          (streaming-ready contract; adopter-fed production data; demo uses synthetic context events)
        + aasa.associate_fulfillment_status    (BOPIS/pickup extension; no PII)
                │
                ▼
   gold_associate_*_current
     · inventory + order = MATERIALIZED VIEW (CLUSTER BY store/product|order)
     · price / ops / freshness = plain views
     · optional UC row filter: filters.sql (store_id scope)
                │
                ├── UC Metric Views (Genie / AI/BI)
                └── tools.associate_realtime_access (policy + envelope)
                         │
                         ▼
                associate_lookup_audit
```

Demo/CI may `--demote-materialized` (rewrite MVs to plain views) via `tools/ddl_exec.py`.

Event time vs ingest time vs processed time vs current-state update time are preserved on events and projected into gold freshness fields.

## Source-to-serving lineage

| Output | Grain | Business keys | Sources | Serving |
|---|---|---|---|---|
| `gold_associate_product_inventory_current` | product × store | `product_id`, `store_id` | `inventory_position` + inventory events | **MV** + `CLUSTER BY (store_id, product_id)` |
| `gold_associate_price_promotion_current` | product × store (assortment) | `product_id`, `store_id` | `product`/`product_price` + `promotion`/`promotion_scope` + price events | plain view |
| `gold_associate_order_status_current` | order | `order_id` | `associate_fulfillment_status` + order events | **MV** + `CLUSTER BY (store_id, order_id)` |
| `gold_associate_operational_context_current` | store × context | `store_id`, `context_id` | replenishment flags + equipment alerts + ops events | plain view |
| `gold_associate_data_freshness` | feed × store | `feed_name`, `store_id` | max event/ingest timestamps | plain view |
| `associate_lookup_audit` | lookup | `associate_lookup_audit_id` | lookup service | table |

**Retention (guidance):** events 90 days hot / longer cold per adopter policy; audit 1 year; current-state views are derived (no separate retention).

**Idempotency:** `associate_context_event_id` unique; current-state = latest `(event_timestamp, ingest_timestamp)` per entity key after id dedupe.

**Serving materialization:** `gold_associate_product_inventory_current` and `gold_associate_order_status_current` are `CREATE OR REFRESH MATERIALIZED VIEW` with trailing `CLUSTER BY` for associate point lookups. Other gold objects stay plain views.

## Store-scope UC row filter (defence in depth)

The Python policy in `tools/associate_realtime_access/` does not protect Genie / DBSQL `SELECT` on gold. After gold exists, apply `filters.sql` (walkthrough: `notebook-templates/store_scope_row_filters.sql`):

1. Create `${aasa_schema}.associate_store_scope(store_id)` — default groups `aasa_cross_store` and `aasa_store_<store_id>` (rename to your IdP).
2. `SET ROW FILTER … ON (store_id)` on each store-grained gold object.
3. Not executed by `apply_model_ddl` (same deploy-gated pattern as `masks.sql`).
4. If inventory/order were demoted to plain views, use `ALTER VIEW` instead of `ALTER TABLE` for those two.

## Change Data Feed + ingest path

Extension tables ship with `delta.enableChangeDataFeed = true`:

| Table | Cluster keys | Why CDF |
|---|---|---|
| `associate_context_event` | `(store_id, product_id, event_timestamp)` | Incremental MV refresh, Lakebase sync, late-event debug |
| `associate_fulfillment_status` | `(store_id, order_id)` | Same for order gold / sync |
| `associate_lookup_audit` | `(store_id, request_timestamp)` | Ops telemetry sync / incremental consumers |

Adopter ingest template: `notebook-templates/associate_context_event_ingest.sql` (Auto Loader streaming table → MERGE on `associate_context_event_id` → `REFRESH MATERIALIZED VIEW` inventory/order).

## Genie + certification

- `comments.sql` tags gold + metric views with `system.certification_status = certified` (ADR 0010 / Genie Ontology).
- Import `genie_space.json` after substituting `${catalog}` / `${aasa_schema}` — instructions force `inventory_basis` / `warning` surfacing and forbid invented shelf coords or “nearest store” wording.

## Lakebase (adopter serving)

See `LAKEBASE_SERVING.md`. Gold stays Delta (ADR 0005); sync certified MVs to Lakebase for sub-second mobile/POS keyed lookups. FGAC does not propagate — sync a store-scoped view if needed.

## Honest freshness semantics (associate-facing)

Downstream UIs **must** surface `inventory_basis`, `explanation`, and `warning` — do not present day-grain snapshots as live shelf counts.

| `inventory_basis` | Meaning | Freshness rule |
|---|---|---|
| `daily_snapshot` | Latest `inventory_position.date_key` only — **end-of-day grain** | Same calendar day → `fresh` (EOD semantics); 1 day behind → `delayed`; older → `stale`. Warning always notes “not live shelf counts.” |
| `event_overlay` | Intra-day `associate_context_event` inventory overlay present | Lag from ingest timestamp; fresh &lt; 60m, delayed 60–1440m, stale &gt; 1440m. Adopter streaming target ≤ 5 min. |

`freshness_status = fresh` on a `daily_snapshot` row means “the EOD snapshot for today is present,” **not** “the shelf was counted in the last hour.”

## Location model (explicit gap)

ORDM has **no shelf / bay / planogram geo model**.

| Field | Meaning |
|---|---|
| `sales_floor_or_backroom_location` | Optional free-text `location_code` from an inventory event (e.g. `A-12-B`, `BACKROOM-3`) |
| `location_basis = event_location_code` | A code was supplied on an event |
| `location_basis = not_modeled` | No code — lookup returns `NOT_AVAILABLE` for location |

Never invent aisle coordinates. Clients should render “location not available in catalog” when basis is `not_modeled`.

## Nearby-store alternatives (explicit rule)

When local stock is out / low, `nearby_store_with_stock_id` is the **same `store.region`**, `store_status = active`, other store, with on-hand &gt; 0, ranked by quantity then `store_id`.

| Field | Meaning |
|---|---|
| `nearby_store_match_basis = same_region_on_hand` | Region peer with stock — **not** distance / drive-time / geo nearest-neighbor |

Associates (and UIs) must not label this “nearest store.” Prefer copy such as “Also in stock at store {id} (same region).”

## Package use-case status

| Use case | Status | Notes |
|---|---|---|
| **Real-Time Data Access** | `done` | This document + gold/lookup contract |
| **Associates Best Next Actions** | `done` | Prioritized action queue; populated on the demo deploy from synthetic data |
| **Digital Assistant Selling Tools** | `done` | Outcome funnel and metric view; populated on the demo deploy from synthetic data |

## Request / response examples (redacted)

### Success — product availability (event overlay)

```json
{
  "request_id": "REQ-100",
  "status": "SUCCESS",
  "data": {
    "product_id": "P-100",
    "store_id": "S-01",
    "stock_status": "IN_STOCK",
    "quantity_on_hand": 24.0,
    "inventory_basis": "event_overlay",
    "location_basis": "event_location_code",
    "freshness_status": "fresh"
  },
  "warnings": [],
  "freshness": {"freshness_status": "fresh", "freshness_lag_minutes": 8.0},
  "source_lineage": {"domains": ["inventory"], "source_system": "synth_inventory"},
  "access_decision": {"decision": "allow", "reason_code": "STORE_SCOPE_ALLOWED", "allowed": true},
  "generated_at": "2026-08-11T15:00:00Z",
  "correlation_id": "CORR-100"
}
```

### EOD snapshot only — honest warning

```json
{
  "request_id": "REQ-100b",
  "status": "SUCCESS",
  "data": {
    "product_id": "P-100",
    "store_id": "S-01",
    "inventory_basis": "daily_snapshot",
    "snapshot_date_key": "2026-08-11",
    "freshness_status": "fresh"
  },
  "warnings": [
    "Quantities are end-of-day snapshot grain — not intra-day real-time unless an inventory event overlay is present."
  ],
  "explanation": "End-of-day inventory_position snapshot for date_key=2026-08-11 — not live shelf counts."
}
```

### Access denied — wrong store

```json
{
  "request_id": "REQ-101",
  "status": "ACCESS_DENIED",
  "data": null,
  "access_decision": {"decision": "deny", "reason_code": "STORE_SCOPE_DENIED", "allowed": false},
  "correlation_id": "CORR-101"
}
```

### Partial result — inventory yes, price delayed/missing

```json
{
  "request_id": "REQ-102",
  "status": "PARTIAL_RESULT",
  "data": {"product_id": "P-100", "store_id": "S-01", "inventory_stock_status": "IN_STOCK", "price": null},
  "warnings": ["Price/promotion domain unavailable for this product/store."],
  "source_lineage": {"domains": ["inventory"], "missing_domains": ["price"]}
}
```

## Operational runbook — freshness incidents

1. Query `gold_associate_data_freshness` for `sla_state = 'breach'` or `freshness_status = 'stale'`.
2. Identify feed (`inventory_position`, `associate_context_event_*`, `associate_fulfillment_status`).
3. For inventory: check whether rows are `inventory_basis = daily_snapshot` (EOD only) vs missing/late event overlays.
4. Check adopter ingestion checkpoint / job run for that source system.
5. Associate-facing clients must surface `STALE_DATA` / `UPSTREAM_DATA_DELAY` and EOD warnings — do not silently treat as live real-time.
6. After recovery, confirm lag returns to `fresh` and audit error rate drops.

## Diagrams

Mermaid / DBML sources live under `diagrams/`. Rendered SVG snapshots are produced by `make regen-svg` (Chromium + mermaid-cli) and are also refreshed by CI on same-repo PRs. If SVGs are absent locally, open the `.mmd` sources or run:

```bash
make regen-svg
```

## Limitations and next steps

| Topic | Current state | Next step |
|---|---|---|
| Inventory without event overlay | **EOD day-grain** — honesty fields `inventory_basis`, warning, explanation | Wire `associate_context_event_ingest.sql` (or equivalent) |
| Shelf / bay location | Optional `location_code` only; `location_basis = not_modeled` → `NOT_AVAILABLE` | Future planogram / CSS smart-shelf if promoted |
| Nearby-store alternative | Same region + on-hand &gt; 0 (`nearby_store_match_basis`) | Optional distance / fulfillment-node ranking in adopter layer |
| Point-lookup latency | Inventory + order gold are **materialized views** (`CLUSTER BY` store/product\|order) | Keep price/ops/freshness as views unless query volume warrants MV |
| Store-scope on Genie/DBSQL | Template in `filters.sql` (adopter-applied UC row filter) | Wire IdP groups or labor eligibility bridge |
| Event / fulfillment incrementality | **CDF enabled** on event, fulfillment, audit tables | Use CDF consumers for MV refresh + Lakebase Triggered/Continuous |
| Genie honesty | `genie_space.json` + certified tags on gold/metrics | Create Genie Space in adopter workspace |
| Sub-second mobile serving | Spec in `LAKEBASE_SERVING.md` (adopter sync) | Create synced tables from certified MVs |
| Best Next Actions | **Done** | Prioritized action queue; populated on the demo deploy from synthetic data |
| Digital Assistant Selling Tools | **Done** | Outcome funnel and metric view; populated on the demo deploy from synthetic data |
| UC DQ monitors / DBSQL lookup UDFs | Not shipped | Optional P2 adopter artifacts |
