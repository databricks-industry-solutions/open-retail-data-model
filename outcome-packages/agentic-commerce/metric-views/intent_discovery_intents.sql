-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce
-- Metric View: intent_discovery_intents
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-10-12
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-10-12
-- ============================================================
-- Intent-grain KPIs for Intent Product Discovery: how many shopper intents were
-- captured and how many returned nothing. One row per discovery_intent_event, with
-- its count of returned result events (LEFT JOIN, so an intent with no results is
-- kept with 0). Zero-Result Rate follows the glossary: intent events that return
-- no result events divided by total intent events. The result-grain KPIs (CTR,
-- add-to-cart, conversion) are in mv_intent_discovery_result_performance.
-- Privacy-safe: no intent text, hash, session or customer identifier is exposed.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${ac_schema}.mv_intent_discovery_intents
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Intent Product Discovery intent-grain KPIs: shopper intents captured, intents that returned no results, zero-result rate and results returned per intent, by channel, intent category and date."
source: >
  SELECT
    i.discovery_channel,
    i.intent_category,
    i.event_date,
    COUNT(r.discovery_result_event_id) AS result_event_count
  FROM ${catalog}.${ac_schema}.discovery_intent_event i
  LEFT JOIN ${catalog}.${ac_schema}.discovery_result_event r
    ON r.discovery_intent_event_id = i.discovery_intent_event_id
  GROUP BY i.discovery_intent_event_id, i.discovery_channel, i.intent_category, i.event_date

fields:
  - name: discovery_channel
    expr: discovery_channel
    display_name: "Discovery Channel"
    comment: "Surface where the intent was captured (for example web, mobile_app, kiosk, store_associate, voice, api)."
    synonyms: ["channel", "surface"]
  - name: intent_category
    expr: intent_category
    display_name: "Intent Category"
    comment: "Classified category of the shopper intent."
    synonyms: ["category", "intent_type"]
  - name: event_date
    expr: event_date
    display_name: "Intent Date"
    comment: "Date the intent was captured."
    synonyms: ["date"]

measures:
  - name: intent_count
    expr: COUNT(*)
    display_name: "Intents"
    comment: "Count of discovery intent events."
    synonyms: ["searches", "intent_events"]
  - name: zero_result_intent_count
    expr: SUM(CASE WHEN result_event_count = 0 THEN 1 ELSE 0 END)
    display_name: "Zero-Result Intents"
    comment: "Intent events that returned no result events."
    synonyms: ["null_searches", "no_result_intents"]
  - name: zero_result_rate
    expr: SUM(CASE WHEN result_event_count = 0 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0)
    display_name: "Zero-Result Rate"
    comment: "Intent events that return no result events divided by total intent events (glossary Zero-Result Rate)."
    synonyms: ["null_search_rate", "no_result_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
  - name: results_per_intent
    expr: SUM(result_event_count) / NULLIF(COUNT(*), 0)
    display_name: "Results per Intent"
    comment: "Returned result events per intent event, a ratio-of-sums."
    synonyms: ["avg_results_returned"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 2
$$;
