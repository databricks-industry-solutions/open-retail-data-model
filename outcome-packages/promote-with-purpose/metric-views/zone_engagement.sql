-- ============================================================
-- ORDM · Outcome Package · Promote with Purpose
-- Metric View: zone_engagement
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-08-10
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-10 by @a0x8o
-- ============================================================
-- Weekly engagement per location zone: active offers, triggers, pseudonymous
-- reach and the trigger-to-redemption conversion rate.
--
-- The zone is joined on the DURABLE zone_id, never the version-specific zone_sk
-- (standard §A.16), so a re-versioned zone does not fragment into two rows and no
-- SCD2 surrogate is exposed as a groupable dimension.
--
-- conversion_rate is a RATIO OF SUMS. gold_zone_engagement_weekly stores the rate
-- but not its numerator, so the redemption count is reconstructed in the source as
-- conversion_rate x trigger_events — see the measure comment for the rounding
-- caveat that carries.
--
-- PRIVACY: no customer key, no coordinate, no device identifier. The zone's
-- geohash centroid is deliberately NOT projected.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${promo_schema}.mv_zone_engagement
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Weekly location-zone engagement: active offers, triggers, pseudonymous reach and trigger-to-redemption conversion."
source: >
  SELECT
    g.zone_id,
    z.zone_type,
    z.store_id,
    g.fiscal_week_id,
    g.active_offers,
    g.trigger_events,
    g.unique_customers,
    ROUND(g.conversion_rate * g.trigger_events) AS redemption_events
  FROM ${catalog}.${promo_schema}.gold_zone_engagement_weekly g
  JOIN ${catalog}.${promo_schema}.offer_zone z
    ON z.zone_id = g.zone_id AND z.is_current = TRUE

fields:
  - name: zone_id
    expr: zone_id
    display_name: "Zone ID"
    comment: "Durable business key for the location zone."
    synonyms: ["zone", "geofence_id", "area_id"]

  - name: zone_type
    expr: zone_type
    display_name: "Zone Type"
    comment: "Zone geometry kind: store_radius, polygon, beacon, mall_common_area."
    synonyms: ["geofence_type", "area_type", "zone_kind"]

  - name: store_id
    expr: store_id
    display_name: "Anchor Store ID"
    comment: "Durable business key of the store the zone is anchored to."
    synonyms: ["location_id", "site", "store"]

  - name: fiscal_week_id
    expr: fiscal_week_id
    display_name: "Fiscal Week"
    comment: "NRF 4-5-4 fiscal week identifier (fiscal_year * 100 + fiscal_week)."
    synonyms: ["week", "retail_week", "fiscal_period"]

measures:
  - name: active_offers
    expr: SUM(active_offers)
    display_name: "Active Offers"
    comment: "Distinct active location offers with events in the zone-week."
    synonyms: ["live_offers", "running_offers", "offer_count"]

  - name: trigger_events
    expr: SUM(trigger_events)
    display_name: "Triggers"
    comment: "Number of trigger events recorded in the zone-week."
    synonyms: ["triggers", "entries", "trigger_count"]

  - name: unique_customers
    expr: SUM(unique_customers)
    display_name: "Customers Engaged"
    comment: "Pseudonymous customers engaged, summed across zone-weeks (a customer active in two weeks counts twice)."
    synonyms: ["reach", "engaged_customers", "audience"]

  - name: conversion_rate
    expr: SUM(redemption_events) / NULLIF(SUM(trigger_events), 0)
    display_name: "Conversion Rate"
    comment: "Redemptions / triggers. Ratio of sums; the numerator is reconstructed from the stored DECIMAL(9,4) rate, so it carries that rounding."
    synonyms: ["trigger_conversion", "redeem_rate", "conversion"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2
$$;
