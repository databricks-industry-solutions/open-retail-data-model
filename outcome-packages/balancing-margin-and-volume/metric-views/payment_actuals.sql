-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- Metric View: payment_actuals
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-10-11
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: pending - BMV owner ack required
-- ============================================================
-- Event-date (cash basis) revenue leakage metrics at product x store x day grain.
-- Exposes settled sales, refunds, chargebacks, and adjustments with normalized rate
-- measures (ratio-of-sums). All amounts are dated by the payment EVENT date
-- (when money was settled/refunded/charged back), not the original sale date.
-- Per-product leakage amounts are allocated by order-revenue-share from the gold table.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${bmv_schema}.mv_payment_actuals
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Payment-side revenue leakage metrics at product x store x day grain. Exposes settled sales, refunds, chargebacks, and adjustments with normalized rate measures (ratio-of-sums). Amounts dated by payment event date (cash basis). Per-product amounts are order-revenue-share allocations."
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
    g.settled_sale_amount_lc,
    g.refund_amount_lc,
    g.chargeback_amount_lc,
    g.adjustment_amount_lc
  FROM ${catalog}.${bmv_schema}.gold_payment_actuals g
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
    comment: "Daily grain; attribution date is payment event date (refunds/chargebacks dated when money settles, not original sale date)"
    synonyms: ['payment_date', 'event_date']

  - name: category
    expr: category
    comment: "Merchandising category"
    synonyms: ['merch_category', 'department']

  - name: store_format
    expr: store_format
    comment: "Store format or classification"
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
  # Goal: Revenue Leakage Analysis
  # ============================================================

  - name: settled_sale_amount_lc
    expr: sum(settled_sale_amount_lc)
    display_name: "Settled Sales (payment date)"
    comment: "Total realized sales revenue from settled/captured payment events (order-grain events allocated to product x store x day via order line weight). This is the base denominator for all leakage rate calculations. Dated by payment event."
    synonyms: ['order_settled_sales', 'settled_order_payments']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: refund_amount_lc
    expr: sum(refund_amount_lc)
    display_name: "Refunds (payment date)"
    comment: "Total refund magnitude (allocated, excluding declined/voided refunds). Contra-revenue representing voluntary customer returns processed as separate refund-typed payment events. Per-product amounts allocated by order-revenue share. Dated by payment event."
    synonyms: ['cash_refunds', 'refunds_by_payment_date']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: refund_rate
    expr: sum(refund_amount_lc) / nullif(sum(settled_sale_amount_lc), 0)
    display_name: "Refund Rate (payment date)"
    comment: "Refund magnitude as a percentage of settled sales (ratio-of-sums: total refunds / total settled sales). No rolling or cohort logic baked in; filter date_key or fiscal_season at query time for period-specific rates. Dated by payment event."
    synonyms: ['refund_pct', 'cash_refund_rate']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: chargeback_amount_lc
    expr: sum(chargeback_amount_lc)
    display_name: "Chargebacks (payment date)"
    comment: "Total chargeback magnitude (allocated, excluding declined/voided). Involuntary reversals initiated by the customer's payment provider (fraud/dispute), kept separate from refunds for root-cause analysis. Per-product amounts allocated by order-revenue share. Dated by payment event."
    synonyms: ['cash_chargebacks', 'chargebacks_by_payment_date', 'involuntary_returns']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: chargeback_rate
    expr: sum(chargeback_amount_lc) / nullif(sum(settled_sale_amount_lc), 0)
    display_name: "Chargeback Rate (payment date)"
    comment: "Chargeback magnitude as a percentage of settled sales (ratio-of-sums). Signals payment fraud or customer dispute risk; distinct from refund_rate for merchant risk assessment. Dated by payment event."
    synonyms: ['dispute_rate', 'chargeback_pct', 'cash_chargeback_rate']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: adjustment_amount_lc
    expr: sum(adjustment_amount_lc)
    display_name: "Adjustments (payment date)"
    comment: "Total adjustment magnitude (allocated, excluding declined/voided). Post-sale goodwill credits, corrections, or disputed-amount settlements; a non-negative magnitude (payment.amount is >= 0 by contract) treated as contra-revenue, as in gold_payment_actuals. Per-product amounts allocated by order-revenue share. Dated by payment event."
    synonyms: ['cash_adjustments', 'adjustments_by_payment_date', 'payment_adjustments']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: adjustment_rate
    expr: sum(adjustment_amount_lc) / nullif(sum(settled_sale_amount_lc), 0)
    display_name: "Adjustment Rate (payment date)"
    comment: "Adjustment magnitude as a percentage of settled sales (ratio-of-sums). Reflects post-sale discretionary credits (loyalty, goodwill, dispute settlement); isolated to measure operational fairness/discounting policy. Dated by payment event."
    synonyms: ['adjustment_pct', 'payment_adjustment_rate']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: total_leakage_amount
    expr: sum(refund_amount_lc) + sum(chargeback_amount_lc) + sum(adjustment_amount_lc)
    display_name: "Payment Reversals (payment date)"
    comment: "Refunds plus chargebacks plus adjustments, dated by the payment event. Excludes order sales that were never captured or settled; mv_realized_margin leakage_lc includes them and is dated by the sale."
    synonyms: ['cash_leakage', 'total_reversals']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: payment_leakage_rate
    expr: (sum(refund_amount_lc) + sum(chargeback_amount_lc) + sum(adjustment_amount_lc)) / nullif(sum(settled_sale_amount_lc), 0)
    display_name: "Payment Reversal Rate (payment date)"
    comment: "Aggregate leakage (all contra-revenue) as a percentage of settled sales (ratio-of-sums). Holistic metric for revenue retention; complement is net realized revenue pct. Dated by payment event."
    synonyms: ['payment_reversal_pct', 'reversal_share_of_settled']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: net_revenue_after_leakage
    expr: sum(settled_sale_amount_lc) - sum(refund_amount_lc) - sum(chargeback_amount_lc) - sum(adjustment_amount_lc)
    display_name: "Settled Sales After Reversals (payment date)"
    comment: "Settled sales less all contra-revenue (refunds, chargebacks, adjustments). True net revenue from the payment perspective (not yet adjusted for cost to yield realized margin). Dated by payment event."
    synonyms: ['net_payment_revenue', 'cash_revenue_after_reversals']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: net_revenue_retention_pct
    expr: (sum(settled_sale_amount_lc) - sum(refund_amount_lc) - sum(chargeback_amount_lc) - sum(adjustment_amount_lc)) / nullif(sum(settled_sale_amount_lc), 0)
    display_name: "Settled Sales Retained % (payment date)"
    comment: "Percentage of settled sales retained after leakage (ratio-of-sums). Complement to payment_leakage_rate; a clean measure of end-to-end payment health. Dated by payment event."
    synonyms: ['revenue_retention_rate', 'net_revenue_pct', 'non_leakage_rate']
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

$$;
