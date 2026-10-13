-- ============================================================
-- ORDM · Outcome Package · AI-Assisted Store Associates
-- View: gold_associate_data_freshness
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-08-11
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-11
-- ============================================================
-- Domain-level freshness metrics for associate real-time access.
-- SLA: fresh < 60 min lag, delayed 60–1440 min, stale > 1440 min
-- (aligned with early-risk feed_freshness). Inventory day snapshots
-- without event overlay are evaluated on load_timestamp age.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${aasa_schema}.gold_associate_data_freshness AS
SELECT
  feed_name,
  store_id,
  last_source_event_timestamp,
  last_ingest_timestamp,
  last_processed_timestamp,
  freshness_lag_minutes,
  CASE
    WHEN freshness_lag_minutes IS NULL THEN 'UNKNOWN'
    WHEN freshness_lag_minutes > 1440 THEN 'stale'
    WHEN freshness_lag_minutes > 60 THEN 'delayed'
    ELSE 'fresh'
  END AS freshness_status,
  CASE
    WHEN freshness_lag_minutes IS NULL THEN 'UNKNOWN'
    WHEN freshness_lag_minutes > 60 THEN 'breach'
    ELSE 'within_sla'
  END AS sla_state,
  event_count
FROM (
  SELECT
    'inventory_position' AS feed_name,
    store_id,
    CAST(MAX(date_key) AS TIMESTAMP) AS last_source_event_timestamp,
    MAX(load_timestamp) AS last_ingest_timestamp,
    MAX(load_timestamp) AS last_processed_timestamp,
    ROUND((UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(MAX(load_timestamp))) / 60.0, 1)
      AS freshness_lag_minutes,
    COUNT(*) AS event_count
  FROM ${catalog}.${inventory_schema}.inventory_position
  GROUP BY store_id

  UNION ALL

  SELECT
    'associate_context_event_inventory' AS feed_name,
    store_id,
    MAX(event_timestamp),
    MAX(ingest_timestamp),
    MAX(COALESCE(processed_timestamp, ingest_timestamp)),
    ROUND((UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(MAX(ingest_timestamp))) / 60.0, 1),
    COUNT(*)
  FROM ${catalog}.${aasa_schema}.associate_context_event
  WHERE event_domain = 'inventory'
  GROUP BY store_id

  UNION ALL

  SELECT
    'associate_context_event_price' AS feed_name,
    store_id,
    MAX(event_timestamp),
    MAX(ingest_timestamp),
    MAX(COALESCE(processed_timestamp, ingest_timestamp)),
    ROUND((UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(MAX(ingest_timestamp))) / 60.0, 1),
    COUNT(*)
  FROM ${catalog}.${aasa_schema}.associate_context_event
  WHERE event_domain IN ('price', 'promotion')
  GROUP BY store_id

  UNION ALL

  SELECT
    'associate_fulfillment_status' AS feed_name,
    store_id,
    MAX(last_event_timestamp),
    MAX(data_freshness_timestamp),
    MAX(data_freshness_timestamp),
    ROUND((UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(MAX(data_freshness_timestamp))) / 60.0, 1),
    COUNT(*)
  FROM ${catalog}.${aasa_schema}.associate_fulfillment_status
  GROUP BY store_id

  UNION ALL

  SELECT
    'associate_lookup_audit' AS feed_name,
    store_id,
    MAX(request_timestamp),
    MAX(generated_at),
    MAX(generated_at),
    ROUND((UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(MAX(generated_at))) / 60.0, 1),
    COUNT(*)
  FROM ${catalog}.${aasa_schema}.associate_lookup_audit
  GROUP BY store_id
);
