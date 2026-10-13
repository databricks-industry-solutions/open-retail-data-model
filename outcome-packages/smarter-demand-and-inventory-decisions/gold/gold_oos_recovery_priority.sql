-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- View: gold_oos_recovery_priority
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Ranks open OOS events by EXPECTED MARGIN recovery potential.
--
-- Review finding A15: the prior version ranked by raw estimated REVENUE, so a
-- low-margin high-revenue SKU out-ranked a high-margin one, and the design's
-- recoverability weighting was ignored. Ranking is now by expected margin =
-- estimated_margin_recovery * recoverability_probability, falling back to margin,
-- then revenue, then lost margin/revenue to date, so partially-populated data still
-- ranks sensibly.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${sdi_schema}.gold_oos_recovery_priority AS
SELECT
  oc.oos_event_id,
  oc.product_id,
  oc.store_id,
  oc.oos_severity,
  oc.abc_class,
  oc.lost_revenue_to_date,
  ora.estimated_revenue_recovery,
  ora.estimated_margin_recovery,
  ora.recoverability_probability,
  ora.estimated_margin_recovery * COALESCE(ora.recoverability_probability, 1.0)
    AS expected_margin_recovery,
  ora.action_type,
  ora.action_status,
  -- Explicit CAST: ROW_NUMBER() is BIGINT in Databricks SQL, but sqlglot's
  -- annotate_types() only resolves it from 30.9.0 up. The cast makes the
  -- generated contract type independent of the sqlglot version.
  CAST(ROW_NUMBER() OVER (
    ORDER BY COALESCE(
               ora.estimated_margin_recovery * COALESCE(ora.recoverability_probability, 1.0),
               ora.estimated_margin_recovery,
               ora.estimated_revenue_recovery,
               oc.lost_revenue_to_date, 0) DESC,
             CASE oc.abc_class WHEN 'A' THEN 1 WHEN 'B' THEN 2 ELSE 3 END
  ) AS BIGINT) AS recovery_priority_rank
FROM ${catalog}.${sdi_schema}.gold_oos_current oc
LEFT JOIN ${catalog}.${sdi_schema}.oos_recovery_action ora
  ON ora.oos_event_sk = oc.oos_event_sk
 AND ora.action_status IN ('recommended', 'approved');
