-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Metric View: item_visibility
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-08-18
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-19
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.mv_item_visibility
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "RFID item-visibility quality: read volume, unique visible items, attribution, unregistered and stray rates, duplicates and freshness."
source: ${catalog}.${css_schema}.gold_item_visibility_daily

fields:
  - name: store_id
    expr: store_id
    display_name: "Store"
    comment: "Durable store business key."
    synonyms: ["store", "site", "location"]

  - name: product_id
    expr: product_id
    display_name: "Product"
    comment: "Durable product key; NULL groups unregistered EPCs that could not resolve to a product."
    synonyms: ["product", "sku", "item"]

  - name: trading_date
    expr: trading_date
    display_name: "Trading Date"
    comment: "Business date of the visibility observations."
    synonyms: ["date", "day", "business_date"]

measures:
  - name: read_event_count
    expr: SUM(read_event_count)
    display_name: "Read Event Count"
    comment: "Deduplicated EPC × reader × second visibility events."
    synonyms: ["reads", "rfid_events", "visibility_events"]

  - name: visible_item_count
    expr: SUM(distinct_items_read)
    display_name: "Visible Item Count"
    comment: "Daily distinct serialized items read. Sum across days is item-days, not globally distinct items."
    synonyms: ["items_seen", "tagged_units_seen", "item_days"]

  - name: unregistered_epc_rate
    expr: SUM(unregistered_read_count) / NULLIF(SUM(read_event_count), 0)
    display_name: "Unregistered EPC Rate"
    comment: "Share of read events whose EPC has no commissioned registry row."
    synonyms: ["unknown_tag_rate", "uncommissioned_rate"]
    format:
      type: percentage
      decimal_places: {type: exact, places: 1}

  - name: stray_read_rate
    expr: SUM(stray_read_count) / NULLIF(SUM(read_event_count), 0)
    display_name: "Stray Read Rate"
    comment: "Share of reads suspected to be RF bleed and excluded from location/presence state."
    synonyms: ["rf_bleed_rate", "misattribution_rate"]
    format:
      type: percentage
      decimal_places: {type: exact, places: 1}

  - name: duplicate_delivery_rate
    expr: SUM(duplicate_delivery_count) / NULLIF(SUM(read_event_count) + SUM(duplicate_delivery_count), 0)
    display_name: "Duplicate Delivery Rate"
    comment: "Suppressed duplicate deliveries as a share of delivered plus retained event records."
    synonyms: ["duplicate_rate", "redelivery_rate"]
    format:
      type: percentage
      decimal_places: {type: exact, places: 1}

  - name: average_attribution_confidence
    expr: SUM(avg_attribution_confidence * read_event_count) / NULLIF(SUM(read_event_count), 0)
    display_name: "Average Attribution Confidence"
    comment: "Read-count-weighted confidence that events belong to their stated read point."
    synonyms: ["attribution_quality", "location_confidence"]
    format:
      type: percentage
      decimal_places: {type: exact, places: 1}

  - name: max_freshness_age_minutes
    expr: MAX(freshness_age_minutes)
    display_name: "Maximum Freshness Age (Minutes)"
    comment: "Oldest latest-event age among grouped store-product-days."
    synonyms: ["feed_age", "read_age", "staleness_minutes"]
$$;
