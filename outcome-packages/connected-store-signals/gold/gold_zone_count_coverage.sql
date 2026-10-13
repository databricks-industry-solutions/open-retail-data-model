-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_zone_count_coverage
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-08-18
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-19
-- ============================================================
-- GRAIN: one current store zone. Cadence and recent-session lookback are adopter
-- policy inputs; starter defaults are seven and 30 days, respectively.
-- ADR 0038 intentionally keeps count-coverage calculations on wall clock; the
-- historical-demo item-presence clock does not apply to this operational cadence.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_zone_count_coverage AS
WITH counted AS (
  SELECT
    e.store_id,
    e.store_zone_id,
    MAX(e.trading_date) AS last_counted_date,
    COUNT(DISTINCT CASE
      WHEN e.trading_date >= date_sub(current_date(), ${rfid_count_lookback_days})
      THEN e.rfid_count_session_id
    END) AS count_sessions_in_lookback,
    COUNT(DISTINCT e.tagged_item_id) AS lifetime_units_observed
  FROM ${catalog}.${css_schema}.rfid_read_event e
  WHERE e.rfid_count_session_sk IS NOT NULL
    AND COALESCE(e.is_stray_suspect, FALSE) = FALSE
  GROUP BY e.store_id, e.store_zone_id
)
SELECT
  z.store_sk,
  z.store_id,
  z.store_zone_sk,
  z.store_zone_id,
  z.zone_code,
  z.zone_name,
  z.zone_type,
  z.is_sales_floor,
  c.last_counted_date,
  datediff(current_date(), c.last_counted_date) AS days_since_last_count,
  CAST(${rfid_count_target_cadence_days} AS INT) AS target_cadence_days,
  c.last_counted_date IS NULL OR
    datediff(current_date(), c.last_counted_date) > ${rfid_count_target_cadence_days} AS is_overdue,
  CAST(${rfid_count_lookback_days} AS INT) AS count_lookback_days,
  COALESCE(c.count_sessions_in_lookback, 0) AS count_sessions_in_lookback,
  COALESCE(c.lifetime_units_observed, 0) AS lifetime_units_observed,
  current_timestamp() AS fresh_as_of_ts
FROM ${catalog}.${css_schema}.store_zone z
LEFT JOIN counted c
  ON z.store_id = c.store_id AND z.store_zone_id = c.store_zone_id
WHERE z.is_current = TRUE
  AND z.zone_type <> 'site';
