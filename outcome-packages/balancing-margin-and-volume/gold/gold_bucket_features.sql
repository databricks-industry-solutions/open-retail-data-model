-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- View: gold_bucket_features
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-06-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================
-- Categorical bands and buckets for simplified segmentation.
--
-- Definitions (Segmentation Buckets):
--   margin_health_bucket          = Categorical indicator of gross margin performance (e.g., 'High', 'Healthy', 'Bleeding').
--   competitive_pressure_bucket   = Categorical indicator of competitor price aggression (e.g., 'Severe', 'Moderate', 'Low').
--   discount_depth_bucket         = Categorical depth of the current markdown (e.g., 'Clearance >50%', 'Shallow <10%').
--   demand_bucket_7d              = Categorical volume tier based on the last 7 days of sales.
--   weeks_of_cover_bucket         = Inventory health indicator categorizing stock life (e.g., '<1 Week', 'Overstock').
--   article_age_bucket            = Lifecycle stage of the product (e.g., 'New Arrival', 'Mature', 'End of Life').
--   demand_velocity_bucket        = Categorical speed of sales (e.g., 'Fast Mover', 'Slow Mover').
--   promo_frequency_bucket        = Categorical classification of how often the item is discounted.
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${bmv_schema}.gold_bucket_features AS

WITH comp_prices AS (
  SELECT
    product_sk,
    product_id,
    date_key,
    AVG(competitor_price) AS competitor_regular_price_lc
  FROM ${catalog}.${bmv_schema}.competitor_price
  GROUP BY product_sk, product_id, date_key
),
base_spine AS (
  SELECT
    s.*,
    p.cost_price_lc,
    p.gross_margin_pct,
    p.effective_price_lc,
    (s.discount_value_lc / NULLIF(s.gross_sales_lc, 0)) AS markdown_depth_pct,
    c.competitor_regular_price_lc,
    SUM(s.units_sold) OVER w_7d AS demand_7d,
    SUM(CASE WHEN prm.is_on_promo THEN 1 ELSE 0 END) OVER w_28d AS promo_days_28d
  FROM ${catalog}.${bmv_schema}.gold_sales_actuals s
  LEFT JOIN ${catalog}.${bmv_schema}.gold_price_actuals p 
    ON s.product_sk = p.product_sk AND s.store_sk = p.store_sk AND s.date_key = p.date_key
  LEFT JOIN comp_prices c 
    ON s.product_sk = c.product_sk AND s.date_key = c.date_key
  LEFT JOIN ${catalog}.${bmv_schema}.gold_promotional_features prm
    ON s.product_sk = prm.product_sk AND s.store_sk = prm.store_sk AND s.date_key = prm.date_key
  WINDOW 
    w_7d AS (PARTITION BY s.product_sk, s.store_sk ORDER BY s.date_key ROWS BETWEEN 6 PRECEDING AND CURRENT ROW),
    w_28d AS (PARTITION BY s.product_sk, s.store_sk ORDER BY s.date_key ROWS BETWEEN 27 PRECEDING AND CURRENT ROW)
)
SELECT
  b.product_sk,
  b.store_sk,
  b.product_id,
  b.store_id,
  CAST(b.date_key AS DATE) AS date_key,

  -- ============================================================
  -- Goal: Price Optimization
  -- ============================================================
  CAST(CASE 
    WHEN b.gross_margin_pct > 0.40 THEN 'High'
    WHEN b.gross_margin_pct > 0.15 THEN 'Healthy'
    WHEN b.gross_margin_pct <= 0 THEN 'Bleeding'
    ELSE 'Low'
  END AS STRING) AS margin_health_bucket,
  
  CAST(CASE
    WHEN b.competitor_regular_price_lc < (b.effective_price_lc * 0.90) THEN 'Severe'
    WHEN b.competitor_regular_price_lc < b.effective_price_lc THEN 'Moderate'
    ELSE 'Low'
  END AS STRING) AS competitive_pressure_bucket,
  
  CAST(CASE
    WHEN b.markdown_depth_pct >= 0.50 THEN 'Clearance >50%'
    WHEN b.markdown_depth_pct >= 0.20 THEN 'Deep 20-50%'
    WHEN b.markdown_depth_pct > 0.00 THEN 'Shallow <20%'
    ELSE 'No Discount'
  END AS STRING) AS discount_depth_bucket,

  -- ============================================================
  -- Goal: Elastic Modelling
  -- ============================================================
  CAST(CASE
    WHEN b.demand_7d > 100 THEN 'High Volume'
    WHEN b.demand_7d > 20 THEN 'Medium Volume'
    ELSE 'Low Volume'
  END AS STRING) AS demand_bucket_7d,
  
  -- NOTE: weeks_of_cover is deferred
  CAST(NULL AS STRING) AS weeks_of_cover_bucket,
  
  -- NOTE: article_age_bucket is a placeholder. Derive from real product attributes (e.g. launch date).
  CAST(NULL AS STRING) AS article_age_bucket,
  
  CAST(CASE 
    WHEN b.demand_7d > 100 THEN 'Fast Mover'
    WHEN b.demand_7d > 20 THEN 'Standard'
    ELSE 'Slow Mover'
  END AS STRING) AS demand_velocity_bucket,
  
  CAST(CASE
    WHEN b.promo_days_28d > 14 THEN 'High'
    WHEN b.promo_days_28d > 4 THEN 'Occasional'
    ELSE 'Rare'
  END AS STRING) AS promo_frequency_bucket

FROM base_spine b
CLUSTER BY (product_sk, store_sk, date_key);
