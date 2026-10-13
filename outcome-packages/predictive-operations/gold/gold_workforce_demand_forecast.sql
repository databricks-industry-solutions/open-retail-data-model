-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · Workforce Optimization
-- View: gold_workforce_demand_forecast
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-08-10
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-11
-- ============================================================
-- Transparent heuristic demand forecast at
-- store x business_date x interval x zone x role.
--
-- Signal preference (true 30-min when available):
--   1. customer_order_line.event_timestamp bucketed to interval_minutes
--      (canonical-core/order) — preferred for transaction_count / pickup_orders.
--   2. Seasonal same-DOW rolling average of those interval actuals, with
--      hierarchical fallback store×role×slot -> role×slot -> global slot.
--   3. If order history is sparse for a slot, fall back to day-grain sales
--      spread with a fixed intra-day profile (legacy path).
--
-- Connected Store Signals foot traffic is preferred for the foot_traffic
-- driver when CSS is deployed — see notebook-templates/workforce_optimization.sql
-- and tests/support/workforce_optimization.prefer_demand_signals (gold does not
-- hard-depend on css_schema so Predictive Operations still deploys without CSS).
--
-- Uncertainty proxy = +/- 20% of the point forecast.
-- Default horizon: next 7 days; default interval: 30 minutes
-- from current labor_standard (else 30).
--
-- ORDM trains and serves no models (ADR 0043). Adopter pipelines
-- may write calibrated rows into workforce_demand_forecast with
-- forecast_method = 'model'.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${predops_schema}.gold_workforce_demand_forecast AS
WITH params AS (
  SELECT
    COALESCE(MAX(interval_minutes), 30) AS interval_minutes,
    7 AS forecast_horizon_days
  FROM ${catalog}.${predops_schema}.labor_standard
  WHERE is_current = TRUE AND is_active = TRUE
),
-- ---- Preferred: true interval history from order event timestamps ----
order_intervals AS (
  SELECT
    o.store_id,
    CAST(o.event_timestamp AS DATE) AS business_date,
    dayofweek(CAST(o.event_timestamp AS DATE)) AS dow,
    hour(o.event_timestamp) AS hour_of_day,
    CAST(floor(minute(o.event_timestamp) / p.interval_minutes) * p.interval_minutes AS INT) AS minute_of_hour,
    SUM(COALESCE(o.units, 1)) AS order_units,
    p.interval_minutes
  FROM ${catalog}.${order_schema}.customer_order_line o
  CROSS JOIN params p
  WHERE o.event_timestamp IS NOT NULL
  GROUP BY o.store_id, CAST(o.event_timestamp AS DATE), dayofweek(CAST(o.event_timestamp AS DATE)),
           hour(o.event_timestamp),
           CAST(floor(minute(o.event_timestamp) / p.interval_minutes) * p.interval_minutes AS INT),
           p.interval_minutes
),
order_slot_avg AS (
  SELECT store_id, dow, hour_of_day, minute_of_hour, AVG(order_units) AS avg_units
  FROM order_intervals
  GROUP BY store_id, dow, hour_of_day, minute_of_hour
),
order_role_slot_avg AS (
  SELECT dow, hour_of_day, minute_of_hour, AVG(order_units) AS avg_units
  FROM order_intervals
  GROUP BY dow, hour_of_day, minute_of_hour
),
order_global_slot_avg AS (
  SELECT hour_of_day, minute_of_hour, AVG(order_units) AS avg_units
  FROM order_intervals
  GROUP BY hour_of_day, minute_of_hour
),
-- ---- Fallback: day-grain sales + fixed intra-day profile ----
hours AS (
  SELECT explode(sequence(8, 19)) AS hour_of_day
),
intra_day AS (
  SELECT hour_of_day,
         CASE hour_of_day
           WHEN 8 THEN 0.05 WHEN 9 THEN 0.07 WHEN 10 THEN 0.09 WHEN 11 THEN 0.10
           WHEN 12 THEN 0.12 WHEN 13 THEN 0.11 WHEN 14 THEN 0.09 WHEN 15 THEN 0.08
           WHEN 16 THEN 0.08 WHEN 17 THEN 0.09 WHEN 18 THEN 0.07 WHEN 19 THEN 0.05
           ELSE 0.0 END AS hour_share
  FROM hours
),
intervals AS (
  SELECT
    h.hour_of_day,
    h.hour_share / CAST((60 / p.interval_minutes) AS DOUBLE) AS interval_share,
    explode(sequence(0, 60 - p.interval_minutes, p.interval_minutes)) AS minute_of_hour,
    p.interval_minutes,
    p.forecast_horizon_days
  FROM intra_day h
  CROSS JOIN params p
),
roles AS (
  SELECT explode(array('cashier', 'sales_associate', 'fulfillment', 'inventory', 'supervisor')) AS role_code
),
stores AS (
  SELECT store_sk, store_id
  FROM ${catalog}.${store_schema}.store
  WHERE is_current = TRUE AND store_status = 'active'
),
hist_daily AS (
  SELECT
    s.store_id,
    s.date_key AS business_date,
    dayofweek(s.date_key) AS dow,
    SUM(s.units) AS txn_proxy
  FROM ${catalog}.${transaction_schema}.sales s
  GROUP BY s.store_id, s.date_key, dayofweek(s.date_key)
),
store_dow_avg AS (
  SELECT store_id, dow, AVG(txn_proxy) AS avg_units
  FROM hist_daily
  GROUP BY store_id, dow
),
role_dow_avg AS (
  SELECT dow, AVG(txn_proxy) AS avg_units
  FROM hist_daily
  GROUP BY dow
),
global_avg AS (
  SELECT AVG(txn_proxy) AS avg_units FROM hist_daily
),
future_dates AS (
  SELECT explode(sequence(current_date(), date_add(current_date(), p.forecast_horizon_days - 1))) AS business_date,
         p.interval_minutes,
         p.forecast_horizon_days
  FROM params p
),
base AS (
  SELECT
    st.store_sk,
    st.store_id,
    fd.business_date,
    timestamp(concat(CAST(fd.business_date AS STRING), ' ',
                     lpad(CAST(iv.hour_of_day AS STRING), 2, '0'), ':',
                     lpad(CAST(iv.minute_of_hour AS STRING), 2, '0'), ':00')) AS interval_start_ts,
    timestamp(concat(CAST(fd.business_date AS STRING), ' ',
                     lpad(CAST(iv.hour_of_day AS STRING), 2, '0'), ':',
                     lpad(CAST(iv.minute_of_hour AS STRING), 2, '0'), ':00'))
      + make_interval(0, 0, 0, 0, 0, iv.interval_minutes, 0) AS interval_end_ts,
    iv.interval_minutes,
    'storewide' AS department_or_zone,
    r.role_code,
    dayofweek(fd.business_date) AS dow,
    iv.hour_of_day,
    iv.minute_of_hour,
    iv.interval_share,
    fd.forecast_horizon_days
  FROM stores st
  CROSS JOIN future_dates fd
  CROSS JOIN intervals iv
  CROSS JOIN roles r
),
forecasted AS (
  SELECT
    b.*,
    -- Prefer order-interval seasonal average; else sales day-profile fallback.
    CASE
      WHEN osa.avg_units IS NOT NULL THEN osa.avg_units
      WHEN ora.avg_units IS NOT NULL THEN ora.avg_units
      WHEN oga.avg_units IS NOT NULL THEN oga.avg_units
      ELSE COALESCE(sda.avg_units, rda.avg_units, g.avg_units, 0) * b.interval_share
    END
      * CASE b.role_code
          WHEN 'cashier' THEN 1.0
          WHEN 'sales_associate' THEN 0.8
          WHEN 'fulfillment' THEN 0.25
          WHEN 'inventory' THEN 0.15
          WHEN 'supervisor' THEN 0.05
          ELSE 0.5 END AS forecast_driver_units,
    CASE
      WHEN osa.avg_units IS NOT NULL THEN 'seasonal_rolling_avg'
      WHEN ora.avg_units IS NOT NULL OR oga.avg_units IS NOT NULL THEN 'hierarchical_fallback'
      WHEN sda.avg_units IS NOT NULL THEN 'seasonal_rolling_avg'
      ELSE 'hierarchical_fallback'
    END AS forecast_method,
    -- model_version is a RESERVED column, NULL for the shipped heuristic rows
    -- (ADR 0028 §4; same contract as store_risk_score.model_version). ORDM
    -- trains and serves no models, so a version label here would imply a
    -- calibrated model that does not exist. An adopter pipeline writing rows
    -- with forecast_method = 'model' populates it.
    CAST(NULL AS STRING) AS model_version
  FROM base b
  LEFT JOIN order_slot_avg osa
    ON osa.store_id = b.store_id AND osa.dow = b.dow
   AND osa.hour_of_day = b.hour_of_day AND osa.minute_of_hour = b.minute_of_hour
  LEFT JOIN order_role_slot_avg ora
    ON ora.dow = b.dow AND ora.hour_of_day = b.hour_of_day AND ora.minute_of_hour = b.minute_of_hour
  LEFT JOIN order_global_slot_avg oga
    ON oga.hour_of_day = b.hour_of_day AND oga.minute_of_hour = b.minute_of_hour
  LEFT JOIN store_dow_avg sda ON sda.store_id = b.store_id AND sda.dow = b.dow
  LEFT JOIN role_dow_avg rda ON rda.dow = b.dow
  CROSS JOIN global_avg g
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
  CASE role_code
    WHEN 'cashier' THEN 'transaction_count'
    WHEN 'sales_associate' THEN 'foot_traffic'
    WHEN 'fulfillment' THEN 'pickup_orders'
    WHEN 'inventory' THEN 'receiving_units'
    WHEN 'supervisor' THEN 'store_open_coverage'
    ELSE 'transaction_count'
  END AS demand_driver,
  CAST(forecast_driver_units AS DECIMAL(18,4)) AS forecast_driver_units,
  CAST(forecast_driver_units * 0.8 AS DECIMAL(18,4)) AS forecast_lower_bound,
  CAST(forecast_driver_units * 1.2 AS DECIMAL(18,4)) AS forecast_upper_bound,
  forecast_method,
  model_version,
  forecast_horizon_days,
  current_timestamp() AS forecast_origin_ts
FROM forecasted
WHERE forecast_driver_units >= 0;
