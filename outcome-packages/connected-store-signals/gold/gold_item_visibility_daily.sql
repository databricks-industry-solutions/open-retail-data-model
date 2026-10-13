-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_item_visibility_daily
-- Layer: outcome package (gold / metric support)
-- Version: 0.5
-- Generated: 2026-08-18
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-19
-- ============================================================
-- GRAIN: store × product × trading date. Count fields remain additive inputs for
-- visibility-quality rates; average confidence, percentile lag, and freshness are
-- explicitly non-additive diagnostics at this daily grain.
-- RFID freshness uses ADR 0038's resolved item-presence evaluation clock so its
-- freshness_age_minutes and fresh_as_of_ts agree with gold_item_current_state.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_item_visibility_daily AS
SELECT
  store_id,
  product_id,
  trading_date,
  COUNT(*) AS read_event_count,
  COUNT(DISTINCT tagged_item_id) AS distinct_items_read,
  SUM(CASE WHEN is_unregistered_epc THEN 1 ELSE 0 END) AS unregistered_read_count,
  SUM(CASE WHEN is_stray_suspect THEN 1 ELSE 0 END) AS stray_read_count,
  SUM(read_count) AS raw_ping_count,
  SUM(COALESCE(duplicate_delivery_count, 0)) AS duplicate_delivery_count,
  AVG(attribution_confidence) AS avg_attribution_confidence,
  percentile_approx(timestampdiff(SECOND, event_ts, ingest_timestamp), 0.95) AS arrival_lag_seconds_p95,
  MAX(event_ts) AS latest_event_ts,
  timestampdiff(MINUTE, MAX(event_ts), ${rfid_as_of_ts}) AS freshness_age_minutes,
  CAST(${rfid_as_of_ts} AS TIMESTAMP) AS fresh_as_of_ts
FROM ${catalog}.${css_schema}.rfid_read_event
GROUP BY store_id, product_id, trading_date;
