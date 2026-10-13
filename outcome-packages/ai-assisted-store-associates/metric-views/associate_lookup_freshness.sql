-- ============================================================
-- ORDM · Outcome Package · AI-Assisted Store Associates
-- Metric View: associate_lookup_freshness
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-08-11
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-11
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${aasa_schema}.mv_associate_lookup_freshness
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Associate Real-Time Data Access feed freshness. Tracks lag and SLA state by feed and store."
source: >
  SELECT
    feed_name,
    store_id,
    freshness_status,
    sla_state,
    freshness_lag_minutes,
    event_count,
    last_source_event_timestamp,
    last_ingest_timestamp
  FROM ${catalog}.${aasa_schema}.gold_associate_data_freshness

fields:
  - name: feed_name
    expr: feed_name
    display_name: "Feed Name"
    comment: "Associate context feed being monitored."
    synonyms: ["data_source", "pipeline", "domain_feed"]

  - name: store_id
    expr: store_id
    display_name: "Store ID"
    comment: "Store scope for the freshness observation."
    synonyms: ["location_id", "store"]

  - name: freshness_status
    expr: freshness_status
    display_name: "Freshness Status"
    comment: "fresh (<60 min), delayed (60-1440 min), stale (>1440 min)."
    synonyms: ["feed_status", "staleness_status"]

  - name: sla_state
    expr: sla_state
    display_name: "SLA State"
    comment: "within_sla or breach relative to the 60-minute associate lookup objective."
    synonyms: ["sla_status", "threshold_state"]

measures:
  - name: freshness_lag_minutes
    expr: MAX(freshness_lag_minutes)
    display_name: "Freshness Lag (Minutes)"
    comment: "Minutes since last successful ingest for the feed."
    synonyms: ["lag_minutes", "age_minutes"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: event_count
    expr: SUM(event_count)
    display_name: "Event Count"
    comment: "Rows contributing to the freshness observation."
    synonyms: ["row_count", "volume"]

  - name: stale_feed_count
    expr: COUNT(*) FILTER (WHERE freshness_status = 'stale')
    display_name: "Stale Feeds"
    comment: "Feeds with lag over 24 hours."
    synonyms: ["stale_count"]

  - name: sla_breach_count
    expr: COUNT(*) FILTER (WHERE sla_state = 'breach')
    display_name: "SLA Breaches"
    comment: "Feeds exceeding the 60-minute associate freshness objective."
    synonyms: ["breach_count", "sla_violations"]
$$;
