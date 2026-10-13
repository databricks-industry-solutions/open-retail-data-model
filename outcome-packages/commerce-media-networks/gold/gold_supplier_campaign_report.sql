-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- View: gold_supplier_campaign_report
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). The supplier-facing publish surface.
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- Supplier-safe campaign report: campaign_day rolled to advertiser × campaign,
-- threshold-suppressed rows excluded, no person-level data. This is the surface a
-- supplier/advertiser consumes (entitlement is applied by a row filter on
-- advertiser at deploy time; the ledger/entitlement bridge is the
-- data-sharing-with-suppliers package).
--
-- Attribution: the aggregate is single-model per campaign×day (the campaign's
-- configured model, guarded by acd_single_attribution_model), so the SUM to
-- advertiser × campaign stays within one model; it is disclosed as attribution_model.
-- ============================================================

-- Additivity: SUMs campaign_day grouped by advertiser×campaign with no grain filter;
-- correct only under the aggregate's one-partition-per-campaign×day contract
-- (acd_uniform_breakout + acd_grain_single_level) — see campaign_day header.
CREATE OR REPLACE VIEW ${catalog}.${cmn_schema}.gold_supplier_campaign_report AS
SELECT
  a.advertiser_id,
  sb.brand_name,
  a.campaign_id,
  c.campaign_name,
  MAX(a.attribution_model) AS attribution_model,
  MIN(a.metric_date) AS first_active_date,
  MAX(a.metric_date) AS last_active_date,
  SUM(a.impressions)          AS impressions,
  SUM(a.viewable_impressions) AS viewable_impressions,
  SUM(a.clicks)               AS clicks,
  SUM(a.conversions)          AS conversions,
  SUM(a.units)                AS units,
  SUM(a.media_spend_net)      AS media_spend_net,
  SUM(a.attributed_net_sales) AS attributed_net_sales,
  SUM(a.new_to_brand_sales)   AS new_to_brand_sales,
  SUM(a.incremental_sales)    AS incremental_sales,
  ROUND(SUM(a.attributed_net_sales) / NULLIF(SUM(a.media_spend_net), 0), 4) AS roas_net,
  ROUND(SUM(a.incremental_sales)    / NULLIF(SUM(a.media_spend_net), 0), 4) AS iroas,
  current_timestamp() AS fresh_as_of_ts
FROM ${catalog}.${cmn_schema}.campaign_day a
LEFT JOIN ${catalog}.${cmn_schema}.advertiser sb
  ON sb.advertiser_id = a.advertiser_id AND sb.is_current = TRUE
LEFT JOIN ${catalog}.${cmn_schema}.campaign c
  ON c.campaign_id = a.campaign_id AND c.is_current = TRUE
WHERE COALESCE(a.privacy_suppressed_flag, FALSE) = FALSE
GROUP BY a.advertiser_id, sb.brand_name, a.campaign_id, c.campaign_name;
