-- ============================================================
-- ORDM · Outcome Package · Early Risk Detection
-- Metric View: feed_freshness
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-06-30
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-02 by @sreekanthmunigati
-- ============================================================
-- Feed freshness metric: monitors how current the data feeds are
-- by measuring the age and latency of the most recent events in
-- each key table. A stale feed is itself a disruption signal —
-- if shipment status events stop arriving, the control tower is
-- flying blind.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${risk_schema}.mv_feed_freshness
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Data feed freshness monitoring. Tracks the age and latency of key event feeds. A stale feed is itself a disruption signal."
source: >
  SELECT
    feed_name,
    last_event_timestamp,
    last_ingest_timestamp,
    avg_latency_seconds,
    max_latency_seconds,
    total_events,
    feed_age_minutes,
    CASE
      WHEN feed_age_minutes > 1440 THEN 'stale'
      WHEN feed_age_minutes > 60 THEN 'delayed'
      ELSE 'fresh'
    END AS freshness_status
  FROM (
    SELECT
      'shipment_tracking' AS feed_name,
      MAX(event_timestamp) AS last_event_timestamp,
      MAX(ingest_timestamp) AS last_ingest_timestamp,
      ROUND(AVG(latency_seconds), 1) AS avg_latency_seconds,
      MAX(latency_seconds) AS max_latency_seconds,
      COUNT(*) AS total_events,
      ROUND((UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(MAX(ingest_timestamp))) / 60.0, 1) AS feed_age_minutes
    FROM ${catalog}.${logistics_schema}.shipment_tracking
    UNION ALL
    SELECT
      'disruption_event' AS feed_name,
      MAX(event_timestamp),
      MAX(ingest_timestamp),
      ROUND(AVG(latency_seconds), 1),
      MAX(latency_seconds),
      COUNT(*),
      ROUND((UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(MAX(ingest_timestamp))) / 60.0, 1)
    FROM ${catalog}.${risk_schema}.disruption_event
    UNION ALL
    SELECT
      'inventory_position' AS feed_name,
      CAST(MAX(date_key) AS TIMESTAMP),
      MAX(load_timestamp),
      CAST(NULL AS DOUBLE),
      CAST(NULL AS INT),
      COUNT(*),
      ROUND((UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(MAX(load_timestamp))) / 60.0, 1)
    FROM ${catalog}.${inventory_schema}.inventory_position
  )

fields:
  - name: feed_name
    expr: feed_name
    display_name: "Feed Name"
    comment: "Name of the data feed being monitored."
    synonyms: ["data_source", "pipeline", "feed"]

  - name: freshness_status
    expr: freshness_status
    display_name: "Freshness Status"
    comment: "Feed health: fresh (<60 min), delayed (60 min - 24 hr), stale (>24 hr)."
    synonyms: ["feed_status", "health_status", "pipeline_status"]

  - name: last_event_timestamp
    expr: last_event_timestamp
    display_name: "Last Event"
    comment: "Timestamp of the most recent event in this feed."
    synonyms: ["latest_event", "last_seen"]

  - name: last_ingest_timestamp
    expr: last_ingest_timestamp
    display_name: "Last Ingested"
    comment: "Timestamp of the most recent ingestion for this feed."
    synonyms: ["latest_ingest", "last_loaded"]

measures:
  - name: feed_age_minutes
    expr: MAX(feed_age_minutes)
    display_name: "Feed Age (Minutes)"
    comment: "Minutes since the last event was ingested. Lower = fresher."
    synonyms: ["staleness", "age_minutes", "minutes_since_update"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: avg_latency_seconds
    expr: AVG(avg_latency_seconds)
    display_name: "Avg Ingest Latency (Seconds)"
    comment: "Average time in seconds between event occurrence and lakehouse ingestion."
    synonyms: ["ingest_lag", "processing_delay", "latency"]
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

  - name: total_events
    expr: SUM(total_events)
    display_name: "Total Events"
    comment: "Total number of events across all monitored feeds."
    synonyms: ["event_count", "record_count", "volume"]

  - name: feed_count
    expr: COUNT(*)
    display_name: "Feed Count"
    comment: "Number of feeds being monitored."
    synonyms: ["source_count", "pipeline_count"]

  - name: stale_feed_count
    expr: COUNT(*) FILTER (WHERE freshness_status = 'stale')
    display_name: "Stale Feeds"
    comment: "Number of feeds with no new data in over 24 hours."
    synonyms: ["stale_count", "unhealthy_feeds"]
$$;
