-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_receiving_verification
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-08-18
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-19
-- ============================================================
-- GRAIN: one row per linked shipment line, or one row per store × product × trading
-- day of unlinked receiving reads (verification_tier says which).
-- Linked rows are shipment-line evidence. Unlinked receiving reads remain honest
-- store × product × day evidence and are never guessed onto overlapping shipments.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_receiving_verification AS
WITH linked_reads AS (
  SELECT
    e.shipment_line_sk,
    e.shipment_line_id,
    e.store_id,
    e.product_id,
    MIN(e.event_ts) AS window_start_ts,
    MAX(e.event_ts) AS window_end_ts,
    COUNT(DISTINCT e.tagged_item_id) AS observed_units
  FROM ${catalog}.${css_schema}.rfid_read_event e
  WHERE e.biz_step_uri = 'https://ref.gs1.org/cbv/BizStep-receiving'
    AND e.shipment_line_sk IS NOT NULL
    AND COALESCE(e.is_stray_suspect, FALSE) = FALSE
  GROUP BY e.shipment_line_sk, e.shipment_line_id, e.store_id, e.product_id
), linked AS (
  SELECT
    'linked_shipment' AS verification_tier,
    sl.shipment_id,
    r.shipment_line_sk,
    r.shipment_line_id,
    r.store_id,
    r.product_id,
    r.window_start_ts,
    r.window_end_ts,
    sl.shipped_quantity AS expected_units,
    r.observed_units,
    r.observed_units - sl.shipped_quantity AS unit_variance,
    CASE
      WHEN r.observed_units = sl.shipped_quantity THEN 'verified'
      WHEN r.observed_units < sl.shipped_quantity THEN 'short'
      ELSE 'over'
    END AS verification_status
  FROM linked_reads r
  JOIN ${catalog}.${logistics_schema}.shipment_line sl
    ON r.shipment_line_sk = sl.shipment_line_sk
), unlinked AS (
  SELECT
    'unlinked_window_evidence' AS verification_tier,
    CAST(NULL AS STRING) AS shipment_id,
    CAST(NULL AS BIGINT) AS shipment_line_sk,
    CAST(NULL AS STRING) AS shipment_line_id,
    store_id,
    product_id,
    MIN(event_ts) AS window_start_ts,
    MAX(event_ts) AS window_end_ts,
    CAST(NULL AS INT) AS expected_units,
    COUNT(DISTINCT tagged_item_id) AS observed_units,
    CAST(NULL AS BIGINT) AS unit_variance,
    'evidence_only' AS verification_status
  FROM ${catalog}.${css_schema}.rfid_read_event
  WHERE biz_step_uri = 'https://ref.gs1.org/cbv/BizStep-receiving'
    AND shipment_line_sk IS NULL
    AND COALESCE(is_stray_suspect, FALSE) = FALSE
  GROUP BY store_id, product_id, trading_date
)
SELECT
  CAST(u.verification_tier AS STRING) AS verification_tier,
  CAST(u.shipment_id AS STRING) AS shipment_id,
  CAST(u.shipment_line_sk AS BIGINT) AS shipment_line_sk,
  CAST(u.shipment_line_id AS STRING) AS shipment_line_id,
  CAST(u.store_id AS STRING) AS store_id,
  CAST(u.product_id AS STRING) AS product_id,
  CAST(u.window_start_ts AS TIMESTAMP) AS window_start_ts,
  CAST(u.window_end_ts AS TIMESTAMP) AS window_end_ts,
  CAST(u.expected_units AS INT) AS expected_units,
  CAST(u.observed_units AS BIGINT) AS observed_units,
  CAST(u.unit_variance AS BIGINT) AS unit_variance,
  CAST(u.verification_status AS STRING) AS verification_status
FROM (
  SELECT * FROM linked
  UNION ALL
  SELECT * FROM unlinked
) u;
