-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- View: gold_effective_forecast
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Statistical demand forecast enriched with the latest approved planner adjustment.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${sdi_schema}.gold_effective_forecast AS
WITH latest_adj AS (
  SELECT
    planning_unit_sk,
    planning_unit_id,
    forecast_date_key,
    adjustment_quantity,
    adjustment_method,
    ROW_NUMBER() OVER (
      PARTITION BY planning_unit_sk, forecast_date_key
      ORDER BY adjusted_at_timestamp DESC
    ) AS rn
  FROM ${catalog}.${sdi_schema}.forecast_adjustment
  WHERE approval_status = 'approved'
),
base AS (
  SELECT
    df.planning_unit_sk,
    df.planning_unit_id,
    df.forecast_date_key,
    fc.fiscal_week_id AS fiscal_period_key,
    df.forecast_quantity AS statistical_forecast_quantity,
    df.forecast_horizon_type,
    df.unit_of_measure
  FROM ${catalog}.${sdi_schema}.demand_forecast df
  LEFT JOIN ${catalog}.${calendar_schema}.fiscal_calendar fc ON fc.date_key = df.forecast_date_key
  WHERE df.forecast_horizon_type != 'backtest'
)
SELECT
  b.planning_unit_sk,
  b.planning_unit_id,
  b.forecast_date_key,
  b.fiscal_period_key,
  b.statistical_forecast_quantity,
  CASE
    WHEN la.adjustment_method = 'absolute' THEN la.adjustment_quantity
    WHEN la.adjustment_method = 'delta' THEN b.statistical_forecast_quantity + la.adjustment_quantity
    WHEN la.adjustment_method = 'pct' THEN b.statistical_forecast_quantity * (1 + la.adjustment_quantity / 100)
    ELSE b.statistical_forecast_quantity
  END AS effective_forecast_quantity,
  b.forecast_horizon_type,
  b.unit_of_measure
FROM base b
LEFT JOIN latest_adj la
  ON la.planning_unit_sk = b.planning_unit_sk
 AND la.forecast_date_key = b.forecast_date_key
 AND la.rn = 1;
