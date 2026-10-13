-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_zone_traffic_interval_shared
-- Layer: outcome package (gold / disclosure-controlled compatibility)
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-28
-- ============================================================
-- GRAIN: one disclosure-approved canonical area interval.
--
-- This deliberately differs from the daily shared view's NULL-cell contract.
-- The retired CMN interface has no disclosure flag and must retain interval start
-- and duration, so publishing a NULL-measure row would disclose the protected
-- interval through those required metadata columns. Suppressed, invalid, NULL-count,
-- and sub-policy-duration intervals are therefore OMITTED completely.
--
-- Device identity remains lineage only. The release-blocking canonical-overlap
-- check guarantees that one subject/report/level interval cannot be published from
-- both `_ALL` and device-native series.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_zone_traffic_interval_shared AS
WITH admitted_interval AS (
SELECT
  CONCAT_WS(
    '|',
    f.store_id,
    f.store_zone_id,
    CAST(UNIX_TIMESTAMP(f.interval_start_ts) AS STRING),
    CAST(f.interval_minutes AS STRING)
  ) AS shared_zone_traffic_interval_id,
  f.store_sk,
  f.store_id,
  f.store_zone_id,
  z.zone_code,
  f.interval_start_ts,
  f.interval_end_ts,
  f.trading_date,
  f.interval_minutes,
  t.footfall_count,
  t.dwell_seconds_total,
  t.dwell_count,
  t.dwell_seconds_total / NULLIF(t.dwell_count, 0) AS avg_dwell_seconds,
  p.sensing_disclosure_policy_id
FROM ${catalog}.${css_schema}.sensor_report_interval f
JOIN ${catalog}.${css_schema}.foot_traffic_interval_detail t
  ON f.sensor_report_interval_sk = t.sensor_report_interval_sk
JOIN ${catalog}.${css_schema}.store_zone z
  ON f.store_zone_sk = z.store_zone_sk
JOIN ${catalog}.${css_schema}.sensing_deployment d
  ON f.sensing_deployment_sk = d.sensing_deployment_sk
JOIN ${catalog}.${css_schema}.sensing_disclosure_policy p
  ON d.external_disclosure_policy_id = p.sensing_disclosure_policy_id
 AND f.trading_date >= p.effective_from_date
 AND (p.effective_to_date IS NULL OR f.trading_date < p.effective_to_date)
WHERE f.report_type = 'gs1:Count'
  AND f.subject_type = 'space'
  AND f.aggregation_level = 'area'
  AND COALESCE(f.measurement_validity, 'valid') <> 'invalid'
  AND f.interval_minutes >= p.minimum_interval_minutes
  AND t.footfall_count IS NOT NULL
  AND NOT (t.footfall_count = 0 AND p.suppress_zero_flag)
  AND t.footfall_count >= p.k_threshold
)
SELECT
  CAST(XXHASH64(shared_zone_traffic_interval_id) AS BIGINT)
    AS shared_zone_traffic_interval_sk,
  shared_zone_traffic_interval_id,
  store_sk,
  store_id,
  store_zone_id,
  zone_code,
  interval_start_ts,
  interval_end_ts,
  trading_date,
  interval_minutes,
  footfall_count,
  dwell_seconds_total,
  dwell_count,
  avg_dwell_seconds,
  sensing_disclosure_policy_id
FROM admitted_interval;
