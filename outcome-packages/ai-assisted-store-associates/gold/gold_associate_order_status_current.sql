-- ============================================================
-- ORDM · Outcome Package · AI-Assisted Store Associates
-- View: gold_associate_order_status_current   (MATERIALIZED VIEW)
-- Layer: outcome package (gold / consumable)
-- Materialization: Lakeflow Declarative Pipeline materialized view for
--   associate point-lookup latency. Clustered on (store_id, order_id).
--   Demo/CI may --demote-materialized to a plain view (tools/ddl_exec.py).
-- Version: 0.5
-- Generated: 2026-08-11
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-11
-- ============================================================
-- Associate-safe order / fulfillment current state. Sourced from the
-- package extension associate_fulfillment_status (canonical order
-- domain has no BOPIS lifecycle). No customer PII columns.
--
-- Store-scope: apply the deploy-time row filter in filters.sql so Genie /
-- DBSQL consumers cannot bypass the Python policy layer.
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${aasa_schema}.gold_associate_order_status_current AS
WITH latest_order_event AS (
  SELECT
    e.*,
    ROW_NUMBER() OVER (
      PARTITION BY e.order_id
      ORDER BY e.event_timestamp DESC, e.ingest_timestamp DESC, e.associate_context_event_sk DESC
    ) AS rn
  FROM ${catalog}.${aasa_schema}.associate_context_event e
  WHERE e.event_domain = 'order'
    AND e.order_id IS NOT NULL
)
SELECT
  afs.associate_fulfillment_status_sk,
  afs.associate_fulfillment_status_id,
  afs.order_id,
  afs.store_sk,
  afs.store_id,
  s.store_name,
  afs.fulfillment_type,
  COALESCE(ev.status_code, afs.order_status) AS order_status,
  afs.pickup_readiness,
  afs.pickup_location_code,
  COALESCE(NULLIF(afs.exception_state, 'none'), CAST(NULL AS STRING)) AS exception_state,
  afs.requires_customer_verification,
  COALESCE(ev.event_timestamp, afs.last_event_timestamp) AS last_event_timestamp,
  COALESCE(ev.ingest_timestamp, afs.data_freshness_timestamp) AS source_ingest_timestamp,
  afs.data_freshness_timestamp AS current_state_updated_at,
  COALESCE(ev.source_system, afs.source_system) AS source_system,
  CASE
    WHEN (UNIX_TIMESTAMP(CURRENT_TIMESTAMP())
          - UNIX_TIMESTAMP(COALESCE(ev.ingest_timestamp, afs.data_freshness_timestamp))) > 86400
      THEN 'stale'
    WHEN (UNIX_TIMESTAMP(CURRENT_TIMESTAMP())
          - UNIX_TIMESTAMP(COALESCE(ev.ingest_timestamp, afs.data_freshness_timestamp))) > 3600
      THEN 'delayed'
    ELSE 'fresh'
  END AS freshness_status,
  ROUND(
    (UNIX_TIMESTAMP(CURRENT_TIMESTAMP())
     - UNIX_TIMESTAMP(COALESCE(ev.ingest_timestamp, afs.data_freshness_timestamp))) / 60.0,
    1
  ) AS freshness_lag_minutes,
  CASE
    WHEN afs.requires_customer_verification = TRUE
      THEN 'Order status available after authorized customer verification at the store.'
    ELSE CONCAT('Fulfillment status ', COALESCE(ev.status_code, afs.order_status),
                ' for pickup readiness ', afs.pickup_readiness, '.')
  END AS explanation,
  CASE
    WHEN (UNIX_TIMESTAMP(CURRENT_TIMESTAMP())
          - UNIX_TIMESTAMP(COALESCE(ev.ingest_timestamp, afs.data_freshness_timestamp))) > 3600
      THEN 'Order status feed exceeds freshness SLA; confirm in OMS before releasing merchandise.'
    ELSE CAST(NULL AS STRING)
  END AS warning
FROM ${catalog}.${aasa_schema}.associate_fulfillment_status afs
JOIN ${catalog}.${store_schema}.store s
  ON s.store_id = afs.store_id AND s.is_current = TRUE
LEFT JOIN latest_order_event ev
  ON ev.rn = 1 AND ev.order_id = afs.order_id
CLUSTER BY (store_id, order_id);
