-- ============================================================
-- ORDM · Outcome Package · Actionable Customer Understanding
-- Metric View: customer_lifetime_value
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-10-12
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-10-12
-- ============================================================
-- Semantic layer over gold_customer_ltv, one row per customer: historical and
-- predicted CLV, monetary value per order, purchase frequency and recency, and the
-- churn-risk share, sliced by value tier and RFM cell. The definitions are the ACU
-- glossary's (CLV historical / predicted, RFM, value tier). This view serves the
-- Customer Lifetime Value use case of unified-customer-view, which maps to
-- gold_customer_ltv across packages; it lives here, next to the gold view it reads,
-- so it adds no new cross-package deploy dependency.
--
-- avg_order_value is SUM(total_spend) / SUM(frequency), spend per order across the
-- selected customers, never an average of per-customer averages. No person-level
-- field: profile_id is not a dimension.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${acu_schema}.mv_customer_lifetime_value
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Customer lifetime value KPIs: historical and predicted CLV, spend per order, purchase frequency and recency, and churn-risk share, by value tier and RFM cell."
source: >
  SELECT
    ltv.value_tier,
    ltv.rfm_score,
    ltv.r_score,
    ltv.f_score,
    ltv.m_score,
    ltv.churn_risk_proxy,
    ltv.recency_periods,
    ltv.frequency,
    ltv.total_spend,
    ltv.historical_clv,
    ltv.predicted_clv
  FROM ${catalog}.${acu_schema}.gold_customer_ltv ltv

fields:
  - name: value_tier
    expr: value_tier
    display_name: "Value Tier"
    comment: "historical_clv bucketed on stable fixed thresholds: PLATINUM >= 2500 / GOLD >= 1000 / SILVER >= 250 / BRONZE else."
    synonyms: ["tier", "customer_value_tier"]
  - name: rfm_score
    expr: rfm_score
    display_name: "RFM Cell"
    comment: "Combined RFM cell = 100*R + 10*F + M (111..555), each score from stable fixed thresholds."
    synonyms: ["rfm", "rfm_cell"]
  - name: r_score
    expr: r_score
    display_name: "Recency Score"
    comment: "Recency score 1-5 (5 = most recent)."
    synonyms: ["recency_score"]
  - name: f_score
    expr: f_score
    display_name: "Frequency Score"
    comment: "Frequency score 1-5 (5 = most frequent)."
    synonyms: ["frequency_score"]
  - name: m_score
    expr: m_score
    display_name: "Monetary Score"
    comment: "Monetary score 1-5 (5 = highest spend)."
    synonyms: ["monetary_score"]
  - name: churn_risk_proxy
    expr: churn_risk_proxy
    display_name: "Churn Risk"
    comment: "Heuristic flag: recency exceeds 2x the customer's typical purchase cadence (tenure / frequency)."
    synonyms: ["at_risk", "churn_flag"]

measures:
  - name: customer_count
    expr: COUNT(*)
    display_name: "Customers"
    comment: "Count of customers with a lifetime-value record."
    synonyms: ["clv_customers", "customers_with_clv"]
  - name: total_historical_clv
    expr: SUM(historical_clv)
    display_name: "Historical CLV (Total)"
    comment: "Total realized gross margin to date, SUM(net_amount - units x unit_cost), reporting/base currency; can be negative (a real loss)."
    synonyms: ["realized_clv", "lifetime_margin"]
  - name: avg_historical_clv
    expr: AVG(historical_clv)
    display_name: "Historical CLV (Avg per Customer)"
    comment: "Mean realized gross margin to date per customer, reporting/base currency."
    synonyms: ["avg_clv", "clv_per_customer"]
  - name: total_predicted_clv
    expr: SUM(predicted_clv)
    display_name: "Predicted CLV (Total)"
    comment: "Total transparent forward estimate (not an ML model): avg_order_margin x frequency_per_period x expected_active_periods, clamped >= 0 per customer, reporting/base currency."
    synonyms: ["forward_clv", "expected_value"]
  - name: avg_predicted_clv
    expr: AVG(predicted_clv)
    display_name: "Predicted CLV (Avg per Customer)"
    comment: "Mean predicted CLV per customer, reporting/base currency."
    synonyms: ["avg_forward_clv"]
  - name: total_spend
    expr: SUM(total_spend)
    display_name: "Total Spend"
    comment: "Total net spend in the observation window, reporting/base currency."
    synonyms: ["lifetime_spend", "net_spend"]
  - name: avg_order_value
    expr: SUM(total_spend) / NULLIF(SUM(frequency), 0)
    display_name: "Avg Order Value"
    comment: "Net spend per order across the selected customers = SUM(total_spend) / SUM(frequency), a ratio-of-sums, reporting/base currency."
    synonyms: ["aov", "spend_per_order"]
  - name: avg_frequency
    expr: AVG(frequency)
    display_name: "Avg Purchase Frequency"
    comment: "Mean distinct purchase occasions (orders) per customer in the observation window."
    synonyms: ["orders_per_customer", "frequency"]
  - name: avg_recency_periods
    expr: AVG(recency_periods)
    display_name: "Avg Recency (Fiscal Periods)"
    comment: "Mean fiscal periods (NRF 4-5-4) since each customer's last order."
    synonyms: ["avg_recency", "periods_since_last_order"]
  - name: churn_risk_rate
    expr: AVG(CASE WHEN churn_risk_proxy THEN 1.0 ELSE 0 END)
    display_name: "Churn Risk Rate"
    comment: "Share of customers flagged by the churn-risk heuristic."
    synonyms: ["at_risk_share", "churn_risk_share"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
$$;
