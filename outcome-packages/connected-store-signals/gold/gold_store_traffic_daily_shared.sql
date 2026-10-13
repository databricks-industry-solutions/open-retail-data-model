-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_store_traffic_daily_shared
-- Layer: outcome package (gold / disclosure-controlled shared)
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-28
-- ============================================================
-- GRAIN: one row per store × trading_date, for an explicitly shared audience.
--
-- Suppression is evaluated after canonical intervals have been aggregated to a day,
-- which is coarser than the configured minimum window. Every traffic-derived measure
-- is NULL together. Operational truth remains in gold_store_traffic_daily_current.
--
-- Prior-year values, quality numerators, observed-zero flags, and interval counts are
-- deliberately absent because they can narrow or reconstruct a suppressed cell.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_store_traffic_daily_shared AS
WITH policy_by_store_day AS (
  SELECT
    f.store_id,
    f.trading_date,
    MIN(p.sensing_disclosure_policy_id) AS sensing_disclosure_policy_id,
    MIN(p.k_threshold) AS k_threshold,
    MIN(CAST(p.suppress_zero_flag AS INT)) = 1 AS suppress_zero_flag,
    MIN(p.minimum_interval_minutes) AS minimum_interval_minutes
  FROM ${catalog}.${css_schema}.sensor_report_interval f
  JOIN ${catalog}.${css_schema}.sensing_deployment d
    ON f.sensing_deployment_sk = d.sensing_deployment_sk
  JOIN ${catalog}.${css_schema}.sensing_disclosure_policy p
    ON d.external_disclosure_policy_id = p.sensing_disclosure_policy_id
   AND f.trading_date >= p.effective_from_date
   AND (p.effective_to_date IS NULL OR f.trading_date < p.effective_to_date)
  WHERE f.report_type = 'gs1:Count'
    AND f.subject_type = 'space'
    AND f.aggregation_level = 'site'
  GROUP BY f.store_id, f.trading_date
  HAVING MIN(p.sensing_disclosure_policy_sk) = MAX(p.sensing_disclosure_policy_sk)
),
governed AS (
  SELECT
    o.*,
    p.sensing_disclosure_policy_id,
    p.minimum_interval_minutes,
    CASE
      WHEN o.interval_minutes_total < p.minimum_interval_minutes THEN TRUE
      WHEN o.footfall_count = 0 AND p.suppress_zero_flag THEN TRUE
      WHEN o.footfall_count < p.k_threshold THEN TRUE
      ELSE FALSE
    END AS disclosure_suppressed_flag
  FROM ${catalog}.${css_schema}.gold_store_traffic_daily_current o
  JOIN policy_by_store_day p
    ON o.store_id = p.store_id
   AND o.trading_date = p.trading_date
)
SELECT
  store_id,
  trading_date,
  fiscal_year,
  fiscal_period,
  fiscal_week,
  fiscal_week_id,
  fiscal_week_index,
  day_of_week,
  is_holiday,

  CASE WHEN disclosure_suppressed_flag THEN CAST(NULL AS BIGINT)
       ELSE footfall_count END AS footfall_count,
  CASE WHEN disclosure_suppressed_flag THEN CAST(NULL AS BIGINT)
       ELSE entry_count END AS entry_count,
  CASE WHEN disclosure_suppressed_flag THEN CAST(NULL AS BIGINT)
       ELSE exit_count END AS exit_count,
  CASE WHEN disclosure_suppressed_flag THEN CAST(NULL AS BIGINT)
       ELSE peak_occupancy END AS peak_occupancy,
  CASE WHEN disclosure_suppressed_flag THEN CAST(NULL AS DOUBLE)
       ELSE avg_occupancy END AS avg_occupancy,
  CASE WHEN disclosure_suppressed_flag THEN CAST(NULL AS BIGINT)
       ELSE dwell_seconds_total END AS dwell_seconds_total,
  CASE WHEN disclosure_suppressed_flag THEN CAST(NULL AS BIGINT)
       ELSE dwell_count END AS dwell_count,
  CASE WHEN disclosure_suppressed_flag THEN CAST(NULL AS DOUBLE)
       ELSE avg_dwell_seconds END AS avg_dwell_seconds,

  counting_unit,
  staff_exclusion_enabled,
  group_counting_enabled,
  time_mode,
  sensing_disclosure_policy_id,
  disclosure_suppressed_flag,
  'site' AS aggregation_level,
  current_timestamp() AS fresh_as_of_ts
FROM governed;
