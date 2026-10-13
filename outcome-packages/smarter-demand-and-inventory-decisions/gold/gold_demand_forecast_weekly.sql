-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- View: gold_demand_forecast_weekly
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Demand forecast aggregated to fiscal week with planning unit and dimension context.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${sdi_schema}.gold_demand_forecast_weekly AS
SELECT
  df.demand_forecast_id,
  df.planning_unit_sk,
  df.planning_unit_id,
  pu.grain_type,
  pu.product_id,
  pu.store_id,
  fc.fiscal_week_id,
  df.forecast_horizon_type,
  df.forecast_origin_date_key,
  SUM(df.forecast_quantity) AS forecast_quantity,
  df.unit_of_measure
FROM ${catalog}.${sdi_schema}.demand_forecast df
JOIN ${catalog}.${sdi_schema}.planning_unit pu ON pu.planning_unit_sk = df.planning_unit_sk
LEFT JOIN ${catalog}.${calendar_schema}.fiscal_calendar fc ON fc.date_key = df.forecast_date_key
GROUP BY
  df.demand_forecast_id, df.planning_unit_sk, df.planning_unit_id,
  pu.grain_type, pu.product_id, pu.store_id,
  fc.fiscal_week_id, df.forecast_horizon_type, df.forecast_origin_date_key, df.unit_of_measure;
