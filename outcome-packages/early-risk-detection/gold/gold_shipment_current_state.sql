-- ============================================================
-- ORDM · Outcome Package · Early Risk Detection
-- View: gold_shipment_current_state
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-06-30
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-03 by @sreekanthmunigati
-- ============================================================
-- Current-state view: one row per shipment showing its latest tracking
-- checkpoint, carrier ETA, and transit progress. Driven from the
-- shipment header with a LEFT JOIN to the canonical-core
-- shipment_tracking feed, so shipments with no tracking events yet
-- (e.g. planned, pre-first-scan) are still visible with their header
-- status. Transit elapsed is capped at actual_arrival_date for
-- delivered shipments.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${risk_schema}.gold_shipment_current_state AS
WITH latest_tracking AS (
  SELECT
    st.*,
    ROW_NUMBER() OVER (
      PARTITION BY st.shipment_id
      ORDER BY st.event_timestamp DESC, st.shipment_tracking_sk DESC
    ) AS rn
  FROM ${catalog}.${logistics_schema}.shipment_tracking st
)
SELECT
  s.shipment_sk,
  s.shipment_id,
  s.supplier_id,
  s.supplier_sk,
  sup.supplier_name,
  s.lane_sk,
  s.lane_id,
  s.destination_store_id,
  s.carrier_name,
  s.transport_mode,
  s.ship_date,
  s.original_eta_date,
  s.estimated_arrival_date,
  s.actual_arrival_date,
  -- If no tracking yet, fall back to shipment_status from the header
  COALESCE(lt.checkpoint_type, s.shipment_status) AS current_status,
  lt.checkpoint_message       AS current_status_reason,
  lt.event_timestamp          AS last_event_timestamp,
  lt.facility_name            AS last_known_location,
  lt.city                     AS last_known_city,
  lt.country_code             AS last_known_country,
  lt.latitude                 AS last_known_latitude,
  lt.longitude                AS last_known_longitude,
  lt.carrier_code,
  lt.tracking_number,
  COALESCE(lt.carrier_eta_date, s.estimated_arrival_date) AS current_eta_date,
  -- ETA slip: positive = late, negative = early
  DATEDIFF(COALESCE(lt.carrier_eta_date, s.estimated_arrival_date), s.original_eta_date) AS eta_slip_days,
  -- Transit elapsed: cap at actual arrival for delivered shipments
  DATEDIFF(COALESCE(s.actual_arrival_date, CURRENT_DATE()), s.ship_date) AS transit_elapsed_days,
  la.planned_transit_days,
  -- Freshness
  lt.ingest_timestamp         AS last_ingest_timestamp,
  lt.latency_seconds          AS last_event_latency_seconds
FROM ${catalog}.${logistics_schema}.shipment s
LEFT JOIN latest_tracking lt ON lt.shipment_id = s.shipment_id AND lt.rn = 1
LEFT JOIN ${catalog}.${supplier_schema}.supplier sup ON sup.supplier_id = s.supplier_id AND sup.is_current = TRUE
LEFT JOIN ${catalog}.${logistics_schema}.lane la ON la.lane_id = s.lane_id AND la.is_current = TRUE;
