-- ============================================================
-- ORDM · Outcome Package · Promote with Purpose
-- Metric View: location_offer_performance
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-08-10
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-10 by @a0x8o
-- ============================================================
-- The location-offer delivery funnel — triggered, suppressed, delivered, opened,
-- redeemed — with the four rates and redemption-attributed sales, sliceable by
-- offer configuration, store and fiscal week.
--
-- Every rate is a RATIO OF SUMS, never an average of the per-row rate already on
-- the gold table: averaging a bounded rate across weeks or stores weights small
-- cells equally with large ones and does not reproduce the true rate.
--
-- PRIVACY: this view exposes no customer key and no location or device attribute.
-- Reach appears only as an aggregate count.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${promo_schema}.mv_location_offer_performance
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Location-based offer delivery funnel and its four rates, by offer configuration, store and fiscal week."
source: >
  SELECT
    lo.location_offer_id,
    lo.promotion_id,
    lo.trigger_type,
    lo.channel,
    lo.status,
    g.store_id,
    st.store_name,
    st.region,
    g.fiscal_week_id,
    g.trigger_events,
    g.suppressed_events,
    g.delivered_events,
    g.opened_events,
    g.redemptions,
    g.unique_customers_reached,
    g.attributed_sales_amount
  FROM ${catalog}.${promo_schema}.gold_location_offer_performance g
  JOIN ${catalog}.${promo_schema}.location_offer lo
    ON lo.location_offer_sk = g.location_offer_sk
  JOIN ${catalog}.${store_schema}.store st
    ON st.store_id = g.store_id AND st.is_current = TRUE

fields:
  - name: location_offer_id
    expr: location_offer_id
    display_name: "Offer ID"
    comment: "Durable business key for the location-triggered offer."
    synonyms: ["offer_id", "offer", "location_offer"]

  - name: promotion_id
    expr: promotion_id
    display_name: "Promotion ID"
    comment: "Durable business key of the promotion this offer delivers."
    synonyms: ["promo_id", "promotion", "deal_id"]

  - name: trigger_type
    expr: trigger_type
    display_name: "Trigger Type"
    comment: "Device signal that fires the offer: geofence_enter, geofence_exit, dwell, beacon_proximity."
    synonyms: ["trigger", "signal_type", "fire_condition"]

  - name: channel
    expr: channel
    display_name: "Channel"
    comment: "Delivery channel: push, sms, email, in_app."
    synonyms: ["delivery_channel", "medium", "send_channel"]

  - name: status
    expr: status
    display_name: "Offer Status"
    comment: "Offer lifecycle state: draft, active, paused, ended."
    synonyms: ["offer_status", "lifecycle_state", "state"]

  - name: store_id
    expr: store_id
    display_name: "Store ID"
    comment: "Durable business key for the store where the events occurred."
    synonyms: ["location_id", "site", "store"]

  - name: store_name
    expr: store_name
    display_name: "Store Name"
    comment: "Display name of the store."
    synonyms: ["location_name", "site_name"]

  - name: region
    expr: region
    display_name: "Region"
    comment: "Geographic region the store belongs to."
    synonyms: ["area", "territory", "market"]

  - name: fiscal_week_id
    expr: fiscal_week_id
    display_name: "Fiscal Week"
    comment: "NRF 4-5-4 fiscal week identifier (fiscal_year * 100 + fiscal_week)."
    synonyms: ["week", "retail_week", "fiscal_period"]

measures:
  - name: trigger_events
    expr: SUM(trigger_events)
    display_name: "Triggers"
    comment: "Number of times the offer's trigger condition fired."
    synonyms: ["triggers", "trigger_count", "fires"]

  - name: delivered_events
    expr: SUM(delivered_events)
    display_name: "Delivered"
    comment: "Number of offers actually delivered to a customer."
    synonyms: ["deliveries", "sends", "delivered_count"]

  - name: suppressed_events
    expr: SUM(suppressed_events)
    display_name: "Suppressed"
    comment: "Number of triggers suppressed by consent, frequency caps or quiet hours."
    synonyms: ["suppressions", "blocked", "throttled"]

  - name: redemptions
    expr: SUM(redemptions)
    display_name: "Redemptions"
    comment: "Number of delivered offers redeemed against a transaction."
    synonyms: ["redeemed", "conversions", "redemption_count"]

  - name: unique_customers_reached
    expr: SUM(unique_customers_reached)
    display_name: "Customers Reached"
    comment: "Pseudonymous customers with a delivered offer, summed across store-weeks (a customer reached in two stores counts twice)."
    synonyms: ["reach", "audience_reached", "customers"]

  - name: delivery_rate
    expr: SUM(delivered_events) / NULLIF(SUM(delivered_events) + SUM(suppressed_events), 0)
    display_name: "Delivery Rate"
    comment: "Delivered / (delivered + suppressed). Ratio of sums, not an average of per-row rates."
    synonyms: ["send_rate", "delivery_ratio", "pass_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: open_rate
    expr: SUM(opened_events) / NULLIF(SUM(delivered_events), 0)
    display_name: "Open Rate"
    comment: "Opened / delivered. Ratio of sums, not an average of per-row rates."
    synonyms: ["engagement_rate", "open_ratio"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: redemption_rate
    expr: SUM(redemptions) / NULLIF(SUM(delivered_events), 0)
    display_name: "Redemption Rate"
    comment: "Redemptions / delivered. Ratio of sums, not an average of per-row rates."
    synonyms: ["conversion_rate", "redeem_rate", "take_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: suppression_rate
    expr: SUM(suppressed_events) / NULLIF(SUM(delivered_events) + SUM(suppressed_events), 0)
    display_name: "Suppression Rate"
    comment: "Suppressed / (delivered + suppressed). Ratio of sums, not an average of per-row rates."
    synonyms: ["throttle_rate", "block_rate", "suppression_ratio"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: attributed_sales_amount
    expr: SUM(attributed_sales_amount)
    display_name: "Attributed Sales"
    comment: "Net revenue on transactions attributed to a redeemed offer, in the reporting/base currency."
    synonyms: ["redemption_sales", "attributed_revenue", "offer_revenue"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 2
$$;
