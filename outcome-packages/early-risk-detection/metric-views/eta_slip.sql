-- ============================================================
-- ORDM · Outcome Package · Early Risk Detection
-- Metric View: eta_slip
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-06-30
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-02 by @sreekanthmunigati
-- ============================================================
-- ETA slip metric: measures the difference between the current/actual
-- arrival date and the original ETA at dispatch. Positive = late.
-- Grained at shipment level; aggregatable by supplier, lane, carrier,
-- and time period.
--
-- ETA source design: For delivered shipments, effective_arrival_date uses
-- actual_arrival_date (definitive). For in-transit shipments, it falls back
-- to estimated_arrival_date (the load-time ETA from the shipment header).
-- This is intentional: the KPI lens measures outcome vs plan using the
-- header ETA, while the real-time lens in gold_shipment_current_state
-- uses the carrier's revised ETA (carrier_eta_date from shipment_tracking).
-- See glossary "ETA slip" for the two-lens design.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${risk_schema}.mv_eta_slip
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "ETA slip measurement per shipment. Positive slip = late arrival relative to the original ETA at dispatch."
source: >
  SELECT
    s.shipment_sk,
    s.shipment_id,
    s.supplier_sk,
    s.supplier_id,
    sup.supplier_name,
    s.lane_sk,
    s.lane_id,
    s.carrier_name,
    s.transport_mode,
    s.ship_date,
    s.original_eta_date,
    COALESCE(s.actual_arrival_date, s.estimated_arrival_date) AS effective_arrival_date,
    DATEDIFF(COALESCE(s.actual_arrival_date, s.estimated_arrival_date), s.original_eta_date) AS eta_slip_days_raw,
    s.shipment_status,
    la.planned_transit_days,
    DATEDIFF(COALESCE(s.actual_arrival_date, CURRENT_DATE()), s.ship_date) AS actual_transit_days_raw
  FROM ${catalog}.${logistics_schema}.shipment s
  LEFT JOIN ${catalog}.${supplier_schema}.supplier sup
    ON sup.supplier_id = s.supplier_id AND sup.is_current = TRUE
  LEFT JOIN ${catalog}.${logistics_schema}.lane la
    ON la.lane_id = s.lane_id AND la.is_current = TRUE
  WHERE s.original_eta_date IS NOT NULL
    AND s.ship_date IS NOT NULL
    AND (s.shipment_status IS NULL OR s.shipment_status != 'cancelled')

fields:
  - name: shipment_id
    expr: shipment_id
    display_name: "Shipment ID"
    comment: "Durable business key for the shipment."
    synonyms: ["shipment", "ASN", "shipment_number"]

  - name: supplier_name
    expr: supplier_name
    display_name: "Supplier"
    comment: "Name of the supplier who dispatched the shipment."
    synonyms: ["vendor", "supplier", "shipper"]

  - name: carrier_name
    expr: carrier_name
    display_name: "Carrier"
    comment: "Carrier or logistics provider."
    synonyms: ["logistics_provider", "carrier", "transporter"]

  - name: transport_mode
    expr: transport_mode
    display_name: "Transport Mode"
    comment: "How goods move: road, rail, ocean, air, or intermodal."
    synonyms: ["mode", "shipping_method"]

  - name: ship_date
    expr: ship_date
    display_name: "Ship Date"
    comment: "Date the shipment departed origin."
    synonyms: ["dispatch_date", "departure_date"]
    format:
      type: date
      date_format: year_month_day

  - name: original_eta_date
    expr: original_eta_date
    display_name: "Original ETA"
    comment: "Estimated arrival date at time of dispatch, before any revisions."
    synonyms: ["planned_arrival", "baseline_eta"]
    format:
      type: date
      date_format: year_month_day

  - name: effective_arrival_date
    expr: effective_arrival_date
    display_name: "Effective Arrival Date"
    comment: "Actual arrival date if delivered, otherwise current estimated arrival."
    synonyms: ["arrival_date", "actual_arrival"]
    format:
      type: date
      date_format: year_month_day

  - name: eta_slip_tier
    expr: >
      CASE
        WHEN eta_slip_days_raw > 3 THEN 'severe'
        WHEN eta_slip_days_raw > 1 THEN 'moderate'
        WHEN eta_slip_days_raw > 0 THEN 'minor'
        ELSE 'on_time_or_early'
      END
    display_name: "ETA Slip Tier"
    comment: "Severity tier: severe (>3d late), moderate (1-3d), minor (0-1d), on_time_or_early."
    synonyms: ["delay_severity", "slip_category"]

  - name: shipment_status
    expr: shipment_status
    display_name: "Shipment Status"
    comment: "Current lifecycle status: planned, in_transit, delivered, cancelled."
    synonyms: ["status", "delivery_status"]

measures:
  - name: eta_slip_days
    expr: AVG(eta_slip_days_raw)
    display_name: "Avg ETA Slip (Days)"
    comment: "Average ETA slip in days across shipments. Positive = late, negative = early."
    synonyms: ["average_delay", "mean_slip", "avg_delay_days"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: max_eta_slip_days
    expr: MAX(eta_slip_days_raw)
    display_name: "Max ETA Slip (Days)"
    comment: "Worst-case ETA slip in days."
    synonyms: ["worst_delay", "peak_slip"]

  - name: shipment_count
    expr: COUNT(DISTINCT shipment_id)
    display_name: "Shipment Count"
    comment: "Number of shipments."
    synonyms: ["total_shipments", "num_shipments"]

  - name: late_shipment_count
    expr: COUNT(DISTINCT shipment_id) FILTER (WHERE eta_slip_days_raw > 0 AND shipment_status = 'delivered')
    display_name: "Late Shipments"
    comment: "Number of delivered shipments that arrived after the original ETA."
    synonyms: ["delayed_shipments", "overdue_count"]

  - name: on_time_rate
    expr: >
      1.0 - CAST(COUNT(DISTINCT shipment_id) FILTER (WHERE eta_slip_days_raw > 0 AND shipment_status = 'delivered') AS DOUBLE)
      / NULLIF(COUNT(DISTINCT shipment_id) FILTER (WHERE shipment_status = 'delivered'), 0)
    display_name: "On-Time Rate"
    comment: "Fraction of delivered shipments arriving on or before the original ETA."
    synonyms: ["OTD", "on_time_delivery_rate", "otd_pct"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: avg_actual_transit_days
    expr: AVG(actual_transit_days_raw) FILTER (WHERE shipment_status = 'delivered')
    display_name: "Avg Transit Days"
    comment: "Average actual transit time in days (delivered shipments only)."
    synonyms: ["mean_transit_time", "average_transit"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1
$$;
