-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_unaccounted_exits
-- Layer: outcome package (gold / item-state outcome)
-- Version: 0.5
-- Generated: 2026-08-18
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-19
-- ============================================================
-- GRAIN: one item exit event. No person, basket, transaction or video linkage.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_unaccounted_exits AS
WITH exits AS (
  SELECT
    e.*,
    z.zone_type,
    MAX(CASE WHEN e.disposition_uri = 'https://ref.gs1.org/cbv/Disp-retail_sold'
              OR e.biz_step_uri = 'https://ref.gs1.org/cbv/BizStep-shipping'
             THEN 1 ELSE 0 END)
      OVER (
        PARTITION BY e.tagged_item_id
        ORDER BY e.event_ts, e.ingest_timestamp, e.rfid_read_event_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) AS has_accounted_disposition
  FROM ${catalog}.${css_schema}.rfid_read_event e
  JOIN ${catalog}.${css_schema}.store_zone z
    ON e.store_zone_sk = z.store_zone_sk
  WHERE COALESCE(e.is_stray_suspect, FALSE) = FALSE
)
SELECT
  rfid_read_event_id AS unaccounted_exit_id,
  tagged_item_sk,
  tagged_item_id,
  product_sk,
  product_id,
  store_sk,
  store_id,
  store_zone_sk,
  store_zone_id,
  sensor_device_sk,
  sensor_device_id,
  event_ts AS exit_event_ts,
  trading_date,
  direction_confidence,
  attribution_confidence,
  disposition_uri,
  biz_step_uri,
  'no_sold_or_shipping_disposition' AS exception_reason
FROM exits
WHERE direction_code = 'out'
  AND zone_type IN ('entrance', 'perimeter')
  AND has_accounted_disposition = 0;
