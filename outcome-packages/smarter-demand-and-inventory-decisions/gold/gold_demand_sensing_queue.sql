-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- View: gold_demand_sensing_queue
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Unresolved demand sensing signals and forecast divergence for short-horizon triage.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${sdi_schema}.gold_demand_sensing_queue AS
SELECT
  dss.demand_sensing_signal_id,
  dss.signal_timestamp,
  dss.signal_category,
  dss.signal_type,
  dss.severity,
  dss.product_id,
  dss.store_id,
  dss.planning_unit_id,
  dss.signal_description
FROM ${catalog}.${sdi_schema}.demand_sensing_signal dss
WHERE COALESCE(dss.resolved_flag, FALSE) = FALSE;
