-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_zone_item_presence_current
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-08-18
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-19
-- ============================================================
-- GRAIN: one row per store × zone × product for fresh, attributed item state.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_zone_item_presence_current AS
SELECT
  store_id,
  store_zone_id,
  product_id,
  COUNT(DISTINCT tagged_item_id) AS units_present,
  MIN(latest_event_ts) AS oldest_supporting_event_ts,
  MAX(latest_event_ts) AS newest_supporting_event_ts,
  MAX(freshness_age_minutes) AS max_freshness_age_minutes,
  MAX(fresh_as_of_ts) AS fresh_as_of_ts
FROM ${catalog}.${css_schema}.gold_item_current_state
WHERE derived_presence_state = 'present'
  AND product_id IS NOT NULL
GROUP BY store_id, store_zone_id, product_id;
