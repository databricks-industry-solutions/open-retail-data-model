-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- View: gold_inventory_health
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Per product x store inventory health combining position, velocity, policy, and forecast.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${sdi_schema}.gold_inventory_health AS
WITH params AS (
  SELECT 14 AS avg_window
),
latest_date AS (
  SELECT MAX(date_key) AS max_date FROM ${catalog}.${inventory_schema}.inventory_position
),
current_inventory AS (
  SELECT
    ip.product_id, ip.product_sk, ip.store_id, ip.store_sk,
    ip.units_on_hand_eod, ip.units_in_transit, ip.is_stockout, ip.date_key
  FROM ${catalog}.${inventory_schema}.inventory_position ip
  JOIN latest_date ld ON ip.date_key = ld.max_date
),
trailing_sales AS (
  SELECT s.product_id, s.store_id, SUM(s.units) AS total_units
  FROM ${catalog}.${transaction_schema}.sales s
  CROSS JOIN params p
  CROSS JOIN latest_date ld
  WHERE s.date_key BETWEEN DATE_SUB(ld.max_date, p.avg_window - 1) AND ld.max_date
  GROUP BY s.product_id, s.store_id
),
policy AS (
  SELECT ip.*, pol.safety_stock_quantity, pol.reorder_point_quantity, pol.max_quantity,
         pol.planning_unit_sk
  FROM ${catalog}.${sdi_schema}.inventory_policy pol
  JOIN ${catalog}.${sdi_schema}.planning_unit pu ON pu.planning_unit_sk = pol.planning_unit_sk
  JOIN current_inventory ip ON ip.product_id = pu.product_id AND ip.store_id = pu.store_id
  WHERE pol.is_current = TRUE
),
combined AS (
  SELECT
    ci.product_id, ci.product_sk, ci.store_id, ci.store_sk,
    ci.units_on_hand_eod, ci.units_in_transit, ci.is_stockout, ci.date_key AS snapshot_date,
    COALESCE(ts.total_units, 0) AS trailing_units_sold,
    CAST(COALESCE(ts.total_units, 0) AS DOUBLE) / p.avg_window AS avg_daily_sales,
    pol.safety_stock_quantity, pol.reorder_point_quantity, pol.max_quantity,
    seg.abc_class, seg.xyz_class,
    fac.bias_pct AS forecast_bias_pct
  FROM current_inventory ci
  CROSS JOIN params p
  LEFT JOIN trailing_sales ts ON ts.product_id = ci.product_id AND ts.store_id = ci.store_id
  LEFT JOIN policy pol ON pol.product_id = ci.product_id AND pol.store_id = ci.store_id
  LEFT JOIN ${catalog}.${sdi_schema}.planning_unit pu ON pu.product_id = ci.product_id AND pu.store_id = ci.store_id
  LEFT JOIN ${catalog}.${sdi_schema}.planning_unit_segment seg ON seg.planning_unit_sk = pu.planning_unit_sk
  LEFT JOIN ${catalog}.${sdi_schema}.forecast_accuracy fac
    ON fac.planning_unit_sk = pu.planning_unit_sk
   AND fac.forecast_date_key = ci.date_key
)
SELECT
  c.*,
  CASE WHEN c.avg_daily_sales > 0 THEN ROUND(c.units_on_hand_eod / c.avg_daily_sales, 1) END AS days_of_supply,
  CASE WHEN c.avg_daily_sales > 0 THEN ROUND((c.units_on_hand_eod + COALESCE(c.units_in_transit, 0)) / c.avg_daily_sales, 1) END AS days_of_supply_with_transit,
  GREATEST(0, c.units_on_hand_eod - COALESCE(c.max_quantity, 0)) AS overstock_quantity,
  GREATEST(0, COALESCE(c.reorder_point_quantity, 0) - c.units_on_hand_eod) AS understock_quantity,
  c.units_on_hand_eod * p.unit_cost AS inventory_value,
  CASE
    WHEN c.is_stockout = TRUE THEN 'stockout'
    WHEN c.avg_daily_sales > 0 AND c.units_on_hand_eod / c.avg_daily_sales < 3 THEN 'at_risk'
    WHEN c.max_quantity IS NOT NULL AND c.units_on_hand_eod > c.max_quantity THEN 'overstock'
    ELSE 'healthy'
  END AS inventory_position_status
FROM combined c
JOIN ${catalog}.${product_schema}.product p ON p.product_id = c.product_id AND p.is_current = TRUE;
