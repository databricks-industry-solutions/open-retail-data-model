-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_css_device_health
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Ideal Lakebase serving projection.
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-28
-- ============================================================
-- GRAIN: one row per device × report_type × aggregation_level × trading_date.
--
-- report_type and aggregation_level ARE PART OF THE GRAIN, not an afterthought. The fact
-- carries one row per (subject, report_type, aggregation_level, interval), so a single
-- entrance counter emits BOTH an `area` row and the store's `site` row for the same
-- interval. Grouping by device and date alone therefore counted every entrance counter --
-- the most important device in the estate -- twice, inflating intervals_reported,
-- observations_expected/received and so the headline missing_observation_rate, and
-- corrupting source-message summaries. A dual-purpose device reporting both a count and a
-- temperature would have been conflated the same way.
-- Carrying both discriminators in the GROUP BY keeps every ratio over a coherent
-- denominator; sri_device_health_grain asserts it.
--
-- ONE VIEW, dimensioned by device_type, replacing what an earlier design had as four
-- near-identical views (traffic feed freshness, sensor fleet health, RFID feed
-- freshness, ESL fleet health) -- all computing online %, battery, feed age, latency and
-- missing-rate over sensor_device plus the latest event per table. ORDM already has this
-- idiom: early-risk-detection/metric-views/feed_freshness.sql UNION-ALLs three sources
-- into ONE metric view with fresh|delayed|stale thresholds.
--
-- The consequence that matters for scope: IoT, RFID and Smart Shelf add ROWS to this
-- view, not new views. That is decision 0.3 of the design note in practice.
--
-- Includes the checks a sensing estate actually fails on, which generic freshness
-- monitoring misses: interval-level source-message gaps, session discontinuity,
-- calibration expiry, and BACnet Out_Of_Service.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_css_device_health AS
WITH device_day AS (
  SELECT
    f.sensor_device_id,
    -- The version-in-effect surrogate, carried so the attributes below resolve AS OF the
    -- measurement (§A.16). It is grouped ALONGSIDE trading_date, never alone: grouping on
    -- an SCD2 _sk with no date key fragments a re-versioned entity. A device re-versioned
    -- mid-day therefore yields two rows for that day — which is the correct answer when
    -- the thing you are investigating is a firmware-driven step change in counting.
    f.sensor_device_sk,
    f.sensing_deployment_sk,
    f.trading_date,
    f.report_type,
    f.aggregation_level,
    COUNT(*)                              AS intervals_reported,
    SUM(f.expected_observation_count)     AS observations_expected,
    SUM(f.source_observation_count)       AS observations_received,
    SUM(f.source_message_count)           AS source_message_count,
    AVG(f.uptime_ratio)                   AS avg_uptime_ratio,
    AVG(f.coverage_ratio)                 AS avg_coverage_ratio,
    MAX(f.latency_seconds)                AS max_latency_seconds,
    AVG(f.latency_seconds)                AS avg_latency_seconds,
    MAX(f.interval_end_ts)                AS last_interval_end_ts,
    MAX(f.ingest_timestamp)               AS last_ingest_ts,
    SUM(CASE WHEN f.measurement_validity = 'valid'   THEN 1 ELSE 0 END) AS valid_intervals,
    SUM(CASE WHEN f.measurement_validity = 'invalid' THEN 1 ELSE 0 END) AS invalid_intervals,
    SUM(CASE WHEN f.is_imputed            THEN 1 ELSE 0 END) AS imputed_intervals,
    SUM(CASE WHEN t.is_zero_observed      THEN 1 ELSE 0 END) AS observed_zero_intervals,
    SUM(CASE WHEN f.is_capped             THEN 1 ELSE 0 END) AS capped_intervals,
    SUM(CASE WHEN f.arrival_completeness = 'late_arrived' THEN 1 ELSE 0 END) AS late_arrived_intervals,
    SUM(f.historical_message_count)       AS historical_message_count,
    SUM(f.bad_quality_message_count)      AS bad_quality_message_count,
    SUM(f.sequence_gap_count)             AS sequence_gap_count,
    SUM(f.duplicate_delivery_count)       AS duplicate_delivery_count,
    COUNT(DISTINCT f.source_session_id)   AS session_count,
    MAX(f.restatement_version)            AS max_restatement_version
  FROM ${catalog}.${css_schema}.sensor_report_interval f
  LEFT JOIN ${catalog}.${css_schema}.foot_traffic_interval_detail t
    ON f.sensor_report_interval_sk = t.sensor_report_interval_sk
  WHERE f.sensor_device_id <> '_ALL'
  GROUP BY f.sensor_device_id, f.sensor_device_sk, f.sensing_deployment_sk,
           f.trading_date, f.report_type, f.aggregation_level
),
rfid_event_day AS (
  SELECT
    e.sensor_device_id,
    e.sensor_device_sk,
    e.sensing_deployment_sk,
    e.trading_date,
    COUNT(*) AS events_reported,
    SUM(e.read_count) AS source_message_count,
    SUM(COALESCE(e.duplicate_delivery_count, 0)) AS duplicate_delivery_count,
    SUM(CASE WHEN e.is_stray_suspect THEN 1 ELSE 0 END) AS stray_events,
    SUM(CASE WHEN timestampdiff(SECOND, e.event_ts, e.ingest_timestamp) > 3600
             THEN 1 ELSE 0 END) AS late_events,
    SUM(CASE WHEN timestampdiff(SECOND, e.event_ts, e.ingest_timestamp) > 86400
             THEN 1 ELSE 0 END) AS historical_events,
    COUNT(DISTINCT e.rfid_count_session_id) AS session_count,
    MAX(e.event_ts) AS last_event_ts,
    MAX(e.ingest_timestamp) AS last_ingest_ts,
    AVG(timestampdiff(SECOND, e.event_ts, e.ingest_timestamp)) AS avg_latency_seconds,
    MAX(timestampdiff(SECOND, e.event_ts, e.ingest_timestamp)) AS max_latency_seconds
  FROM ${catalog}.${css_schema}.rfid_read_event e
  GROUP BY e.sensor_device_id, e.sensor_device_sk, e.sensing_deployment_sk,
           e.trading_date
),
rfid_reader_day AS (
  -- Seed every current registered reader for today so a silent reader remains visible.
  -- UNION (rather than UNION ALL) collapses the seed when the reader has events today.
  SELECT
    e.sensor_device_id,
    e.sensor_device_sk,
    e.sensing_deployment_sk,
    e.trading_date
  FROM rfid_event_day e
  UNION
  SELECT
    d.sensor_device_id,
    d.sensor_device_sk,
    d.sensing_deployment_sk,
    current_date() AS trading_date
  FROM ${catalog}.${css_schema}.sensor_device d
  WHERE d.is_current = TRUE
    AND d.device_type = 'rfid_reader'
    AND COALESCE(d.device_status, 'active') <> 'decommissioned'
),
rfid_device_day AS (
  SELECT
    d.sensor_device_id,
    d.sensor_device_sk,
    d.sensing_deployment_sk,
    d.trading_date,
    COALESCE(e.events_reported, 0) AS events_reported,
    COALESCE(e.source_message_count, 0) AS source_message_count,
    COALESCE(e.duplicate_delivery_count, 0) AS duplicate_delivery_count,
    COALESCE(e.stray_events, 0) AS stray_events,
    COALESCE(e.late_events, 0) AS late_events,
    COALESCE(e.historical_events, 0) AS historical_events,
    COALESCE(e.session_count, 0) AS session_count,
    e.last_event_ts,
    e.last_ingest_ts,
    e.avg_latency_seconds,
    e.max_latency_seconds
  FROM rfid_reader_day d
  LEFT JOIN rfid_event_day e
    ON d.sensor_device_sk = e.sensor_device_sk
   AND d.trading_date = e.trading_date
),
-- ---- Smart Shelf: ESL ack health, aggregated under the GATEWAY device. Labels are
-- endpoints below a gateway, not sensor_device rows, and they never impersonate
-- devices in fleet health. Distinct labels acked is projected as observations_received;
-- label-level match state lives in gold_price_accuracy_current. The gateway resolves
-- through the version-pinned
-- esl_label _sk the price observation captured (§A.16).
esl_ack_day AS (
  SELECT
    l.sensor_device_sk,
    o.trading_date,
    COUNT(*) AS acks_reported,
    COUNT(DISTINCT o.esl_label_id) AS labels_acked,
    SUM(CASE WHEN timestampdiff(MINUTE, o.observed_at_ts, o.ingest_timestamp) > 360
             THEN 1 ELSE 0 END) AS late_acks,
    SUM(CASE WHEN timestampdiff(MINUTE, o.observed_at_ts, o.ingest_timestamp) > 1440
             THEN 1 ELSE 0 END) AS historical_acks,
    MAX(o.observed_at_ts) AS last_event_ts,
    MAX(o.ingest_timestamp) AS last_ingest_ts,
    AVG(timestampdiff(SECOND, o.observed_at_ts, o.ingest_timestamp)) AS avg_latency_seconds,
    MAX(timestampdiff(SECOND, o.observed_at_ts, o.ingest_timestamp)) AS max_latency_seconds
  FROM ${catalog}.${css_schema}.esl_price_observation o
  JOIN ${catalog}.${css_schema}.esl_label l
    ON o.esl_label_sk = l.esl_label_sk
  WHERE o.observation_source = 'platform_ack'
  GROUP BY l.sensor_device_sk, o.trading_date
),
esl_gateway_day AS (
  -- Seed every current registered gateway for today so a silent gateway stays visible
  -- (the rfid_reader_day idiom; UNION collapses the seed when the gateway acked today).
  SELECT e.sensor_device_sk, e.trading_date
  FROM esl_ack_day e
  UNION
  SELECT d.sensor_device_sk, current_date() AS trading_date
  FROM ${catalog}.${css_schema}.sensor_device d
  WHERE d.is_current = TRUE
    AND d.device_type = 'esl_gateway'
    AND COALESCE(d.device_status, 'active') <> 'decommissioned'
),
esl_device_day AS (
  SELECT
    g.sensor_device_sk,
    g.trading_date,
    COALESCE(e.acks_reported, 0) AS acks_reported,
    COALESCE(e.labels_acked, 0) AS labels_acked,
    COALESCE(e.late_acks, 0) AS late_acks,
    COALESCE(e.historical_acks, 0) AS historical_acks,
    e.last_event_ts,
    e.last_ingest_ts,
    e.avg_latency_seconds,
    e.max_latency_seconds
  FROM esl_gateway_day g
  LEFT JOIN esl_ack_day e
    ON g.sensor_device_sk = e.sensor_device_sk
   AND g.trading_date = e.trading_date
)
SELECT
  d.store_id,
  d.device_type,
  CAST(dd.trading_date AS DATE) AS trading_date,
  dd.report_type,
  dd.aggregation_level,

  d.sensor_device_id,
  -- The version key is PROJECTED, not just grouped on. A consumer needs it to join SCD2
  -- attributes as-of under §A.16, and css_device_health_grain needs it to assert the grain
  -- on the real version key rather than on firmware_version — which is a descriptive
  -- attribute, so a device re-versioned for a calibration renewal would fail that check
  -- while a genuine duplicate sharing a firmware string would slip past it.
  CAST(dd.sensor_device_sk AS BIGINT) AS sensor_device_sk,
  d.sensing_technology,
  d.device_status,
  d.store_zone_id,
  d.manufacturer,
  d.model,
  d.firmware_version,
  d.battery_powered,

  CAST(dd.intervals_reported AS BIGINT) AS intervals_reported,
  dd.observations_expected,
  CAST(dd.observations_received AS BIGINT) AS observations_received,

  -- Missing-observation rate, the primary fleet KPI.
  1 - (dd.observations_received / NULLIF(dd.observations_expected, 0)) AS missing_observation_rate,

  dd.avg_uptime_ratio,
  dd.avg_coverage_ratio,
  CAST(dd.valid_intervals AS BIGINT) AS valid_intervals,
  CAST(dd.valid_intervals / NULLIF(dd.intervals_reported, 0) AS DOUBLE) AS valid_interval_share,
  dd.invalid_intervals,
  dd.imputed_intervals,
  dd.observed_zero_intervals,
  dd.capped_intervals,
  CAST(dd.late_arrived_intervals AS BIGINT) AS late_arrived_intervals,
  CAST(dd.historical_message_count AS BIGINT) AS historical_message_count,
  dd.bad_quality_message_count,
  dd.max_restatement_version,

  -- Feed age and freshness banding, following the fresh|delayed|stale idiom already
  -- established by early-risk-detection/metric-views/feed_freshness.sql.
  CAST(dd.last_interval_end_ts AS TIMESTAMP) AS last_interval_end_ts,
  CAST(dd.last_ingest_ts AS TIMESTAMP) AS last_ingest_ts,
  CAST(dd.avg_latency_seconds AS DOUBLE) AS avg_latency_seconds,
  CAST(dd.max_latency_seconds AS BIGINT) AS max_latency_seconds,
  timestampdiff(MINUTE, dd.last_ingest_ts, current_timestamp()) AS feed_age_minutes,
  CASE
    WHEN timestampdiff(MINUTE, dd.last_ingest_ts, current_timestamp()) <= 60  THEN 'fresh'
    WHEN timestampdiff(MINUTE, dd.last_ingest_ts, current_timestamp()) <= 360 THEN 'delayed'
    ELSE 'stale'
  END AS feed_freshness_status,

  -- Session integrity. A reboot mid-day and a seq gap are different faults with
  -- different causes, so they are reported separately rather than rolled into one score.
  dd.session_count,
  dd.session_count > 1 AS had_session_restart,
  CAST(dd.source_message_count AS BIGINT) AS source_message_count,
  dd.sequence_gap_count,
  dd.duplicate_delivery_count,

  -- Calibration. Regulated metrology for vaccine storage (CDC/VFC requires a
  -- NIST-traceable certificate retained 3 years and recalibration per the certificate),
  -- so expiry is a fleet-health concern rather than an admin one.
  d.calibration_valid_to,
  d.calibration_certificate_id,
  d.accuracy_tolerance,
  d.probe_type,
  d.is_backup_device,
  CASE
    WHEN d.calibration_valid_to IS NULL                                   THEN 'unknown'
    WHEN d.calibration_valid_to <  current_date()                         THEN 'expired'
    WHEN d.calibration_valid_to <= date_add(current_date(), 30)           THEN 'expiring_soon'
    ELSE 'current'
  END AS calibration_status,

  -- BACnet Out_Of_Service means Present_Value is SIMULATED. Surfacing it here is what
  -- stops a commissioning device's fabricated readings being read as real.
  d.bacnet_out_of_service,

  -- The governance record, so a fleet review and a privacy review read the same row.
  d.sensing_deployment_id,
  p.sensing_method_code,
  p.deployment_status,
  p.dpia_completed_flag,
  p.ai_act_notice_status,

  current_timestamp() AS fresh_as_of_ts
FROM device_day dd
-- Plain equi-join on the dimension PRIMARY KEY, with NO is_current predicate (§A.16). The
-- _sk the fact carries is already version-specific and was resolved as-of at ingest, so
-- this is both the as-of-correct join and the cheap one. Joining on the durable _id plus
-- is_current would instead decorate a historical day with today's firmware, calibration
-- and DPIA state — which would silently defeat the reason these masters are SCD2 at all,
-- since mv_device_health tells the user to group by firmware_version to investigate a
-- counting discontinuity.
JOIN ${catalog}.${css_schema}.sensor_device d
  ON dd.sensor_device_sk = d.sensor_device_sk
LEFT JOIN ${catalog}.${css_schema}.sensing_deployment p
  ON dd.sensing_deployment_sk = p.sensing_deployment_sk

UNION ALL

SELECT
  d.store_id,
  d.device_type,
  CAST(rd.trading_date AS DATE) AS trading_date,
  'rfid:ReadEvent' AS report_type,
  'device' AS aggregation_level,
  d.sensor_device_id,
  CAST(rd.sensor_device_sk AS BIGINT) AS sensor_device_sk,
  d.sensing_technology,
  d.device_status,
  d.store_zone_id,
  d.manufacturer,
  d.model,
  d.firmware_version,
  d.battery_powered,
  CAST(rd.events_reported AS BIGINT) AS intervals_reported,
  CAST(NULL AS BIGINT) AS observations_expected,
  CAST(NULL AS BIGINT) AS observations_received,
  CAST(NULL AS DOUBLE) AS missing_observation_rate,
  CAST(NULL AS DOUBLE) AS avg_uptime_ratio,
  CAST(NULL AS DOUBLE) AS avg_coverage_ratio,
  CAST(rd.events_reported - rd.stray_events AS BIGINT) AS valid_intervals,
  CAST((rd.events_reported - rd.stray_events) / NULLIF(rd.events_reported, 0) AS DOUBLE) AS valid_interval_share,
  rd.stray_events AS invalid_intervals,
  CAST(0 AS BIGINT) AS imputed_intervals,
  CAST(0 AS BIGINT) AS observed_zero_intervals,
  CAST(0 AS BIGINT) AS capped_intervals,
  CAST(rd.late_events AS BIGINT) AS late_arrived_intervals,
  CAST(rd.historical_events AS BIGINT) AS historical_message_count,
  rd.stray_events AS bad_quality_message_count,
  CAST(0 AS INT) AS max_restatement_version,
  CAST(rd.last_event_ts AS TIMESTAMP) AS last_interval_end_ts,
  CAST(rd.last_ingest_ts AS TIMESTAMP) AS last_ingest_ts,
  CAST(rd.avg_latency_seconds AS DOUBLE) AS avg_latency_seconds,
  CAST(rd.max_latency_seconds AS BIGINT) AS max_latency_seconds,
  timestampdiff(MINUTE, rd.last_ingest_ts, current_timestamp()) AS feed_age_minutes,
  CASE
    WHEN timestampdiff(MINUTE, rd.last_ingest_ts, current_timestamp()) <= 60  THEN 'fresh'
    WHEN timestampdiff(MINUTE, rd.last_ingest_ts, current_timestamp()) <= 360 THEN 'delayed'
    ELSE 'stale'
  END AS feed_freshness_status,
  rd.session_count,
  FALSE AS had_session_restart,
  CAST(rd.source_message_count AS BIGINT) AS source_message_count,
  CAST(0 AS BIGINT) AS sequence_gap_count,
  rd.duplicate_delivery_count,
  d.calibration_valid_to,
  d.calibration_certificate_id,
  d.accuracy_tolerance,
  d.probe_type,
  d.is_backup_device,
  CASE
    WHEN d.calibration_valid_to IS NULL                                   THEN 'unknown'
    WHEN d.calibration_valid_to <  current_date()                         THEN 'expired'
    WHEN d.calibration_valid_to <= date_add(current_date(), 30)           THEN 'expiring_soon'
    ELSE 'current'
  END AS calibration_status,
  d.bacnet_out_of_service,
  d.sensing_deployment_id,
  p.sensing_method_code,
  p.deployment_status,
  p.dpia_completed_flag,
  p.ai_act_notice_status,
  current_timestamp() AS fresh_as_of_ts
FROM rfid_device_day rd
JOIN ${catalog}.${css_schema}.sensor_device d
  ON rd.sensor_device_sk = d.sensor_device_sk
LEFT JOIN ${catalog}.${css_schema}.sensing_deployment p
  ON rd.sensing_deployment_sk = p.sensing_deployment_sk

UNION ALL

-- Smart Shelf ESL gateway ack health (rows, not a new view — the header's contract).
-- Ack liveness per gateway per day; the ack IS the message, so validity axes that
-- describe interval measurement do not apply and are reported as such.
SELECT
  d.store_id,
  d.device_type,
  CAST(ed.trading_date AS DATE) AS trading_date,
  'esl:PriceAck' AS report_type,
  'device' AS aggregation_level,
  d.sensor_device_id,
  CAST(ed.sensor_device_sk AS BIGINT) AS sensor_device_sk,
  d.sensing_technology,
  d.device_status,
  d.store_zone_id,
  d.manufacturer,
  d.model,
  d.firmware_version,
  d.battery_powered,
  CAST(ed.acks_reported AS BIGINT) AS intervals_reported,
  CAST(NULL AS BIGINT) AS observations_expected,
  -- Reuse the view's source-observation breadth column for distinct endpoint labels.
  CAST(ed.labels_acked AS BIGINT) AS observations_received,
  CAST(NULL AS DOUBLE) AS missing_observation_rate,
  CAST(NULL AS DOUBLE) AS avg_uptime_ratio,
  CAST(NULL AS DOUBLE) AS avg_coverage_ratio,
  CAST(ed.acks_reported AS BIGINT) AS valid_intervals,
  CAST(ed.acks_reported / NULLIF(ed.acks_reported, 0) AS DOUBLE) AS valid_interval_share,
  CAST(0 AS BIGINT) AS invalid_intervals,
  CAST(0 AS BIGINT) AS imputed_intervals,
  CAST(0 AS BIGINT) AS observed_zero_intervals,
  CAST(0 AS BIGINT) AS capped_intervals,
  CAST(ed.late_acks AS BIGINT) AS late_arrived_intervals,
  CAST(ed.historical_acks AS BIGINT) AS historical_message_count,
  CAST(0 AS BIGINT) AS bad_quality_message_count,
  CAST(0 AS INT) AS max_restatement_version,
  CAST(ed.last_event_ts AS TIMESTAMP) AS last_interval_end_ts,
  CAST(ed.last_ingest_ts AS TIMESTAMP) AS last_ingest_ts,
  CAST(ed.avg_latency_seconds AS DOUBLE) AS avg_latency_seconds,
  CAST(ed.max_latency_seconds AS BIGINT) AS max_latency_seconds,
  timestampdiff(MINUTE, ed.last_ingest_ts, current_timestamp()) AS feed_age_minutes,
  CASE
    WHEN timestampdiff(MINUTE, ed.last_ingest_ts, current_timestamp()) <= 60  THEN 'fresh'
    WHEN timestampdiff(MINUTE, ed.last_ingest_ts, current_timestamp()) <= 360 THEN 'delayed'
    ELSE 'stale'
  END AS feed_freshness_status,
  CAST(0 AS BIGINT) AS session_count,
  FALSE AS had_session_restart,
  CAST(ed.acks_reported AS BIGINT) AS source_message_count,
  CAST(0 AS BIGINT) AS sequence_gap_count,
  CAST(0 AS BIGINT) AS duplicate_delivery_count,
  d.calibration_valid_to,
  d.calibration_certificate_id,
  d.accuracy_tolerance,
  d.probe_type,
  d.is_backup_device,
  CASE
    WHEN d.calibration_valid_to IS NULL                                   THEN 'unknown'
    WHEN d.calibration_valid_to <  current_date()                         THEN 'expired'
    WHEN d.calibration_valid_to <= date_add(current_date(), 30)           THEN 'expiring_soon'
    ELSE 'current'
  END AS calibration_status,
  d.bacnet_out_of_service,
  d.sensing_deployment_id,
  p.sensing_method_code,
  p.deployment_status,
  p.dpia_completed_flag,
  p.ai_act_notice_status,
  current_timestamp() AS fresh_as_of_ts
FROM esl_device_day ed
JOIN ${catalog}.${css_schema}.sensor_device d
  ON ed.sensor_device_sk = d.sensor_device_sk
LEFT JOIN ${catalog}.${css_schema}.sensing_deployment p
  ON d.sensing_deployment_sk = p.sensing_deployment_sk;
