-- ============================================================
-- ORDM · Outcome Package · AI-Assisted Store Associates
-- View: gold_associate_operational_context_current
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-08-11
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-11
-- ============================================================
-- Store-level operational signals safe for associate display:
-- replenishment / shelf-gap hints from inventory, equipment alerts
-- from equipment_reading, and optional operations events.
-- Excludes loss-prevention, margin, and employee personal data.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${aasa_schema}.gold_associate_operational_context_current AS
WITH replenishment AS (
  SELECT
    ip.store_id,
    ip.product_id,
    ip.date_key,
    ip.load_timestamp,
    ip.record_source,
    ROW_NUMBER() OVER (
      PARTITION BY ip.store_id, ip.product_id
      ORDER BY ip.date_key DESC, ip.load_timestamp DESC
    ) AS rn
  FROM ${catalog}.${inventory_schema}.inventory_position ip
  WHERE ip.replenishment_flag = TRUE
),
equipment_alerts AS (
  SELECT
    eq.store_id,
    eq.equipment_id,
    eq.equipment_type,
    eq.installation_zone,
    er.reading_type,
    er.error_code,
    er.is_anomaly,
    er.threshold_breached,
    er.event_timestamp,
    er.ingest_timestamp,
    er.record_source,
    ROW_NUMBER() OVER (
      PARTITION BY eq.store_id, eq.equipment_id
      ORDER BY er.event_timestamp DESC, er.ingest_timestamp DESC
    ) AS rn
  FROM ${catalog}.${equipment_schema}.equipment eq
  JOIN ${catalog}.${equipment_schema}.equipment_reading er
    ON er.equipment_id = eq.equipment_id
  WHERE eq.is_current = TRUE
    AND (er.is_anomaly = TRUE OR er.threshold_breached IS NOT NULL)
),
ops_events AS (
  SELECT
    e.*,
    ROW_NUMBER() OVER (
      PARTITION BY e.store_id, COALESCE(e.equipment_id, e.product_id, e.status_code)
      ORDER BY e.event_timestamp DESC, e.ingest_timestamp DESC
    ) AS rn
  FROM ${catalog}.${aasa_schema}.associate_context_event e
  WHERE e.event_domain = 'operations'
    AND e.store_id IS NOT NULL
),
unioned AS (
  SELECT
    r.store_id,
    'replenishment_task' AS context_type,
    CONCAT('REPL-', r.store_id, '-', r.product_id) AS context_id,
    r.product_id AS related_product_id,
    CAST(NULL AS STRING) AS related_equipment_id,
    'medium' AS severity,
    'open' AS resolution_status,
    CONCAT('Replenishment indicated for product ', r.product_id, '.') AS signal_summary,
    CAST(r.date_key AS TIMESTAMP) AS source_event_timestamp,
    r.load_timestamp AS source_ingest_timestamp,
    r.load_timestamp AS current_state_updated_at,
    r.record_source AS source_system
  FROM replenishment r
  WHERE r.rn = 1

  UNION ALL

  SELECT
    ea.store_id,
    'equipment_alert' AS context_type,
    CONCAT('EQ-', ea.equipment_id) AS context_id,
    CAST(NULL AS STRING) AS related_product_id,
    ea.equipment_id AS related_equipment_id,
    CASE
      WHEN ea.threshold_breached IN ('critical_low', 'critical_high') THEN 'high'
      WHEN ea.threshold_breached IS NOT NULL THEN 'medium'
      ELSE 'medium'
    END AS severity,
    'open' AS resolution_status,
    CONCAT('Equipment ', ea.equipment_id, ' (', ea.equipment_type, ') alert in zone ',
           COALESCE(ea.installation_zone, 'unknown'), '.') AS signal_summary,
    ea.event_timestamp AS source_event_timestamp,
    ea.ingest_timestamp AS source_ingest_timestamp,
    ea.ingest_timestamp AS current_state_updated_at,
    ea.record_source AS source_system
  FROM equipment_alerts ea
  WHERE ea.rn = 1

  UNION ALL

  SELECT
    oe.store_id,
    COALESCE(oe.event_type, 'operations_signal') AS context_type,
    oe.associate_context_event_id AS context_id,
    oe.product_id AS related_product_id,
    oe.equipment_id AS related_equipment_id,
    COALESCE(oe.status_code, 'info') AS severity,
    'open' AS resolution_status,
    COALESCE(oe.event_payload_summary, 'Operations signal.') AS signal_summary,
    oe.event_timestamp AS source_event_timestamp,
    oe.ingest_timestamp AS source_ingest_timestamp,
    COALESCE(oe.processed_timestamp, oe.ingest_timestamp) AS current_state_updated_at,
    oe.source_system AS source_system
  FROM ops_events oe
  WHERE oe.rn = 1
)
SELECT
  u.store_id,
  s.store_sk,
  s.store_name,
  u.context_type,
  u.context_id,
  u.related_product_id,
  u.related_equipment_id,
  u.severity,
  u.resolution_status,
  u.signal_summary,
  u.source_event_timestamp,
  u.source_ingest_timestamp,
  u.current_state_updated_at,
  u.source_system,
  CASE
    WHEN (UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(u.source_ingest_timestamp)) > 86400
      THEN 'stale'
    WHEN (UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(u.source_ingest_timestamp)) > 3600
      THEN 'delayed'
    ELSE 'fresh'
  END AS freshness_status,
  ROUND(
    (UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(u.source_ingest_timestamp)) / 60.0,
    1
  ) AS freshness_lag_minutes,
  u.signal_summary AS explanation,
  CASE
    WHEN (UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(u.source_ingest_timestamp)) > 3600
      THEN 'Operational signal may be stale; confirm on the floor.'
    ELSE CAST(NULL AS STRING)
  END AS warning
FROM unioned u
JOIN ${catalog}.${store_schema}.store s
  ON s.store_id = u.store_id AND s.is_current = TRUE;
