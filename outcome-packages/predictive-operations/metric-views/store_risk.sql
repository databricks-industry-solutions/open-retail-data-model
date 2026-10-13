-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · Store Performance use case
-- Metric View: store_risk
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-07-27
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-27 by @sreekanthmunigati
-- ============================================================
-- Store Operational Risk metric: the Store Operational Risk Score and its
-- per-domain sub-scores, grained at store x as_of_date and aggregatable by
-- region, district, risk tier, and time period.
--
-- SOURCE: the append-only store_risk_score HISTORY fact (heuristic rows), NOT the
-- gold_store_operational_risk view. The gold view scores a single as_of_date
-- (CURRENT_DATE), so a trend query through it would collapse to one point; the
-- fact carries the daily snapshot history that makes the avg/max-over-time
-- measures and the as_of_date dimension meaningful (the leading-vs-lagging
-- promise). Store display attributes (name/region/district) come from a plain
-- equi-join on the store_sk the pipeline wrote — there is NO as-of resolution
-- here; the view attaches whatever store version that store_sk points to. In v1
-- the fact carries the current store version (see the store_sk note in
-- tables/store_risk_score.sql), so this is correct today; a backfill that writes
-- historical as_of_date rows must resolve the effective store_sk upstream for the
-- attributes to be as-of-correct.
--
-- HONESTY (ADR 0028): operational_risk_score is a heuristic INDEX (0-100),
-- not a calibrated probability. Aggregations here are of that index.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${predops_schema}.mv_store_risk
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Store operational risk measurement over time. Higher score = higher near-term risk. Heuristic index, not a probability. Read the over-time series as DIRECTIONAL triage, not a metrologically stable series — the sales discount-depth normalizer (cross-store p95) is re-derived per scoring run, so a score can move across dates from a shifting fleet distribution as well as from the store itself (design spec §4)."
source: >
  SELECT
    srs.store_id,
    st.store_name,
    st.region,
    st.district,
    srs.as_of_date,
    srs.horizon_days,
    srs.operational_risk_score,
    srs.operational_risk_tier,
    srs.inventory_risk,
    srs.supply_chain_risk,
    srs.sales_margin_risk,
    srs.equipment_risk,
    srs.labor_risk,
    srs.domains_scored,
    srs.top_risk_domains
  FROM ${catalog}.${predops_schema}.store_risk_score srs
  LEFT JOIN ${catalog}.${store_schema}.store st
    ON st.store_sk = srs.store_sk
  WHERE srs.score_method = 'heuristic'

fields:
  - name: store_id
    expr: store_id
    display_name: "Store ID"
    comment: "Durable business key for the store (portable cross-deployment key)."
    synonyms: ["store", "location_id", "site_id"]

  - name: store_name
    expr: store_name
    display_name: "Store"
    comment: "Display name of the store."
    synonyms: ["location", "site"]

  - name: region
    expr: region
    display_name: "Region"
    comment: "Store region for roll-up."
    synonyms: ["area", "geo"]

  - name: district
    expr: district
    display_name: "District"
    comment: "Store district for roll-up."
    synonyms: ["zone", "territory"]

  - name: operational_risk_tier
    expr: operational_risk_tier
    display_name: "Risk Tier"
    comment: "Risk tier: UNKNOWN (no domain scored), LOW, MEDIUM, HIGH, CRITICAL."
    synonyms: ["risk_level", "tier", "severity"]

  - name: top_risk_domains
    expr: top_risk_domains
    display_name: "Top Risk Domains"
    comment: "Domains contributing most to the score (the Diagnose step)."
    synonyms: ["primary_risk", "risk_drivers", "root_cause"]

  - name: as_of_date
    expr: as_of_date
    display_name: "As-of Date"
    comment: "Snapshot date the score is computed for."
    synonyms: ["date", "snapshot_date"]
    format:
      type: date
      date_format: year_month_day

  - name: horizon_days
    expr: horizon_days
    display_name: "Horizon (days)"
    comment: "Declared forward assessment horizon the score is interpreted against (7 in v1)."
    synonyms: ["horizon", "forward_window"]

  - name: domains_scored
    expr: domains_scored
    display_name: "Domains Scored"
    comment: "How many domains had a present (non-NULL) sub-score feeding the composite (0-5; cx deferred); lets a consumer gauge how complete a score's coverage is."
    synonyms: ["coverage", "domains_present", "domain_count"]

measures:
  - name: avg_operational_risk_score
    expr: AVG(operational_risk_score)
    display_name: "Avg Risk Score"
    comment: "Average Store Operational Risk Score (0-100) across the selected stores/dates. When averaged across dates, treat as directional triage, not a stable series (the discount normalizer re-bases per run — see the view comment / design spec §4)."
    synonyms: ["mean_risk", "average_risk_score", "risk"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: max_operational_risk_score
    expr: MAX(operational_risk_score)
    display_name: "Peak Risk Score"
    comment: "Highest Store Operational Risk Score in the selection. Across dates, treat as directional triage, not a stable series (the discount normalizer re-bases per run — see the view comment / design spec §4)."
    synonyms: ["worst_risk", "peak_risk"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: store_count
    expr: COUNT(DISTINCT store_id)
    display_name: "Store Count"
    comment: "Number of distinct stores scored."
    synonyms: ["num_stores", "total_stores"]

  - name: high_risk_store_count
    expr: COUNT(DISTINCT CASE WHEN operational_risk_tier IN ('HIGH', 'CRITICAL') THEN store_id END)
    display_name: "High-Risk Stores"
    comment: "Number of distinct stores at HIGH or CRITICAL risk tier."
    synonyms: ["at_risk_stores", "stores_at_risk", "flagged_stores"]

  - name: avg_inventory_risk
    expr: AVG(inventory_risk)
    display_name: "Avg Inventory Risk"
    comment: "Average inventory domain sub-score (0-100)."
    synonyms: ["inventory_risk", "stockout_risk"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: avg_supply_chain_risk
    expr: AVG(supply_chain_risk)
    display_name: "Avg Supply-Chain Risk"
    comment: "Average supply-chain domain sub-score (0-100)."
    synonyms: ["supplier_risk", "procurement_risk"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: avg_sales_margin_risk
    expr: AVG(sales_margin_risk)
    display_name: "Avg Sales/Margin Risk"
    comment: "Average sales/margin domain sub-score (0-100)."
    synonyms: ["sales_risk", "margin_risk"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: avg_equipment_risk
    expr: AVG(equipment_risk)
    display_name: "Avg Equipment Risk"
    comment: "Average equipment domain sub-score (0-100)."
    synonyms: ["asset_risk", "equipment_risk"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: avg_labor_risk
    expr: AVG(labor_risk)
    display_name: "Avg Labor Risk"
    comment: "Average labor/workforce domain sub-score (0-100) from coverage shortfalls."
    synonyms: ["workforce_risk", "labor_risk", "staffing_risk"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: avg_domains_scored
    expr: AVG(domains_scored)
    display_name: "Avg Domains Scored"
    comment: "Average number of domains feeding the composite (0-5; cx deferred) — a coverage/quality gauge for the scores in the selection."
    synonyms: ["avg_coverage", "mean_domains_present"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1
$$;
