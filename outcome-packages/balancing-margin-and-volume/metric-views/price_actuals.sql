-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- Metric View: price_actuals
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-06-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================
-- Daily price points and margin actuals.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${bmv_schema}.mv_price_actuals
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Daily price points and margin actuals."
source: ${catalog}.${bmv_schema}.gold_price_actuals

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

  - name: price_change_direction
    expr: price_change_direction
    comment: "Indicator of whether the price increased, decreased, or remained flat"
    synonyms: ['markdown_or_markup_indicator']

measures:
  # ============================================================
  # Goal: Price Optimization
  # ============================================================
  - name: average_selling_price
    expr: sum(net_sales_lc) / nullif(sum(units_sold), 0)
    display_name: "Average Selling Price"
    comment: "Volume-weighted Average Selling Price (ASP)"
    synonyms: ['realized_asp', 'net_price_per_unit']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: avg_base_price
    expr: avg(base_price_lc)
    display_name: "Average Base Price"
    comment: "Average base price"
    synonyms: ['original_ticket_price', 'regular_shelf_price']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: weighted_gross_margin_rate
    expr: (sum(net_sales_lc) - sum(cost_price_lc * units_sold)) / nullif(sum(net_sales_lc), 0)
    display_name: "Weighted Gross Margin %"
    comment: "Weighted gross margin percentage"
    synonyms: ['profit_margin_pct', 'margin_rate_blended']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: total_cost
    expr: sum(cost_price_lc * units_sold)
    display_name: "Total Cost"
    comment: "Total cost of goods sold"
    synonyms: ['cogs_total', 'inventory_cost_value']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: total_net_sales
    expr: sum(net_sales_lc)
    display_name: "Total Net Sales"
    comment: "Total net sales value"
    synonyms: ['realized_revenue', 'net_dollars_earned']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: total_gross_profit
    expr: sum(net_sales_lc) - sum(cost_price_lc * units_sold)
    display_name: "Total Gross Profit"
    comment: "Total gross profit in local currency"
    synonyms: ['gross_margin_dollars', 'profit_dollars_earned']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: avg_realized_discount
    expr: avg(realized_discount_pct)
    display_name: "Average Realized Discount %"
    comment: "Average realized discount percentage"
    synonyms: ['average_markdown_amt', 'mean_discount_value']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  # ============================================================
  # Goal: Elastic Modelling
  # ============================================================
  - name: avg_log_effective_price
    expr: avg(log_effective_price)
    display_name: "Log Effective Price"
    comment: "Average log transformation of effective price"
    synonyms: ['ln_price_metric', 'logarithmic_price']
    format:
      type: number
      decimal_places:
        type: exact
        places: 4

  - name: avg_price_change_magnitude_pct
    expr: avg(price_change_magnitude_pct)
    display_name: "Price Change Magnitude %"
    comment: "The percentage change in price compared to the previous period"
    synonyms: ['ticket_change_size_pct', 'price_delta_ratio']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: avg_days_since_last_price_change
    expr: avg(days_since_last_price_change)
    display_name: "Days Since Last Price Change"
    comment: "Tracks the decay of consumer shock as they adapt to new prices"
    synonyms: ['ticket_age_days', 'price_stability_duration']
    format:
      type: number
      decimal_places:
        type: exact
        places: 0

  - name: avg_price_barrier_proximity
    expr: avg(price_barrier_proximity)
    display_name: "Price Barrier Proximity"
    comment: "Proximity to psychological boundaries like .99"
    synonyms: ['psychological_threshold_distance', 'charm_price_gap']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2
$$;
