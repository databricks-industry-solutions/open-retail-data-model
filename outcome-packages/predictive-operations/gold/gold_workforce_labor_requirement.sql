-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · Workforce Optimization
-- View: gold_workforce_labor_requirement
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-08-10
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-10
-- ============================================================
-- Translates gold_workforce_demand_forecast drivers through current
-- labor_standard rows into required labor hours and headcount.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${predops_schema}.gold_workforce_labor_requirement AS
WITH active_standards AS (
  -- Make the join to the forecast provably 1:1. Nothing in the schema stops two
  -- concurrently-active standards sharing one (role, driver, zone); a second one
  -- would fan this view out past its declared store x date x interval x zone x role
  -- grain and inflate the SUMs that feed gold_labor_risk and, through it,
  -- gold_store_operational_risk.labor_risk. ls_active_key_unique reports that
  -- condition as a DQ error; this ranking picks a single winner so the view stays
  -- correct in the meantime.
  --
  -- standard_version is a free-form label ('v1', '2026-Q3'), so DESC on it is
  -- lexical, not semantic ordering -- 'v9' sorts above 'v10'. It leads the ORDER BY
  -- as the declared intent, with effective_from_date as the reliable recency signal
  -- behind it and labor_standard_id last so the pick is deterministic even when both
  -- leading keys tie.
  --
  -- ROW_NUMBER in a subquery rather than QUALIFY: QUALIFY is Databricks-only and
  -- open-source Spark rejects it, which would put this view beyond the repo's
  -- local-Spark gold-view tests and beyond apply_model_ddl's no-warehouse fallback.
  -- The subquery form is the dominant pattern in the gold layer and is equivalent.
  SELECT
    labor_standard_id,
    standard_version,
    role_code,
    demand_driver,
    COALESCE(department_or_zone, 'storewide') AS department_or_zone,
    interval_minutes,
    driver_units_per_labor_hour,
    labor_hours_per_driver_unit,
    minimum_headcount,
    coverage_rationale,
    ROW_NUMBER() OVER (
      PARTITION BY role_code, demand_driver, COALESCE(department_or_zone, 'storewide')
      ORDER BY standard_version DESC, effective_from_date DESC, labor_standard_id DESC
    ) AS standard_rank
  FROM ${catalog}.${predops_schema}.labor_standard
  WHERE is_current = TRUE AND is_active = TRUE
),
standards AS (
  SELECT
    labor_standard_id,
    standard_version,
    role_code,
    demand_driver,
    department_or_zone,
    interval_minutes,
    driver_units_per_labor_hour,
    labor_hours_per_driver_unit,
    minimum_headcount,
    coverage_rationale,
    COALESCE(
      labor_hours_per_driver_unit,
      CAST(1.0 AS DECIMAL(18,6)) / CAST(driver_units_per_labor_hour AS DECIMAL(18,6))
    ) AS hours_per_unit
  FROM active_standards
  WHERE standard_rank = 1
),
joined AS (
  SELECT
    f.store_sk,
    f.store_id,
    f.business_date,
    f.interval_start_ts,
    f.interval_end_ts,
    f.interval_minutes,
    f.department_or_zone,
    f.role_code,
    f.demand_driver,
    f.forecast_driver_units,
    s.labor_standard_id,
    s.standard_version AS labor_standard_version,
    s.hours_per_unit AS applied_labor_standard,
    s.minimum_headcount,
    s.coverage_rationale,
    CASE
      WHEN f.demand_driver IN ('store_open_coverage', 'minimum_coverage')
        THEN CAST(GREATEST(s.minimum_headcount, 1) AS DECIMAL(18,4))
             * (CAST(f.interval_minutes AS DECIMAL(18,4)) / 60.0)
      ELSE CAST(f.forecast_driver_units * s.hours_per_unit AS DECIMAL(18,4))
    END AS raw_required_hours
  FROM ${catalog}.${predops_schema}.gold_workforce_demand_forecast f
  INNER JOIN standards s
    ON s.role_code = f.role_code
   AND s.demand_driver = f.demand_driver
   AND s.department_or_zone = f.department_or_zone
)
SELECT
  store_sk,
  store_id,
  business_date,
  interval_start_ts,
  interval_end_ts,
  interval_minutes,
  department_or_zone,
  role_code,
  demand_driver,
  forecast_driver_units,
  labor_standard_id,
  labor_standard_version,
  CAST(applied_labor_standard AS DECIMAL(18,6)) AS applied_labor_standard,
  CAST(GREATEST(
         raw_required_hours,
         CAST(minimum_headcount AS DECIMAL(18,4)) * (CAST(interval_minutes AS DECIMAL(18,4)) / 60.0)
       ) AS DECIMAL(18,4)) AS required_labor_hours,
  CAST(
    GREATEST(
      raw_required_hours / (CAST(interval_minutes AS DECIMAL(18,4)) / 60.0),
      CAST(minimum_headcount AS DECIMAL(18,4))
    ) AS DECIMAL(18,4)
  ) AS required_headcount,
  minimum_headcount,
  coverage_rationale
FROM joined;
