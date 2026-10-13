-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- View: gold_oos_rate
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- OOS rate KPIs from daily inventory position snapshots.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${sdi_schema}.gold_oos_rate AS
SELECT
  ip.store_id,
  p.category,
  fc.fiscal_week_id,
  COUNT(*) AS total_sku_days,
  SUM(CASE WHEN ip.is_stockout = TRUE THEN 1 ELSE 0 END) AS stockout_sku_days,
  CAST(SUM(CASE WHEN ip.is_stockout = TRUE THEN 1 ELSE 0 END) AS DOUBLE) / COUNT(*) AS oos_rate_pct
FROM ${catalog}.${inventory_schema}.inventory_position ip
JOIN ${catalog}.${product_schema}.product p ON p.product_id = ip.product_id AND p.is_current = TRUE
LEFT JOIN ${catalog}.${calendar_schema}.fiscal_calendar fc ON fc.date_key = ip.date_key
GROUP BY ip.store_id, p.category, fc.fiscal_week_id;
