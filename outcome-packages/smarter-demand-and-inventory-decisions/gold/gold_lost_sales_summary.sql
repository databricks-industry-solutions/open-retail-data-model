-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- View: gold_lost_sales_summary
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Aggregated lost sales by category, cause, and fiscal period.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${sdi_schema}.gold_lost_sales_summary AS
SELECT
  p.category,
  oe.oos_cause,
  fc.fiscal_week_id,
  SUM(lse.lost_units) AS total_lost_units,
  SUM(lse.lost_revenue) AS total_lost_revenue,
  COUNT(DISTINCT oe.oos_event_id) AS oos_event_count
FROM ${catalog}.${sdi_schema}.lost_sales_estimate lse
JOIN ${catalog}.${sdi_schema}.oos_event oe ON oe.oos_event_sk = lse.oos_event_sk
JOIN ${catalog}.${product_schema}.product p ON p.product_id = oe.product_id AND p.is_current = TRUE
LEFT JOIN ${catalog}.${calendar_schema}.fiscal_calendar fc ON fc.date_key = lse.estimate_date_key
GROUP BY p.category, oe.oos_cause, fc.fiscal_week_id;
