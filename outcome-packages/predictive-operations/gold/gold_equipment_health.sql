-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · In-Store Equipment Maintenance use case
-- View: gold_equipment_health
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-15
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-29 by @sreekanthmunigati
-- ============================================================
-- Per-equipment health dashboard: latest reading summary, anomaly
-- counts, current status, and a health score (0-100). The primary
-- monitoring surface for store operations teams.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${predops_schema}.gold_equipment_health AS
WITH latest_readings AS (
  SELECT
    er.equipment_id,
    er.reading_type,
    er.reading_value,
    er.reading_unit,
    er.is_anomaly,
    er.error_code,
    er.event_timestamp,
    ROW_NUMBER() OVER (PARTITION BY er.equipment_id, er.reading_type ORDER BY er.event_timestamp DESC) AS rn
  FROM ${catalog}.${equipment_schema}.equipment_reading er
),
reading_summary AS (
  SELECT
    equipment_id,
    MAX(CASE WHEN reading_type = 'temperature' THEN reading_value END) AS latest_temperature,
    MAX(CASE WHEN reading_type = 'power_kw' THEN reading_value END) AS latest_power_kw,
    MAX(CASE WHEN reading_type = 'vibration' THEN reading_value END) AS latest_vibration,
    MAX(CASE WHEN reading_type = 'runtime_hours' THEN reading_value END) AS latest_runtime_hours,
    MAX(event_timestamp) AS last_reading_timestamp
  FROM latest_readings
  WHERE rn = 1
  GROUP BY equipment_id
),
anomaly_stats AS (
  SELECT
    equipment_id,
    COUNT(*) AS total_readings_7d,
    SUM(CASE WHEN is_anomaly = TRUE THEN 1 ELSE 0 END) AS anomaly_count_7d,
    SUM(CASE WHEN error_code IS NOT NULL THEN 1 ELSE 0 END) AS error_count_7d
  FROM ${catalog}.${equipment_schema}.equipment_reading
  WHERE event_timestamp >= CURRENT_TIMESTAMP() - INTERVAL 7 DAYS
  GROUP BY equipment_id
),
recent_work_orders AS (
  SELECT
    equipment_id,
    COUNT(*) AS wo_count_90d,
    SUM(CASE WHEN work_order_type = 'corrective' THEN 1 ELSE 0 END) AS corrective_wo_count_90d,
    SUM(COALESCE(downtime_hours, 0)) AS total_downtime_hours_90d
  FROM ${catalog}.${predops_schema}.work_order
  WHERE created_date >= CURRENT_DATE() - INTERVAL 90 DAYS
    AND work_order_status != 'cancelled'
  GROUP BY equipment_id
)
SELECT
  eq.equipment_sk,
  eq.equipment_id,
  eq.equipment_name,
  eq.equipment_type,
  eq.manufacturer,
  eq.model_number,
  eq.store_id,
  st.store_name,
  eq.installation_zone,
  eq.equipment_status,
  eq.criticality,
  eq.install_date,
  eq.warranty_expiry_date,
  -- Reading summary
  rs.latest_temperature,
  rs.latest_power_kw,
  rs.latest_vibration,
  rs.latest_runtime_hours,
  rs.last_reading_timestamp,
  -- Anomaly stats (7 days)
  COALESCE(ans.total_readings_7d, 0) AS total_readings_7d,
  COALESCE(ans.anomaly_count_7d, 0) AS anomaly_count_7d,
  COALESCE(ans.error_count_7d, 0) AS error_count_7d,
  CASE
    WHEN COALESCE(ans.total_readings_7d, 0) > 0
    THEN ROUND(CAST(ans.anomaly_count_7d AS DOUBLE) / ans.total_readings_7d, 4)
    ELSE NULL
  END AS anomaly_rate_7d,
  -- Work order stats (90 days)
  COALESCE(rwo.wo_count_90d, 0) AS wo_count_90d,
  COALESCE(rwo.corrective_wo_count_90d, 0) AS corrective_wo_count_90d,
  COALESCE(rwo.total_downtime_hours_90d, 0) AS total_downtime_hours_90d,
  -- Health score: 0-100, higher = healthier
  CASE
    WHEN eq.equipment_status = 'out_of_service' THEN 0
    WHEN eq.equipment_status = 'degraded' THEN
      -- Degraded: cap at 50, omit error_count penalty (already priced into status)
      CAST(GREATEST(0, 50 - COALESCE(ans.anomaly_count_7d, 0) * 5 - COALESCE(rwo.corrective_wo_count_90d, 0) * 10) AS INT)
    ELSE
      CAST(GREATEST(0, LEAST(100,
        100
        - COALESCE(ans.anomaly_count_7d, 0) * 5
        - COALESCE(ans.error_count_7d, 0) * 10
        - COALESCE(rwo.corrective_wo_count_90d, 0) * 10
      )) AS INT)
  END AS health_score,
  -- Health tier
  CASE
    WHEN eq.equipment_status = 'out_of_service' THEN 'failed'
    WHEN eq.equipment_status = 'degraded' THEN 'degraded'
    WHEN COALESCE(ans.anomaly_count_7d, 0) > 5 OR COALESCE(rwo.corrective_wo_count_90d, 0) > 2 THEN 'at_risk'
    ELSE 'healthy'
  END AS health_tier
FROM ${catalog}.${equipment_schema}.equipment eq
LEFT JOIN ${catalog}.${store_schema}.store st
  ON st.store_sk = eq.store_sk
LEFT JOIN reading_summary rs
  ON rs.equipment_id = eq.equipment_id
LEFT JOIN anomaly_stats ans
  ON ans.equipment_id = eq.equipment_id
LEFT JOIN recent_work_orders rwo
  ON rwo.equipment_id = eq.equipment_id
WHERE eq.is_current = TRUE
  AND eq.equipment_status != 'decommissioned';
