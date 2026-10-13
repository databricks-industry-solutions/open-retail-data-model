-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- Metric View: aggregation_features
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-06-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================
-- Cross-sectional aggregations (store, category, brand level).
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${bmv_schema}.mv_aggregation_features
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Cross-sectional aggregations (store, category, brand level)."
source: >
  SELECT
    s.product_sk,
    s.store_sk,
    s.product_id,
    s.store_id,
    CAST(s.date_key AS DATE) AS date_key,
    p.category,
    p.subcategory,
    p.brand,
    s.units_sold,
    s.net_sales_lc,
    s.gross_sales_lc AS gross_revenue,
    s.discount_value_lc AS discount_amount,
    prm.is_on_promo
  FROM ${catalog}.${bmv_schema}.gold_sales_actuals s
  LEFT JOIN ${catalog}.${product_schema}.product p 
    ON s.product_sk = p.product_sk AND p.is_current = TRUE
  LEFT JOIN ${catalog}.${bmv_schema}.gold_promotional_features prm 
    ON s.product_sk = prm.product_sk AND s.store_sk = prm.store_sk AND s.date_key = prm.date_key
  WHERE s.units_sold > 0

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
    synonyms: ['store_id']

  - name: date_key
    expr: date_key
    comment: "Daily grain."
    synonyms: ['snapshot_date']

  - name: category
    expr: category
    comment: "Top-level merchandising category."
    synonyms: ['product_category']

  - name: subcategory
    expr: subcategory
    comment: "Merchandising subcategory."
    synonyms: ['product_subcategory']

  - name: brand
    expr: brand
    comment: "Product brand."
    synonyms: ['brand_name']

measures:
  # ============================================================
  # Goal: Price Optimization
  # ============================================================
  - name: store_avg_discount_pct
    expr: SUM(discount_amount) / NULLIF(SUM(gross_revenue), 0)
    display_name: "Store Avg Discount %"
    comment: "Average discount percentage across the store."
    synonyms: ['store_markdown_depth']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  # ============================================================
  # Goal: Elastic Modelling
  # ============================================================
  - name: store_total_units_sold
    expr: SUM(units_sold)
    display_name: "Store Total Units Sold"
    comment: "Total units sold across all products in the store."
    synonyms: ['store_volume']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: store_total_revenue
    expr: SUM(net_sales_lc)
    display_name: "Store Total Revenue"
    comment: "Total revenue across all products in the store."
    synonyms: ['store_sales']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: category_units_sold
    expr: SUM(units_sold)
    display_name: "Category Units Sold"
    comment: "Total volume of the category."
    synonyms: ['category_volume']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: category_revenue
    expr: SUM(net_sales_lc)
    display_name: "Category Revenue"
    comment: "Total revenue of the category."
    synonyms: ['category_sales']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: category_avg_effective_price
    expr: SUM(net_sales_lc) / NULLIF(SUM(units_sold), 0)
    display_name: "Category Avg Effective Price"
    comment: "The volume-weighted average price of the category."
    synonyms: ['category_asp']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: subcategory_units_sold
    expr: SUM(units_sold)
    display_name: "Subcategory Units Sold"
    comment: "Total volume of the subcategory."
    synonyms: ['subcategory_volume']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: subcategory_revenue
    expr: SUM(net_sales_lc)
    display_name: "Subcategory Revenue"
    comment: "Total revenue of the subcategory."
    synonyms: ['subcategory_sales']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: subcategory_avg_effective_price
    expr: SUM(net_sales_lc) / NULLIF(SUM(units_sold), 0)
    display_name: "Subcategory Avg Effective Price"
    comment: "The volume-weighted average price of the subcategory."
    synonyms: ['subcategory_asp']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: brand_units_sold
    expr: SUM(units_sold)
    display_name: "Brand Units Sold"
    comment: "Total volume sold for the brand."
    synonyms: ['brand_volume']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: brand_revenue
    expr: SUM(net_sales_lc)
    display_name: "Brand Revenue"
    comment: "Total revenue of the brand."
    synonyms: ['brand_sales']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: brand_avg_effective_price
    expr: SUM(net_sales_lc) / NULLIF(SUM(units_sold), 0)
    display_name: "Brand Avg Effective Price"
    comment: "The volume-weighted average price of the brand."
    synonyms: ['brand_asp']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2
      
  - name: brand_promo_count_active
    expr: SUM(CASE WHEN is_on_promo THEN 1 ELSE 0 END)
    display_name: "Brand Promo Count Active"
    comment: "Number of active promotions currently running for the brand."
    synonyms: ['brand_active_promotions']
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
$$;
