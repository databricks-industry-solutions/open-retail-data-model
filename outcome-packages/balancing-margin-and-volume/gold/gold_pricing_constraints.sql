-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- View: gold_pricing_constraints
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-06-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================
-- Business constraints limiting the price optimization solver.
--
-- Definitions (Constraints):
--   mrp_lc               = Maximum Retail Price ceiling.
--   min_margin_pct       = Minimum acceptable profit margin percentage.
--   max_discount_pct     = Maximum allowed discount depth percentage.
--   min_price_lc         = Derived minimum price bounded by cost and min margin.
--   max_price_lc         = Derived maximum price bounded by MRP.
--   max_competitor_index = Maximum allowable price index against the primary competitor.
--   price_rounding_rule_code = Rule applied to round recommended prices.
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${bmv_schema}.gold_pricing_constraints AS

WITH joined_base AS (
  SELECT
    s.product_sk,
    s.store_sk,
    s.product_id,
    s.store_id,
    s.date_key,
    p.list_price AS mrp_lc, /* NOTE: Using list_price as a proxy for MRP until a dedicated MRP source is available */
    pr.cost_price_lc
  FROM ${catalog}.${bmv_schema}.gold_sales_actuals s
  LEFT JOIN ${catalog}.${product_schema}.product p 
    ON s.product_sk = p.product_sk
  LEFT JOIN ${catalog}.${bmv_schema}.gold_price_actuals pr 
    ON s.product_sk = pr.product_sk AND s.store_sk = pr.store_sk AND s.date_key = pr.date_key
)
SELECT
  j.product_sk,
  j.store_sk,
  j.product_id,
  j.store_id,
  CAST(j.date_key AS DATE) AS date_key,

  -- ============================================================
  -- Goal: Price Optimization
  -- ============================================================
  -- Hard Ceilings
  CAST(j.mrp_lc AS DECIMAL(18,2)) AS mrp_lc,

  -- Margin Floors & Discount Ceilings
  CAST(0.10 AS DECIMAL(5,4)) AS min_margin_pct, /* NOTE: Source this business guardrail from category-level config when available */
  CAST(0.50 AS DECIMAL(5,4)) AS max_discount_pct, /* NOTE: Source this business guardrail from category-level config when available */
  
  -- Price Bounds (Derived)
  -- max_price = Static guardrail (stock-awareness deferred with weeks_of_cover).
  CAST(COALESCE(j.mrp_lc, j.cost_price_lc * 5.00) AS DECIMAL(18,2)) AS max_price_lc, /* NOTE: Source 5.00 multiplier from config when available */
  -- min_price = cost / (1 - min_margin) to guarantee at least 10% margin. 
  -- We clamp it to max_price_lc using LEAST() so it never mathematically exceeds the hard ceiling.
  CAST(LEAST(j.cost_price_lc / (1.0 - 0.10), COALESCE(j.mrp_lc, j.cost_price_lc * 5.00)) AS DECIMAL(18,2)) AS min_price_lc,

  -- Competitive Bounds
  CAST(1.05 AS DECIMAL(5,4)) AS max_competitor_index, /* NOTE: Source this business guardrail from category-level config when available */

  -- Formatting Rules
  CAST('ROUND_TO_99' AS STRING) AS price_rounding_rule_code

FROM joined_base j
CLUSTER BY (product_sk, store_sk, date_key);
