-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- View: gold_service_level_attainment
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-23
-- ============================================================
-- ACHIEVED service level vs TARGET, per store x category x fiscal week. Review
-- finding A2 noted the package modeled only service-level TARGETS and never
-- measured attainment, despite inventory_position.is_stockout / stockout_pct_day
-- being available in core. This computes two attained measures with distinct,
-- correctly-labelled definitions (they are NOT interchangeable):
--   - attained_in_stock_rate = 1 - (stockout SKU-days / total SKU-days)
--       A TIME-based measure: the share of SKU-days fully in stock. Answers
--       "how often were we in stock", not "how much demand did we meet".
--   - attained_fill_rate     = units_sold / (units_sold + lost_units)
--       A true DEMAND-weighted (Type II / beta) fill rate: units met divided by
--       units demanded, where unmet demand is the censoring-aware lost_units from
--       lost_sales_estimate (NOT the stockout-constrained actual). This is the
--       correct like-for-like counterpart to a fill_rate target — an earlier draft
--       used 1 - SUM(stockout_pct_day)/SKU-days, which is a second TIME-based
--       availability measure with no demand in the denominator, so differencing it
--       against a Type-II target was the very A2 conflation this view exists to avoid.
-- Ratios are computed as ratio-of-sums (not a mean of per-row rates).
--
-- The gap is compared against the target's own service_measure_type:
--   - fill_rate target        -> attained_fill_rate       (exact, Type II vs Type II)
--   - in_stock_rate target    -> attained_in_stock_rate   (exact, time-share vs time-share)
--   - cycle_service_level     -> attained_in_stock_rate   (APPROXIMATION, see below)
-- service_level_gap_to_target selects the attained measure and gap_measure_type records
-- which one was used.
--
-- APPROXIMATION for cycle_service_level targets: CSL (Type I / alpha) is a per-cycle
-- non-stockout PROBABILITY, not a time-share, so there is no exact same-unit attained
-- counterpart in this view — the time-based attained_in_stock_rate is used as the closest
-- available proxy. This is the same CSL-vs-availability approximation that
-- safety_stock_sizing.sql documents for the sizing path (in_stock_rate approximated by the
-- CSL z). gap_measure_type = 'in_stock_rate' honestly records the proxy, so a consumer
-- differencing a CSL target reads the gap against a time-share measure, not a per-cycle one.
-- An exact per-cycle attainment measure (stockout episodes / replenishment cycles) is a
-- documented follow-up.
--
-- Target scope (v0.1): the DEFAULT segment target (abc_class IS NULL AND xyz_class
-- IS NULL) is applied to every store x category row. This view's grain is
-- store x category, which does NOT carry the ABC/XYZ segmentation that
-- service_level_target keys on, so the seeded segment-specific targets (e.g. A/X,
-- C/Z) are modeled but not yet joined here. Joining segment targets requires
-- carrying abc_class/xyz_class onto this grain (available via gold_inventory_health)
-- and is a documented follow-up, not a silent omission.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${sdi_schema}.gold_service_level_attainment AS
WITH pos AS (
  SELECT
    ip.store_id,
    p.category,
    fc.fiscal_week_id,
    COUNT(*) AS total_sku_days,
    SUM(CASE WHEN ip.is_stockout = TRUE THEN 1 ELSE 0 END) AS stockout_sku_days
  FROM ${catalog}.${inventory_schema}.inventory_position ip
  JOIN ${catalog}.${product_schema}.product p ON p.product_id = ip.product_id AND p.is_current = TRUE
  LEFT JOIN ${catalog}.${calendar_schema}.fiscal_calendar fc ON fc.date_key = ip.date_key
  GROUP BY ip.store_id, p.category, fc.fiscal_week_id
),
sales_agg AS (
  -- units MET (sold) at the store x category x week grain
  SELECT
    s.store_id,
    p.category,
    fc.fiscal_week_id,
    SUM(s.units) AS units_sold
  FROM ${catalog}.${transaction_schema}.sales s
  JOIN ${catalog}.${product_schema}.product p ON p.product_id = s.product_id AND p.is_current = TRUE
  LEFT JOIN ${catalog}.${calendar_schema}.fiscal_calendar fc ON fc.date_key = s.date_key
  GROUP BY s.store_id, p.category, fc.fiscal_week_id
),
lost_agg AS (
  -- units UNMET (censoring-aware lost demand) at the same grain, via the OOS episode
  SELECT
    oe.store_id,
    p.category,
    fc.fiscal_week_id,
    SUM(lse.lost_units) AS lost_units
  FROM ${catalog}.${sdi_schema}.lost_sales_estimate lse
  JOIN ${catalog}.${sdi_schema}.oos_event oe ON oe.oos_event_sk = lse.oos_event_sk
  JOIN ${catalog}.${product_schema}.product p ON p.product_id = oe.product_id AND p.is_current = TRUE
  LEFT JOIN ${catalog}.${calendar_schema}.fiscal_calendar fc ON fc.date_key = lse.estimate_date_key
  GROUP BY oe.store_id, p.category, fc.fiscal_week_id
),
default_target AS (
  SELECT target_service_level_pct, target_fill_rate_pct, service_measure_type
  FROM ${catalog}.${sdi_schema}.service_level_target
  WHERE is_current = TRUE AND abc_class IS NULL AND xyz_class IS NULL
  LIMIT 1
)
SELECT
  pos.store_id,
  pos.category,
  pos.fiscal_week_id,
  pos.total_sku_days,
  pos.stockout_sku_days,
  COALESCE(sa.units_sold, 0) AS units_sold,
  COALESCE(la.lost_units, 0) AS lost_units,
  -- time-based: share of SKU-days fully in stock
  1 - (CAST(pos.stockout_sku_days AS DOUBLE) / NULLIF(pos.total_sku_days, 0)) AS attained_in_stock_rate,
  -- demand-weighted (Type II): units met / units demanded (met + censoring-aware lost)
  CAST(COALESCE(sa.units_sold, 0) AS DOUBLE)
    / NULLIF(COALESCE(sa.units_sold, 0) + COALESCE(la.lost_units, 0), 0) AS attained_fill_rate,
  dt.service_measure_type AS target_measure_type,
  COALESCE(dt.target_service_level_pct, dt.target_fill_rate_pct) AS target_service_level_pct,
  -- which attained measure the gap is computed against (matches the target type)
  CASE WHEN dt.service_measure_type = 'fill_rate' THEN 'fill_rate' ELSE 'in_stock_rate' END
    AS gap_measure_type,
  -- TRUE when the gap is the CSL-vs-time-share APPROXIMATION: a cycle_service_level target
  -- (per-cycle probability) differenced against the time-based attained_in_stock_rate, for
  -- want of an exact per-cycle attained measure. FALSE when the units match exactly
  -- (fill_rate vs attained_fill_rate, or in_stock_rate vs attained_in_stock_rate).
  (dt.service_measure_type = 'cycle_service_level') AS gap_is_approximate,
  -- like-for-like gap: fill_rate target vs attained fill rate, otherwise vs in-stock rate
  -- (exact for in_stock_rate; approximate for cycle_service_level — see gap_is_approximate)
  CASE
    WHEN dt.service_measure_type = 'fill_rate'
      THEN (CAST(COALESCE(sa.units_sold, 0) AS DOUBLE)
             / NULLIF(COALESCE(sa.units_sold, 0) + COALESCE(la.lost_units, 0), 0))
           - COALESCE(dt.target_service_level_pct, dt.target_fill_rate_pct)
    ELSE (1 - (CAST(pos.stockout_sku_days AS DOUBLE) / NULLIF(pos.total_sku_days, 0)))
         - COALESCE(dt.target_service_level_pct, dt.target_fill_rate_pct)
  END AS service_level_gap_to_target
FROM pos
LEFT JOIN sales_agg sa
  ON sa.store_id = pos.store_id AND sa.category = pos.category AND sa.fiscal_week_id = pos.fiscal_week_id
LEFT JOIN lost_agg la
  ON la.store_id = pos.store_id AND la.category = pos.category AND la.fiscal_week_id = pos.fiscal_week_id
-- LEFT JOIN (not CROSS JOIN): if no default-segment target is seeded, attainment rows
-- still return with a NULL target and NULL gap, rather than the whole view going empty
-- (which would be indistinguishable from "no attainment data").
LEFT JOIN default_target dt ON TRUE;
