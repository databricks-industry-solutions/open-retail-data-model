-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · Workforce Optimization
-- View: gold_workforce_forecast_accuracy
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-08-11
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-11
-- ============================================================
-- Backtest accuracy for workforce demand forecasts when actuals exist.
-- Actuals preference (same spirit as the forecast view):
--   foot_traffic     -> CSS site-level footfall when css_schema is readable
--                       (this view does NOT hard-join CSS — adopters overlay
--                       CSS actuals in the notebook / pipeline; core actuals use
--                       order-line interval buckets and labor_actuals hours).
--   transaction_count / pickup_orders -> customer_order_line units in interval
--   else -> NULL actual (row excluded from MAPE denominator)
--
-- MAPE = mean(|forecast - actual| / nullif(actual,0)) over rows with actual > 0
-- Bias = mean(forecast - actual) over rows with actual IS NOT NULL
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${predops_schema}.gold_workforce_forecast_accuracy AS
WITH params AS (
  SELECT COALESCE(MAX(interval_minutes), 30) AS interval_minutes
  FROM ${catalog}.${predops_schema}.labor_standard
  WHERE is_current = TRUE AND is_active = TRUE
),
forecasts AS (
  SELECT
    f.store_id,
    f.business_date,
    f.interval_start_ts,
    f.interval_end_ts,
    f.interval_minutes,
    f.department_or_zone,
    f.role_code,
    f.demand_driver,
    f.forecast_driver_units,
    f.forecast_method,
    f.model_version,
    f.workforce_optimization_run_id AS optimization_run_id
  FROM ${catalog}.${predops_schema}.workforce_demand_forecast f
  WHERE f.business_date < current_date()   -- backtest only (actuals available)
),
order_actuals AS (
  SELECT
    o.store_id,
    CAST(o.event_timestamp AS DATE) AS business_date,
    timestamp(concat(
      CAST(CAST(o.event_timestamp AS DATE) AS STRING), ' ',
      lpad(CAST(hour(o.event_timestamp) AS STRING), 2, '0'), ':',
      lpad(CAST(CAST(floor(minute(o.event_timestamp) / p.interval_minutes) * p.interval_minutes AS INT) AS STRING), 2, '0'),
      ':00'
    )) AS interval_start_ts,
    SUM(COALESCE(o.units, 1)) AS actual_units
  FROM ${catalog}.${order_schema}.customer_order_line o
  CROSS JOIN params p
  WHERE o.event_timestamp IS NOT NULL
    AND CAST(o.event_timestamp AS DATE) < current_date()
  GROUP BY o.store_id, CAST(o.event_timestamp AS DATE),
           hour(o.event_timestamp),
           CAST(floor(minute(o.event_timestamp) / p.interval_minutes) * p.interval_minutes AS INT),
           p.interval_minutes
),
labor_hour_actuals AS (
  SELECT
    a.store_id,
    a.role_code,
    a.business_date,
    COALESCE(a.department_or_zone, 'storewide') AS department_or_zone,
    timestamp(concat(
      CAST(a.business_date AS STRING), ' ',
      lpad(CAST(hour(a.clock_in_ts) AS STRING), 2, '0'), ':',
      lpad(CAST(CAST(floor(minute(a.clock_in_ts) / p.interval_minutes) * p.interval_minutes AS INT) AS STRING), 2, '0'),
      ':00'
    )) AS interval_start_ts,
    SUM(a.worked_hours) AS actual_hours
  FROM ${catalog}.${labor_schema}.labor_actuals a
  CROSS JOIN params p
  WHERE a.actuals_status IN ('approved', 'adjusted')
    AND a.business_date < current_date()
  GROUP BY a.store_id, a.role_code, a.business_date,
           COALESCE(a.department_or_zone, 'storewide'),
           hour(a.clock_in_ts),
           CAST(floor(minute(a.clock_in_ts) / p.interval_minutes) * p.interval_minutes AS INT),
           p.interval_minutes
),
joined AS (
  SELECT
    f.*,
    CASE
      WHEN f.demand_driver IN ('transaction_count', 'pickup_orders') THEN oa.actual_units
      WHEN f.demand_driver IN ('store_open_coverage', 'minimum_coverage') THEN la.actual_hours
      ELSE oa.actual_units
    END AS actual_driver_units
  FROM forecasts f
  LEFT JOIN order_actuals oa
    ON oa.store_id = f.store_id
   AND oa.business_date = f.business_date
   AND oa.interval_start_ts = f.interval_start_ts
  LEFT JOIN labor_hour_actuals la
    ON la.store_id = f.store_id
   AND la.role_code = f.role_code
   AND la.business_date = f.business_date
   AND la.department_or_zone = f.department_or_zone
   AND la.interval_start_ts = f.interval_start_ts
)
SELECT
  store_id,
  business_date,
  interval_start_ts,
  interval_end_ts,
  interval_minutes,
  department_or_zone,
  role_code,
  demand_driver,
  forecast_driver_units,
  actual_driver_units,
  CAST(forecast_driver_units - actual_driver_units AS DECIMAL(18,4)) AS forecast_error,
  CAST(
    CASE WHEN actual_driver_units IS NOT NULL AND actual_driver_units <> 0
         THEN abs(forecast_driver_units - actual_driver_units) / abs(actual_driver_units)
         ELSE NULL END AS DOUBLE
  ) AS ape,
  forecast_method,
  model_version,
  optimization_run_id
FROM joined;
