-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- Metric View: trend_features
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-06-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================
-- Macro trends and modeled baseline feedback loops.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${bmv_schema}.mv_trend_features
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Macro trends and modeled baseline feedback loops."
source: >
  WITH subcat_daily AS (
    SELECT
      p.subcategory,
      s.store_sk,
      s.date_key,
      SUM(s.units_sold) AS subcategory_daily_units_sold
    FROM ${catalog}.${bmv_schema}.gold_sales_actuals s
    LEFT JOIN ${catalog}.${product_schema}.product p ON s.product_sk = p.product_sk AND p.is_current = TRUE
    GROUP BY p.subcategory, s.store_sk, s.date_key
  )
  SELECT
    s.product_sk,
    s.store_sk,
    s.product_id,
    s.store_id,
    CAST(s.date_key AS DATE) AS date_key,
    sd.subcategory_daily_units_sold,
    CAST(NULL AS DOUBLE) AS subcategory_yoy_growth_pct,
    CAST(NULL AS DOUBLE) AS baseline_units_sold_forecast
  FROM ${catalog}.${bmv_schema}.gold_sales_actuals s
  LEFT JOIN ${catalog}.${product_schema}.product p ON s.product_sk = p.product_sk AND p.is_current = TRUE
  LEFT JOIN subcat_daily sd ON p.subcategory = sd.subcategory AND s.store_sk = sd.store_sk AND s.date_key = sd.date_key

fields:
  - name: product_sk
    expr: product_sk
    comment: "Surrogate key for the product."
  - name: store_sk
    expr: store_sk
    comment: "Surrogate key for the store."
  - name: product_id
    expr: product_id
    comment: "Universal article identifier."
    synonyms: ['article_id']
  - name: store_id
    expr: store_id
    comment: "Universal store identifier."
    synonyms: ['location_id']
  - name: date_key
    expr: date_key
    comment: "Daily grain."
    synonyms: ['snapshot_date']

measures:
  # ============================================================
  # Goal: Elastic Modelling
  # ============================================================
  - name: subcategory_units_sold
    expr: SUM(subcategory_daily_units_sold)
    display_name: "Subcategory Units Sold"
    comment: "Units sold for the subcategory."
    synonyms: ['subcat_volume']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2
$$;
