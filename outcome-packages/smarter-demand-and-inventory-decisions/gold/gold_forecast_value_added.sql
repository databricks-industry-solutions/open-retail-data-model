-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- View: gold_forecast_value_added
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-22
-- ============================================================
-- Forecast Value Added: matched-lag naive baseline vs statistical model vs planner-
-- enriched forecast, at the SAME period the accuracy row is measured.
--
-- Review finding A11: the prior version (a) filtered to grain_type='store_sku' so
-- FVA was unavailable for rolled-up grains, (b) used a CURRENT-DATE 14-day trailing
-- mean as the naive baseline (leaking today's data into a historical period), and
-- (c) selected the enriched forecast but never differenced it, so the planner value
-- add - FVA's whole point - was not computed. This version:
--   - carries grain_type through (no store_sku filter),
--   - uses a MATCHED-LAG NAIVE baseline: the actual from lag_weeks earlier at the
--     same planning unit (a per-period baseline aligned to the forecast lag, not a
--     current-date mean). This is a random-walk-at-lag naive, NOT a seasonal (e.g.
--     52-week) naive; a true seasonal baseline would offset by the season length,
--     which the accuracy grain here does not carry.
--   - computes BOTH fva_model_vs_naive (statistical model over naive) AND
--     fva_enriched_vs_model (planner enrichment over the model), each as the
--     reduction in absolute percentage error at that period.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${sdi_schema}.gold_forecast_value_added AS
WITH acc AS (
  SELECT
    fa.planning_unit_sk,
    fa.planning_unit_id,
    fa.forecast_date_key,
    fa.actual_quantity,
    fa.forecast_quantity,
    fa.effective_forecast_quantity,
    fa.lag_weeks
  FROM ${catalog}.${sdi_schema}.forecast_accuracy fa
),
matched_lag_naive AS (
  -- baseline = actual from lag_weeks before the measured period (same planning unit)
  SELECT
    a.planning_unit_sk,
    a.forecast_date_key,
    prior.actual_quantity AS naive_forecast
  FROM acc a
  LEFT JOIN acc prior
    ON prior.planning_unit_sk = a.planning_unit_sk
   AND prior.forecast_date_key = DATE_SUB(a.forecast_date_key, a.lag_weeks * 7)
)
SELECT
  a.planning_unit_sk,
  a.planning_unit_id,
  pu.grain_type,
  a.forecast_date_key,
  a.forecast_quantity AS model_forecast,
  sn.naive_forecast,
  a.effective_forecast_quantity AS enriched_forecast,
  a.actual_quantity,
  -- FVA of the statistical model over the matched-lag naive baseline (APE reduction)
  CASE
    WHEN a.actual_quantity > 0 AND sn.naive_forecast IS NOT NULL THEN
      (1 - ABS(a.actual_quantity - a.forecast_quantity) / a.actual_quantity)
      - (1 - ABS(a.actual_quantity - sn.naive_forecast) / a.actual_quantity)
    ELSE NULL
  END AS fva_model_vs_naive,
  -- FVA of the planner-enriched forecast over the statistical model (APE reduction)
  CASE
    WHEN a.actual_quantity > 0 AND a.effective_forecast_quantity IS NOT NULL THEN
      (1 - ABS(a.actual_quantity - a.effective_forecast_quantity) / a.actual_quantity)
      - (1 - ABS(a.actual_quantity - a.forecast_quantity) / a.actual_quantity)
    ELSE NULL
  END AS fva_enriched_vs_model
FROM acc a
JOIN ${catalog}.${sdi_schema}.planning_unit pu ON pu.planning_unit_sk = a.planning_unit_sk
LEFT JOIN matched_lag_naive sn
  ON sn.planning_unit_sk = a.planning_unit_sk
 AND sn.forecast_date_key = a.forecast_date_key;
