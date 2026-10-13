-- ============================================================
-- ORDM · Outcome Package · Unified Customer View
-- Metric View: cdp_campaign_touch
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-10-12
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-10-12
-- ============================================================
-- The campaign KPIs of the UCV glossary as a UC Metric View over the campaign_touch
-- extension table (ADR 0026), one row per campaign interaction with a customer.
-- campaign_reach is COUNT(DISTINCT profile_id): a customer touched several times
-- counts once. profile_id is used only inside that count, never as a dimension.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${ucv_schema}.mv_cdp_campaign_touch
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "CDP campaign KPIs: campaign interactions and distinct customers reached, by promotion, channel, direction, touch type and delivery status."
source: >
  SELECT
    ct.profile_id,
    ct.promo_id,
    ct.channel_code,
    ct.touch_direction,
    ct.touch_type,
    ct.delivery_status_code,
    ct.touch_date
  FROM ${catalog}.${ucv_schema}.campaign_touch ct

fields:
  - name: promo_id
    expr: promo_id
    display_name: "Promotion"
    comment: "Promotion (campaign) the touch belongs to."
    synonyms: ["campaign", "promotion"]
  - name: channel_code
    expr: channel_code
    display_name: "Channel"
    comment: "Channel of the touch."
    synonyms: ["channel", "medium"]
  - name: touch_direction
    expr: touch_direction
    display_name: "Direction"
    comment: "Outbound (sent to the customer) or inbound (customer response)."
    synonyms: ["direction"]
  - name: touch_type
    expr: touch_type
    display_name: "Touch Type"
    comment: "Kind of interaction (for example send, open, click)."
    synonyms: ["interaction_type", "event_type"]
  - name: delivery_status_code
    expr: delivery_status_code
    display_name: "Delivery Status"
    comment: "Delivery outcome of the touch."
    synonyms: ["delivery_status"]
  - name: touch_date
    expr: touch_date
    display_name: "Touch Date"
    comment: "Date of the touch."
    synonyms: ["date"]

measures:
  - name: campaign_touch_count
    expr: COUNT(*)
    display_name: "Campaign Touches"
    comment: "Count of campaign interactions (glossary campaign_touch_count)."
    synonyms: ["touches", "interactions"]
  - name: campaign_reach
    expr: COUNT(DISTINCT profile_id)
    display_name: "Campaign Reach"
    comment: "Distinct customers touched (glossary campaign_reach); a customer touched several times counts once."
    synonyms: ["reach", "customers_reached"]
$$;
