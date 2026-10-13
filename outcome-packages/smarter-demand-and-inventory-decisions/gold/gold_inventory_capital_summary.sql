-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- View: gold_inventory_capital_summary
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Aggregated working capital and excess/understock exposure by category and ABC class.
--
-- Valuation basis is explicit and consistent:
--   - inventory_value / excess (overstock) are working capital -> COST basis
--     (units x unit_cost), matching gold_inventory_health.inventory_value.
--   - understock exposure is the gross margin we stand to miss if the gap is not
--     filled -> MARGIN-at-risk basis (units x (list_price - unit_cost)), NOT full
--     retail. Full-retail overstated the loss by counting COGS we never incur, and
--     mixing a retail figure into a cost-basis working-capital view double-counted
--     margin. Kept as a separate column, never summed with the cost-basis figures.
-- gold_inventory_health is a latest-snapshot view (one row per product x store at
-- the max date), so joining product on is_current = TRUE is the correct as-of basis
-- here; there are no historical rows to misvalue.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${sdi_schema}.gold_inventory_capital_summary AS
SELECT
  p.category,
  ih.abc_class,
  COUNT(*) AS sku_store_count,
  SUM(ih.inventory_value) AS total_inventory_value,
  SUM(ih.overstock_quantity * p.unit_cost) AS excess_inventory_value,
  SUM(ih.understock_quantity * GREATEST(p.list_price - p.unit_cost, 0)) AS understock_margin_at_risk
FROM ${catalog}.${sdi_schema}.gold_inventory_health ih
JOIN ${catalog}.${product_schema}.product p ON p.product_id = ih.product_id AND p.is_current = TRUE
GROUP BY p.category, ih.abc_class;
