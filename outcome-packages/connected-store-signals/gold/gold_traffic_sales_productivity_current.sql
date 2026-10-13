-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_traffic_sales_productivity_current
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Ideal Lakebase serving projection.
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-28
-- ============================================================
-- GRAIN: one row per store × trading_date. This is the ONLY grain at which traffic and
-- sales can legitimately meet: canonical-core.transaction.sales is product × store ×
-- DAY with no zone and no hour. This view publishes the measures ORDM can support:
-- sales per entry and units per entry. It deliberately has no conversion-rate surface;
-- a canonical transaction or receipt count does not yet exist, so the numerator for
-- transactions / visitors is unavailable.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_traffic_sales_productivity_current AS
WITH traffic AS (
  SELECT
    store_id,
    trading_date,
    footfall_count,
    entry_count,
    exit_count,
    visitor_count_adjusted,
    avg_dwell_seconds,
    -- The numerator and denominator behind avg_dwell_seconds travel WITH it, so a metric
    -- view re-aggregating a week can recompute the mean instead of averaging averages.
    dwell_seconds_total,
    dwell_count,
    peak_occupancy,
    avg_occupancy,
    interval_minutes_total,
    occupancy_interval_minutes_total,
    coverage_interval_minutes_total,
    interval_count,
    counting_unit,
    staff_exclusion_enabled,
    avg_coverage_ratio,
    valid_interval_share,
    complete_interval_share,
    is_zero_observed,
    fiscal_year,
    fiscal_week,
    fiscal_week_id,
    fiscal_week_index,
    day_of_week,
    is_holiday,
    footfall_count_py,
    footfall_growth_py
  FROM ${catalog}.${css_schema}.gold_store_traffic_daily_current
),
store_sales AS (
  SELECT
    s.store_id,
    s.date_key AS trading_date,
    SUM(s.units)         AS units,
    SUM(s.gross_revenue) AS gross_revenue,
    SUM(s.net_revenue)   AS net_revenue,
    SUM(s.discount_amount) AS discount_amount,
    MIN(s.currency_code) AS currency_code,
    -- Promotion pressure, not a promotion join: a store-day is "on promo" if any of its
    -- product rows carried a real promotion. NO_PROMO is the sentinel for non-promoted
    -- sales, so it must be excluded rather than treated as a promotion.
    MAX(CASE WHEN s.promo_id IS NOT NULL AND s.promo_id <> 'NO_PROMO' THEN 1 ELSE 0 END) = 1 AS promo_active_flag,
    COUNT(DISTINCT CASE WHEN s.promo_id IS NOT NULL AND s.promo_id <> 'NO_PROMO' THEN s.promo_id END) AS active_promo_count
  FROM ${catalog}.${transaction_schema}.sales s
  GROUP BY s.store_id, s.date_key
)
SELECT
  t.store_id,
  t.trading_date,
  t.fiscal_year,
  t.fiscal_week,
  t.fiscal_week_id,
  t.fiscal_week_index,
  t.day_of_week,
  t.is_holiday,

  -- Traffic side
  t.footfall_count,
  t.entry_count,
  t.exit_count,
  t.visitor_count_adjusted,
  t.avg_dwell_seconds,
  t.dwell_seconds_total,
  t.dwell_count,
  t.peak_occupancy,
  t.avg_occupancy,
  t.interval_minutes_total,
  t.occupancy_interval_minutes_total,
  t.coverage_interval_minutes_total,
  t.interval_count,
  t.footfall_count_py,
  t.footfall_growth_py,

  -- Sales side
  ss.units,
  ss.gross_revenue,
  ss.net_revenue,
  ss.discount_amount,
  ss.currency_code,
  COALESCE(ss.promo_active_flag, FALSE) AS promo_active_flag,
  COALESCE(ss.active_promo_count, 0)    AS active_promo_count,

  -- Buildable and honest today. The denominator is named in each measure rather than
  -- hidden in a basis/default field. Directional counters populate entries; every
  -- traffic counter can populate footfall.
  ss.net_revenue / NULLIF(t.entry_count, 0) AS sales_per_entry,
  ss.units       / NULLIF(t.entry_count, 0) AS units_per_entry,
  ss.net_revenue / NULLIF(t.footfall_count, 0) AS sales_per_footfall,
  ss.units       / NULLIF(t.footfall_count, 0) AS units_per_footfall,

  -- Counting convention travels with every number derived from a count.
  t.counting_unit,
  t.staff_exclusion_enabled,

  -- Quality, so a low-coverage day is not silently compared against a complete one.
  t.avg_coverage_ratio,
  t.valid_interval_share,
  t.complete_interval_share,
  t.is_zero_observed,

  current_timestamp() AS fresh_as_of_ts
FROM traffic t
LEFT JOIN store_sales ss
  ON t.store_id = ss.store_id
 AND t.trading_date = ss.trading_date;
