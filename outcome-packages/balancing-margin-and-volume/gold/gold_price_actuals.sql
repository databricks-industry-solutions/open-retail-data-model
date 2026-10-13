-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- View: gold_price_actuals
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-06-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================
-- Daily price points and margin actuals.
--
-- Definitions (Pricing and Margin):
--   base_price_lc                = The regular, undiscounted shelf price in local currency.
--   effective_price_lc           = The actual price paid after promotional discounts.
--   mrp_lc                       = Manufacturer suggested retail price in local currency.
--   gross_margin_pct             = (effective_price_lc - cost_price_lc) / effective_price_lc.
--   cost_price_lc                = The unit cost of goods sold.
--   price_change_direction       = Indicator of whether the price increased, decreased, or remained flat.
--   price_change_magnitude_pct   = The percentage change in price compared to the previous period.
--   days_since_last_price_change = Tracks the decay of consumer shock as they adapt to new prices.
--   price_barrier_proximity      = effective_price_lc % 1.00, measuring proximity to psychological boundaries like .99.
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${bmv_schema}.gold_price_actuals AS
WITH daily_sales AS (
  SELECT
    product_sk,
    store_sk,
    product_id,
    store_id,
    date_key,
    SUM(units) AS units_sold,
    SUM(net_revenue) AS net_sales_lc
  FROM ${catalog}.${transaction_schema}.sales
  WHERE units > 0
  GROUP BY product_sk, store_sk, product_id, store_id, date_key
),
prices AS (
  SELECT
    s.product_sk,
    s.store_sk,
    s.product_id,
    s.store_id,
    s.date_key,
    s.units_sold,
    s.net_sales_lc,
    (s.net_sales_lc / s.units_sold) AS effective_price_lc,
    pl.amount AS base_price_lc,
    pc.amount AS cost_price_lc,
    p.list_price AS mrp_lc
  FROM daily_sales s
  LEFT JOIN ${catalog}.${product_schema}.product p
    ON s.product_sk = p.product_sk
  LEFT JOIN ${catalog}.${product_schema}.product_price pl
    ON s.product_sk = pl.product_sk 
    AND pl.price_type = 'list'
  LEFT JOIN ${catalog}.${product_schema}.product_price pc
    ON s.product_sk = pc.product_sk 
    AND pc.price_type = 'cost'
),
price_changes AS (
  SELECT
    *,
    LAG(effective_price_lc) OVER (PARTITION BY product_sk, store_sk ORDER BY date_key) AS prev_effective_price,
    LAG(date_key) OVER (PARTITION BY product_sk, store_sk ORDER BY date_key) AS prev_date_key
  FROM prices
)
SELECT
  p.product_sk,
  p.store_sk,
  p.product_id,
  p.store_id,
  CAST(p.date_key AS DATE) AS date_key,

  -- ============================================================
  -- Goal: Price Optimization
  -- ============================================================
  CAST(p.units_sold AS DECIMAL(12,3)) AS units_sold,
  CAST(p.net_sales_lc AS DECIMAL(18,2)) AS net_sales_lc,
  CAST(p.effective_price_lc AS DECIMAL(18,2)) AS effective_price_lc,
  CAST(p.base_price_lc AS DECIMAL(18,2)) AS base_price_lc,
  CAST(p.cost_price_lc AS DECIMAL(18,2)) AS cost_price_lc,
  CAST(p.mrp_lc AS DECIMAL(18,2)) AS mrp_lc,
  CAST(CASE WHEN p.base_price_lc > 0 THEN (p.base_price_lc - p.effective_price_lc) / p.base_price_lc ELSE 0 END AS DECIMAL(5,4)) AS realized_discount_pct,
  CAST(CASE WHEN p.mrp_lc > 0 THEN (p.mrp_lc - p.effective_price_lc) / p.mrp_lc ELSE 0.0 END AS DECIMAL(5,4)) AS price_vs_mrp_pct,
  CAST(CASE WHEN p.effective_price_lc > 0 THEN (p.effective_price_lc - p.cost_price_lc) / p.effective_price_lc ELSE 0 END AS DECIMAL(5,4)) AS gross_margin_pct,

  -- ============================================================
  -- Goal: Elastic Modelling
  -- ============================================================
  CAST(CASE WHEN p.effective_price_lc > 0 THEN LN(p.effective_price_lc) ELSE NULL END AS DECIMAL(10,6)) AS log_effective_price,
  CAST(ABS(p.effective_price_lc - p.prev_effective_price) / NULLIF(p.prev_effective_price, 0) > 0.5 AS BOOLEAN) AS is_price_anomaly,
  
  CAST(CASE 
    WHEN p.effective_price_lc > p.prev_effective_price THEN 'INCREASE'
    WHEN p.effective_price_lc < p.prev_effective_price THEN 'DECREASE'
    ELSE 'FLAT' 
  END AS STRING) AS price_change_direction,
  
  CAST(CASE WHEN p.prev_effective_price > 0 THEN (p.effective_price_lc - p.prev_effective_price) / p.prev_effective_price ELSE 0 END AS DECIMAL(5,4)) AS price_change_magnitude_pct,
  CAST(DATEDIFF(p.date_key, p.prev_date_key) AS INT) AS days_since_last_price_change,
  CAST(p.effective_price_lc % 1.00 AS DECIMAL(5,4)) AS price_barrier_proximity

FROM price_changes p
CLUSTER BY (product_sk, store_sk, date_key);
