-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · Workforce Optimization
-- View: gold_labor_risk
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-08-10
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-10
-- ============================================================
-- Store-grain labor/workforce risk sub-score (0-100, higher = riskier).
-- Transparent heuristic: 100 * (1 - coverage_pct) over the next 7 days,
-- plus escalators for critical shortfall intervals. Slots into
-- gold_store_operational_risk.labor_risk (ADR 0043).
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${predops_schema}.gold_labor_risk AS
WITH gap AS (
  SELECT
    store_id,
    coverage_pct,
    shortfall_severity,
    shortfall_hours,
    required_labor_hours
  FROM ${catalog}.${predops_schema}.gold_workforce_coverage_gap
  WHERE business_date BETWEEN current_date() AND date_add(current_date(), 6)
),
agg AS (
  SELECT
    store_id,
    SUM(required_labor_hours) AS required_hours_7d,
    SUM(shortfall_hours) AS shortfall_hours_7d,
    AVG(coverage_pct) AS avg_coverage_pct,
    SUM(CASE WHEN shortfall_severity = 'critical' THEN 1 ELSE 0 END) AS critical_intervals,
    SUM(CASE WHEN shortfall_severity IN ('high', 'critical') THEN 1 ELSE 0 END) AS high_or_critical_intervals,
    COUNT(*) AS intervals_scored
  FROM gap
  GROUP BY store_id
),
stores AS (
  SELECT store_sk, store_id, store_name, region, district
  FROM ${catalog}.${store_schema}.store
  WHERE is_current = TRUE
)
SELECT
  s.store_sk,
  s.store_id,
  s.store_name,
  s.region,
  s.district,
  current_date() AS as_of_date,
  a.required_hours_7d,
  a.shortfall_hours_7d,
  a.avg_coverage_pct,
  a.critical_intervals,
  a.high_or_critical_intervals,
  a.intervals_scored,
  CAST(
    LEAST(
      100.0,
      GREATEST(
        0.0,
        100.0 * (1.0 - COALESCE(a.avg_coverage_pct, 0.0))
          + CASE WHEN a.critical_intervals > 0 THEN 15.0 ELSE 0.0 END
          + CASE WHEN a.high_or_critical_intervals > 3 THEN 10.0 ELSE 0.0 END
      )
    ) AS DOUBLE
  ) AS labor_risk
FROM stores s
INNER JOIN agg a ON a.store_id = s.store_id;
