-- ============================================================
-- ORDM · Outcome Package · Data Sharing with Suppliers
-- View: gold_demand_plan_exceptions
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Inherits the entitlement carried by
--   gold_joint_demand_plan (principal_id); apply the same deploy-time row filter.
-- Version: 0.5
-- Generated: 2026-08-01
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-01
-- ============================================================
-- CPFR exception queue over gold_joint_demand_plan: the plan rows that need
-- collaborative attention, ranked by demand value at risk. An exception is raised
-- when the two parties disagree beyond a tolerance, when a party has not submitted
-- a plan for a scope the other party (or the consensus) did, or when the agreed
-- consensus diverges materially from the statistical baseline. Reads only the
-- entitled joint plan, so it exposes no row a partner could not already see.
--
-- Grain: one row per exception (principal × supplier × product × fiscal week), same as
-- the underlying entitled joint plan — the row carries principal_id and priority_rank is
-- ranked within each principal, so aggregate only within a principal (or after the row
-- filter) to avoid double-counting across entitled principals.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${dss_schema}.gold_demand_plan_exceptions AS
WITH flagged AS (
  SELECT
    principal_id,
    supplier_id,
    supplier_name,
    product_id,
    product_name,
    fiscal_week_id,
    plan_cycle_id,
    retailer_qty,
    supplier_qty,
    consensus_qty,
    retailer_value_net,
    supplier_value_net,
    consensus_value_net,
    currency_code,
    statistical_forecast_qty,
    plan_variance_pct,
    consensus_vs_baseline_pct,
    -- Exception taxonomy (first matching reason wins). The 0.20 / 0.30 tolerances are
    -- LITERAL reference defaults baked into this view; "tuning" them means editing this
    -- SQL (there is no deploy-time parameter). A deployment that needs them configurable
    -- should lift them to a small threshold table or a bundle variable.
    CASE
      WHEN retailer_qty IS NULL AND (supplier_qty IS NOT NULL OR consensus_qty IS NOT NULL) THEN 'missing_retailer_plan'
      WHEN supplier_qty IS NULL AND (retailer_qty IS NOT NULL OR consensus_qty IS NOT NULL) THEN 'missing_supplier_plan'
      WHEN ABS(COALESCE(plan_variance_pct, 0)) > 0.20 THEN 'party_disagreement'
      WHEN ABS(COALESCE(consensus_vs_baseline_pct, 0)) > 0.30 THEN 'consensus_baseline_divergence'
      ELSE NULL
    END AS exception_reason,
    -- Demand value at risk ranks the queue. Prefer the agreed consensus value; when a
    -- party plan is missing there is no consensus yet, so fall back to whichever party
    -- value IS present (the larger), so a missing-plan exception is NOT pinned to 0 and
    -- can out-rank a low-value disagreement.
    COALESCE(
      consensus_value_net,
      GREATEST(COALESCE(retailer_value_net, 0), COALESCE(supplier_value_net, 0))
    ) AS demand_value_at_risk
  FROM ${catalog}.${dss_schema}.gold_joint_demand_plan
)
SELECT
  principal_id,
  supplier_id,
  supplier_name,
  product_id,
  product_name,
  fiscal_week_id,
  plan_cycle_id,
  exception_reason,
  retailer_qty,
  supplier_qty,
  consensus_qty,
  statistical_forecast_qty,
  plan_variance_pct,
  consensus_vs_baseline_pct,
  demand_value_at_risk,
  currency_code,
  -- Explicit CAST: ROW_NUMBER() is BIGINT in Databricks SQL, but sqlglot's
  -- annotate_types() only resolves it from 30.9.0 up. The cast makes the
  -- generated contract type independent of the sqlglot version.
  CAST(ROW_NUMBER() OVER (PARTITION BY principal_id
                          ORDER BY demand_value_at_risk DESC, supplier_id, product_id, fiscal_week_id) AS BIGINT) AS priority_rank,
  current_timestamp() AS fresh_as_of_ts
FROM flagged
WHERE exception_reason IS NOT NULL;
