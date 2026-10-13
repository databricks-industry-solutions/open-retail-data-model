-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- View: gold_forecast_accuracy
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Forecast accuracy dashboard with ABC/XYZ segment attributes.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${sdi_schema}.gold_forecast_accuracy AS
SELECT
  fa.forecast_accuracy_sk,
  fa.planning_unit_sk,
  fa.planning_unit_id,
  fa.forecast_date_key,
  fa.actual_quantity,
  fa.forecast_quantity,
  fa.effective_forecast_quantity,
  fa.lag_weeks,
  fa.accuracy_pct,
  fa.bias_pct,
  fa.mape,
  fa.is_stockout_censored,
  seg.abc_class,
  seg.xyz_class,
  seg.cluster_id,
  pu.grain_type,
  pu.product_id,
  pu.store_id
FROM ${catalog}.${sdi_schema}.forecast_accuracy fa
JOIN ${catalog}.${sdi_schema}.planning_unit pu ON pu.planning_unit_sk = fa.planning_unit_sk
LEFT JOIN ${catalog}.${sdi_schema}.planning_unit_segment seg
  ON seg.planning_unit_sk = fa.planning_unit_sk
LEFT JOIN ${catalog}.${calendar_schema}.fiscal_calendar fc ON fc.date_key = fa.forecast_date_key
 AND seg.fiscal_period_key = fc.fiscal_week_id;
