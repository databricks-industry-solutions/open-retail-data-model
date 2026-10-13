-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- View: gold_inventory_policy_compliance
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Compares current inventory position against active policy thresholds.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${sdi_schema}.gold_inventory_policy_compliance AS
SELECT
  ih.product_id,
  ih.store_id,
  ih.units_on_hand_eod,
  ih.reorder_point_quantity,
  ih.max_quantity,
  ih.days_of_supply,
  ih.units_on_hand_eod < COALESCE(ih.reorder_point_quantity, 0) AS is_below_rop,
  ih.units_on_hand_eod > COALESCE(ih.max_quantity, 999999999) AS is_above_max,
  ih.inventory_position_status
FROM ${catalog}.${sdi_schema}.gold_inventory_health ih;
