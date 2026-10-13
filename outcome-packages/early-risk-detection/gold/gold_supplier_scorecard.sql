-- ============================================================
-- ORDM · Outcome Package · Early Risk Detection
-- View: gold_supplier_scorecard   (MATERIALIZED VIEW)
-- Layer: outcome package (gold / consumable)
-- Materialization: Lakeflow Declarative Pipeline materialized view, refreshed on
--   the fiscal-period cadence. gold_procurement_risk and gold_category_growth
--   read the MATERIALIZED table, so the KPI aggregation runs once per refresh.
-- Version: 0.5
-- Generated: 2026-06-09
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-09
-- ============================================================
-- Per-supplier performance scorecard, one row per supplier x fiscal period
-- (NRF 4-5-4 period from the fiscal calendar). The objective input to
-- procurement-risk decisions.
--
-- KPIs (per supplier x fiscal period):
--   otif_pct  = lines delivered ON TIME (actual <= promised) AND IN FULL
--               (received >= ordered * IN_FULL_TOLERANCE, default 1.0)
--               / total order lines.
--   fill_rate = SUM(received_qty) / SUM(ordered_qty).
--   avg_lead_time_days = mean(actual_delivery_date - order_date) over delivered lines.
--   lead_time_variance = POPULATION variance (var_pop) of lead time over delivered lines.
--   defect_rate = (defective + returned units) / received units.
--   price_compliance_pct = lines with unit_price <= contract_price / total order lines.
--
-- Composite (0-100), weights surfaced in the `w` CTE (NOT buried). Each KPI is
-- normalized to a 0-100 sub-score (higher = better) BEFORE weighting:
--   otif_score   = otif_pct * 100
--   fill_score   = LEAST(fill_rate, 1) * 100
--   lead_score   = 100 * GREATEST(0, 1 - lead_time_variance / VAR_CAP)   (VAR_CAP days^2)
--   defect_score = 100 * GREATEST(0, 1 - defect_rate / DEFECT_CAP)
--   price_score  = price_compliance_pct * 100
--   composite_score = SUM(weight_i * score_i) / SUM(weight_i)   (weights sum to 100)
-- composite_score is NULL only if a component KPI is undefined (surfaced as a
-- DQ metric, not a failure).
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${risk_schema}.gold_supplier_scorecard AS
WITH w AS (
  -- Composite weights (sum to 100) and normalization caps. Single, visible home.
  SELECT
    35  AS w_otif,
    25  AS w_fill,
    20  AS w_lead,
    15  AS w_defect,
    5   AS w_price,
    1.0 AS in_full_tolerance,   -- received must be >= ordered * tolerance
    25.0 AS var_cap,            -- lead_time_variance (days^2) mapped to lead_score 0
    0.10 AS defect_cap          -- defect_rate mapped to defect_score 0
),
lines AS (
  SELECT
    pol.supplier_sk,
    pol.supplier_id,
    c.fiscal_year,
    c.fiscal_period,
    pol.ordered_qty,
    pol.received_qty,
    pol.defective_qty,
    pol.returned_qty,
    pol.unit_price,
    pol.contract_price,
    pol.actual_delivery_date,
    pol.promised_date,
    w.in_full_tolerance,
    datediff(pol.actual_delivery_date, pol.order_date) AS lead_time_days
  FROM ${catalog}.${procurement_schema}.purchase_order_line pol
  JOIN ${catalog}.${calendar_schema}.fiscal_calendar c
    ON pol.order_date = c.date_key
  CROSS JOIN w
),
agg AS (
  SELECT
    l.supplier_sk,
    l.supplier_id,
    l.fiscal_year,
    l.fiscal_period,
    COUNT(*) AS order_lines,
    SUM(CASE WHEN l.actual_delivery_date IS NOT NULL
              AND l.actual_delivery_date <= l.promised_date
              AND l.received_qty >= l.ordered_qty * l.in_full_tolerance
             THEN 1 ELSE 0 END) AS otif_lines,
    SUM(l.ordered_qty)  AS ordered_units,
    SUM(l.received_qty) AS received_units,
    SUM(l.defective_qty + l.returned_qty) AS defect_units,
    AVG(l.lead_time_days)     AS avg_lead_time_days,
    VAR_POP(l.lead_time_days) AS lead_time_variance,
    SUM(CASE WHEN l.unit_price <= l.contract_price THEN 1 ELSE 0 END) AS price_compliant_lines
  FROM lines l
  GROUP BY l.supplier_sk, l.supplier_id, l.fiscal_year, l.fiscal_period
)
SELECT
  a.supplier_sk,
  a.supplier_id,
  s.supplier_name,
  s.country_code,
  a.fiscal_year,
  a.fiscal_period,
  a.order_lines,
  CAST(a.otif_lines AS DOUBLE) / a.order_lines                       AS otif_pct,
  CAST(a.received_units AS DOUBLE) / NULLIF(a.ordered_units, 0)      AS fill_rate,
  a.avg_lead_time_days,
  a.lead_time_variance,
  CAST(a.defect_units AS DOUBLE) / NULLIF(a.received_units, 0)       AS defect_rate,
  CAST(a.price_compliant_lines AS DOUBLE) / a.order_lines            AS price_compliance_pct,
  (
    w.w_otif   * (CAST(a.otif_lines AS DOUBLE) / a.order_lines * 100)
  + w.w_fill   * (LEAST(CAST(a.received_units AS DOUBLE) / NULLIF(a.ordered_units, 0), 1) * 100)
  + w.w_lead   * (100 * GREATEST(0, 1 - a.lead_time_variance / w.var_cap))
  + w.w_defect * (100 * GREATEST(0, 1 - (CAST(a.defect_units AS DOUBLE) / NULLIF(a.received_units, 0)) / w.defect_cap))
  + w.w_price  * (CAST(a.price_compliant_lines AS DOUBLE) / a.order_lines * 100)
  ) / (w.w_otif + w.w_fill + w.w_lead + w.w_defect + w.w_price)      AS composite_score
FROM agg a
CROSS JOIN w
JOIN ${catalog}.${supplier_schema}.supplier s
  ON s.supplier_sk = a.supplier_sk;
