-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- Metric View: campaign_performance
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-07-14
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-14
-- ============================================================
-- Semantic layer over campaign_day: the conformed retail-media delivery +
-- outcome KPIs (impressions, clicks, spend, attributed sales, ROAS, CTR, CVR,
-- viewability, IVT rate, new-to-brand, iROAS) with campaign / advertiser /
-- delivery-channel / attribution-model dimensions for Genie and AI/BI. Attributed
-- measures are single-model per campaign x day (guarded by acd_single_attribution_model),
-- so the ratio measures never mix attribution models. Supplier-safe: threshold-
-- suppressed rows are excluded; no person-level data.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${cmn_schema}.mv_campaign_performance
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Retail-media campaign performance KPIs (delivery, attribution, incrementality) by campaign, advertiser, delivery channel, and attribution model."
source: >
  SELECT
    a.metric_date,
    a.advertiser_id,
    sb.brand_name,
    a.campaign_id,
    c.campaign_name,
    a.delivery_channel_id,
    a.attribution_model,
    a.impressions,
    a.viewable_impressions,
    a.gross_impressions,
    a.invalid_traffic_impressions,
    a.clicks,
    a.conversions,
    a.orders,
    a.units,
    a.media_spend_net,
    a.attributed_net_sales,
    a.same_sku_sales,
    a.halo_sales,
    a.new_to_brand_sales,
    a.incremental_sales
  FROM ${catalog}.${cmn_schema}.campaign_day a
  LEFT JOIN ${catalog}.${cmn_schema}.campaign c
    ON c.campaign_id = a.campaign_id AND c.is_current = TRUE
  LEFT JOIN ${catalog}.${cmn_schema}.advertiser sb
    ON sb.advertiser_id = a.advertiser_id AND sb.is_current = TRUE
  WHERE COALESCE(a.privacy_suppressed_flag, FALSE) = FALSE

fields:
  - name: metric_date
    expr: metric_date
    display_name: "Metric Date"
    comment: "Business date of the aggregate."
    synonyms: ["date", "day", "report_date"]

  - name: advertiser_id
    expr: advertiser_id
    display_name: "Advertiser ID"
    comment: "Durable advertiser business key."
    synonyms: ["advertiser", "brand_owner"]

  - name: brand_name
    expr: brand_name
    display_name: "Brand"
    comment: "Advertised brand name."
    synonyms: ["brand", "advertiser_brand"]

  - name: campaign_id
    expr: campaign_id
    display_name: "Campaign ID"
    comment: "Durable campaign business key."
    synonyms: ["campaign"]

  - name: campaign_name
    expr: campaign_name
    display_name: "Campaign Name"
    comment: "Campaign display name."
    synonyms: ["campaign_title"]

  - name: delivery_channel_id
    expr: delivery_channel_id
    display_name: "Delivery Channel"
    comment: "Coarse distribution channel the ad ran in (onsite_web, offsite, in_store_screen, dooh, ...)."
    synonyms: ["channel", "surface", "environment"]

  - name: attribution_model
    expr: attribution_model
    display_name: "Attribution Model"
    comment: "The single attribution model the attributed measures are reported under for this campaign x day."
    synonyms: ["attribution", "model"]

measures:
  - name: impressions
    expr: SUM(impressions)
    display_name: "Impressions"
    comment: "Total impressions."
    synonyms: ["imps", "delivered_impressions"]

  - name: viewable_impressions
    expr: SUM(viewable_impressions)
    display_name: "Viewable Impressions"
    comment: "Viewable impressions (MRC/IAB)."
    synonyms: ["viewable_imps"]

  - name: clicks
    expr: SUM(clicks)
    display_name: "Clicks"
    comment: "Total clicks."
    synonyms: ["click_count"]

  - name: conversions
    expr: SUM(conversions)
    display_name: "Conversions"
    comment: "Attributed conversions."
    synonyms: ["conv"]

  - name: media_spend_net
    expr: SUM(media_spend_net)
    display_name: "Media Spend (Net)"
    comment: "Net media spend, reporting/base currency."
    synonyms: ["spend", "net_spend", "ad_spend"]

  - name: attributed_net_sales
    expr: SUM(attributed_net_sales)
    display_name: "Attributed Net Sales"
    comment: "Attributed net sales, reporting/base currency."
    synonyms: ["attributed_sales", "ad_attributed_revenue"]

  - name: new_to_brand_sales
    expr: SUM(new_to_brand_sales)
    display_name: "New-to-Brand Sales"
    comment: "New-to-brand attributed sales."
    synonyms: ["ntb_sales"]

  - name: incremental_sales
    expr: SUM(incremental_sales)
    display_name: "Incremental Sales"
    comment: "Incremental sales (from experiment), reporting/base currency."
    synonyms: ["lift_sales", "causal_sales"]

  - name: ctr
    expr: SUM(clicks) / NULLIF(SUM(impressions), 0)
    display_name: "CTR"
    comment: "Click-through rate = clicks / impressions."
    synonyms: ["click_through_rate", "click_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: viewable_rate
    expr: SUM(viewable_impressions) / NULLIF(SUM(impressions), 0)
    display_name: "Viewable Rate"
    comment: "Viewable impressions / impressions."
    synonyms: ["viewability", "viewability_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: ivt_rate
    expr: SUM(invalid_traffic_impressions) / NULLIF(SUM(gross_impressions), 0)
    display_name: "IVT Rate"
    comment: "Invalid-traffic impressions / gross impressions."
    synonyms: ["invalid_traffic_rate", "ivt"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: cvr
    expr: SUM(conversions) / NULLIF(SUM(clicks), 0)
    display_name: "CVR"
    comment: "Conversion rate = conversions / clicks."
    synonyms: ["conversion_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: roas_net
    expr: SUM(attributed_net_sales) / NULLIF(SUM(media_spend_net), 0)
    display_name: "ROAS (Net)"
    comment: "Return on ad spend = attributed_net_sales / media_spend_net."
    synonyms: ["roas", "return_on_ad_spend"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: iroas
    expr: SUM(incremental_sales) / NULLIF(SUM(media_spend_net), 0)
    display_name: "iROAS"
    comment: "Incremental ROAS = incremental_sales / media_spend_net."
    synonyms: ["incremental_roas"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: new_to_brand_rate
    expr: SUM(new_to_brand_sales) / NULLIF(SUM(attributed_net_sales), 0)
    display_name: "New-to-Brand Rate"
    comment: "New-to-brand sales / attributed net sales."
    synonyms: ["ntb_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2
$$;
