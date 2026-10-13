-- ============================================================
-- ORDM · Outcome Package · Promote with Purpose
-- Metric View: promo_roi
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-08-10
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-10 by @a0x8o
-- ============================================================
-- Post-Promotion ROI by promotion: incremental units and margin against trade
-- spend, with the two value-killers (cannibalization, forward buy) kept visible
-- alongside the headline result.
--
-- roi is a RATIO OF SUMS — SUM(incremental_margin) / SUM(trade_spend) — never an
-- average of the per-promotion roi already on the gold view, which would weight a
-- $1k promo the same as a $1m one.
--
-- gold_promo_roi is already one row per promotion and carries no _sk, so no SCD2
-- resolution is required here; every dimension is a durable business key.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${promo_schema}.mv_promo_roi
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Post-promotion ROI by promotion: incremental margin against trade spend, with cannibalization and forward-buy drag."
source: >
  SELECT
    promo_id,
    promo_name,
    promo_type,
    funding_type,
    funded_by,
    incremental_units,
    incremental_revenue,
    incremental_margin,
    trade_spend,
    cannibalization_margin,
    forward_buy_margin,
    net_incremental_margin
  FROM ${catalog}.${promo_schema}.gold_promo_roi

fields:
  - name: promo_id
    expr: promo_id
    display_name: "Promotion ID"
    comment: "Durable business key for the promotion."
    synonyms: ["promotion_id", "deal_id", "promo"]

  - name: promo_name
    expr: promo_name
    display_name: "Promotion Name"
    comment: "Display name of the promotion."
    synonyms: ["promotion_name", "campaign_name", "deal_name"]

  - name: promo_type
    expr: promo_type
    display_name: "Promotion Type"
    comment: "Promotion mechanic (for example TPR, feature, display)."
    synonyms: ["mechanic", "deal_type", "promotion_mechanic"]

  - name: funding_type
    expr: funding_type
    display_name: "Funding Type"
    comment: "How the promotion is funded (for example scan-down, bill-back)."
    synonyms: ["funding_mechanism", "trade_funding", "deal_funding"]

  - name: funded_by
    expr: funded_by
    display_name: "Funded By"
    comment: "Party bearing the trade spend: retailer, supplier or shared."
    synonyms: ["funding_party", "payer", "sponsor"]

measures:
  - name: incremental_units
    expr: SUM(incremental_units)
    display_name: "Incremental Units"
    comment: "Promoted units above the trailing non-promoted baseline. Not clamped: negative means the promotion lost volume."
    synonyms: ["lift_units", "uplift", "incremental_volume"]

  - name: incremental_revenue
    expr: SUM(incremental_revenue)
    display_name: "Incremental Revenue"
    comment: "Revenue above baseline, in the reporting/base currency."
    synonyms: ["lift_revenue", "uplift_revenue", "incremental_sales"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: incremental_margin
    expr: SUM(incremental_margin)
    display_name: "Incremental Margin"
    comment: "Margin above baseline, in the reporting/base currency. Not clamped."
    synonyms: ["lift_margin", "uplift_margin", "incremental_profit"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: trade_spend
    expr: SUM(trade_spend)
    display_name: "Trade Spend"
    comment: "Planned trade spend allocated to the promotion, in the reporting/base currency."
    synonyms: ["promo_spend", "trade_investment", "deal_cost"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: roi
    expr: SUM(incremental_margin) / NULLIF(SUM(trade_spend), 0)
    display_name: "ROI"
    comment: "Incremental margin per unit of trade spend. Ratio of sums, so large and small promotions are weighted by their actual spend."
    synonyms: ["return_on_investment", "return_on_spend", "ROAS"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: cannibalization_margin
    expr: SUM(cannibalization_margin)
    display_name: "Cannibalization Margin"
    comment: "Margin lost on substitute SKUs in the same category during the promotion window."
    synonyms: ["cannibalisation", "substitution_loss", "cannibal_drag"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: forward_buy_margin
    expr: SUM(forward_buy_margin)
    display_name: "Forward Buy Margin"
    comment: "Margin lost on promoted SKUs in the weeks after the promotion (pantry loading)."
    synonyms: ["pantry_loading", "pull_forward", "forward_buy_drag"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: net_incremental_margin
    expr: SUM(net_incremental_margin)
    display_name: "Net Incremental Margin"
    comment: "Incremental margin less cannibalization and forward-buy drag. Negative means the promotion destroyed value."
    synonyms: ["net_margin", "true_lift", "net_profit_impact"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 2
$$;
