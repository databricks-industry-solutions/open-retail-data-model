-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · Workforce Optimization
-- View: gold_workforce_coverage_gap
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-08-10
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-10
-- ============================================================
-- Compares required headcount to published labor_schedule coverage
-- (and proposed recommendations when present) to surface understaffed
-- intervals. Feeds labor_risk and coverage exceptions.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${predops_schema}.gold_workforce_coverage_gap AS
WITH req AS (
  SELECT *
  FROM ${catalog}.${predops_schema}.gold_workforce_labor_requirement
),
sched AS (
  SELECT
    store_id,
    role_code,
    COALESCE(department_or_zone, 'storewide') AS department_or_zone,
    shift_start_ts,
    shift_end_ts,
    scheduled_hours
  FROM ${catalog}.${labor_schema}.labor_schedule
  WHERE schedule_status = 'published'
),
rec AS (
  SELECT
    store_id,
    role_code,
    department_or_zone,
    shift_start_ts,
    shift_end_ts,
    assigned_hours
  FROM ${catalog}.${predops_schema}.workforce_schedule_recommendation
  -- PROPOSED ONLY, deliberately. An accepted recommendation is published into
  -- labor_schedule (schedule_source = 'recommendation_accepted'), where the sched
  -- CTE above already counts it; including 'accepted' here counted the same shift
  -- twice, overstating covered_hours, understating shortfall_hours, and deflating
  -- labor_risk. The published schedule is the source of truth for committed
  -- coverage; this term adds only the not-yet-committed proposals on top of it.
  WHERE recommendation_status = 'proposed'
),
-- Coverage is aggregated with JOIN + GROUP BY, NOT a correlated scalar subquery.
-- A subquery of the form SUM(CASE WHEN s.ts < r.ts ...) mixes outer (r) and local (s)
-- references inside one aggregate, which Databricks rejects with
-- UNSUPPORTED_SUBQUERY_EXPRESSION_CATEGORY.AGGREGATE_FUNCTION_MIXED_OUTER_LOCAL_REFERENCES.
-- Moving the overlap predicate into the JOIN keeps the semantics identical: only
-- overlapping shifts contribute, and an interval with no overlap yields no row and
-- COALESCEs to 0 exactly as the old CASE ... ELSE 0 did.
--
-- Coverage is keyed on (store, role, zone, interval) and NOT on demand_driver, matching
-- the old subqueries' correlation keys. Requirements are finer-grained (one row per
-- demand_driver), so aggregating over a DISTINCT interval spine and joining back gives
-- each driver row the same interval coverage instead of multiplying it.
intervals AS (
  SELECT DISTINCT
    store_id,
    role_code,
    department_or_zone,
    interval_start_ts,
    interval_end_ts
  FROM req
),
sched_cov AS (
  SELECT
    i.store_id,
    i.role_code,
    i.department_or_zone,
    i.interval_start_ts,
    i.interval_end_ts,
    SUM((unix_timestamp(LEAST(s.shift_end_ts, i.interval_end_ts))
       - unix_timestamp(GREATEST(s.shift_start_ts, i.interval_start_ts))) / 3600.0
    ) AS scheduled_hours
  FROM intervals i
  JOIN sched s
    ON  s.store_id           = i.store_id
    AND s.role_code          = i.role_code
    AND s.department_or_zone = i.department_or_zone
    AND s.shift_start_ts     < i.interval_end_ts
    AND s.shift_end_ts       > i.interval_start_ts
  GROUP BY i.store_id, i.role_code, i.department_or_zone,
           i.interval_start_ts, i.interval_end_ts
),
rec_cov AS (
  SELECT
    i.store_id,
    i.role_code,
    i.department_or_zone,
    i.interval_start_ts,
    i.interval_end_ts,
    SUM((unix_timestamp(LEAST(x.shift_end_ts, i.interval_end_ts))
       - unix_timestamp(GREATEST(x.shift_start_ts, i.interval_start_ts))) / 3600.0
    ) AS recommended_hours
  FROM intervals i
  JOIN rec x
    ON  x.store_id           = i.store_id
    AND x.role_code          = i.role_code
    AND x.department_or_zone = i.department_or_zone
    AND x.shift_start_ts     < i.interval_end_ts
    AND x.shift_end_ts       > i.interval_start_ts
  GROUP BY i.store_id, i.role_code, i.department_or_zone,
           i.interval_start_ts, i.interval_end_ts
),
covered AS (
  SELECT
    r.store_sk,
    r.store_id,
    r.business_date,
    r.interval_start_ts,
    r.interval_end_ts,
    r.department_or_zone,
    r.role_code,
    r.required_headcount,
    r.required_labor_hours,
    COALESCE(sc.scheduled_hours, 0.0) AS scheduled_hours,
    COALESCE(rc.recommended_hours, 0.0) AS recommended_hours
  FROM req r
  LEFT JOIN sched_cov sc
    ON  sc.store_id           = r.store_id
    AND sc.role_code          = r.role_code
    AND sc.department_or_zone = r.department_or_zone
    AND sc.interval_start_ts  = r.interval_start_ts
    AND sc.interval_end_ts    = r.interval_end_ts
  LEFT JOIN rec_cov rc
    ON  rc.store_id           = r.store_id
    AND rc.role_code          = r.role_code
    AND rc.department_or_zone = r.department_or_zone
    AND rc.interval_start_ts  = r.interval_start_ts
    AND rc.interval_end_ts    = r.interval_end_ts
)
SELECT
  store_sk,
  store_id,
  business_date,
  interval_start_ts,
  interval_end_ts,
  department_or_zone,
  role_code,
  required_labor_hours,
  required_headcount,
  CAST(scheduled_hours AS DECIMAL(18,4)) AS scheduled_hours,
  CAST(recommended_hours AS DECIMAL(18,4)) AS recommended_hours,
  CAST(scheduled_hours + recommended_hours AS DECIMAL(18,4)) AS covered_hours,
  CAST(
    GREATEST(
      required_labor_hours - (scheduled_hours + recommended_hours),
      0
    ) AS DECIMAL(18,4)
  ) AS shortfall_hours,
  CAST(
    CASE WHEN required_labor_hours > 0
         THEN LEAST((scheduled_hours + recommended_hours) / required_labor_hours, 2.0)
         ELSE 1.0 END AS DOUBLE
  ) AS coverage_pct,
  CASE
    WHEN required_labor_hours - (scheduled_hours + recommended_hours) <= 0 THEN 'none'
    WHEN (scheduled_hours + recommended_hours) / NULLIF(required_labor_hours, 0) >= 0.85 THEN 'low'
    WHEN (scheduled_hours + recommended_hours) / NULLIF(required_labor_hours, 0) >= 0.60 THEN 'medium'
    WHEN (scheduled_hours + recommended_hours) / NULLIF(required_labor_hours, 0) >= 0.35 THEN 'high'
    ELSE 'critical'
  END AS shortfall_severity
FROM covered;
