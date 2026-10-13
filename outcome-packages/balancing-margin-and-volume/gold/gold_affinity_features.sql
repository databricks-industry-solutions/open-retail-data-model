-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- View: gold_affinity_features
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-06-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================
-- Cross-elasticity and affinity scores for complementary / substitute items.
--
-- Definitions (Assortment Optimization):
-- * substitute_demand_transfer_pct: Share of this SKU's demand assumed to move to its mapped substitutes if
--     it is removed or out of stock. HEURISTIC: reads each substitute's affinity_coefficient as the share
--     of shoppers who would accept that substitute and combines them as independent acceptances,
--     1 - PRODUCT(1 - affinity). 0 when no substitute is mapped. An assumption over product_relationship,
--     not estimated from observed substitution; adopters can replace it with a fitted demand-transfer model.
-- ============================================================
--
-- Definitions (Affinity and Cannibalization):
--   substitute_price_ratio           = Own price divided by average substitute price.
--   complement_price_ratio           = Own price divided by average complement price.
--   substitute_markdown_depth_pct    = Average markdown depth of substitute products.
--   complement_markdown_depth_pct    = Average markdown depth of complement products.
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${bmv_schema}.gold_affinity_features AS
WITH relationships AS (
  SELECT
    product_sk,
    product_id,
    related_product_sk,
    related_product_id,
    relationship_type,
    affinity_coefficient
  FROM ${catalog}.${bmv_schema}.product_relationship
),
related_sales AS (
  SELECT
    r.product_sk,
    r.product_id,
    ds.store_sk,
    ds.store_id,
    ds.date_key,
    r.relationship_type,
    r.affinity_coefficient,
    (ds.net_sales_lc / NULLIF(ds.units_sold, 0)) AS related_price,
    (ds.discount_value_lc / NULLIF(ds.gross_sales_lc, 0)) AS related_markdown
  FROM relationships r
  JOIN ${catalog}.${bmv_schema}.gold_sales_actuals ds 
    ON r.related_product_sk = ds.product_sk
),
-- per-SKU demand transfer to substitutes (static per product; see header). Affinity is capped just below
-- 1 so LN stays finite; a 1.0 affinity still yields a transfer of ~1.
substitute_transfer AS (
  SELECT
    product_id,
    1 - EXP(SUM(LN(1 - LEAST(CAST(affinity_coefficient AS DOUBLE), 0.9999)))) AS transfer_pct
  FROM relationships
  WHERE relationship_type = 'substitute' AND affinity_coefficient > 0
  GROUP BY product_id                                    -- durable key: pools a product's SCD2 versions
),
aggregated_related AS (
  SELECT
    product_sk,
    store_sk,
    product_id,
    store_id,
    date_key,
    SUM(CASE WHEN relationship_type = 'substitute' THEN related_price * affinity_coefficient END) / 
      NULLIF(SUM(CASE WHEN relationship_type = 'substitute' THEN affinity_coefficient END), 0) AS avg_substitute_price,
    SUM(CASE WHEN relationship_type = 'complement' THEN related_price * affinity_coefficient END) / 
      NULLIF(SUM(CASE WHEN relationship_type = 'complement' THEN affinity_coefficient END), 0) AS avg_complement_price,
    SUM(CASE WHEN relationship_type = 'substitute' THEN related_markdown * affinity_coefficient END) / 
      NULLIF(SUM(CASE WHEN relationship_type = 'substitute' THEN affinity_coefficient END), 0) AS avg_substitute_markdown,
    SUM(CASE WHEN relationship_type = 'complement' THEN related_markdown * affinity_coefficient END) / 
      NULLIF(SUM(CASE WHEN relationship_type = 'complement' THEN affinity_coefficient END), 0) AS avg_complement_markdown
  FROM related_sales
  GROUP BY product_sk, store_sk, product_id, store_id, date_key
)
SELECT
  ds.product_sk,
  ds.store_sk,
  ds.product_id,
  ds.store_id,
  CAST(ds.date_key AS DATE) AS date_key,
  
  -- ============================================================
  -- Goal: Elastic Modelling
  -- ============================================================
  CAST((ds.net_sales_lc / NULLIF(ds.units_sold, 0)) / NULLIF(ar.avg_substitute_price, 0) AS DECIMAL(8,4)) AS substitute_price_ratio,
  CAST((ds.net_sales_lc / NULLIF(ds.units_sold, 0)) / NULLIF(ar.avg_complement_price, 0) AS DECIMAL(8,4)) AS complement_price_ratio,
  CAST(ar.avg_substitute_markdown AS DECIMAL(8,4)) AS substitute_markdown_depth_pct,
  CAST(ar.avg_complement_markdown AS DECIMAL(8,4)) AS complement_markdown_depth_pct,

  -- ============================================================
  -- Goal: Assortment Optimization
  -- ============================================================
  CAST(COALESCE(st.transfer_pct, 0) AS DECIMAL(8,4)) AS substitute_demand_transfer_pct

FROM ${catalog}.${bmv_schema}.gold_sales_actuals ds
LEFT JOIN aggregated_related ar 
  ON ds.product_sk = ar.product_sk 
 AND ds.store_sk = ar.store_sk 
 AND ds.date_key = ar.date_key
LEFT JOIN substitute_transfer st
  ON ds.product_id = st.product_id
CLUSTER BY (product_sk, store_sk, date_key);
