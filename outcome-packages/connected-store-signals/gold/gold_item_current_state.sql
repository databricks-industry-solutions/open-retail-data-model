-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_item_current_state
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-08-18
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-19
-- ============================================================
-- GRAIN: one row per serialized item (durable tagged_item_id).
-- Stray-suspect reads never drive state. A recall is persistent until a future
-- explicit release mechanism is modeled; ordinary dispositions use the latest event.
-- Reference freshness windows are 120 minutes for fixed readers and 24 hours for
-- mobile sweeps. Adopters may tighten them without changing the event contract.
-- The evaluation clock defaults to wall clock; historical demos may explicitly
-- evaluate at the RFID event-time maximum under ADR 0038 without rewriting history.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_item_current_state AS
WITH attributed AS (
  SELECT
    e.*,
    d.is_mobile_platform,
    ROW_NUMBER() OVER (
      PARTITION BY e.tagged_item_id
      ORDER BY e.event_ts DESC, e.ingest_timestamp DESC, e.rfid_read_event_id DESC
    ) AS state_rank,
    MAX(CASE
          WHEN e.disposition_uri = 'https://ref.gs1.org/cbv/Disp-recalled'
          THEN e.event_ts
        END) OVER (PARTITION BY e.tagged_item_id) AS recalled_at_ts
  FROM ${catalog}.${css_schema}.rfid_read_event e
  JOIN ${catalog}.${css_schema}.sensor_device d
    ON e.sensor_device_sk = d.sensor_device_sk
  WHERE COALESCE(e.is_stray_suspect, FALSE) = FALSE
), latest AS (
  SELECT * FROM attributed WHERE state_rank = 1
)
SELECT
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
  sensing_deployment_sk,
  sensing_deployment_id,
  event_ts AS latest_event_ts,
  ingest_timestamp AS latest_ingest_ts,
  biz_step_uri AS latest_biz_step_uri,
  CASE
    WHEN recalled_at_ts IS NOT NULL THEN 'https://ref.gs1.org/cbv/Disp-recalled'
    ELSE disposition_uri
  END AS derived_disposition_uri,
  direction_code AS latest_direction_code,
  attribution_confidence,
  zone_source,
  is_mobile_platform,
  CAST(CASE
    WHEN is_mobile_platform THEN ${rfid_mobile_freshness_minutes}
    ELSE ${rfid_fixed_freshness_minutes}
  END AS INT) AS freshness_window_minutes,
  timestampdiff(MINUTE, event_ts, ${rfid_as_of_ts}) AS freshness_age_minutes,
  -- PRECEDENCE: known state outranks evidence age. A KNOWN terminal fact (recall, sold,
  -- shipped, decommissioned, damaged/expired/stolen) does not expire, so it is decided
  -- BEFORE the freshness test; `stale` is reserved for an item we would otherwise call
  -- `present` but whose evidence has aged out -- i.e. it qualifies 'present', not the
  -- terminal states. Ordering the freshness test first (as this view originally did) both
  -- contradicted the persistent-recall contract above and made `absent` almost
  -- unreachable: terminal items stop being read, so a sold item on a fixed reader aged
  -- past its 120-minute window within two hours and read `stale` forever after. Evidence
  -- age remains available for every row -- terminal ones included -- in
  -- freshness_age_minutes / freshness_window_minutes.
  CASE
    WHEN recalled_at_ts IS NOT NULL THEN 'unavailable'
    WHEN disposition_uri IN (
      'https://ref.gs1.org/cbv/Disp-retail_sold',
      'https://ref.gs1.org/cbv/Disp-in_transit'
    ) OR biz_step_uri IN (
      'https://ref.gs1.org/cbv/BizStep-shipping',
      'https://ref.gs1.org/cbv/BizStep-decommissioning'
    ) THEN 'absent'
    WHEN disposition_uri IN (
      'https://ref.gs1.org/cbv/Disp-damaged',
      'https://ref.gs1.org/cbv/Disp-expired',
      'https://ref.gs1.org/cbv/Disp-stolen',
      'https://ref.gs1.org/cbv/Disp-unavailable'
    ) THEN 'unavailable'
    WHEN timestampdiff(MINUTE, event_ts, ${rfid_as_of_ts}) >
         CASE
           WHEN is_mobile_platform THEN ${rfid_mobile_freshness_minutes}
           ELSE ${rfid_fixed_freshness_minutes}
         END THEN 'stale'
    ELSE 'present'
  END AS derived_presence_state,
  recalled_at_ts,
  CAST(${rfid_as_of_ts} AS TIMESTAMP) AS fresh_as_of_ts
FROM latest;
