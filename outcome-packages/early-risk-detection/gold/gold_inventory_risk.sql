-- ============================================================
-- ORDM · Outcome Package · Early Risk Detection
-- View: gold_inventory_risk
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-06-30
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-30 by @sreekanthmunigati
-- ============================================================
-- Per-product x store inventory risk view: days-of-supply,
-- stockout risk score, and reorder signals. Built on the canonical
-- inventory_position fact and a trailing sales velocity from the
-- transaction domain.
--
-- Definitions:
--   avg_daily_sales = trailing AVG_WINDOW-day average units sold.
--   days_of_supply  = units_on_hand_eod / avg_daily_sales.
--   stockout_risk_score = 0-100 score: lower days_of_supply and
--     higher stockout history yield higher risk.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${risk_schema}.gold_inventory_risk AS
WITH params AS (
  SELECT
    14 AS avg_window,       -- trailing days for sales velocity
    3.0 AS low_dos_threshold,   -- days-of-supply below which risk is high
    14.0 AS safe_dos_threshold  -- days-of-supply above which risk is low
),
latest_date AS (
  SELECT MAX(date_key) AS max_date
  FROM ${catalog}.${inventory_schema}.inventory_position
),
current_inventory AS (
  SELECT
    ip.product_id,
    ip.product_sk,
    ip.store_id,
    ip.store_sk,
    ip.units_on_hand_eod,
    ip.units_in_transit,
    ip.is_stockout,
    ip.stockout_pct_day,
    ip.date_key
  FROM ${catalog}.${inventory_schema}.inventory_position ip
  JOIN latest_date ld ON ip.date_key = ld.max_date
),
trailing_sales AS (
  SELECT
    s.product_id,
    s.store_id,
    SUM(s.units) AS total_units_sold
  FROM ${catalog}.${transaction_schema}.sales s
  CROSS JOIN params p
  CROSS JOIN latest_date ld
  WHERE s.date_key BETWEEN DATE_SUB(ld.max_date, p.avg_window - 1) AND ld.max_date
  GROUP BY s.product_id, s.store_id
),
combined AS (
  SELECT
    ci.product_id,
    ci.product_sk,
    ci.store_id,
    ci.store_sk,
    ci.units_on_hand_eod,
    ci.units_in_transit,
    ci.is_stockout,
    ci.stockout_pct_day,
    ci.date_key AS snapshot_date,
    COALESCE(ts.total_units_sold, 0) AS trailing_units_sold,
    CAST(COALESCE(ts.total_units_sold, 0) AS DOUBLE) / NULLIF(p.avg_window, 0) AS avg_daily_sales,
    p.low_dos_threshold,
    p.safe_dos_threshold
  FROM current_inventory ci
  CROSS JOIN params p
  LEFT JOIN trailing_sales ts
    ON ts.product_id = ci.product_id AND ts.store_id = ci.store_id
)
SELECT
  product_id,
  product_sk,
  store_id,
  store_sk,
  units_on_hand_eod,
  units_in_transit,
  is_stockout,
  stockout_pct_day,
  snapshot_date,
  trailing_units_sold,
  avg_daily_sales,
  CASE
    WHEN avg_daily_sales > 0 THEN ROUND(units_on_hand_eod / avg_daily_sales, 1)
    ELSE NULL
  END AS days_of_supply,
  CASE
    WHEN avg_daily_sales > 0 THEN ROUND((units_on_hand_eod + COALESCE(units_in_transit, 0)) / avg_daily_sales, 1)
    ELSE NULL
  END AS days_of_supply_with_transit,
  -- Stockout risk score: 0-100, higher = riskier
  CASE
    WHEN is_stockout = TRUE THEN 100
    WHEN avg_daily_sales <= 0 THEN 0
    ELSE CAST(LEAST(100, GREATEST(0,
      100 * (1 - LEAST(units_on_hand_eod / avg_daily_sales, safe_dos_threshold) / safe_dos_threshold)
    )) AS INT)
  END AS stockout_risk_score,
  CASE
    WHEN is_stockout = TRUE THEN 'stockout'
    WHEN avg_daily_sales > 0 AND units_on_hand_eod / avg_daily_sales < low_dos_threshold THEN 'critical'
    WHEN avg_daily_sales > 0 AND units_on_hand_eod / avg_daily_sales < safe_dos_threshold THEN 'at_risk'
    ELSE 'healthy'
  END AS inventory_risk_tier
FROM combined;
