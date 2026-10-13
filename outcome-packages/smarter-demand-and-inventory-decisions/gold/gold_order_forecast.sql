-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- View: gold_order_forecast
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Order forecast with planning unit context and open purchase order comparison.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${sdi_schema}.gold_order_forecast AS
SELECT
  ofc.order_forecast_sk,
  ofc.order_forecast_id,
  ofc.planning_unit_sk,
  ofc.planning_unit_id,
  ofc.order_date_key,
  ofc.need_by_date_key,
  ofc.order_forecast_quantity,
  ofc.order_type,
  ofc.source_location_id,
  ofc.destination_store_id,
  pu.product_id,
  pu.store_id,
  ofc.demand_forecast_id,
  ofc.inventory_policy_id
FROM ${catalog}.${sdi_schema}.order_forecast ofc
JOIN ${catalog}.${sdi_schema}.planning_unit pu ON pu.planning_unit_sk = ofc.planning_unit_sk;
