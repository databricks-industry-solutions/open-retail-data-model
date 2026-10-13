-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- Metric View: supplier_campaign_report
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-07-15
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-15
-- ============================================================
-- Semantic layer over gold_supplier_campaign_report: the supplier-safe campaign
-- report (advertiser x campaign, threshold-suppressed, no person-level data) as a
-- Genie / AI-BI metric view, so a supplier can slice ROAS/spend/sales by brand and
-- campaign. Attribution single-model per campaign (agg contract).
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${cmn_schema}.mv_supplier_campaign_report
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Supplier-safe retail-media campaign KPIs (impressions, spend, attributed sales, ROAS, iROAS) by advertiser, brand, and campaign."
source: >
  SELECT
    advertiser_id,
    brand_name,
    campaign_id,
    campaign_name,
    attribution_model,
    impressions,
    viewable_impressions,
    clicks,
    conversions,
    units,
    media_spend_net,
    attributed_net_sales,
    new_to_brand_sales,
    incremental_sales
  FROM ${catalog}.${cmn_schema}.gold_supplier_campaign_report

fields:
  - name: advertiser_id
    expr: advertiser_id
    display_name: "Advertiser ID"
    comment: "Durable advertiser business key."
    synonyms: ["advertiser"]
  - name: brand_name
    expr: brand_name
    display_name: "Brand"
    comment: "Advertised brand name."
    synonyms: ["brand"]
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
  - name: attribution_model
    expr: attribution_model
    display_name: "Attribution Model"
    comment: "The single attribution model the campaign's attributed measures are reported under."
    synonyms: ["attribution", "model"]

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
  - name: new_to_brand_sales
    expr: SUM(new_to_brand_sales)
    display_name: "New-to-Brand Sales"
    comment: "New-to-brand attributed sales."
    synonyms: ["ntb_sales"]
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
