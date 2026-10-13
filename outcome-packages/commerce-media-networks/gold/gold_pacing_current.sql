-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- View: gold_pacing_current
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Ideal Lakebase serving projection.
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- The latest pacing snapshot per campaign (× ad_group × placement) — the current
-- operational pacing state for campaign-ops / alerting. No person-level data.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${cmn_schema}.gold_pacing_current AS
WITH ranked AS (
  SELECT
    p.*,
    ROW_NUMBER() OVER (
      PARTITION BY p.campaign_id, p.ad_group_id, p.placement_id
      ORDER BY p.snapshot_ts DESC
    ) AS rn
  FROM ${catalog}.${cmn_schema}.pacing_snapshot p
)
SELECT
  r.campaign_id,
  c.campaign_name,
  r.ad_group_id,
  r.placement_id,
  r.snapshot_ts,
  r.daily_budget,
  r.planned_spend_to_date,
  r.actual_spend_to_date,
  r.expected_spend_to_date,
  r.projected_end_spend,
  r.pacing_ratio,
  r.pacing_status,
  current_timestamp() AS fresh_as_of_ts
FROM ranked r
LEFT JOIN ${catalog}.${cmn_schema}.campaign c
  ON c.campaign_id = r.campaign_id AND c.is_current = TRUE
WHERE r.rn = 1;
