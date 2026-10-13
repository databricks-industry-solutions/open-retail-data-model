-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- View: gold_competitor_analysis
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-06-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================
-- Competitor price alignment and tracking.
--
-- Definitions (Assortment Optimization):
-- * competitor_assortment_overlap_pct: Percentage of assortment shared with competitor
--
-- Definitions (Competitor Intelligence):
--   competitor_regular_price_lc = The tracked shelf price of the matched competitor (specifically, the cheapest tracked competitor for that date).
--   price_gap_lc               = The absolute difference: effective_price_lc - competitor_regular_price_lc.
--   price_index_vs_comp        = (effective_price_lc / competitor_regular_price_lc) * 100.
--   is_comp_price_below_own    = True if the competitor is pricing lower than our effective price.
--   is_kvi                     = True if the item is a Key Value Item (high price awareness traffic driver).
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${bmv_schema}.gold_competitor_analysis AS
WITH comp_prices_base AS (
  SELECT
    product_sk,
    product_id,
    date_key,
    competitor_sk,
    competitor_id,
    competitor_price AS competitor_regular_price_lc,
    is_on_comp_promo AS is_comp_on_promo,
    'STABLE' AS price_gap_trend_flag,
    ROW_NUMBER() OVER (PARTITION BY product_sk, date_key ORDER BY competitor_price ASC) AS rn
  FROM ${catalog}.${bmv_schema}.competitor_price
),
comp_prices AS (
  -- Intentional filter to compare against only the cheapest tracked competitor in the market.
  SELECT * FROM comp_prices_base WHERE rn = 1
)
SELECT
  s.product_sk,
  s.store_sk,
  s.product_id,
  s.store_id,
  CAST(s.date_key AS DATE) AS date_key,
  CAST(c.competitor_sk AS BIGINT) AS competitor_sk,
  CAST(c.competitor_id AS STRING) AS competitor_id,

  -- ============================================================
  -- Goal: Price Optimization
  -- ============================================================
  CAST(s.units_sold AS DECIMAL(12,3)) AS units_sold,
  CAST(p.effective_price_lc AS DECIMAL(18,2)) AS effective_price_lc,
  CAST(c.competitor_regular_price_lc AS DECIMAL(18,2)) AS competitor_regular_price_lc,
  CAST(c.is_comp_on_promo AS BOOLEAN) AS is_comp_on_promo,
  CAST(p.effective_price_lc - c.competitor_regular_price_lc AS DECIMAL(18,2)) AS price_gap_lc,
  CAST(c.competitor_regular_price_lc < p.effective_price_lc AS BOOLEAN) AS is_comp_price_below_own,

  -- ============================================================
  -- Goal: Elastic Modelling
  -- ============================================================
  CAST((p.effective_price_lc / NULLIF(c.competitor_regular_price_lc, 0)) * 100 AS DECIMAL(8,4)) AS price_index_vs_comp,
  CAST(c.price_gap_trend_flag AS STRING) AS price_gap_trend_flag,
  
  -- KVI Placeholders
  CAST(FALSE AS BOOLEAN) AS is_kvi,
  CAST(0 AS DECIMAL(18,2)) AS kvi_own_revenue_lc,
  CAST(0 AS DECIMAL(18,2)) AS kvi_comp_revenue_lc,

  -- ============================================================
  -- Goal: Assortment Optimization
  -- ============================================================
  CAST(NULL AS DECIMAL(8,4)) AS competitor_assortment_overlap_pct

-- NOTE: The competitor_price.sql data is sparse. To avoid NULLs on non-scraping days, 
-- use a Point-in-Time (PIT) forward-fill join (AS OF join) on the competitor_price table.
FROM ${catalog}.${bmv_schema}.gold_sales_actuals s
LEFT JOIN ${catalog}.${bmv_schema}.gold_price_actuals p
  ON s.product_sk = p.product_sk AND s.store_sk = p.store_sk AND s.date_key = p.date_key
LEFT JOIN comp_prices c ON s.product_sk = c.product_sk AND s.date_key = c.date_key
CLUSTER BY (product_sk, store_sk, date_key);
