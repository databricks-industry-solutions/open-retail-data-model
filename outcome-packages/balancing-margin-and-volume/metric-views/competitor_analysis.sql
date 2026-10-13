-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- Metric View: competitor_analysis
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-06-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================
-- Competitive intelligence metrics and price gaps.
--
-- Definitions (Assortment Optimization):
-- * competitor_assortment_overlap_pct: Percentage of assortment shared with competitor
-- * rolling_sales_velocity_14d: Rolling 14-day sales velocity
-- * rolling_stockout_rate_14d: Rolling 14-day stockout rate
-- * lagged_baseline_velocity: Base volume sold absent of promotions
-- * lagged_margin_contribution: Margin contribution from previous periods
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${bmv_schema}.mv_competitor_analysis
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Competitive intelligence metrics and price gaps."
source: ${catalog}.${bmv_schema}.gold_competitor_analysis

fields:
  - name: product_sk
    expr: product_sk
    comment: "Surrogate key for the product."
  - name: store_sk
    expr: store_sk
    comment: "Surrogate key for the store."
  - name: product_id
    expr: product_id
    comment: "Universal article identifier"
    synonyms: ['article_id', 'item_code', 'sku_number']
  - name: store_id
    expr: store_id
    comment: "Universal store identifier"
    synonyms: ['store_id', 'location_code', 'branch_id']
  - name: date_key
    expr: date_key
    comment: "Daily grain"
    synonyms: ['snapshot_date', 'calendar_day']
  - name: competitor_id
    expr: competitor_id
    comment: "Competitor identifier"
    synonyms: ['rival_id', 'comp_retailer_code']
  - name: is_comp_on_promo
    expr: is_comp_on_promo
    comment: "Boolean indicating if the competitor is currently running a promotion"
    synonyms: ['rival_discount_flag']
  - name: is_comp_price_below_own
    expr: is_comp_price_below_own
    comment: "True if the competitor is pricing lower than our effective price"
    synonyms: ['undercut_flag', 'cheaper_competitor_flag']
  - name: price_gap_trend_flag
    expr: price_gap_trend_flag
    comment: "Indicator of price gap directionality"
    synonyms: ['gap_movement_indicator']

measures:
  # ============================================================
  # Goal: Price Optimization
  # ============================================================
  - name: avg_competitor_price
    expr: avg(competitor_regular_price_lc)
    display_name: "Average Competitor Price"
    comment: "Average regular price of the competitor"
    synonyms: ['rival_current_asp', 'comp_selling_price']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: avg_price_gap
    expr: avg(price_gap_lc)
    display_name: "Average Price Gap"
    comment: "Average absolute price gap versus competitor"
    synonyms: ['competitor_price_difference', 'rival_delta_value']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: total_dollar_price_gap
    expr: sum((effective_price_lc - competitor_regular_price_lc) * units_sold)
    display_name: "Total Dollar Price Gap"
    comment: "Total dollar price gap weighted by volume"
    synonyms: ['aggregate_competitor_variance', 'total_rival_dollar_difference']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  # ============================================================
  # Goal: Elastic Modelling
  # ============================================================
  - name: volume_weighted_cpi
    expr: (sum(effective_price_lc * units_sold) / nullif(sum(competitor_regular_price_lc * units_sold), 0)) * 100
    display_name: "Volume Weighted CPI"
    comment: "Volume-weighted Competitor Price Index (CPI)"
    synonyms: ['sales_adjusted_comp_index', 'demand_weighted_rival_ratio']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2



  # ============================================================
  # Goal: Assortment Optimization
  # ============================================================
  - name: avg_assortment_overlap_pct
    expr: avg(competitor_assortment_overlap_pct)
    display_name: "Average Assortment Overlap"
    comment: "Average assortment overlap percentage"
    synonyms: ['competitor_overlap']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: total_exclusive_skus
    expr: count(product_id)
    display_name: "Total Exclusive SKUs"
    comment: "Number of exclusive SKUs"
    synonyms: ['exclusive_items']
    format:
      type: number
$$;
