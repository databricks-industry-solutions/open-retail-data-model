-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_count_session_summary
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-08-18
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-19
-- ============================================================
-- GRAIN: one row per RFID count session. full_store plans derive from active
-- non-site zones at session start; partial sessions make no plan claim.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_count_session_summary AS
WITH observed AS (
  SELECT
    rfid_count_session_sk,
    COUNT(DISTINCT tagged_item_id) AS units_observed,
    COUNT(DISTINCT store_zone_id) AS zones_observed,
    COUNT(DISTINCT sensor_device_id) AS devices_observed,
    MIN(event_ts) AS first_event_ts,
    MAX(event_ts) AS last_event_ts
  FROM ${catalog}.${css_schema}.rfid_read_event
  WHERE COALESCE(is_stray_suspect, FALSE) = FALSE
  GROUP BY rfid_count_session_sk
), planned_zone_observation AS (
  -- Coverage is the intersection of observed zones and the session's derived plan.
  -- Site rows and other out-of-plan reads remain valid event evidence but cannot make
  -- a full-store plan look more than 100 percent complete.
  SELECT
    s.rfid_count_session_sk,
    COUNT(DISTINCT z.store_zone_id) AS planned_zones_covered
  FROM ${catalog}.${css_schema}.rfid_count_session s
  JOIN ${catalog}.${css_schema}.rfid_read_event e
    ON s.rfid_count_session_sk = e.rfid_count_session_sk
   AND COALESCE(e.is_stray_suspect, FALSE) = FALSE
  JOIN ${catalog}.${css_schema}.store_zone z
    ON e.store_id = z.store_id
   AND e.store_zone_id = z.store_zone_id
   AND s.trading_date >= z.effective_from_date
   AND (z.effective_to_date IS NULL OR s.trading_date < z.effective_to_date)
   AND z.zone_type <> 'site'
  WHERE s.scope_type = 'full_store'
  GROUP BY s.rfid_count_session_sk
), plan AS (
  SELECT
    s.rfid_count_session_sk,
    COUNT(DISTINCT z.store_zone_id) AS planned_zones
  FROM ${catalog}.${css_schema}.rfid_count_session s
  JOIN ${catalog}.${css_schema}.store_zone z
    ON s.store_id = z.store_id
   AND s.trading_date >= z.effective_from_date
   AND (z.effective_to_date IS NULL OR s.trading_date < z.effective_to_date)
   AND z.zone_type <> 'site'
  WHERE s.scope_type = 'full_store'
  GROUP BY s.rfid_count_session_sk
)
SELECT
  s.rfid_count_session_sk,
  s.rfid_count_session_id,
  s.source_session_id,
  s.store_sk,
  s.store_id,
  s.primary_sensor_device_sk,
  s.primary_sensor_device_id,
  s.count_method,
  s.scope_type,
  s.started_at_ts,
  s.ended_at_ts,
  s.trading_date,
  timestampdiff(MINUTE, s.started_at_ts, s.ended_at_ts) AS duration_minutes,
  CASE WHEN s.scope_type = 'full_store' THEN p.planned_zones END AS planned_zones,
  CASE
    WHEN s.scope_type = 'full_store' THEN COALESCE(po.planned_zones_covered, 0)
    ELSE COALESCE(o.zones_observed, 0)
  END AS zones_covered,
  CASE WHEN s.scope_type = 'full_store'
       THEN GREATEST(
         COALESCE(p.planned_zones, 0) - COALESCE(po.planned_zones_covered, 0),
         0
       )
  END AS zones_missed,
  CASE WHEN s.scope_type = 'full_store'
       THEN COALESCE(po.planned_zones_covered, 0) / NULLIF(p.planned_zones, 0)
  END AS zone_coverage_rate,
  COALESCE(o.units_observed, 0) AS units_observed,
  COALESCE(o.devices_observed, 0) AS devices_observed,
  o.first_event_ts,
  o.last_event_ts,
  current_timestamp() AS fresh_as_of_ts
FROM ${catalog}.${css_schema}.rfid_count_session s
LEFT JOIN observed o ON s.rfid_count_session_sk = o.rfid_count_session_sk
LEFT JOIN planned_zone_observation po
  ON s.rfid_count_session_sk = po.rfid_count_session_sk
LEFT JOIN plan p ON s.rfid_count_session_sk = p.rfid_count_session_sk;
