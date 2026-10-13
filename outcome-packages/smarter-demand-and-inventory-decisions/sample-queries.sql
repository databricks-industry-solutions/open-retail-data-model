-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- File: sample-queries.sql
-- Version: 0.5
-- Generated: 2026-07-21
-- ============================================================

-- 1. Effective forecast with ABC/XYZ segment for the next 4 weeks
SELECT
  ef.planning_unit_id,
  ef.forecast_date_key,
  ef.statistical_forecast_quantity,
  ef.effective_forecast_quantity,
  seg.abc_class,
  seg.xyz_class
FROM ${catalog}.${sdi_schema}.gold_effective_forecast ef
LEFT JOIN ${catalog}.${sdi_schema}.planning_unit_segment seg
  ON seg.planning_unit_id = ef.planning_unit_id
  AND seg.fiscal_period_key = ef.fiscal_period_key
WHERE ef.forecast_date_key >= CURRENT_DATE()
ORDER BY ef.forecast_date_key, ef.planning_unit_id
LIMIT 100;

-- 2. Inventory health: SKUs below reorder point
SELECT
  ih.product_id,
  ih.store_id,
  ih.units_on_hand_eod,
  ih.reorder_point_quantity,
  ih.days_of_supply,
  ih.inventory_position_status
FROM ${catalog}.${sdi_schema}.gold_inventory_health ih
WHERE ih.inventory_position_status IN ('at_risk', 'stockout')
ORDER BY ih.days_of_supply NULLS FIRST
LIMIT 50;

-- 3. Active OOS events with lost revenue
SELECT
  oc.product_id,
  oc.store_id,
  oc.oos_start_date_key,
  oc.oos_duration_days,
  oc.oos_severity,
  oc.lost_revenue_to_date,
  oc.is_preventable
FROM ${catalog}.${sdi_schema}.gold_oos_current oc
ORDER BY oc.lost_revenue_to_date DESC NULLS LAST
LIMIT 25;

-- 4. Forecast accuracy by ABC class
SELECT
  fa.abc_class,
  AVG(fa.accuracy_pct) AS avg_accuracy,
  AVG(fa.bias_pct) AS avg_bias
FROM ${catalog}.${sdi_schema}.gold_forecast_accuracy fa
GROUP BY fa.abc_class
ORDER BY fa.abc_class;
