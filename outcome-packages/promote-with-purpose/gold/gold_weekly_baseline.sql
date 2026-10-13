-- ============================================================
-- ORDM · Outcome Package · Promote with Purpose
-- View: gold_weekly_baseline   (MATERIALIZED VIEW)
-- Layer: outcome package (gold / reusable building block)
-- Materialization: Lakeflow Declarative Pipeline materialized view, refreshed
--   on the fiscal-period cadence by the pipeline schedule. Downstream gold
--   views (gold_promo_roi_by_category, gold_promo_roi) read the MATERIALIZED
--   table, so the trailing-baseline scan runs once per refresh, not per query.
-- Version: 0.5
-- Generated: 2026-06-09
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-09
-- ============================================================
-- Per product x store x fiscal week: actual sales and the trailing
-- non-promoted baseline. Materialized once and reused by gold_promo_roi
-- (for promoted SKUs, substitute SKUs and post-promo weeks alike), so the
-- baseline definition lives in ONE place.
--
-- baseline_units = mean weekly NO_PROMO units over the trailing 8 fiscal
-- weeks (current week excluded); NULL when fewer than 4 non-promoted weeks
-- are available. Identical definition to gold_trade_promotion's baseline.
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${promo_schema}.gold_weekly_baseline AS
WITH weekly AS (
  SELECT
    s.product_sk,
    s.store_sk,
    c.fiscal_week_index,
    SUM(s.units)       AS actual_units,
    SUM(s.net_revenue) AS actual_revenue,
    SUM(CASE WHEN s.promo_id = 'NO_PROMO' THEN s.units END) AS nonpromo_units
  FROM ${catalog}.${transaction_schema}.sales s
  JOIN ${catalog}.${calendar_schema}.fiscal_calendar c
    ON s.date_key = c.date_key
  GROUP BY s.product_sk, s.store_sk, c.fiscal_week_index
)
SELECT
  product_sk,
  store_sk,
  fiscal_week_index,
  actual_units,
  actual_revenue,
  CASE
    WHEN COUNT(nonpromo_units) OVER baseline_window >= 4
    THEN AVG(nonpromo_units) OVER baseline_window
  END AS baseline_units
FROM weekly
WINDOW baseline_window AS (
  PARTITION BY product_sk, store_sk
  ORDER BY fiscal_week_index
  RANGE BETWEEN 8 PRECEDING AND 1 PRECEDING
);
