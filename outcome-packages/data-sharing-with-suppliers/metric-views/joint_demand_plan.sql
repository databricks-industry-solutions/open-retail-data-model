-- ============================================================
-- ORDM · Outcome Package · Data Sharing with Suppliers
-- Metric View: joint_demand_plan
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-08-01
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-01
-- ============================================================
-- Semantic layer over gold_joint_demand_plan: the entitled, threshold-suppressed
-- CPFR joint demand plan a retailer and supplier consume together (supplier ×
-- product × fiscal week, no person-level data). Genie / AI-BI ready. Entitlement is
-- applied by the underlying gold view's row filter; this view adds the semantic
-- measure definitions (consensus demand, party disagreement, consensus lift over
-- the statistical baseline).
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${dss_schema}.mv_joint_demand_plan
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Entitled joint demand-planning KPIs (consensus demand, party plans, disagreement, consensus lift over statistical baseline) by supplier, product and fiscal week."
source: >
  SELECT
    principal_id,
    supplier_id,
    product_id,
    fiscal_week_id,
    retailer_qty,
    supplier_qty,
    consensus_qty,
    consensus_value_net,
    statistical_forecast_qty
  FROM ${catalog}.${dss_schema}.gold_joint_demand_plan

fields:
  - name: principal_id
    expr: principal_id
    display_name: "Principal ID"
    comment: "Governance principal entitled to the row. gold_joint_demand_plan emits one row PER entitled principal, so a deploy-time row filter narrows this to the querying group; if two principals are entitled to the same supplier x product x week, aggregating WITHOUT filtering on principal_id would double-count the shared demand. Always scope by principal (the row filter) before summing."
    synonyms: ["principal", "partner_group"]
  - name: supplier_id
    expr: supplier_id
    display_name: "Supplier ID"
    comment: "Durable supplier business key."
    synonyms: ["supplier", "vendor"]
  - name: product_id
    expr: product_id
    display_name: "Product ID"
    comment: "Durable product business key."
    synonyms: ["product", "sku"]
  - name: fiscal_week_id
    expr: fiscal_week_id
    display_name: "Fiscal Week"
    comment: "Fiscal week identifier = fiscal_year * 100 + fiscal_week."
    synonyms: ["week", "fiscal_week"]

measures:
  - name: consensus_qty
    expr: SUM(consensus_qty)
    display_name: "Consensus Demand (Units)"
    comment: "Total agreed consensus demand quantity."
    synonyms: ["consensus_demand", "agreed_units", "joint_forecast"]
  - name: consensus_value_net
    expr: SUM(consensus_value_net)
    display_name: "Consensus Demand (Value)"
    comment: "Total agreed consensus net value, reporting/base currency."
    synonyms: ["consensus_value", "agreed_value"]
  - name: retailer_qty
    expr: SUM(retailer_qty)
    display_name: "Retailer Plan (Units)"
    comment: "Total latest retailer-submitted demand quantity."
    synonyms: ["retailer_forecast", "buyer_plan"]
  - name: supplier_qty
    expr: SUM(supplier_qty)
    display_name: "Supplier Plan (Units)"
    comment: "Total latest supplier-submitted demand quantity."
    synonyms: ["supplier_forecast", "vendor_plan"]
  - name: statistical_forecast_qty
    expr: SUM(statistical_forecast_qty)
    display_name: "Statistical Baseline (Units)"
    comment: "Total statistical demand baseline from the Smarter Demand package (NULL if absent)."
    synonyms: ["baseline_forecast", "stat_forecast"]
  - name: plan_disagreement_pct
    expr: (SUM(retailer_qty) - SUM(supplier_qty)) / NULLIF(SUM(supplier_qty), 0)
    display_name: "Plan Disagreement %"
    comment: "Retailer-vs-supplier disagreement = (retailer_qty - supplier_qty) / supplier_qty."
    synonyms: ["party_variance", "plan_gap"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 4
  - name: consensus_lift_pct
    expr: (SUM(consensus_qty) - SUM(statistical_forecast_qty)) / NULLIF(SUM(statistical_forecast_qty), 0)
    display_name: "Consensus Lift over Baseline %"
    comment: "Collaboration value: consensus demand lift over the statistical baseline = (consensus_qty - statistical_forecast_qty) / statistical_forecast_qty."
    synonyms: ["collaboration_lift", "consensus_uplift"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 4
$$;
