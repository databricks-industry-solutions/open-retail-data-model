-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- View: gold_incrementality_readout
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral).
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- Experiment readout: the latest incrementality result per experiment × metric ×
-- analysis slice, with lift, iROAS, confidence interval, and significance, joined
-- to the experiment/campaign/advertiser dimensions. Suppressed rows excluded.
-- No person-level data (statistical output).
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${cmn_schema}.gold_incrementality_readout AS
WITH latest AS (
  SELECT
    r.*,
    ROW_NUMBER() OVER (
      PARTITION BY r.experiment_id, r.metric_name, r.analysis_level, r.product_id
      ORDER BY r.snapshot_date DESC
    ) AS rn
  FROM ${catalog}.${cmn_schema}.incrementality_result r
  WHERE COALESCE(r.suppressed_flag, FALSE) = FALSE
)
SELECT
  l.experiment_id,
  e.experiment_name,
  e.methodology,
  l.campaign_id,
  c.campaign_name,
  l.advertiser_id,
  l.product_id,
  l.snapshot_date,
  l.metric_name,
  l.analysis_level,
  l.incremental_sales_amount,
  l.incremental_margin_amount,
  l.media_spend_amount,
  l.lift_pct,
  l.iroas_value,
  l.confidence_level_pct,
  l.ci_lower_value,
  l.ci_upper_value,
  l.p_value,
  l.statistical_significance_flag,
  l.sample_size_treatment,
  l.sample_size_control,
  current_timestamp() AS fresh_as_of_ts
FROM latest l
LEFT JOIN ${catalog}.${cmn_schema}.experiment e
  ON e.experiment_id = l.experiment_id AND e.is_current = TRUE
LEFT JOIN ${catalog}.${cmn_schema}.campaign c
  ON c.campaign_id = l.campaign_id AND c.is_current = TRUE
WHERE l.rn = 1;
