-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- View: gold_campaign_performance
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Promote to a materialized view
--   at deploy time for serving; definition unchanged.
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- Campaign × day performance KPIs, rolled up from campaign_day and joined to
-- the media campaign / advertiser dimensions. Supplier-safe (no person-level
-- data); threshold-suppressed rows are excluded.
--
-- Attribution: campaign_day carries exactly ONE attribution model per
-- campaign×day (the campaign's configured model, guarded by
-- acd_single_attribution_model), so summing the attributed measures here does NOT
-- mix models; the model is passed through as attribution_model for disclosure. The
-- KPI definitions are in the glossary (engine-neutral); this view materializes them:
--   ctr = clicks / impressions
--   viewable_rate = viewable_impressions / impressions
--   ivt_rate = invalid_traffic_impressions / gross_impressions
--   cvr = conversions / clicks
--   roas_net = attributed_net_sales / media_spend_net
--   iroas = incremental_sales / media_spend_net
--   new_to_brand_rate = new_to_brand_sales / attributed_net_sales
-- ============================================================

-- Additivity: SUMs campaign_day grouped by campaign×day with no grain filter; this is
-- correct only because the aggregate's one-partition-per-campaign×day contract holds
-- (acd_uniform_breakout + acd_grain_single_level) — see campaign_day header.
CREATE OR REPLACE VIEW ${catalog}.${cmn_schema}.gold_campaign_performance AS
WITH agg AS (
  SELECT
    a.metric_date,
    a.advertiser_id,
    a.campaign_id,
    MAX(a.attribution_model)      AS attribution_model,  -- one model per grain (acd_single_attribution_model)
    SUM(a.impressions)            AS impressions,
    SUM(a.viewable_impressions)   AS viewable_impressions,
    SUM(a.gross_impressions)      AS gross_impressions,
    SUM(a.invalid_traffic_impressions) AS invalid_traffic_impressions,
    SUM(a.clicks)                 AS clicks,
    SUM(a.conversions)            AS conversions,
    SUM(a.orders)                 AS orders,
    SUM(a.units)                  AS units,
    SUM(a.media_spend_net)        AS media_spend_net,
    SUM(a.media_spend_gross)      AS media_spend_gross,
    SUM(a.attributed_net_sales)   AS attributed_net_sales,
    SUM(a.attributed_gross_sales) AS attributed_gross_sales,
    SUM(a.same_sku_sales)         AS same_sku_sales,
    SUM(a.halo_sales)             AS halo_sales,
    SUM(a.new_to_brand_sales)     AS new_to_brand_sales,
    SUM(a.incremental_sales)      AS incremental_sales
  FROM ${catalog}.${cmn_schema}.campaign_day a
  WHERE COALESCE(a.privacy_suppressed_flag, FALSE) = FALSE
  GROUP BY a.metric_date, a.advertiser_id, a.campaign_id
)
SELECT
  g.metric_date,
  g.campaign_id,
  c.campaign_name,
  g.advertiser_id,
  sb.brand_name,
  g.attribution_model,
  g.impressions,
  g.viewable_impressions,
  g.clicks,
  g.conversions,
  g.orders,
  g.units,
  g.media_spend_net,
  g.attributed_net_sales,
  g.same_sku_sales,
  g.halo_sales,
  g.new_to_brand_sales,
  g.incremental_sales,
  ROUND(g.clicks / NULLIF(g.impressions, 0), 6)                          AS ctr,
  ROUND(g.viewable_impressions / NULLIF(g.impressions, 0), 6)            AS viewable_rate,
  ROUND(g.invalid_traffic_impressions / NULLIF(g.gross_impressions, 0), 6) AS ivt_rate,
  ROUND(g.conversions / NULLIF(g.clicks, 0), 6)                          AS cvr,
  ROUND(g.attributed_net_sales / NULLIF(g.media_spend_net, 0), 4)        AS roas_net,
  ROUND(g.incremental_sales / NULLIF(g.media_spend_net, 0), 4)           AS iroas,
  ROUND(g.new_to_brand_sales / NULLIF(g.attributed_net_sales, 0), 6)     AS new_to_brand_rate,
  current_timestamp() AS fresh_as_of_ts
FROM agg g
LEFT JOIN ${catalog}.${cmn_schema}.campaign c
  ON c.campaign_id = g.campaign_id AND c.is_current = TRUE
LEFT JOIN ${catalog}.${cmn_schema}.advertiser sb
  ON sb.advertiser_id = g.advertiser_id AND sb.is_current = TRUE;
