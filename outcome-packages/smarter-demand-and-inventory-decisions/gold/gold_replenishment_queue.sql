-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- View: gold_replenishment_queue
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Open replenishment recommendations ranked by ABC class service impact.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${sdi_schema}.gold_replenishment_queue AS
SELECT
  ir.inventory_recommendation_id,
  ir.planning_unit_id,
  ir.recommendation_date_key,
  ir.recommended_order_quantity,
  ir.recommended_order_date_key,
  ir.recommendation_reason,
  ir.recommendation_status,
  seg.abc_class,
  ih.inventory_position_status,
  ih.days_of_supply,
  -- Explicit CAST: ROW_NUMBER() is BIGINT in Databricks SQL, but sqlglot's
  -- annotate_types() only resolves it from 30.9.0 up. The cast makes the
  -- generated contract type independent of the sqlglot version.
  CAST(ROW_NUMBER() OVER (
    ORDER BY CASE seg.abc_class WHEN 'A' THEN 1 WHEN 'B' THEN 2 ELSE 3 END,
             ih.days_of_supply NULLS FIRST
  ) AS BIGINT) AS priority_rank
FROM ${catalog}.${sdi_schema}.inventory_recommendation ir
JOIN ${catalog}.${sdi_schema}.planning_unit pu ON pu.planning_unit_sk = ir.planning_unit_sk
LEFT JOIN ${catalog}.${sdi_schema}.planning_unit_segment seg ON seg.planning_unit_sk = ir.planning_unit_sk
LEFT JOIN ${catalog}.${sdi_schema}.gold_inventory_health ih
  ON ih.product_id = pu.product_id AND ih.store_id = pu.store_id
WHERE ir.recommendation_status = 'open';
