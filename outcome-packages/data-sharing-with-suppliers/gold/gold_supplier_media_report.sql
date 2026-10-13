-- ============================================================
-- ORDM · Outcome Package · Data Sharing with Suppliers
-- View: gold_supplier_media_report
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Apply a deploy-time row filter on
--   principal_id (= the querying group) so each supplier sees only entitled rows.
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- The ENTITLED supplier media report: the Commerce Media Networks
-- campaign_day rolled to advertiser × campaign, joined to reporting_entitlement
-- so every row carries the principal_id permitted to see it (brand-wide or
-- campaign-scoped). Threshold-suppressed and below-threshold rows are excluded.
-- No person-level data. This is the row-filter source for supplier sharing;
-- pairs with supplier_media_report_snapshot (the immutable published freeze).
-- ============================================================

-- Additivity: SUMs commerce-media-networks.campaign_day grouped by advertiser×campaign
-- with no grain filter; correct only under that aggregate's one-partition-per-campaign×day
-- contract (acd_uniform_breakout + acd_grain_single_level) — see campaign_day header.
CREATE OR REPLACE VIEW ${catalog}.${dss_schema}.gold_supplier_media_report AS
WITH rollup AS (
  SELECT
    a.advertiser_id,
    a.campaign_id,
    SUM(a.impressions)          AS impressions,
    SUM(a.viewable_impressions) AS viewable_impressions,
    SUM(a.clicks)               AS clicks,
    SUM(a.conversions)          AS conversions,
    SUM(a.units)                AS units,
    SUM(a.media_spend_net)      AS media_spend_net,
    SUM(a.attributed_net_sales) AS attributed_net_sales,
    SUM(a.new_to_brand_sales)   AS new_to_brand_sales,
    SUM(a.incremental_sales)    AS incremental_sales
  FROM ${catalog}.${cmn_schema}.campaign_day a
  WHERE COALESCE(a.privacy_suppressed_flag, FALSE) = FALSE
  GROUP BY a.advertiser_id, a.campaign_id
),
ent AS (
  SELECT principal_id, advertiser_id, campaign_id, min_disclosure_threshold
  FROM ${catalog}.${dss_schema}.reporting_entitlement
  WHERE is_current = TRUE AND entitlement_status = 'active'
)
SELECT
  e.principal_id,
  r.advertiser_id,
  sb.brand_name,
  r.campaign_id,
  c.campaign_name,
  r.impressions,
  r.viewable_impressions,
  r.clicks,
  r.conversions,
  r.units,
  r.media_spend_net,
  r.attributed_net_sales,
  r.new_to_brand_sales,
  r.incremental_sales,
  ROUND(r.attributed_net_sales / NULLIF(r.media_spend_net, 0), 4) AS roas_net,
  ROUND(r.incremental_sales    / NULLIF(r.media_spend_net, 0), 4) AS iroas,
  current_timestamp() AS fresh_as_of_ts
FROM rollup r
JOIN ent e
  ON e.advertiser_id = r.advertiser_id
 AND (e.campaign_id IS NULL OR e.campaign_id = r.campaign_id)
-- Most-specific entitlement wins: if a principal holds BOTH a brand-wide grant
-- (campaign_id IS NULL) and a campaign-scoped grant covering this rollup's
-- campaign, drop the brand-wide match so the row is emitted once, not twice.
-- Written as an anti-join (LEFT JOIN here + IS NULL in the WHERE), not as an EXISTS
-- in the ON clause: Databricks rejects a correlated subquery in a join predicate that
-- references both join inputs (UNSUPPORTED_CORRELATED_EXPRESSION_IN_JOIN_CONDITION),
-- and only at query time, so CREATE VIEW succeeds while every read fails.
LEFT JOIN ent e2
  ON e.campaign_id IS NULL
 AND e2.principal_id = e.principal_id
 AND e2.advertiser_id = r.advertiser_id
 AND e2.campaign_id = r.campaign_id
LEFT JOIN ${catalog}.${cmn_schema}.advertiser sb
  ON sb.advertiser_id = r.advertiser_id AND sb.is_current = TRUE
LEFT JOIN ${catalog}.${cmn_schema}.campaign c
  ON c.campaign_id = r.campaign_id AND c.is_current = TRUE
-- Disclosure threshold (k-anonymity basis): gate on the CONVERSION count — the
-- smallest, most re-identifying aggregate here (it can approach individual-level).
-- This is deliberately conservative: a high-impression, zero-conversion campaign is
-- fully suppressed (0 < threshold), and impression/reach counts are only ever
-- disclosed on rows that already clear the conversion floor. If a future policy
-- needs an independent impression/reach minimum, add it as a second predicate.
WHERE e2.principal_id IS NULL  -- the anti-join above (principal_id is NOT NULL in the DDL)
  AND r.conversions >= COALESCE(e.min_disclosure_threshold, 0);
