-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- Metric View: outcome_variables
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-06-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================
-- Computed ML outputs, elasticity coefficients, and recommendations.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${bmv_schema}.mv_outcome_variables
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Computed ML outputs, elasticity coefficients, and recommendations."
source: >
  WITH base_spine AS (
    SELECT
      s.product_sk,
      s.store_sk,
      s.product_id,
      s.store_id,
      s.date_key,
      s.units_sold,
      s.net_sales_lc,
      p.effective_price_lc,
      s.discount_value_lc,
      prm.promo_sk,
      prm.promo_id,
      p.cost_price_lc,
      (s.net_sales_lc - (s.units_sold * p.cost_price_lc)) AS gross_margin_lc
    FROM ${catalog}.${bmv_schema}.gold_sales_actuals s
    LEFT JOIN ${catalog}.${bmv_schema}.gold_price_actuals p 
      ON s.product_sk = p.product_sk AND s.store_sk = p.store_sk AND s.date_key = p.date_key
    LEFT JOIN ${catalog}.${bmv_schema}.gold_promotional_features prm
      ON s.product_sk = prm.product_sk AND s.store_sk = prm.store_sk AND s.date_key = prm.date_key
  )
  SELECT
    b.product_sk,
    b.store_sk,
    b.product_id,
    b.store_id,
    CAST(b.date_key AS DATE) AS date_key,
    CAST(b.units_sold AS DECIMAL(12,3)) AS units_sold,
    CAST(b.net_sales_lc AS DECIMAL(18,2)) AS net_sales_lc,
    CAST(b.effective_price_lc AS DECIMAL(18,2)) AS effective_price_lc,
    CAST(b.cost_price_lc AS DECIMAL(18,2)) AS cost_price_lc,
    CAST(b.discount_value_lc AS DECIMAL(18,2)) AS discount_value_lc,
    CAST(b.promo_sk AS BIGINT) AS promo_sk,
    CAST(b.promo_id AS STRING) AS promo_id,
    CAST(NULL AS DECIMAL(18,2)) AS recommended_optimal_price_lc,
    CAST(NULL AS DECIMAL(5,4))  AS recommended_discount_pct,
    CAST(NULL AS DECIMAL(12,3)) AS predicted_units_at_optimal_price,
    CAST(NULL AS DECIMAL(18,2)) AS predicted_revenue_at_optimal_lc,
    CAST(NULL AS STRING)        AS price_action_recommendation,
    CAST(NULL AS DECIMAL(12,3)) AS predicted_incremental_units,
    CAST(b.gross_margin_lc AS DECIMAL(18,2)) AS gross_margin_lc,
    CAST(b.cost_price_lc * 1.10 AS DECIMAL(18,2)) AS min_price_corridor_lc,
    CAST(b.cost_price_lc * 5.00 AS DECIMAL(18,2)) AS max_price_corridor_lc,
    CAST('ROUND_TO_99' AS STRING) AS price_rounding_rule_code,
    CAST(NULL AS DECIMAL(8,4))  AS point_own_price_elasticity,
    CAST(NULL AS DECIMAL(8,4))  AS cross_elasticity_proxy,
    CAST(NULL AS DECIMAL(8,4))  AS elasticity_confidence_lower,
    CAST(NULL AS DECIMAL(8,4))  AS elasticity_confidence_upper,
    CAST(NULL AS DECIMAL(8,4))  AS promo_elasticity_lift_adj,
    CAST(CASE WHEN b.units_sold > 0 AND b.effective_price_lc > 0 THEN TRUE ELSE FALSE END AS BOOLEAN) AS is_valid_for_elasticity_training,
    CAST(NULL AS INT)           AS days_since_launch,
    CAST(1.0000 AS DECIMAL(5,4)) AS data_completeness_score,
    CAST('v1.0' AS STRING)      AS model_version,
    CAST(CURRENT_TIMESTAMP() AS TIMESTAMP) AS scored_at
  FROM base_spine b

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
  - name: promo_sk
    expr: promo_sk
    comment: "Surrogate key for the promotion"
    synonyms: ['promo_sk']
  - name: promo_id
    expr: promo_id
    comment: "Active promotion identifier"
    synonyms: ['campaign_code', 'promo_id']

measures:
  # ============================================================
  # Goal: Price Optimization
  # ============================================================
  - name: avg_recommended_price
    expr: avg(recommended_optimal_price_lc)
    display_name: "Average Recommended Price"
    comment: "Average recommended optimal price"
    synonyms: ['optimal_suggested_price', 'model_target_price']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: total_predicted_revenue
    expr: sum(predicted_revenue_at_optimal_lc)
    display_name: "Predicted Revenue"
    comment: "Predicted revenue at the optimal price point"
    synonyms: ['forecasted_sales_dollars', 'expected_revenue_total']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: predicted_revenue_lift
    expr: sum(predicted_revenue_at_optimal_lc) - sum(net_sales_lc)
    display_name: "Predicted Revenue Lift"
    comment: "Predicted incremental revenue lift ($)"
    synonyms: ['simulated_revenue_gain', 'expected_incremental_dollars']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: avg_recommended_discount
    expr: avg(recommended_discount_pct)
    display_name: "Recommended Discount %"
    comment: "Average recommended discount percentage"
    synonyms: ['suggested_markdown_depth', 'optimal_promo_pct']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  # ============================================================
  # Goal: Elastic Modelling
  # ============================================================
  - name: base_elasticity
    expr: avg(point_own_price_elasticity) filter (where promo_id = 'NO_PROMO')
    display_name: "Base Elasticity"
    comment: "Base price elasticity of demand"
    synonyms: ['regular_price_sensitivity', 'organic_ped']
    format:
      type: number
      decimal_places:
        type: max
        places: 4

  - name: promo_elasticity
    expr: avg(point_own_price_elasticity + promo_elasticity_lift_adj) filter (where promo_id != 'NO_PROMO')
    display_name: "Promo Elasticity"
    comment: "Promotional price elasticity of demand"
    synonyms: ['discount_sensitivity', 'markdown_ped']
    format:
      type: number
      decimal_places:
        type: max
        places: 4

  - name: volume_weighted_cross_elasticity
    expr: sum(cross_elasticity_proxy * units_sold) / nullif(sum(units_sold), 0)
    display_name: "Volume Weighted Cross Elasticity"
    comment: "Volume-weighted average cross elasticity proxy"
    synonyms: ['cannibalization_factor', 'halo_effect_metric']
    format:
      type: number
      decimal_places:
        type: max
        places: 4

  - name: total_pricing_headroom
    expr: sum((recommended_optimal_price_lc - effective_price_lc) * units_sold)
    display_name: "Total Pricing Headroom"
    comment: "Total pricing headroom (revenue left on table)"
    synonyms: ['unrealized_margin_dollars', 'left_on_table_value']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: predicted_profit_lift
    expr: sum(predicted_revenue_at_optimal_lc - (cost_price_lc * predicted_units_at_optimal_price)) - sum((effective_price_lc - cost_price_lc) * units_sold)
    display_name: "Predicted Profit Lift"
    comment: "Predicted incremental profit lift at optimal price"
    synonyms: ['simulated_profit_gain', 'expected_margin_increase']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: elasticity_confidence_spread
    expr: avg(elasticity_confidence_upper - elasticity_confidence_lower)
    display_name: "Elasticity Confidence Spread"
    comment: "Spread between upper and lower elasticity confidence intervals"
    synonyms: ['model_certainty_band', 'ped_error_margin']
    format:
      type: number
      decimal_places:
        type: max
        places: 4

  - name: pricing_power_index
    expr: avg(((effective_price_lc - cost_price_lc) / nullif(effective_price_lc, 0)) - (-1.0 / nullif(point_own_price_elasticity, 0)))
    display_name: "Pricing Power Index"
    comment: "Pricing Power Index (Lerner Index Deviation)"
    synonyms: ['lerner_monopoly_power', 'brand_pricing_strength']
    format:
      type: number
      decimal_places:
        type: max
        places: 4

  - name: incremental_profit_rom
    expr: sum(predicted_incremental_units * (effective_price_lc - cost_price_lc)) / nullif(sum(discount_value_lc), 0)
    display_name: "Return on Markdown"
    comment: "Incremental Profit Return on Markdown (ROM)"
    synonyms: ['return_on_markdown_pct', 'promo_profit_roi']
    format:
      type: number
      decimal_places:
        type: max
        places: 4
$$;
