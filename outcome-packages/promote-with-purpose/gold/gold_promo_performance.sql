-- ============================================================
-- ORDM · Outcome Package · Promote with Purpose
-- View: gold_promo_performance   (one row per promotion)
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-06-09
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-09
-- ============================================================
-- Operational "did it sell?" summary per promotion: scope size, promoted
-- units/revenue, baseline units, planned trade spend, and planned vs realized
-- lift. The financial "did it pay off?" view is gold_promo_roi.
--
-- A clean roll-up of gold_trade_promotion (promo x product x store x week) to
-- one row per promotion, with a single join to the promotion dimension for
-- mechanics and dates. Grouping keys are enumerated explicitly, no
-- always-true filters, single dimension join, base table scanned once.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${promo_schema}.gold_promo_performance AS
WITH agg AS (
  SELECT
    promo_id,
    COUNT(DISTINCT product_id)     AS scope_skus,
    COUNT(DISTINCT store_id)       AS scope_stores,
    COUNT(DISTINCT fiscal_week_id) AS fiscal_weeks,
    SUM(promoted_units)            AS promoted_units,
    SUM(promoted_revenue)          AS promoted_revenue,
    SUM(baseline_units)            AS baseline_units,
    SUM(planned_trade_spend)       AS planned_trade_spend,
    MAX(planned_lift_pct)          AS planned_lift_pct
  FROM ${catalog}.${promo_schema}.gold_trade_promotion
  GROUP BY promo_id
)
SELECT
  a.promo_id,
  p.promo_name,
  p.promo_type,
  p.funding_type,
  p.funded_by,
  p.start_date,
  p.end_date,
  a.scope_skus,
  a.scope_stores,
  a.fiscal_weeks,
  a.promoted_units,
  a.promoted_revenue,
  a.baseline_units,
  a.planned_trade_spend,
  a.planned_lift_pct,
  (100.0 * (a.promoted_units - a.baseline_units) / NULLIF(a.baseline_units, 0)) AS realized_lift_pct
FROM agg a
JOIN ${catalog}.${marketing_schema}.promotion p
  ON p.promo_id = a.promo_id AND p.is_current = true;
