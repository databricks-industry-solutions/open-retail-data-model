-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- Metric View: realized_margin
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-10-11
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: pending - BMV owner ack required
-- ============================================================
-- Realized margin and revenue leakage metrics across sales channels.
--
-- Definitions (Realized Margin & Revenue Leakage):
-- * booked_revenue: POS net sales plus order-channel booked (line net) sales.
-- * realized_revenue: POS net sales plus order-channel settled sales, less refunds, chargebacks and adjustments.
-- * revenue_leakage: booked minus realized = unsettled order sales + refunds + chargebacks + adjustments
--   (order channel only; POS carries no payment reversals in ORDM).
-- * realized_margin: realized revenue minus COGS (units x product.unit_cost). Same basis as
--   net revenue minus units x cost elsewhere in ORDM; gold_price_actuals derives its
--   gross_margin_pct from the product_price cost row, so the two agree when those costs agree.
-- * leakage_rate divides by total booked revenue (diluted by POS); order_channel_leakage_rate
--   divides by order-channel booked sales.
-- * sale-cohort basis: POS rows dated by sale day; order rows dated by order_date; payment reversals attributed to order_date, not event date.
--
-- Amount basis: payment sale amounts are expected on the same tax- and shipping-exclusive basis as
-- customer_order_line.net_amount. An adopter whose tenders include tax or shipping must net them out
-- upstream; otherwise settled sales exceed booked sales and unsettled sales go negative
-- (bmv_realized_margin_unsettled_sanity). gold_payment_actuals shares this basis.
-- Assumptions: Allocation uses order-revenue-share weight (same as gold_payment_actuals);
-- refunded merchandise not assumed restocked (no COGS recovery); COGS uses product_sk version;
-- adjustments are contra-revenue; adjustments/refunds with no order_id excluded;
-- recent cohorts immature (reversals can land weeks after sale); operational estimate, not accounting close.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${bmv_schema}.mv_realized_margin
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Realized margin and revenue leakage metrics."
source: >
  SELECT
    g.product_id,
    g.store_id,
    g.date_key,
    g.currency_code,
    p.category,
    s.store_format,
    fc.fiscal_year,
    fc.fiscal_season,
    fc.fiscal_period,
    g.booked_revenue_lc,
    g.realized_revenue_lc,
    g.leakage_lc,
    g.order_refund_lc,
    g.order_chargeback_lc,
    g.order_adjustment_lc,
    g.order_unsettled_sales_lc,
    g.cogs_lc,
    g.booked_margin_lc,
    g.realized_margin_lc,
    g.order_booked_sales_lc
  FROM ${catalog}.${bmv_schema}.gold_realized_margin g
  LEFT JOIN ${catalog}.${product_schema}.product p ON g.product_sk = p.product_sk
  LEFT JOIN ${catalog}.${store_schema}.store s ON g.store_sk = s.store_sk
  LEFT JOIN ${catalog}.${calendar_schema}.fiscal_calendar fc ON g.date_key = fc.date_key

fields:
  - name: product_id
    expr: product_id
    comment: "Universal article identifier"
    synonyms: ['article_id', 'item_code', 'sku_number']
  - name: store_id
    expr: store_id
    comment: "Universal store identifier"
    synonyms: ['location_code', 'branch_id']
  - name: date_key
    expr: date_key
    comment: "Daily grain; sale-cohort basis (POS dated by sale day, orders dated by order_date)"
    synonyms: ['sale_date', 'order_date', 'cohort_date']
  - name: category
    expr: category
    comment: "Merchandising category"
    synonyms: ['merch_category', 'department']
  - name: store_format
    expr: store_format
    comment: "Store format or classification. Order-channel rows carry the store the order is attributed to (ship-to or fulfilling store), so this dimension applies to both channels."
    synonyms: ['format_type', 'store_class']
  - name: fiscal_year
    expr: fiscal_year
    comment: "NRF 4-5-4 fiscal year, conformed on fiscal_calendar. Group with fiscal_period or fiscal_season so the same period in different years is not merged."
    synonyms: ['retail_year', 'fy']
  - name: fiscal_season
    expr: fiscal_season
    comment: "Retail merchandising half-year season (spring = fiscal periods 1-6, fall = 7-12), conformed on fiscal_calendar"
    synonyms: ['retail_season', 'merch_season', 'half_year']
  - name: fiscal_period
    expr: fiscal_period
    comment: "Fiscal period or month"
    synonyms: ['fiscal_month', 'retail_period']
  - name: currency_code
    expr: currency_code
    comment: "Reporting/base currency of all monetary measures (ISO 4217), single-currency by construction"
    synonyms: ['base_currency', 'reporting_currency']

measures:
  # ============================================================
  # Revenue Base (Booked vs Realized)
  # ============================================================
  - name: booked_revenue_lc
    expr: sum(booked_revenue_lc)
    display_name: "Booked Revenue (sale cohort)"
    comment: "Total revenue recognized at sale (POS net sales + order booked sales), gross of all reversals"
    synonyms: ['total_booked_sales', 'booked_net_sales']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: realized_revenue_lc
    expr: sum(realized_revenue_lc)
    display_name: "Realized Revenue (sale cohort)"
    comment: "POS net sales plus order-channel SETTLED sales, less refunds, chargebacks and adjustments attributed to the original order date (excludes order sales never captured or settled). Sale-cohort basis."
    synonyms: ['cohort_realized_revenue', 'sale_cohort_net_revenue']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  # ============================================================
  # Leakage Components
  # ============================================================
  - name: leakage_lc
    expr: sum(leakage_lc)
    display_name: "Revenue Leakage incl. Unsettled (sale cohort)"
    comment: "Booked revenue not realized: unsettled orders, refunds, chargebacks, adjustments combined"
    synonyms: ['cohort_leakage', 'sale_cohort_revenue_shortfall']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: refund_lc
    expr: sum(order_refund_lc)
    display_name: "Refunds (sale cohort)"
    comment: "Refund magnitude attributed to sale-cohort date; voluntary customer returns"
    synonyms: ['cohort_refunds', 'refunds_by_sale_date']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: chargeback_lc
    expr: sum(order_chargeback_lc)
    display_name: "Chargebacks (sale cohort)"
    comment: "Chargeback magnitude attributed to sale-cohort date; involuntary payment provider reversals"
    synonyms: ['cohort_chargebacks', 'chargebacks_by_sale_date']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: adjustment_lc
    expr: sum(order_adjustment_lc)
    display_name: "Adjustments (sale cohort)"
    comment: "Adjustment magnitude attributed to sale-cohort date; post-sale credits and settlements"
    synonyms: ['cohort_adjustments', 'adjustments_by_sale_date']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: unsettled_sales_lc
    expr: sum(order_unsettled_sales_lc)
    display_name: "Unsettled Sales"
    comment: "Order revenue booked but not yet settled or captured; operational leakage pending collection"
    synonyms: ['pending_settlement', 'pending_capture', 'in_flight_revenue']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  # ============================================================
  # Cost and Margin
  # ============================================================
  - name: cogs_lc
    expr: sum(cogs_lc)
    display_name: "Cost of Goods Sold"
    comment: "Total COGS (POS and order channels); product_sk version used at ingest time"
    synonyms: ['realized_margin_cogs', 'cohort_cost_of_goods_sold']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: booked_margin_lc
    expr: sum(booked_margin_lc)
    display_name: "Booked Gross Profit"
    comment: "Booked revenue minus COGS; gross of all payment reversals"
    synonyms: ['gross_profit_accrual', 'margin_before_leakage']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: realized_margin_lc
    expr: sum(realized_margin_lc)
    display_name: "Realized Gross Profit"
    comment: "Realized revenue minus COGS; net of all refunds, chargebacks, and adjustments; sale-cohort basis"
    synonyms: ['realized_gross_profit', 'margin_after_leakage']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  # ============================================================
  # Margin Rates
  # ============================================================
  - name: booked_margin_pct
    expr: sum(booked_margin_lc) / nullif(sum(booked_revenue_lc), 0)
    display_name: "Booked Margin %"
    comment: "Booked gross margin rate (ratio-of-sums); gross of payment reversals"
    synonyms: ['booked_margin_rate', 'gross_margin_pct_accrual']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: realized_margin_pct
    expr: sum(realized_margin_lc) / nullif(sum(realized_revenue_lc), 0)
    display_name: "Realized Margin %"
    comment: "Realized gross margin rate (ratio-of-sums); net of all reversals; sale-cohort basis"
    synonyms: ['realized_margin_rate', 'post_leakage_margin_pct']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  # ============================================================
  # Leakage Rates
  # ============================================================
  - name: leakage_rate
    expr: sum(leakage_lc) / nullif(sum(booked_revenue_lc), 0)
    display_name: "Leakage Rate of Booked Revenue (sale cohort)"
    comment: "Revenue leakage as a percentage of total booked revenue across POS and order channels (ratio-of-sums); combines unsettled, refund, chargeback, adjustment. Diluted by the POS share, which carries no reversals; use order_channel_leakage_rate to compare leakage intensity. Sale-cohort basis."
    synonyms: ['cohort_leakage_rate', 'leakage_pct_of_booked']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: order_channel_leakage_rate
    expr: sum(leakage_lc) / nullif(sum(order_booked_sales_lc), 0)
    display_name: "Order Channel Leakage Rate (sale cohort)"
    comment: "Revenue leakage as a percentage of ORDER-channel booked sales (ratio-of-sums). Leakage occurs only on the order channel (POS sales carry no payment reversals in ORDM), so this is the rate to compare across stores or categories; leakage_rate divides by total booked revenue including POS and is diluted by the POS share. Sale-cohort basis."
    synonyms: ['order_leakage_rate', 'cohort_order_leakage_pct']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  # ============================================================
  # Channel Insight
  # ============================================================
  - name: order_channel_share
    expr: sum(order_booked_sales_lc) / nullif(sum(booked_revenue_lc), 0)
    display_name: "Order Channel Share"
    comment: "Proportion of booked revenue from orders (customer_order_line channel, excluding POS)"
    synonyms: ['order_revenue_share', 'ecommerce_revenue_share', 'order_channel_pct']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2
$$;
