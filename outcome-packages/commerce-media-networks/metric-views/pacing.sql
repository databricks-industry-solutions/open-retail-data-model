-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- Metric View: pacing
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-07-15
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-15
-- ============================================================
-- Semantic layer over gold_pacing_current: current budget-pacing state per campaign
-- (rolled up from the latest pacing snapshot per campaign x ad_group x placement).
-- For campaign-ops / alerting via Genie and AI/BI. No person-level data.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${cmn_schema}.mv_pacing
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Current retail-media budget pacing: daily budget, spend-to-date, pacing ratio, and pacing-status counts by campaign."
source: >
  SELECT
    campaign_id,
    campaign_name,
    ad_group_id,
    placement_id,
    pacing_status,
    daily_budget,
    planned_spend_to_date,
    actual_spend_to_date,
    projected_end_spend,
    pacing_ratio
  FROM ${catalog}.${cmn_schema}.gold_pacing_current

fields:
  - name: campaign_id
    expr: campaign_id
    display_name: "Campaign ID"
    comment: "Durable campaign business key."
    synonyms: ["campaign"]
  - name: campaign_name
    expr: campaign_name
    display_name: "Campaign Name"
    comment: "Campaign display name."
    synonyms: ["campaign_title"]
  - name: pacing_status
    expr: pacing_status
    display_name: "Pacing Status"
    comment: "on_track / under_pacing / over_pacing / exhausted."
    synonyms: ["pace_state", "delivery_status"]

measures:
  - name: total_daily_budget
    expr: SUM(daily_budget)
    display_name: "Daily Budget"
    comment: "Sum of daily budget targets, reporting/base currency."
    synonyms: ["budget", "planned_budget"]
  - name: total_actual_spend
    expr: SUM(actual_spend_to_date)
    display_name: "Actual Spend to Date"
    comment: "Sum of cumulative actual spend, reporting/base currency."
    synonyms: ["spend_to_date", "cumulative_spend"]
  - name: total_projected_end_spend
    expr: SUM(projected_end_spend)
    display_name: "Projected End Spend"
    comment: "Sum of projected end-of-flight spend."
    synonyms: ["forecast_spend"]
  - name: avg_pacing_ratio
    expr: AVG(pacing_ratio)
    display_name: "Avg Pacing Ratio"
    comment: "Average actual/planned spend ratio across pacing lines."
    synonyms: ["pace_index", "mean_pacing"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 2
  - name: over_pacing_lines
    expr: COUNT(*) FILTER (WHERE pacing_status = 'over_pacing')
    display_name: "Over-Pacing Lines"
    comment: "Number of pacing lines currently over-pacing."
    synonyms: ["overspend_count"]
  - name: under_pacing_lines
    expr: COUNT(*) FILTER (WHERE pacing_status = 'under_pacing')
    display_name: "Under-Pacing Lines"
    comment: "Number of pacing lines currently under-pacing."
    synonyms: ["underspend_count"]
  - name: exhausted_lines
    expr: COUNT(*) FILTER (WHERE pacing_status = 'exhausted')
    display_name: "Exhausted Lines"
    comment: "Number of pacing lines whose budget is exhausted."
    synonyms: ["depleted_count"]
  - name: pacing_lines
    expr: COUNT(*)
    display_name: "Pacing Lines"
    comment: "Number of campaign x ad_group x placement pacing lines."
    synonyms: ["line_count"]
$$;
