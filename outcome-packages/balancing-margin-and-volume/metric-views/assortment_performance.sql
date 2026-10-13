-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- Metric View: assortment_performance
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-06-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================
-- Assortment performance and elasticity metrics.
--
-- Definitions (Assortment Optimization):
-- * category: Merchandising category
-- * margin_contribution_pct: 14d realized gross-margin rate (ratio-of-sums: margin$ / rate-bearing revenue)
-- * baseline_velocity_units_per_day: 28d non-promo observed mean units/day (ratio-of-sums)
-- * avg_revenue_per_sqft: Revenue per allocated square foot
-- * avg_space_elasticity: average heuristic space elasticity over SKU x store rows with a planogram
--   allocation (the estimate is per space-planning category; see gold_assortment_optimization)
--
-- RESTORED (after 0.2-beta): `avg_space_elasticity` returns. It was removed in 0.1-beta (§15 deprecation
-- note) because `space_elasticity` was 100% NULL; the column is now a computed heuristic estimate.
-- 0.1-beta also renamed `avg_baseline_velocity` -> `baseline_velocity_units_per_day` and
-- `avg_margin_contribution_pct` -> `margin_contribution_pct` (avg-of-ratios -> ratio-of-sums).
-- * avg_revenue_per_facing: Revenue per allocated facing
-- * days_on_hand: Estimated days of inventory on hand
-- * weeks_of_supply: Estimated weeks of inventory supply
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${bmv_schema}.mv_assortment_performance
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Assortment performance metrics."
source: >
  SELECT
    f.product_sk,
    f.store_sk,
    f.product_id,
    f.store_id,
    p.category,
    s.store_format,
    f.allocated_facings,
    f.allocated_sqft,
    f.space_elasticity,
    f.rolling_margin_14d,
    f.rolling_margin_base_rev_14d,
    f.baseline_units_28d,
    f.baseline_nonpromo_days_28d,
    f.rolling_sales_velocity_14d,
    f.rolling_revenue_14d,
    f.units_on_hand_eod
  FROM ${catalog}.${bmv_schema}.gold_assortment_optimization f
  LEFT JOIN ${catalog}.${product_schema}.product p ON f.product_sk = p.product_sk
  LEFT JOIN ${catalog}.${store_schema}.store s ON f.store_sk = s.store_sk

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
    synonyms: ['article_id', 'item_id']
  - name: store_id
    expr: store_id
    comment: "Universal store identifier"
    synonyms: ['location_id', 'site_id']
  - name: category
    expr: category
    comment: "Merchandising category"
    synonyms: ['merch_category', 'department']
  - name: store_format
    expr: store_format
    comment: "Store format or classification"
    synonyms: ['format_type']

measures:
  # ============================================================
  # Goal: Assortment Optimization
  # ============================================================
  - name: avg_revenue_per_sqft
    expr: sum(rolling_revenue_14d) / nullif(sum(allocated_sqft), 0)
    display_name: "Avg Revenue per SqFt"
    comment: "Sales revenue generated per allocated square foot"
    synonyms: ['space_productivity', 'sales_per_sqft']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: avg_revenue_per_facing
    expr: sum(rolling_revenue_14d) / nullif(sum(allocated_facings), 0)
    display_name: "Avg Revenue per Facing"
    comment: "Sales revenue generated per allocated shelf facing"
    synonyms: ['facing_productivity', 'sales_per_facing']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: days_on_hand
    expr: sum(units_on_hand_eod) / nullif(sum(rolling_sales_velocity_14d), 0)
    display_name: "Days on Hand"
    comment: "Estimated days of inventory on hand based on sales velocity"
    synonyms: ['doh', 'inventory_days']
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: weeks_of_supply
    expr: sum(units_on_hand_eod) / nullif(sum(rolling_sales_velocity_14d) * 7, 0)
    display_name: "Weeks of Supply"
    comment: "Estimated weeks of inventory supply based on sales velocity"
    synonyms: ['wos', 'weeks_of_cover']
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: avg_allocated_facings
    expr: avg(allocated_facings)
    display_name: "Avg Allocated Facings"
    comment: "Average number of facings allocated on planogram"
    synonyms: ['facings', 'shelf_space']
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: avg_allocated_sqft
    expr: avg(allocated_sqft)
    display_name: "Avg Allocated Sqft"
    comment: "Average square footage allocated on planogram"
    synonyms: ['sqft', 'allocated_space']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: avg_space_elasticity
    expr: avg(space_elasticity)
    display_name: "Avg Space Elasticity"
    comment: "Average heuristic space elasticity (% change in units per 1% change in facings) over SKU x store rows with a planogram allocation. Observational cross-store estimate per space-planning category, shrunk toward a 0.17 literature prior; not a causal effect."
    synonyms: ['space_elasticity', 'shelf_space_elasticity', 'facing_elasticity']
    format:
      type: number
      decimal_places:
        type: exact
        places: 4

  - name: baseline_velocity_units_per_day
    expr: sum(baseline_units_28d) / nullif(sum(baseline_nonpromo_days_28d), 0)
    display_name: "Baseline Velocity (units/day)"
    comment: "28-day non-promo observed mean units/day (ratio-of-sums), a heuristic baseline proxy"
    synonyms: ['base_volume', 'non_promo_velocity']
    format:
      type: number
      decimal_places:
        type: exact
        places: 3

  - name: margin_contribution_pct
    expr: sum(rolling_margin_14d) / nullif(sum(rolling_margin_base_rev_14d), 0)
    display_name: "Margin Contribution Pct"
    comment: "14-day realized gross-margin rate = margin$ / rate-bearing revenue (ratio-of-sums; denominator excludes days with no gross-margin rate so it isn't biased down)"
    synonyms: ['margin_contribution', 'profit_contribution']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 4
$$;
