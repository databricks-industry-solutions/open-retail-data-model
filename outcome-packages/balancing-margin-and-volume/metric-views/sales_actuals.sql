-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- Metric View: sales_actuals
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-06-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================
-- Grain-level sales and volume actuals.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${bmv_schema}.mv_sales_actuals
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Grain-level sales and volume actuals."
source: ${catalog}.${bmv_schema}.gold_sales_actuals

joins:
  - name: fiscal_calendar
    source: ${catalog}.${calendar_schema}.fiscal_calendar
    on: source.date_key = fiscal_calendar.date_key
    cardinality: many_to_one

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
  - name: fiscal_season
    expr: fiscal_calendar.fiscal_season
    comment: "Retail merchandising half-year season (spring = fiscal periods 1-6, fall = 7-12), conformed on fiscal_calendar."
    synonyms: ['retail_season', 'merch_season']
  - name: fiscal_period
    expr: fiscal_calendar.fiscal_period
    comment: "Fiscal period or month"

measures:
  # ============================================================
  # Goal: Price Optimization
  # ============================================================
  - name: total_units_sold
    expr: sum(units_sold)
    display_name: "Total Units Sold"
    comment: "Total units sold"
    synonyms: ['overall_volume', 'total_quantity_moved']
    format:
      type: number
      decimal_places:
        type: exact
        places: 0

  - name: total_net_sales
    expr: sum(net_sales_lc)
    display_name: "Total Net Sales"
    comment: "Total net sales in local currency"
    synonyms: ['realized_revenue']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: total_discount_value
    expr: sum(discount_value_lc)
    display_name: "Total Discount Value"
    comment: "Total discount value in local currency"
    synonyms: ['total_savings_amount']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: total_gross_sales
    expr: sum(gross_sales_lc)
    display_name: "Total Gross Sales"
    comment: "Total gross sales value"
    synonyms: ['pre_discount_revenue', 'ticket_sales_value']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: markdown_rate
    expr: sum(discount_value_lc) / nullif(sum(gross_sales_lc), 0)
    display_name: "Markdown Rate"
    comment: "Markdown discount value as a percentage of gross sales"
    synonyms: ['discount_percentage', 'markdown_depth_ratio']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: total_returns
    expr: sum(returns_units)
    display_name: "Total Returns"
    comment: "Total units returned"
    synonyms: ['refunded_units', 'returned_items_count']
    format:
      type: number
      decimal_places:
        type: exact
        places: 0

  - name: net_units_sold
    expr: sum(net_units_sold)
    display_name: "Net Units Sold"
    comment: "Net units sold after returns"
    synonyms: ['kept_volume', 'post_returns_quantity']
    format:
      type: number
      decimal_places:
        type: exact
        places: 0

  - name: stockout_adjusted_demand
    expr: sum(units_sold / nullif(1 - stockout_pct_day, 0))
    display_name: "Stockout-Adjusted Demand"
    comment: "Estimated unconstrained demand adjusting for stockouts"
    synonyms: ['unconstrained_demand_estimate', 'lost_sales_adjusted_volume']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  # ============================================================
  # Goal: Elastic Modelling
  # ============================================================
  - name: total_baseline_units_sold
    expr: sum(baseline_units_sold)
    display_name: "Total Baseline Units Sold"
    comment: "De-seasonalized and de-promoted normal demand."
    synonyms: ['organic_volume', 'non_promo_base_demand']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: total_incremental_lift_units
    expr: sum(incremental_lift_units)
    display_name: "Total Incremental Lift Units"
    comment: "Extra units sold attributable specifically to a promotion."
    synonyms: ['promo_driven_extra_volume', 'campaign_lift_quantity']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: avg_stockout_pct_day
    expr: avg(stockout_pct_day)
    display_name: "Avg Stockout Pct per Day"
    comment: "Percentage of the day the product was out of stock on shelf."
    synonyms: ['shelf_empty_duration_pct', 'oos_time_ratio']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  # ============================================================
  # Goal: Assortment Optimization
  # ============================================================
  - name: sell_through_pct
    expr: sum(units_sold) / nullif(sum(units_received_today), 0)
    display_name: "Sell-Through Pct"
    comment: "Units sold as a percentage of units received (ratio of sums) over the query's grouping/filter window. No rolling or seasonal logic is baked in: group by the fiscal_season dimension for season-to-date sell-through, or filter date_key to a trailing window (e.g. 90 days) for rolling sell-through. Replaces the former identical rolling_90d_sell_through_pct + fiscal_season_sell_through_pct measures, whose names implied window/season logic the expr never carried."
    synonyms: ['sell_through_rate', 'str', 'sell_through', 'season_to_date_sell_through', 'rolling_90d_sell_through_pct', 'fiscal_season_sell_through_pct']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2
$$;
