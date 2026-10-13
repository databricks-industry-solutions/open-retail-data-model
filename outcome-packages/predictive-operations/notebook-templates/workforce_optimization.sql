-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Workforce Optimization — forecast + schedule (reference)
-- MAGIC
-- MAGIC ORDM · Predictive Operations · Workforce Optimization · ADR 0043
-- MAGIC
-- MAGIC ORDM trains and serves **no models**. This notebook is a declarative reference
-- MAGIC method: demand from `gold_workforce_demand_forecast` (order-interval preferred,
-- MAGIC sales-profile fallback), labor hours via `labor_standard`, accuracy via
-- MAGIC `gold_workforce_forecast_accuracy`, and scheduling via
-- MAGIC `optimize_schedule(..., method='ortools')` in
-- MAGIC `tests/support/workforce_optimization.py` (greedy fallback if ortools is
-- MAGIC absent). Adapt it; do not treat it as a managed pipeline. Labor-law rules
-- MAGIC must be configured and reviewed for your jurisdiction.
-- MAGIC
-- MAGIC Parameters use the same `${...}` tokens as the DDL.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 1. Preview heuristic demand forecast (next 7 days)
-- MAGIC Prefer true 30-min order timestamps when history exists (`model_version` =
-- MAGIC `heuristic_v2_orders`); otherwise sales day-profile (`heuristic_v2_sales_profile`).

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _workforce_forecast_preview AS
SELECT *
FROM ${catalog}.${predops_schema}.gold_workforce_demand_forecast
WHERE business_date BETWEEN current_date() AND date_add(current_date(), 6);

SELECT store_id, role_code, business_date,
       SUM(forecast_driver_units) AS driver_units,
       MIN(forecast_method) AS forecast_method,
       MIN(model_version) AS model_version
FROM _workforce_forecast_preview
GROUP BY store_id, role_code, business_date
ORDER BY store_id, role_code, business_date
LIMIT 100;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2. Labor requirements from standards

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _workforce_requirements_preview AS
SELECT *
FROM ${catalog}.${predops_schema}.gold_workforce_labor_requirement
WHERE business_date BETWEEN current_date() AND date_add(current_date(), 6);

SELECT store_id, role_code,
       ROUND(SUM(required_labor_hours), 2) AS required_hours,
       ROUND(AVG(required_headcount), 2) AS avg_headcount
FROM _workforce_requirements_preview
GROUP BY store_id, role_code
ORDER BY store_id, role_code;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3. Coverage gaps and labor risk

-- COMMAND ----------

SELECT store_id, role_code, shortfall_severity,
       COUNT(*) AS intervals,
       ROUND(SUM(shortfall_hours), 2) AS shortfall_hours
FROM ${catalog}.${predops_schema}.gold_workforce_coverage_gap
WHERE business_date BETWEEN current_date() AND date_add(current_date(), 6)
  AND shortfall_hours > 0
GROUP BY store_id, role_code, shortfall_severity
ORDER BY shortfall_hours DESC
LIMIT 100;

SELECT store_id, labor_risk, avg_coverage_pct, critical_intervals
FROM ${catalog}.${predops_schema}.gold_labor_risk
ORDER BY labor_risk DESC
LIMIT 50;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 4. Optional: prefer CSS foot traffic when Connected Store Signals is deployed
-- MAGIC
-- MAGIC Gold stays deployable without CSS. When `connected_store_signals` is present,
-- MAGIC overlay **site-level** footfall onto `sales_associate` / `foot_traffic` slots
-- MAGIC (never SUM across CSS `aggregation_level` values). Python helper:
-- MAGIC `prefer_demand_signals(css, orders, sales)`.

-- COMMAND ----------

-- CREATE OR REPLACE TEMP VIEW _css_site_footfall AS
-- SELECT
--   sri.store_id,
--   CAST(sri.interval_start_ts AS DATE) AS business_date,
--   sri.interval_start_ts,
--   sri.interval_end_ts,
--   ft.footfall_count
-- FROM ${catalog}.${css_schema}.sensor_report_interval sri
-- JOIN ${catalog}.${css_schema}.foot_traffic_interval_detail ft
--   ON ft.sensor_report_interval_sk = sri.sensor_report_interval_sk
-- WHERE sri.report_type = 'gs1:Count'
--   AND sri.aggregation_level = 'site'
--   AND sri.subject_type = 'space';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 5. Forecast accuracy (MAPE / bias) when actuals exist
-- MAGIC
-- MAGIC Join historical forecast facts to order-interval / labor_actuals actuals.
-- MAGIC Persist `forecast_mape` / `forecast_bias` onto `workforce_optimization_run`
-- MAGIC (NULL when no pairs).

-- COMMAND ----------

SELECT
  ROUND(AVG(ape), 4) AS forecast_mape,
  ROUND(AVG(forecast_error), 4) AS forecast_bias,
  COUNT(*) AS n_pairs
FROM ${catalog}.${predops_schema}.gold_workforce_forecast_accuracy
WHERE actual_driver_units IS NOT NULL;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 6. Optional MERGE into durable facts
-- MAGIC
-- MAGIC Idempotent on business keys. For schedule recommendations use
-- MAGIC `optimize_schedule(..., method='ortools')` (greedy fallback if ortools missing).

-- COMMAND ----------

-- MERGE INTO ${catalog}.${predops_schema}.workforce_demand_forecast AS t
-- USING (
--   SELECT
--     concat_ws('|', store_id, CAST(business_date AS STRING), CAST(interval_start_ts AS STRING),
--               department_or_zone, role_code, 'WOR-NOTEBOOK-001') AS workforce_demand_forecast_id,
--     'WOR-NOTEBOOK-001' AS workforce_optimization_run_id,
--     store_sk, store_id, business_date, interval_start_ts, interval_end_ts, interval_minutes,
--     department_or_zone, role_code, demand_driver, forecast_driver_units,
--     forecast_lower_bound, forecast_upper_bound, forecast_method, model_version,
--     forecast_horizon_days, forecast_origin_ts,
--     'notebook_reference' AS record_source,
--     current_timestamp() AS load_timestamp
--   FROM ${catalog}.${predops_schema}.gold_workforce_demand_forecast
-- ) AS s
-- ON t.workforce_demand_forecast_id = s.workforce_demand_forecast_id
-- WHEN MATCHED THEN UPDATE SET *
-- WHEN NOT MATCHED THEN INSERT *;
