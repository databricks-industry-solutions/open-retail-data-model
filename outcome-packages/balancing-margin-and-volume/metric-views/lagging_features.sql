-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- Metric View: lagging_features
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-06-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================
-- Time-shifted lag features for elasticity model training.
--
-- Definitions (Assortment Optimization):
-- * competitor_assortment_overlap_pct: Percentage of assortment shared with competitor
-- * rolling_sales_velocity_14d: Rolling 14-day sales velocity
-- * rolling_stockout_rate_14d: Rolling 14-day stockout rate
-- * lagged_baseline_velocity: Base volume sold absent of promotions
-- * lagged_margin_contribution: Margin contribution from previous periods
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${bmv_schema}.mv_lagging_features
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Time-shifted lag features for elasticity model training."
source: >
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
    a.baseline_velocity,
    a.margin_contribution_pct
  FROM ${catalog}.${bmv_schema}.gold_sales_actuals s
  LEFT JOIN ${catalog}.${bmv_schema}.gold_price_actuals p
    ON s.product_sk = p.product_sk AND s.store_sk = p.store_sk AND s.date_key = p.date_key
  LEFT JOIN ${catalog}.${bmv_schema}.gold_assortment_optimization a
    ON s.product_sk = a.product_sk AND s.store_sk = a.store_sk

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
    synonyms: ['article_id', 'sku']
  - name: store_id
    expr: store_id
    comment: "Universal store identifier."
    synonyms: ['location_id']
  - name: date_key
    expr: date_key
    comment: "Daily grain."
    synonyms: ['calendar_day']

measures:
  # ============================================================
  # Goal: Price Optimization
  # ============================================================
  - name: lagged_net_sales_7d
    expr: SUM(net_sales_lc)
    window:
      - order: date_key
        range: current
        offset: -7 day
        semiadditive: last
    display_name: "Lagged Net Sales (7d)"
    comment: "Net sales from previous periods offset by 7 days."
    synonyms: ['lagged_revenue_7d']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: lagged_net_sales_14d
    expr: SUM(net_sales_lc)
    window:
      - order: date_key
        range: current
        offset: -14 day
        semiadditive: last
    display_name: "Lagged Net Sales (14d)"
    comment: "Net sales from previous periods offset by 14 days."
    synonyms: ['lagged_revenue_14d']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: lagged_net_sales_28d
    expr: SUM(net_sales_lc)
    window:
      - order: date_key
        range: current
        offset: -28 day
        semiadditive: last
    display_name: "Lagged Net Sales (28d)"
    comment: "Net sales from previous periods offset by 28 days."
    synonyms: ['lagged_revenue_28d']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: lagged_net_sales_90d
    expr: SUM(net_sales_lc)
    window:
      - order: date_key
        range: current
        offset: -90 day
        semiadditive: last
    display_name: "Lagged Net Sales (90d)"
    comment: "Net sales from previous periods offset by 90 days."
    synonyms: ['lagged_revenue_90d']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: lagged_gross_margin_pct_7d
    expr: AVG(gross_margin_pct)
    window:
      - order: date_key
        range: current
        offset: -7 day
        semiadditive: last
    display_name: "Lagged Gross Margin Pct (7d)"
    comment: "Gross margin from previous periods offset by 7 days."
    synonyms: ['lagged_margin_7d']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: lagged_gross_margin_pct_14d
    expr: AVG(gross_margin_pct)
    window:
      - order: date_key
        range: current
        offset: -14 day
        semiadditive: last
    display_name: "Lagged Gross Margin Pct (14d)"
    comment: "Gross margin from previous periods offset by 14 days."
    synonyms: ['lagged_margin_14d']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: lagged_gross_margin_pct_28d
    expr: AVG(gross_margin_pct)
    window:
      - order: date_key
        range: current
        offset: -28 day
        semiadditive: last
    display_name: "Lagged Gross Margin Pct (28d)"
    comment: "Gross margin from previous periods offset by 28 days."
    synonyms: ['lagged_margin_28d']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: lagged_gross_margin_pct_90d
    expr: AVG(gross_margin_pct)
    window:
      - order: date_key
        range: current
        offset: -90 day
        semiadditive: last
    display_name: "Lagged Gross Margin Pct (90d)"
    comment: "Gross margin from previous periods offset by 90 days."
    synonyms: ['lagged_margin_90d']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  # ============================================================
  # Goal: Elastic Modelling
  # ============================================================
  - name: lagged_units_sold_7d
    expr: SUM(units_sold)
    window:
      - order: date_key
        range: current
        offset: -7 day
        semiadditive: last
    display_name: "Lagged Units Sold (7d)"
    comment: "Total units sold offset by 7 days."
    synonyms: ['lagged_sales_volume_7d']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: lagged_units_sold_14d
    expr: SUM(units_sold)
    window:
      - order: date_key
        range: current
        offset: -14 day
        semiadditive: last
    display_name: "Lagged Units Sold (14d)"
    comment: "Total units sold offset by 14 days."
    synonyms: ['lagged_sales_volume_14d']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: lagged_units_sold_28d
    expr: SUM(units_sold)
    window:
      - order: date_key
        range: current
        offset: -28 day
        semiadditive: last
    display_name: "Lagged Units Sold (28d)"
    comment: "Total units sold offset by 28 days."
    synonyms: ['lagged_sales_volume_28d']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: lagged_units_sold_90d
    expr: SUM(units_sold)
    window:
      - order: date_key
        range: current
        offset: -90 day
        semiadditive: last
    display_name: "Lagged Units Sold (90d)"
    comment: "Total units sold offset by 90 days."
    synonyms: ['lagged_sales_volume_90d']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: lagged_effective_price_7d
    expr: AVG(effective_price_lc)
    window:
      - order: date_key
        range: current
        offset: -7 day
        semiadditive: last
    display_name: "Lagged Effective Price (7d)"
    comment: "Average effective price offset by 7 days."
    synonyms: ['lagged_average_selling_price_7d']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: lagged_effective_price_14d
    expr: AVG(effective_price_lc)
    window:
      - order: date_key
        range: current
        offset: -14 day
        semiadditive: last
    display_name: "Lagged Effective Price (14d)"
    comment: "Average effective price offset by 14 days."
    synonyms: ['lagged_average_selling_price_14d']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: lagged_effective_price_28d
    expr: AVG(effective_price_lc)
    window:
      - order: date_key
        range: current
        offset: -28 day
        semiadditive: last
    display_name: "Lagged Effective Price (28d)"
    comment: "Average effective price offset by 28 days."
    synonyms: ['lagged_average_selling_price_28d']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: lagged_effective_price_90d
    expr: AVG(effective_price_lc)
    window:
      - order: date_key
        range: current
        offset: -90 day
        semiadditive: last
    display_name: "Lagged Effective Price (90d)"
    comment: "Average effective price offset by 90 days."
    synonyms: ['lagged_average_selling_price_90d']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  # ============================================================
  # Goal: Assortment Optimization
  # ============================================================
  - name: lagged_baseline_velocity_7d
    expr: AVG(baseline_velocity)
    window:
      - order: date_key
        range: current
        offset: -7 day
        semiadditive: last
    display_name: "Lagged Baseline Velocity (7d)"
    comment: "Baseline velocity from previous periods offset by 7 days."
    synonyms: ['lagged_prior_velocity_7d']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: lagged_baseline_velocity_14d
    expr: AVG(baseline_velocity)
    window:
      - order: date_key
        range: current
        offset: -14 day
        semiadditive: last
    display_name: "Lagged Baseline Velocity (14d)"
    comment: "Baseline velocity from previous periods offset by 14 days."
    synonyms: ['lagged_prior_velocity_14d']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: lagged_baseline_velocity_28d
    expr: AVG(baseline_velocity)
    window:
      - order: date_key
        range: current
        offset: -28 day
        semiadditive: last
    display_name: "Lagged Baseline Velocity (28d)"
    comment: "Baseline velocity from previous periods offset by 28 days."
    synonyms: ['lagged_prior_velocity_28d']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: lagged_baseline_velocity_90d
    expr: AVG(baseline_velocity)
    window:
      - order: date_key
        range: current
        offset: -90 day
        semiadditive: last
    display_name: "Lagged Baseline Velocity (90d)"
    comment: "Baseline velocity from previous periods offset by 90 days."
    synonyms: ['lagged_prior_velocity_90d']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: lagged_margin_contribution_7d
    expr: AVG(margin_contribution_pct)
    window:
      - order: date_key
        range: current
        offset: -7 day
        semiadditive: last
    display_name: "Lagged Margin Contribution (7d)"
    comment: "Margin contribution from previous periods offset by 7 days."
    synonyms: ['lagged_prior_margin_contribution_7d']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: lagged_margin_contribution_14d
    expr: AVG(margin_contribution_pct)
    window:
      - order: date_key
        range: current
        offset: -14 day
        semiadditive: last
    display_name: "Lagged Margin Contribution (14d)"
    comment: "Margin contribution from previous periods offset by 14 days."
    synonyms: ['lagged_prior_margin_contribution_14d']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: lagged_margin_contribution_28d
    expr: AVG(margin_contribution_pct)
    window:
      - order: date_key
        range: current
        offset: -28 day
        semiadditive: last
    display_name: "Lagged Margin Contribution (28d)"
    comment: "Margin contribution from previous periods offset by 28 days."
    synonyms: ['lagged_prior_margin_contribution_28d']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: lagged_margin_contribution_90d
    expr: AVG(margin_contribution_pct)
    window:
      - order: date_key
        range: current
        offset: -90 day
        semiadditive: last
    display_name: "Lagged Margin Contribution (90d)"
    comment: "Margin contribution from previous periods offset by 90 days."
    synonyms: ['lagged_prior_margin_contribution_90d']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

$$;
