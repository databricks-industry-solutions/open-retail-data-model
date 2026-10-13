-- ============================================================
-- ORDM · Outcome Package · Promote with Purpose
-- View: gold_promo_roi   (one row per promotion)
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-06-09
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-09
-- ============================================================
-- Did the promotion pay off? One row per completed promotion: incremental
-- units / revenue / margin over baseline, ROI on trade spend, realized vs
-- planned lift, and the two value-killers (cannibalization, forward buy).
--
-- This is a clean roll-up of gold_promo_roi_by_category (a MATERIALIZED VIEW; the promo x category
-- drill) — all measures are additive across categories; ROI and realized lift
-- are recomputed from the summed components. trade_spend allocations sum back
-- to the promotion's planned_trade_spend. incremental_* and
-- net_incremental_margin are NOT clamped: negative = the promo lost money.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${promo_schema}.gold_promo_roi AS
SELECT
  promo_id,
  promo_name,
  promo_type,
  funding_type,
  funded_by,
  start_date,
  end_date,
  SUM(promoted_units)        AS promoted_units,
  SUM(promoted_revenue)      AS promoted_revenue,
  SUM(promoted_margin)       AS promoted_margin,
  SUM(baseline_units)        AS baseline_units,
  SUM(baseline_revenue)      AS baseline_revenue,
  SUM(baseline_margin)       AS baseline_margin,
  SUM(incremental_units)     AS incremental_units,
  SUM(incremental_revenue)   AS incremental_revenue,
  SUM(incremental_margin)    AS incremental_margin,
  SUM(trade_spend)           AS trade_spend,
  SUM(incremental_margin) / NULLIF(SUM(trade_spend), 0) AS roi,
  MAX(planned_lift_pct)      AS planned_lift_pct,
  (100.0 * SUM(incremental_units) / NULLIF(SUM(baseline_units), 0)) AS realized_lift_pct,
  SUM(cannibalization_units)  AS cannibalization_units,
  SUM(cannibalization_margin) AS cannibalization_margin,
  SUM(forward_buy_units)      AS forward_buy_units,
  SUM(forward_buy_margin)     AS forward_buy_margin,
  SUM(net_incremental_margin) AS net_incremental_margin
FROM ${catalog}.${promo_schema}.gold_promo_roi_by_category
GROUP BY promo_id, promo_name, promo_type, funding_type, funded_by, start_date, end_date;
