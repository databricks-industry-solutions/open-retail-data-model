-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- View: gold_promotional_features
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-06-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================
-- Promotional events and markdown depth features.
--
-- Definitions (Promotions and Markdowns):
--   is_on_promo                    = Boolean indicating if any promotion is currently active.
--   markdown_event_flag            = Boolean indicating if a specific markdown event is active.
--   markdown_depth_pct             = The percentage depth of the markdown relative to base price.
--   is_promo_start_day             = Boolean indicating if a new promotion started exactly on this date.
--   days_into_promo                = The number of days elapsed since the current promotion started.
--   days_to_promo_end              = The number of days remaining until the current promotion expires.
--   is_promo_last_day              = Boolean indicating if this is the final day of the promotion.
--   days_post_promo_end            = The number of days elapsed since the last promotion ended.
--   is_post_promo_decay_window     = Boolean indicating if the product is in the immediate post-promo "hangover" period.
--   promo_frequency_30d            = The number of distinct promotional days in the last 30 days.
--   days_since_last_promo          = The number of days since the product was last on promotion.
--   concurrent_promo_count         = The number of overlapping promotional mechanics currently active.
--   promo_type                     = Promotion mechanic type (e.g., TPR, DISPLAY).
--   funding_type                   = How the promotion is funded.
--   planned_discount_pct           = The planned percentage depth of the markdown.
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${bmv_schema}.gold_promotional_features AS

WITH active_promos AS (
  SELECT
    ps.product_sk,
    ps.store_sk,
    ps.product_id,
    ps.store_id,
    p.promo_sk,
    p.start_date,
    p.end_date
  FROM ${catalog}.${promo_schema}.promotion_scope ps
  JOIN ${catalog}.${marketing_schema}.promotion p ON ps.promo_sk = p.promo_sk
  WHERE p.promo_id != 'NO_PROMO'
),
sales_base AS (
  SELECT
    product_sk,
    store_sk,
    product_id,
    store_id,
    date_key,
    MAX(promo_sk) AS promo_sk,
    MAX_BY(promo_id, promo_sk) AS promo_id
  FROM ${catalog}.${transaction_schema}.sales
  WHERE units > 0
  GROUP BY product_sk, store_sk, product_id, store_id, date_key
),
promo_mapping AS (
  SELECT
    sb.product_sk,
    sb.store_sk,
    sb.product_id,
    sb.store_id,
    sb.date_key,
    sb.promo_sk,
    sb.promo_id,
    COUNT(DISTINCT ap.promo_sk) AS concurrent_promo_count
  FROM sales_base sb
  LEFT JOIN active_promos ap
    ON sb.product_sk = ap.product_sk
    AND sb.store_sk = ap.store_sk
    AND sb.date_key BETWEEN ap.start_date AND ap.end_date
  GROUP BY sb.product_sk, sb.store_sk, sb.product_id, sb.store_id, sb.date_key, sb.promo_sk, sb.promo_id
),
promo_flags AS (
  SELECT
    s.product_sk,
    s.store_sk,
    s.product_id,
    s.store_id,
    s.date_key,
    pm.promo_sk,
    pm.promo_id,
    pm.concurrent_promo_count,
    s.discount_value_lc / NULLIF(s.gross_sales_lc, 0) AS markdown_depth_pct,
    CASE WHEN pm.promo_id != 'NO_PROMO' AND pm.promo_id IS NOT NULL THEN TRUE ELSE FALSE END AS is_on_promo,
    CASE WHEN pm.promo_id != 'NO_PROMO' AND (s.discount_value_lc / NULLIF(s.gross_sales_lc, 0)) > 0.10 THEN TRUE ELSE FALSE END AS markdown_event_flag,
    LAG(pm.promo_id) OVER (PARTITION BY s.product_sk, s.store_sk ORDER BY s.date_key) AS prev_promo_id,
    SUM(CASE WHEN pm.promo_id != 'NO_PROMO' THEN 1 ELSE 0 END) OVER (PARTITION BY s.product_sk, s.store_sk ORDER BY s.date_key ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS promo_frequency_30d
  FROM ${catalog}.${bmv_schema}.gold_sales_actuals s
  LEFT JOIN promo_mapping pm 
    ON s.product_sk = pm.product_sk AND s.store_sk = pm.store_sk AND s.date_key = pm.date_key
),
promo_context AS (
  SELECT
    p.*,
    pr.promo_type,
    pr.funding_type,
    pr.planned_discount_pct,
    pr.start_date,
    pr.end_date,
    MAX(CASE WHEN p.promo_id != 'NO_PROMO' THEN pr.end_date ELSE NULL END) OVER (
      PARTITION BY p.product_sk, p.store_sk 
      ORDER BY p.date_key 
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS last_promo_end_date
  FROM promo_flags p
  LEFT JOIN ${catalog}.${marketing_schema}.promotion pr ON p.promo_sk = pr.promo_sk
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
  CAST(p.promo_sk AS BIGINT) AS promo_sk,
  CAST(p.promo_id AS STRING) AS promo_id,
  CAST(p.is_on_promo AS BOOLEAN) AS is_on_promo,
  CAST(p.markdown_event_flag AS BOOLEAN) AS markdown_event_flag,
  CAST(p.markdown_depth_pct AS DECIMAL(5,4)) AS markdown_depth_pct,
  CAST(p.planned_discount_pct AS DECIMAL(5,2)) AS planned_discount_pct,

  -- ============================================================
  -- Goal: Elastic Modelling
  -- ============================================================
  CAST(p.promo_type AS STRING) AS promo_type,
  CAST(p.funding_type AS STRING) AS funding_type,
  CAST(p.is_on_promo AND NOT COALESCE(p.prev_promo_id != 'NO_PROMO', FALSE) AS BOOLEAN) AS is_promo_start_day,
  CAST(DATEDIFF(p.date_key, p.start_date) AS INT) AS days_into_promo,
  CAST(DATEDIFF(p.end_date, p.date_key) AS INT) AS days_to_promo_end,
  CAST(CASE WHEN p.date_key = p.end_date THEN TRUE ELSE FALSE END AS BOOLEAN) AS is_promo_last_day,
  CAST(DATEDIFF(p.date_key, p.last_promo_end_date) AS INT) AS days_post_promo_end,
  CAST(CASE WHEN DATEDIFF(p.date_key, p.last_promo_end_date) BETWEEN 1 AND 14 THEN TRUE ELSE FALSE END AS BOOLEAN) AS is_post_promo_decay_window,
  CAST(p.promo_frequency_30d AS INT) AS promo_frequency_30d,
  CAST(CASE WHEN p.is_on_promo THEN 0 ELSE DATEDIFF(p.date_key, p.last_promo_end_date) END AS INT) AS days_since_last_promo,
  CAST(COALESCE(p.concurrent_promo_count, 0) AS INT) AS concurrent_promo_count

FROM promo_context p
CLUSTER BY (product_sk, store_sk, date_key);
