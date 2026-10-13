-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- Metric View: rolling_features
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-06-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================
-- Rolling window averages and stockout rates for ML training.
--
-- Definitions (Assortment Optimization):
-- * competitor_assortment_overlap_pct: Percentage of assortment shared with competitor
-- * rolling_sales_velocity_14d: Rolling 14-day sales velocity
-- * rolling_stockout_rate_14d: Rolling 14-day stockout rate
-- * lagged_baseline_velocity: Base volume sold absent of promotions
-- * lagged_margin_contribution: Margin contribution from previous periods
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${bmv_schema}.mv_rolling_features
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: Rolling window averages and stockout rates.
source: |
  SELECT
    s.product_sk,
    s.store_sk,
    s.product_id,
    s.store_id,
    CAST(s.date_key AS DATE) AS date_key,
    s.units_sold,
    s.net_sales_lc,
    p.effective_price_lc,
    p.gross_margin_pct,
    i.stockout_pct_day,
    c.competitor_regular_price_lc,
    prm.is_on_promo
  FROM ${catalog}.${bmv_schema}.gold_sales_actuals s
  LEFT JOIN ${catalog}.${bmv_schema}.gold_price_actuals p
    ON s.product_sk = p.product_sk AND s.store_sk = p.store_sk AND s.date_key = p.date_key
  LEFT JOIN ${catalog}.${inventory_schema}.inventory_position i
    ON s.product_id = i.product_id AND s.store_id = i.store_id AND s.date_key = i.date_key
  LEFT JOIN ${catalog}.${bmv_schema}.gold_competitor_analysis c
    ON s.product_sk = c.product_sk AND s.store_sk = c.store_sk AND s.date_key = c.date_key
  LEFT JOIN ${catalog}.${bmv_schema}.gold_promotional_features prm
    ON s.product_sk = prm.product_sk AND s.store_sk = prm.store_sk AND s.date_key = prm.date_key
fields:
- name: product_sk
  expr: product_sk
  comment: Surrogate key for the product.
- name: store_sk
  expr: store_sk
  comment: Surrogate key for the store.
- name: product_id
  expr: product_id
  comment: Universal article identifier.
  synonyms:
  - article_id
- name: store_id
  expr: store_id
  comment: Universal store identifier.
  synonyms:
  - location_id
- name: date_key
  expr: date_key
  comment: Daily grain.
  synonyms:
  - snapshot_date
measures:
- name: avg_units_sold_28d
  expr: AVG(units_sold)
  window:
  - order: date_key
    range: trailing 28 day
    semiadditive: last
  display_name: Avg Units Sold (28d)
  comment: Average daily units sold.
  synonyms:
  - daily_volume
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: avg_units_sold_7d
  expr: AVG(units_sold)
  window:
  - order: date_key
    range: trailing 7 day
    semiadditive: last
  display_name: Avg Units Sold (7d)
  comment: Average daily units sold over trailing 7 days.
  synonyms:
  - daily_volume_7d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: avg_units_sold_14d
  expr: AVG(units_sold)
  window:
  - order: date_key
    range: trailing 14 day
    semiadditive: last
  display_name: Avg Units Sold (14d)
  comment: Average daily units sold over trailing 14 days.
  synonyms:
  - daily_volume_14d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: avg_units_sold_90d
  expr: AVG(units_sold)
  window:
  - order: date_key
    range: trailing 90 day
    semiadditive: last
  display_name: Avg Units Sold (90d)
  comment: Average daily units sold over trailing 90 days.
  synonyms:
  - daily_volume_90d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: avg_price_28d
  expr: AVG(effective_price_lc)
  window:
  - order: date_key
    range: trailing 28 day
    semiadditive: last
  display_name: Avg Price (28d)
  comment: Average effective price.
  synonyms:
  - average_unit_price
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: avg_price_7d
  expr: AVG(effective_price_lc)
  window:
  - order: date_key
    range: trailing 7 day
    semiadditive: last
  display_name: Avg Price (7d)
  comment: Average effective price over trailing 7 days.
  synonyms:
  - average_unit_price_7d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: avg_price_14d
  expr: AVG(effective_price_lc)
  window:
  - order: date_key
    range: trailing 14 day
    semiadditive: last
  display_name: Avg Price (14d)
  comment: Average effective price over trailing 14 days.
  synonyms:
  - average_unit_price_14d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: avg_price_90d
  expr: AVG(effective_price_lc)
  window:
  - order: date_key
    range: trailing 90 day
    semiadditive: last
  display_name: Avg Price (90d)
  comment: Average effective price over trailing 90 days.
  synonyms:
  - average_unit_price_90d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: demand_velocity_28d
  expr: AVG(units_sold)
  window:
  - order: date_key
    range: trailing 28 day
    semiadditive: last
  display_name: Demand Velocity (28d)
  comment: A normalized measure of demand speed.
  synonyms:
  - sales_velocity
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: demand_velocity_7d
  expr: AVG(units_sold)
  window:
  - order: date_key
    range: trailing 7 day
    semiadditive: last
  display_name: Demand Velocity (7d)
  comment: A normalized measure of demand speed over trailing 7 days.
  synonyms:
  - sales_velocity_7d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: demand_velocity_14d
  expr: AVG(units_sold)
  window:
  - order: date_key
    range: trailing 14 day
    semiadditive: last
  display_name: Demand Velocity (14d)
  comment: A normalized measure of demand speed over trailing 14 days.
  synonyms:
  - sales_velocity_14d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: demand_velocity_90d
  expr: AVG(units_sold)
  window:
  - order: date_key
    range: trailing 90 day
    semiadditive: last
  display_name: Demand Velocity (90d)
  comment: A normalized measure of demand speed over trailing 90 days.
  synonyms:
  - sales_velocity_90d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: stockout_rate_28d
  expr: AVG(stockout_pct_day)
  window:
  - order: date_key
    range: trailing 28 day
    semiadditive: last
  display_name: Stockout Rate (28d)
  comment: The percentage of days out-of-stock.
  synonyms:
  - oos_percentage
  format:
    type: percentage
    decimal_places:
      type: exact
      places: 2
- name: stockout_rate_7d
  expr: AVG(stockout_pct_day)
  window:
  - order: date_key
    range: trailing 7 day
    semiadditive: last
  display_name: Stockout Rate (7d)
  comment: The percentage of days out-of-stock over trailing 7 days.
  synonyms:
  - oos_percentage_7d
  format:
    type: percentage
    decimal_places:
      type: exact
      places: 2
- name: stockout_rate_14d
  expr: AVG(stockout_pct_day)
  window:
  - order: date_key
    range: trailing 14 day
    semiadditive: last
  display_name: Stockout Rate (14d)
  comment: The percentage of days out-of-stock over trailing 14 days.
  synonyms:
  - oos_percentage_14d
  format:
    type: percentage
    decimal_places:
      type: exact
      places: 2
- name: stockout_rate_90d
  expr: AVG(stockout_pct_day)
  window:
  - order: date_key
    range: trailing 90 day
    semiadditive: last
  display_name: Stockout Rate (90d)
  comment: The percentage of days out-of-stock over trailing 90 days.
  synonyms:
  - oos_percentage_90d
  format:
    type: percentage
    decimal_places:
      type: exact
      places: 2
- name: avg_competitor_price_28d
  expr: AVG(competitor_regular_price_lc)
  window:
  - order: date_key
    range: trailing 28 day
    semiadditive: last
  display_name: Avg Competitor Price (28d)
  comment: Average of the tracked competitor's price.
  synonyms:
  - mean_comp_price
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: avg_competitor_price_7d
  expr: AVG(competitor_regular_price_lc)
  window:
  - order: date_key
    range: trailing 7 day
    semiadditive: last
  display_name: Avg Competitor Price (7d)
  comment: Average of the tracked competitor's price over trailing 7 days.
  synonyms:
  - mean_comp_price_7d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: avg_competitor_price_14d
  expr: AVG(competitor_regular_price_lc)
  window:
  - order: date_key
    range: trailing 14 day
    semiadditive: last
  display_name: Avg Competitor Price (14d)
  comment: Average of the tracked competitor's price over trailing 14 days.
  synonyms:
  - mean_comp_price_14d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: avg_competitor_price_90d
  expr: AVG(competitor_regular_price_lc)
  window:
  - order: date_key
    range: trailing 90 day
    semiadditive: last
  display_name: Avg Competitor Price (90d)
  comment: Average of the tracked competitor's price over trailing 90 days.
  synonyms:
  - mean_comp_price_90d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: promo_frequency_28d
  expr: SUM(CASE WHEN is_on_promo THEN 1 ELSE 0 END) / COUNT(1)
  window:
  - order: date_key
    range: trailing 28 day
    semiadditive: last
  display_name: Promo Frequency (28d)
  comment: The percentage of days on promotion.
  synonyms:
  - promo_density
  format:
    type: percentage
    decimal_places:
      type: exact
      places: 2
- name: promo_frequency_7d
  expr: SUM(CASE WHEN is_on_promo THEN 1 ELSE 0 END) / COUNT(1)
  window:
  - order: date_key
    range: trailing 7 day
    semiadditive: last
  display_name: Promo Frequency (7d)
  comment: The percentage of days on promotion over trailing 7 days.
  synonyms:
  - promo_density_7d
  format:
    type: percentage
    decimal_places:
      type: exact
      places: 2
- name: promo_frequency_14d
  expr: SUM(CASE WHEN is_on_promo THEN 1 ELSE 0 END) / COUNT(1)
  window:
  - order: date_key
    range: trailing 14 day
    semiadditive: last
  display_name: Promo Frequency (14d)
  comment: The percentage of days on promotion over trailing 14 days.
  synonyms:
  - promo_density_14d
  format:
    type: percentage
    decimal_places:
      type: exact
      places: 2
- name: promo_frequency_90d
  expr: SUM(CASE WHEN is_on_promo THEN 1 ELSE 0 END) / COUNT(1)
  window:
  - order: date_key
    range: trailing 90 day
    semiadditive: last
  display_name: Promo Frequency (90d)
  comment: The percentage of days on promotion over trailing 90 days.
  synonyms:
  - promo_density_90d
  format:
    type: percentage
    decimal_places:
      type: exact
      places: 2
- name: sum_net_sales_7d
  expr: SUM(net_sales_lc)
  window:
  - order: date_key
    range: trailing 7 day
    semiadditive: last
  display_name: Sum Net Sales (7d)
  comment: Total net sales over trailing 7 days.
  synonyms:
  - weekly_sales_7d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: sum_net_sales_14d
  expr: SUM(net_sales_lc)
  window:
  - order: date_key
    range: trailing 14 day
    semiadditive: last
  display_name: Sum Net Sales (14d)
  comment: Total net sales over trailing 14 days.
  synonyms:
  - weekly_sales_14d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: sum_net_sales_28d
  expr: SUM(net_sales_lc)
  window:
  - order: date_key
    range: trailing 28 day
    semiadditive: last
  display_name: Sum Net Sales (28d)
  comment: Total net sales over trailing 28 days.
  synonyms:
  - weekly_sales_28d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: sum_net_sales_90d
  expr: SUM(net_sales_lc)
  window:
  - order: date_key
    range: trailing 90 day
    semiadditive: last
  display_name: Sum Net Sales (90d)
  comment: Total net sales over trailing 90 days.
  synonyms:
  - weekly_sales_90d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: avg_gross_margin_pct_7d
  expr: AVG(gross_margin_pct)
  display_name: Avg Gross Margin Pct (7d)
  comment: Average gross margin rate over trailing 7 days.
  synonyms:
  - gross_profit_margin_7d
  format:
    type: percentage
    decimal_places:
      type: exact
      places: 2
  window:
  - order: date_key
    range: trailing 7 day
    semiadditive: last
- name: avg_gross_margin_pct_14d
  expr: AVG(gross_margin_pct)
  display_name: Avg Gross Margin Pct (14d)
  comment: Average gross margin rate over trailing 14 days.
  synonyms:
  - gross_profit_margin_14d
  format:
    type: percentage
    decimal_places:
      type: exact
      places: 2
  window:
  - order: date_key
    range: trailing 14 day
    semiadditive: last
- name: avg_gross_margin_pct_28d
  expr: AVG(gross_margin_pct)
  display_name: Avg Gross Margin Pct (28d)
  comment: Average gross margin rate over trailing 28 days.
  synonyms:
  - gross_profit_margin_28d
  format:
    type: percentage
    decimal_places:
      type: exact
      places: 2
  window:
  - order: date_key
    range: trailing 28 day
    semiadditive: last
- name: avg_gross_margin_pct_90d
  expr: AVG(gross_margin_pct)
  display_name: Avg Gross Margin Pct (90d)
  comment: Average gross margin rate over trailing 90 days.
  synonyms:
  - gross_profit_margin_90d
  format:
    type: percentage
    decimal_places:
      type: exact
      places: 2
  window:
  - order: date_key
    range: trailing 90 day
    semiadditive: last
- name: avg_rolling_sales_velocity_7d
  expr: AVG(units_sold)
  window:
  - order: date_key
    range: trailing 7 day
    semiadditive: last
  display_name: Avg Rolling Sales Velocity (7d)
  comment: Average Sales velocity over trailing 7 days.
  synonyms:
  - avg_14d_velocity_7d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: avg_rolling_sales_velocity_14d
  expr: AVG(units_sold)
  window:
  - order: date_key
    range: trailing 14 day
    semiadditive: last
  display_name: Avg Rolling Sales Velocity (14d)
  comment: Average Sales velocity over trailing 14 days.
  synonyms:
  - avg_14d_velocity_14d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: avg_rolling_sales_velocity_28d
  expr: AVG(units_sold)
  window:
  - order: date_key
    range: trailing 28 day
    semiadditive: last
  display_name: Avg Rolling Sales Velocity (28d)
  comment: Average Sales velocity over trailing 28 days.
  synonyms:
  - avg_14d_velocity_28d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: avg_rolling_sales_velocity_90d
  expr: AVG(units_sold)
  window:
  - order: date_key
    range: trailing 90 day
    semiadditive: last
  display_name: Avg Rolling Sales Velocity (90d)
  comment: Average Sales velocity over trailing 90 days.
  synonyms:
  - avg_14d_velocity_90d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: avg_rolling_stockout_rate_7d
  expr: AVG(stockout_pct_day)
  window:
  - order: date_key
    range: trailing 7 day
    semiadditive: last
  display_name: Avg Rolling Stockout Rate (7d)
  comment: Percentage of days stocked out over trailing 7 days.
  synonyms:
  - avg_14d_stockout_7d
  format:
    type: percentage
    decimal_places:
      type: exact
      places: 2
- name: avg_rolling_stockout_rate_14d
  expr: AVG(stockout_pct_day)
  window:
  - order: date_key
    range: trailing 14 day
    semiadditive: last
  display_name: Avg Rolling Stockout Rate (14d)
  comment: Percentage of days stocked out over trailing 14 days.
  synonyms:
  - avg_14d_stockout_14d
  format:
    type: percentage
    decimal_places:
      type: exact
      places: 2
- name: avg_rolling_stockout_rate_28d
  expr: AVG(stockout_pct_day)
  window:
  - order: date_key
    range: trailing 28 day
    semiadditive: last
  display_name: Avg Rolling Stockout Rate (28d)
  comment: Percentage of days stocked out over trailing 28 days.
  synonyms:
  - avg_14d_stockout_28d
  format:
    type: percentage
    decimal_places:
      type: exact
      places: 2
- name: avg_rolling_stockout_rate_90d
  expr: AVG(stockout_pct_day)
  window:
  - order: date_key
    range: trailing 90 day
    semiadditive: last
  display_name: Avg Rolling Stockout Rate (90d)
  comment: Percentage of days stocked out over trailing 90 days.
  synonyms:
  - avg_14d_stockout_90d
  format:
    type: percentage
    decimal_places:
      type: exact
      places: 2
- name: comp_price_trend_7d
  expr: MIN(competitor_regular_price_lc)
  window:
  - order: date_key
    range: trailing 7 day
    semiadditive: last
  display_name: Rolling Market Minimum Price (7d)
  comment: Rolling market minimum competitor price over trailing 7 days.
  synonyms:
  - rolling_comp_price_7d
  - market_min_trend_7d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: comp_price_trend_14d
  expr: MIN(competitor_regular_price_lc)
  window:
  - order: date_key
    range: trailing 14 day
    semiadditive: last
  display_name: Rolling Market Minimum Price (14d)
  comment: Rolling market minimum competitor price over trailing 14 days.
  synonyms:
  - rolling_comp_price_14d
  - market_min_trend_14d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: comp_price_trend_28d
  expr: MIN(competitor_regular_price_lc)
  window:
  - order: date_key
    range: trailing 28 day
    semiadditive: last
  display_name: Rolling Market Minimum Price (28d)
  comment: Rolling market minimum competitor price over trailing 28 days.
  synonyms:
  - rolling_comp_price_28d
  - market_min_trend_28d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
- name: comp_price_trend_90d
  expr: MIN(competitor_regular_price_lc)
  window:
  - order: date_key
    range: trailing 90 day
    semiadditive: last
  display_name: Rolling Market Minimum Price (90d)
  comment: Rolling market minimum competitor price over trailing 90 days.
  synonyms:
  - rolling_comp_price_90d
  - market_min_trend_90d
  format:
    type: number
    decimal_places:
      type: exact
      places: 2
$$;
