-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- View: gold_sales_actuals
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-06-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================
-- Grain-level sales and volume actuals.
--
-- Definitions (Sales and Demand):
--   units_sold                 = Raw units sold at the till.
--   gross_sales_lc             = Total sales value before discounts.
--   net_sales_lc               = Total sales value after discounts.
--   returns_units              = Units returned by customers.
--   net_units_sold             = units_sold - returns_units.
--   baseline_units_sold        = De-seasonalized and de-promoted normal demand.
--   incremental_lift_units     = Extra units sold attributable specifically to a promotion.
--   stockout_pct_day           = Percentage of the day the product was out of stock on shelf.
--   units_received_today       = Units received today for sell-through calculation.
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${bmv_schema}.gold_sales_actuals AS
WITH daily_sales AS (
  SELECT
    product_sk,
    store_sk,
    product_id,
    store_id,
    date_key,
    SUM(CASE WHEN units > 0 THEN units ELSE 0 END) AS units_sold,
    SUM(CASE WHEN units < 0 THEN ABS(units) ELSE 0 END) AS returns_units,
    SUM(units) AS net_units_sold,
    SUM(gross_revenue) AS gross_sales_lc,
    SUM(net_revenue) AS net_sales_lc,
    SUM(discount_amount) AS discount_value_lc
  FROM ${catalog}.${transaction_schema}.sales
  GROUP BY product_sk, store_sk, product_id, store_id, date_key
),
inventory AS (
  SELECT
    product_sk,
    store_sk,
    date_key,
    MAX(stockout_pct_day) AS stockout_pct_day,
    SUM(units_received_today) AS units_received_today
  FROM ${catalog}.${inventory_schema}.inventory_position
  GROUP BY product_sk, store_sk, date_key
)
SELECT
  s.product_sk,
  s.store_sk,
  s.product_id,
  s.store_id,
  CAST(s.date_key AS DATE) AS date_key,

  -- ============================================================
  -- Goal: Price Optimization
  -- ============================================================
  CAST(s.units_sold AS DECIMAL(12,3)) AS units_sold,
  CAST(s.gross_sales_lc AS DECIMAL(18,2)) AS gross_sales_lc,
  CAST(s.net_sales_lc AS DECIMAL(18,2)) AS net_sales_lc,
  CAST(s.discount_value_lc AS DECIMAL(18,2)) AS discount_value_lc,
  CAST(s.returns_units AS DECIMAL(12,3)) AS returns_units,
  CAST(s.net_units_sold AS DECIMAL(12,3)) AS net_units_sold,

  -- ============================================================
  -- Goal: Elastic Modelling
  -- ============================================================
  CAST(CASE WHEN s.units_sold > 0 THEN LN(s.units_sold) ELSE NULL END AS DECIMAL(10,6)) AS log_units_sold,
  CAST(CASE WHEN s.net_sales_lc > 0 THEN LN(s.net_sales_lc) ELSE NULL END AS DECIMAL(10,6)) AS log_net_sales_lc,
  CAST(NULL AS DECIMAL(12,3)) AS baseline_units_sold,
  CAST(NULL AS DECIMAL(12,3)) AS incremental_lift_units,
  CAST(i.stockout_pct_day AS DECIMAL(5,4)) AS stockout_pct_day,

  -- ============================================================
  -- Goal: Assortment Optimization
  -- ============================================================
  CAST(i.units_received_today AS DECIMAL(12,3)) AS units_received_today
  
FROM daily_sales s
LEFT JOIN inventory i
  ON s.product_sk = i.product_sk AND s.store_sk = i.store_sk AND s.date_key = i.date_key
CLUSTER BY (product_sk, store_sk, date_key);
