-- ============================================================
-- ORDM · Outcome Package · Data Sharing with Suppliers
-- Metric View: supplier_media_report
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-07-15
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-15
-- ============================================================
-- Semantic layer over gold_supplier_media_report: the entitled, threshold-suppressed
-- media-measurement report a supplier/advertiser consumes (advertiser x campaign, no
-- person-level data). Genie / AI-BI ready. Entitlement is applied by the underlying
-- gold view's row filter; this view adds the semantic measure definitions.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${dss_schema}.mv_supplier_media_report
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Entitled supplier media-measurement KPIs (impressions, spend, attributed sales, ROAS, iROAS) by advertiser and campaign."
source: >
  SELECT
    advertiser_id,
    campaign_id,
    impressions,
    viewable_impressions,
    clicks,
    conversions,
    units,
    media_spend_net,
    attributed_net_sales,
    new_to_brand_sales,
    incremental_sales
  FROM ${catalog}.${dss_schema}.gold_supplier_media_report

fields:
  - name: advertiser_id
    expr: advertiser_id
    display_name: "Advertiser ID"
    comment: "Durable advertiser business key."
    synonyms: ["advertiser", "supplier_brand"]
  - name: campaign_id
    expr: campaign_id
    display_name: "Campaign ID"
    comment: "Durable campaign business key."
    synonyms: ["campaign"]

measures:
  - name: impressions
    expr: SUM(impressions)
    display_name: "Impressions"
    comment: "Total impressions."
    synonyms: ["imps"]
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
    synonyms: ["spend", "ad_spend"]
  - name: attributed_net_sales
    expr: SUM(attributed_net_sales)
    display_name: "Attributed Net Sales"
    comment: "Attributed net sales, reporting/base currency."
    synonyms: ["attributed_sales"]
  - name: incremental_sales
    expr: SUM(incremental_sales)
    display_name: "Incremental Sales"
    comment: "Incremental sales from experiments, reporting/base currency."
    synonyms: ["causal_sales"]
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
$$;
