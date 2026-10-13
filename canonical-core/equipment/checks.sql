-- ============================================================
-- ORDM · Canonical Core · Equipment domain · data-quality checks
-- Version: 0.5 · Generated: 2026-07-15 · LLM-generated: true · Reviewed: 2026-07-15
-- Each assertion SELECTs violating rows; 0 rows = PASS. `metric` checks report
-- a value and never fail the run.
-- ============================================================

-- ========== equipment ==========

-- check: equipment_pk_unique | severity: error
SELECT equipment_sk
FROM ${catalog}.${equipment_schema}.equipment
GROUP BY equipment_sk
HAVING COUNT(*) > 1;

-- check: equipment_scd2_current_open | severity: error
SELECT * FROM ${catalog}.${equipment_schema}.equipment
WHERE is_current = TRUE AND effective_to_date IS NOT NULL;

-- check: equipment_scd2_noncurrent_closed | severity: error
SELECT * FROM ${catalog}.${equipment_schema}.equipment
WHERE is_current = FALSE AND effective_to_date IS NULL;

-- check: equipment_scd2_start_before_end | severity: error
SELECT * FROM ${catalog}.${equipment_schema}.equipment
WHERE effective_to_date IS NOT NULL AND effective_from_date > effective_to_date;

-- check: equipment_store_fk_orphan | severity: error
SELECT e.* FROM ${catalog}.${equipment_schema}.equipment e
LEFT JOIN ${catalog}.${store_schema}.store st ON e.store_sk = st.store_sk
WHERE st.store_sk IS NULL AND e.store_sk IS NOT NULL;

-- check: equipment_rowcount | severity: metric
SELECT COUNT(*) AS equipment_rows FROM ${catalog}.${equipment_schema}.equipment;

-- check: equipment_status_distribution | severity: metric
SELECT equipment_status, COUNT(*) AS status_count
FROM ${catalog}.${equipment_schema}.equipment
WHERE is_current = TRUE
GROUP BY equipment_status;

-- check: equipment_type_distribution | severity: metric
SELECT equipment_type, COUNT(*) AS type_count
FROM ${catalog}.${equipment_schema}.equipment
WHERE is_current = TRUE
GROUP BY equipment_type;

-- ========== equipment_reading ==========

-- check: reading_pk_unique | severity: error
SELECT equipment_reading_sk
FROM ${catalog}.${equipment_schema}.equipment_reading
GROUP BY equipment_reading_sk
HAVING COUNT(*) > 1;

-- check: reading_equipment_fk_orphan | severity: error
SELECT er.* FROM ${catalog}.${equipment_schema}.equipment_reading er
LEFT JOIN ${catalog}.${equipment_schema}.equipment eq ON er.equipment_sk = eq.equipment_sk
WHERE eq.equipment_sk IS NULL AND er.equipment_sk IS NOT NULL;

-- check: reading_event_ts_not_future | severity: error
SELECT * FROM ${catalog}.${equipment_schema}.equipment_reading
WHERE event_timestamp > CURRENT_TIMESTAMP();

-- check: reading_latency_nonnegative | severity: error
SELECT * FROM ${catalog}.${equipment_schema}.equipment_reading
WHERE latency_seconds IS NOT NULL AND latency_seconds < 0;

-- check: reading_rowcount | severity: metric
SELECT COUNT(*) AS reading_rows FROM ${catalog}.${equipment_schema}.equipment_reading;

-- check: reading_anomaly_count | severity: metric
SELECT COUNT(*) AS anomaly_count
FROM ${catalog}.${equipment_schema}.equipment_reading
WHERE is_anomaly = TRUE;

-- check: reading_type_distribution | severity: metric
SELECT reading_type, COUNT(*) AS reading_count
FROM ${catalog}.${equipment_schema}.equipment_reading
GROUP BY reading_type;

-- check: reading_avg_latency | severity: metric
SELECT ROUND(AVG(latency_seconds), 1) AS avg_latency_seconds
FROM ${catalog}.${equipment_schema}.equipment_reading;
