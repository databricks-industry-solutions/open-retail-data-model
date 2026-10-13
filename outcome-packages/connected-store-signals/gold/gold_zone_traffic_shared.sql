-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_zone_traffic_shared
-- Layer: outcome package (gold / disclosure-controlled shared)
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-28
-- ============================================================
-- GRAIN: one row per durable store zone × trading_date, for an explicitly shared
-- audience. Suppression is evaluated after canonical intervals have been aggregated
-- to a day. Every traffic-derived measure is NULL together; operational truth remains
-- in gold_zone_traffic_current.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_zone_traffic_shared AS
WITH policy_by_zone_day AS (
  SELECT
    f.store_id,
    f.store_zone_id,
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
    AND f.aggregation_level = 'area'
  GROUP BY f.store_id, f.store_zone_id, f.trading_date
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
  FROM ${catalog}.${css_schema}.gold_zone_traffic_current o
  JOIN policy_by_zone_day p
    ON o.store_id = p.store_id
   AND o.store_zone_id = p.store_zone_id
   AND o.trading_date = p.trading_date
)
SELECT
  store_id,
  store_zone_id,
  zone_code,
  zone_name,
  zone_type,
  parent_zone_id,
  hierarchy_depth,
  is_sales_floor,
  trading_date,
  fiscal_year,
  fiscal_week_id,
  day_of_week,

  CASE WHEN disclosure_suppressed_flag THEN CAST(NULL AS BIGINT)
       ELSE footfall_count END AS footfall_count,
  CASE WHEN disclosure_suppressed_flag THEN CAST(NULL AS BIGINT)
       ELSE entry_count END AS entry_count,
  CASE WHEN disclosure_suppressed_flag THEN CAST(NULL AS BIGINT)
       ELSE exit_count END AS exit_count,
  CASE WHEN disclosure_suppressed_flag THEN CAST(NULL AS BIGINT)
       ELSE passersby_count END AS passersby_count,
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
  CASE WHEN disclosure_suppressed_flag THEN CAST(NULL AS BIGINT)
       ELSE engaged_count END AS engaged_count,
  CASE WHEN disclosure_suppressed_flag THEN CAST(NULL AS BIGINT)
       ELSE passing_count END AS passing_count,
  CASE WHEN disclosure_suppressed_flag THEN CAST(NULL AS DOUBLE)
       ELSE engagement_rate END AS engagement_rate,
  CASE WHEN disclosure_suppressed_flag THEN CAST(NULL AS DOUBLE)
       ELSE footfall_per_sqm END AS footfall_per_sqm,
  CASE WHEN disclosure_suppressed_flag THEN CAST(NULL AS DOUBLE)
       ELSE occupancy_per_sqm END AS occupancy_per_sqm,
  CASE WHEN disclosure_suppressed_flag THEN CAST(NULL AS DOUBLE)
       ELSE peak_capacity_utilisation END AS peak_capacity_utilisation,

  area_sqm,
  capacity_persons,
  counting_unit,
  staff_exclusion_enabled,
  sensing_disclosure_policy_id,
  disclosure_suppressed_flag,
  'area' AS aggregation_level,
  current_timestamp() AS fresh_as_of_ts
FROM governed;
