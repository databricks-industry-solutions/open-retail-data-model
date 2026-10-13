-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- Metric View: incrementality
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-07-14
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-14
-- ============================================================
-- Semantic layer over incrementality_result: causal lift / iROAS readout by
-- experiment, metric, and analysis slice, for Genie and AI/BI. Suppressed
-- (below-threshold / policy) results are excluded; no person-level data
-- (statistical output only).
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${cmn_schema}.mv_incrementality
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Retail-media incrementality readout (incremental sales/margin, lift, iROAS, significance) by experiment, metric, and analysis slice."
source: >
  SELECT
    r.experiment_id,
    e.experiment_name,
    r.campaign_id,
    r.metric_name,
    r.analysis_level,
    r.incremental_sales_amount,
    r.incremental_margin_amount,
    r.media_spend_amount,
    r.lift_pct,
    r.iroas_value,
    r.statistical_significance_flag
  FROM ${catalog}.${cmn_schema}.incrementality_result r
  LEFT JOIN ${catalog}.${cmn_schema}.experiment e
    ON e.experiment_id = r.experiment_id AND e.is_current = TRUE
  WHERE COALESCE(r.suppressed_flag, FALSE) = FALSE

fields:
  - name: experiment_id
    expr: experiment_id
    display_name: "Experiment ID"
    comment: "Durable experiment business key."
    synonyms: ["experiment", "test"]

  - name: experiment_name
    expr: experiment_name
    display_name: "Experiment Name"
    comment: "Experiment display name."
    synonyms: ["test_name"]

  - name: campaign_id
    expr: campaign_id
    display_name: "Campaign ID"
    comment: "Durable campaign business key under test."
    synonyms: ["campaign"]

  - name: metric_name
    expr: metric_name
    display_name: "Metric"
    comment: "Metric evaluated (incremental_sales, incremental_units, roas, conversion_rate, reach)."
    synonyms: ["kpi", "measure_name"]

  - name: analysis_level
    expr: analysis_level
    display_name: "Analysis Level"
    comment: "Slice level of the result (overall, store, geo, product, category, vendor)."
    synonyms: ["slice", "granularity"]

measures:
  - name: incremental_sales
    expr: SUM(incremental_sales_amount)
    display_name: "Incremental Sales"
    comment: "Sum of incremental sales, reporting/base currency."
    synonyms: ["causal_sales", "lift_sales"]

  - name: incremental_margin
    expr: SUM(incremental_margin_amount)
    display_name: "Incremental Margin"
    comment: "Sum of incremental margin, reporting/base currency."
    synonyms: ["causal_margin"]

  - name: media_spend
    expr: SUM(media_spend_amount)
    display_name: "Media Spend"
    comment: "Media spend attributed to the treatment."
    synonyms: ["spend", "treatment_spend"]

  - name: avg_lift_pct
    expr: AVG(lift_pct)
    display_name: "Avg Lift %"
    comment: "Average relative lift of treatment over control, percent."
    synonyms: ["mean_lift", "lift"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: avg_iroas
    expr: AVG(iroas_value)
    display_name: "Avg iROAS"
    comment: "Average incremental ROAS across results."
    synonyms: ["incremental_roas", "mean_iroas"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: significant_results
    expr: COUNT(*) FILTER (WHERE statistical_significance_flag = TRUE)
    display_name: "Significant Results"
    comment: "Number of results that are statistically significant at their confidence level."
    synonyms: ["sig_count"]

  - name: result_count
    expr: COUNT(*)
    display_name: "Results"
    comment: "Number of (non-suppressed) incrementality results."
    synonyms: ["n_results", "readout_count"]
$$;
