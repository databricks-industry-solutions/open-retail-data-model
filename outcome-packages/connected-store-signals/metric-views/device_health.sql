-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Metric View: device_health
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-19
-- ============================================================
-- Sensing-fleet observability: one metric view dimensioned by device_type, replacing
-- what an earlier design had as three parallel fleet views. Following the idiom already
-- set by early-risk-detection/metric-views/feed_freshness.sql.
--
-- The scope consequence: IoT, RFID and Smart Shelf add ROWS here, not new views.
-- RFID rows contribute read volume, freshness and latency. They do not invent interval
-- cadence, expected observations, uptime or coverage; those measures remain NULL. Current
-- registered readers are still present on silent days so zero activity stays observable.
--
-- Includes the failures a sensing estate actually has, which generic feed monitoring
-- misses: Sparkplug seq gaps (the only in-band data-loss detector, ISO/IEC 20237:2023),
-- session restarts, calibration expiry (regulated metrology for vaccine storage), and
-- BACnet Out_Of_Service devices emitting simulated values.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.mv_device_health
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Sensing-fleet health across all Connected Store Signals device types: uptime, coverage, feed freshness, session integrity, calibration status and governance completeness. One view for the whole estate."
source: ${catalog}.${css_schema}.gold_css_device_health

fields:
  - name: store_id
    expr: store_id
    display_name: "Store"
    comment: "Durable store business key."
    synonyms: ["store", "location", "site", "branch"]

  - name: device_type
    expr: device_type
    display_name: "Device Type"
    comment: "The dimension that lets one view serve the whole estate: people_counter, occupancy_sensor, temperature, humidity, co2, illuminance, energy_meter, door_contact, rfid_reader, shelf_sensor, camera, esl_gateway."
    synonyms: ["sensor_type", "equipment_type", "device_kind"]

  - name: sensing_technology
    expr: sensing_technology
    display_name: "Sensing Technology"
    comment: "How the device senses. Drives both the accuracy and the privacy profile."
    synonyms: ["technology", "sensor_technology", "method"]

  - name: sensor_device_id
    expr: sensor_device_id
    display_name: "Device"
    comment: "Durable device business key."
    synonyms: ["device", "sensor", "device_id"]

  - name: store_zone_id
    expr: store_zone_id
    display_name: "Zone"
    comment: "Durable id of the zone the device is installed in."
    synonyms: ["zone", "area", "location_in_store"]

  - name: device_status
    expr: device_status
    display_name: "Device Status"
    comment: "active, inactive, faulty, maintenance or decommissioned."
    synonyms: ["status", "state"]

  - name: trading_date
    expr: trading_date
    display_name: "Trading Date"
    comment: "Business date of the health observation."
    synonyms: ["date", "day", "business_date"]

  - name: feed_freshness_status
    expr: feed_freshness_status
    display_name: "Feed Freshness"
    comment: "fresh (<= 60 min), delayed (<= 6 hr), stale (> 6 hr)."
    synonyms: ["freshness", "feed_status", "pipeline_status"]

  - name: calibration_status
    expr: calibration_status
    display_name: "Calibration Status"
    comment: "current, expiring_soon (<= 30 days), expired, or unknown. Regulated metrology for vaccine storage -- CDC/VFC requires recalibration or replacement per the certificate."
    synonyms: ["calibration", "cal_status"]

  - name: manufacturer
    expr: manufacturer
    display_name: "Manufacturer"
    comment: "Device manufacturer. Useful for isolating a fleet-wide fault to one vendor."
    synonyms: ["vendor", "make", "oem"]

  - name: firmware_version
    expr: firmware_version
    display_name: "Firmware Version"
    comment: "Current firmware. A common cause of a step change in counting behaviour, so it is worth grouping by when investigating a discontinuity."
    synonyms: ["firmware", "software_version"]

  - name: report_type
    expr: report_type
    display_name: "Report Type"
    comment: "What the device was reporting in these intervals: footfall, occupancy, dwell, temperature, humidity and so on. PART OF THE SOURCE GRAIN, because one device can report more than one thing -- filter on it when comparing interval counts across devices."
    synonyms: ["measurement_type", "signal_type", "sensor_report"]

  - name: aggregation_level
    expr: aggregation_level
    display_name: "Aggregation Level"
    comment: "The spatial level the intervals were reported at: site, area or object. PART OF THE SOURCE GRAIN -- an entrance counter emits both its own area rows and the store's site rows, so interval counts are only comparable within one level."
    synonyms: ["level", "spatial_level", "grain"]

  - name: sensing_method_code
    expr: sensing_method_code
    display_name: "Sensing Method"
    comment: "Method from the governance record. Present so a fleet review and a privacy review read the same row."
    synonyms: ["deployment_method", "governance_method"]

measures:
  - name: device_count
    expr: COUNT(DISTINCT sensor_device_id)
    display_name: "Device Count"
    comment: "Distinct devices in the grouping."
    synonyms: ["sensors", "fleet_size", "devices"]

  - name: online_rate
    expr: SUM(avg_uptime_ratio * intervals_reported) / NULLIF(SUM(CASE WHEN avg_uptime_ratio IS NOT NULL THEN intervals_reported END), 0)
    display_name: "Online Rate"
    comment: "Mean share of the interval devices were online, weighted by intervals reported so a device that sent two rows cannot outvote one that sent ninety-six."
    synonyms: ["uptime", "availability", "online_percentage"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: coverage_rate
    expr: SUM(avg_coverage_ratio * intervals_reported) / NULLIF(SUM(CASE WHEN avg_coverage_ratio IS NOT NULL THEN intervals_reported END), 0)
    display_name: "Coverage Rate"
    comment: "Mean share of expected sensors that reported, weighted by intervals reported."
    synonyms: ["coverage", "reporting_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: missing_observation_rate
    expr: 1 - ((SUM(observations_received) FILTER (WHERE observations_expected IS NOT NULL AND observations_received IS NOT NULL)) / NULLIF((SUM(observations_expected) FILTER (WHERE observations_expected IS NOT NULL AND observations_received IS NOT NULL)), 0))
    display_name: "Missing Observation Rate"
    comment: "Share of expected observations that never arrived, computed from the SUMMED numerator and denominator. The primary fleet KPI, so it must not be AVG(missing_observation_rate): that averages per-device rates and gives a device expecting 4 observations the same weight as one expecting 400, which understates a fleet-wide outage precisely when it matters."
    synonyms: ["missing_rate", "data_loss_rate", "gap_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: valid_interval_share
    expr: (SUM(valid_intervals) FILTER (WHERE report_type <> 'rfid:ReadEvent')) / NULLIF((SUM(intervals_reported) FILTER (WHERE report_type <> 'rfid:ReadEvent')), 0)
    display_name: "Valid Interval Share"
    comment: "Share of reported sensor intervals whose measurement was valid, from the summed counts rather than an average of per-device shares. Degraded, invalid and imputed intervals remain in the denominator. RFID events are excluded because their validity field represents non-stray reads; use mv_item_visibility.stray_read_rate for RFID quality."
    synonyms: ["validity_rate", "data_quality"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: feed_age_minutes
    expr: MAX(feed_age_minutes)
    display_name: "Feed Age (Minutes)"
    comment: "Worst feed age in the grouping. Lower is fresher."
    synonyms: ["staleness", "age_minutes", "lag"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 0

  - name: avg_latency_seconds
    expr: SUM(avg_latency_seconds * intervals_reported) / NULLIF(SUM(intervals_reported), 0)
    display_name: "Avg Ingest Latency (Seconds)"
    comment: "Mean seconds between interval end and ingest, weighted by intervals reported."
    synonyms: ["latency", "ingest_lag", "processing_delay"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: max_latency_seconds
    expr: MAX(max_latency_seconds)
    display_name: "Max Ingest Latency (Seconds)"
    comment: "Worst-case ingest latency observed."
    synonyms: ["peak_latency", "worst_lag"]

  - name: stale_device_count
    expr: COUNT(DISTINCT sensor_device_id) FILTER (WHERE feed_freshness_status = 'stale')
    display_name: "Stale Devices"
    comment: "Devices with no data in over 6 hours."
    synonyms: ["stale_count", "silent_devices", "unhealthy_devices"]

  - name: sequence_gap_count
    expr: SUM(sequence_gap_count)
    display_name: "Sequence Gaps"
    comment: "Source messages inferred missing within source sessions, summarized at interval grain."
    synonyms: ["lost_messages", "seq_gaps", "message_loss"]

  - name: session_restart_count
    expr: COUNT(*) FILTER (WHERE had_session_restart)
    display_name: "Session Restarts"
    comment: "Device-days with more than one source_session_id."
    synonyms: ["reboots", "restarts", "session_breaks"]

  - name: historical_message_count
    expr: SUM(historical_message_count)
    display_name: "Historical Messages"
    comment: "Delivered source messages marked as buffered or historical."
    synonyms: ["buffered_messages", "historical_replay"]

  - name: late_arrived_count
    expr: SUM(late_arrived_intervals)
    display_name: "Late-Arrived Intervals"
    comment: "Intervals that landed after their window closed. These feeds are not append-only -- vendors document data arriving hours or days late."
    synonyms: ["late_data", "backfilled_intervals"]

  - name: imputed_interval_count
    expr: SUM(imputed_intervals)
    display_name: "Imputed Intervals"
    comment: "Intervals whose value was modelled rather than measured."
    synonyms: ["estimated_intervals", "modelled_intervals"]

  - name: capped_interval_count
    expr: SUM(capped_intervals)
    display_name: "Capped Intervals"
    comment: "Intervals that hit the hardware detection ceiling. A capped peak is not an exact peak."
    synonyms: ["saturated_intervals", "ceiling_hits"]

  - name: expired_calibration_count
    expr: COUNT(DISTINCT sensor_device_id) FILTER (WHERE calibration_status = 'expired')
    display_name: "Expired Calibrations"
    comment: "Devices past their calibration validity date. For vaccine storage this is a compliance failure, not a maintenance backlog item."
    synonyms: ["out_of_calibration", "calibration_overdue"]

  - name: out_of_service_count
    expr: COUNT(DISTINCT sensor_device_id) FILTER (WHERE bacnet_out_of_service)
    display_name: "Out-of-Service Devices"
    comment: "BACnet Out_Of_Service devices. Their Present_Value is SIMULATED, so any reading from them is fabricated."
    synonyms: ["simulated_devices", "commissioning_devices"]

  - name: missing_dpia_count
    expr: COUNT(DISTINCT sensor_device_id) FILTER (WHERE NOT coalesce(dpia_completed_flag, FALSE))
    display_name: "Devices Without a DPIA"
    comment: "Active devices whose deployment has no completed impact assessment. COALESCE is load-bearing: the deployment join is a LEFT JOIN, so a device with NO governance record at all yields NULL, and a bare NOT NULL is NULL rather than TRUE -- the least-governed devices in the estate would have been the ones this count silently omitted. A governance gap surfaced alongside fleet health, because the two are reviewed by different people who need the same view."
    synonyms: ["governance_gaps", "no_dpia", "unassessed_devices"]
$$;
