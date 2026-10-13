-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- View: gold_inventory_productivity
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-22
-- ============================================================
-- Inventory PRODUCTIVITY metrics (review finding A17: turnover, weeks-of-cover,
-- GMROI, sell-through were entirely absent - the package reported tied-up value
-- but never productivity). Aggregated per category x ABC class over a trailing
-- window, all as ratio-of-sums:
--   - inventory_turnover = trailing COGS / average inventory value (annualized)
--   - weeks_of_cover     = average inventory units / avg weekly sell rate
--   - sell_through_rate  = units sold / (units sold + avg inventory units)
--   - gmroi              = annualized gross margin / average inventory cost
--                          (gross margin = realized net_revenue - COGS)
-- Revenue is the sales fact's realized net_revenue (after discount), so promo-driven
-- margin erosion is reflected rather than hidden by a list-price reconstruction.
--
-- Inventory is the AVERAGE over the trailing window, not the period-end snapshot:
-- textbook turnover and GMROI divide by average inventory, and on a trending SKU an
-- ending-inventory denominator misstates both. avg_inventory_units / avg_inventory_value
-- are the mean of the daily inventory_position snapshots over the same trailing window
-- as sales (avg of units_on_hand_eod, valued at the product's current standard cost),
-- so the numerator (trailing flow) and denominator (average stock) cover one window.
-- All rate measures share one annual time base (turnover and GMROI both annualized
-- from the trailing window), so they are directly comparable in a single row. The
-- annualization / weekly factors derive from params.trailing_days, never hardcoded.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${sdi_schema}.gold_inventory_productivity AS
WITH params AS (
  SELECT 90 AS trailing_days
),
latest_date AS (
  SELECT MAX(date_key) AS max_date FROM ${catalog}.${inventory_schema}.inventory_position
),
trailing_sales AS (
  -- Revenue is the REALIZED money from the sales fact (net_revenue, after promotional
  -- discount), NOT units x list_price. Reconstructing revenue from the product master's
  -- list price ignores discounts and systematically overstates gross margin / GMROI for
  -- any SKU that sold on promo. COGS stays cost-based (units x unit_cost) because the
  -- sales fact carries no cost column; unit_cost is the product master's standard cost.
  SELECT
    s.product_id,
    s.store_id,
    SUM(s.units) AS units_sold,
    SUM(s.units * p.unit_cost) AS cogs,
    SUM(s.net_revenue) AS revenue
  FROM ${catalog}.${transaction_schema}.sales s
  JOIN ${catalog}.${product_schema}.product p ON p.product_id = s.product_id AND p.is_current = TRUE
  CROSS JOIN params pr
  CROSS JOIN latest_date ld
  WHERE s.date_key BETWEEN DATE_SUB(ld.max_date, pr.trailing_days - 1) AND ld.max_date
  GROUP BY s.product_id, s.store_id
),
avg_inventory AS (
  -- AVERAGE inventory over the SAME trailing window as sales: the mean of the daily
  -- units_on_hand_eod snapshots per product x store, valued at the product's current
  -- standard cost. This is the textbook turnover/GMROI denominator; an ending-snapshot
  -- value would misstate both on a trending SKU.
  SELECT
    ip.product_id,
    ip.store_id,
    AVG(ip.units_on_hand_eod) AS avg_units_on_hand,
    AVG(ip.units_on_hand_eod) * MAX(p.unit_cost) AS avg_inventory_value
  FROM ${catalog}.${inventory_schema}.inventory_position ip
  JOIN ${catalog}.${product_schema}.product p ON p.product_id = ip.product_id AND p.is_current = TRUE
  CROSS JOIN params pr
  CROSS JOIN latest_date ld
  WHERE ip.date_key BETWEEN DATE_SUB(ld.max_date, pr.trailing_days - 1) AND ld.max_date
  GROUP BY ip.product_id, ip.store_id
),
health AS (
  -- abc_class label per product x store (latest-snapshot segment assignment)
  SELECT ih.product_id, ih.store_id, ih.abc_class
  FROM ${catalog}.${sdi_schema}.gold_inventory_health ih
),
joined AS (
  SELECT
    p.category,
    h.abc_class,
    pr.trailing_days,
    COALESCE(ai.avg_units_on_hand, 0)   AS avg_units_on_hand,
    COALESCE(ai.avg_inventory_value, 0) AS avg_inventory_value,
    COALESCE(ts.units_sold, 0) AS units_sold,
    COALESCE(ts.cogs, 0)       AS cogs,
    COALESCE(ts.revenue, 0)    AS revenue
  FROM health h
  CROSS JOIN params pr
  JOIN ${catalog}.${product_schema}.product p ON p.product_id = h.product_id AND p.is_current = TRUE
  LEFT JOIN avg_inventory ai ON ai.product_id = h.product_id AND ai.store_id = h.store_id
  LEFT JOIN trailing_sales ts ON ts.product_id = h.product_id AND ts.store_id = h.store_id
)
SELECT
  j.category,
  j.abc_class,
  COUNT(*) AS sku_store_count,
  SUM(j.units_sold) AS trailing_units_sold,
  SUM(j.cogs)       AS trailing_cogs,
  SUM(j.avg_inventory_value) AS avg_inventory_value,
  -- annualized turnover = (trailing COGS scaled to a year) / average inventory value.
  -- The annualization factor derives from trailing_days so it can never drift from the
  -- window CTE.
  (SUM(j.cogs) * (365.0 / MAX(j.trailing_days))) / NULLIF(SUM(j.avg_inventory_value), 0) AS inventory_turnover,
  -- weeks of cover = average on-hand units / avg weekly sell rate over the window
  SUM(j.avg_units_on_hand) / NULLIF(SUM(j.units_sold) / (MAX(j.trailing_days) / 7.0), 0) AS weeks_of_cover,
  -- sell-through = sold / (sold + average on hand)
  SUM(j.units_sold) / NULLIF(SUM(j.units_sold) + SUM(j.avg_units_on_hand), 0) AS sell_through_rate,
  -- GMROI = ANNUALIZED gross margin / average inventory cost, on the same time base as
  -- turnover (GMROI is conventionally an annual ratio; leaving the trailing-window
  -- margin un-annualized here would read ~trailing_days/365 of its true value next to an
  -- annualized turnover in the same row).
  ((SUM(j.revenue) - SUM(j.cogs)) * (365.0 / MAX(j.trailing_days))) / NULLIF(SUM(j.avg_inventory_value), 0) AS gmroi
FROM joined j
GROUP BY j.category, j.abc_class;
