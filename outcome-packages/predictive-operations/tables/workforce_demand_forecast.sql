-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · Workforce Optimization
-- Table: workforce_demand_forecast
-- Layer: outcome package (extension table / transactional fact)
-- Version: 0.5
-- Generated: 2026-08-10
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-10
-- ============================================================
-- Durable demand forecast lines at store x date x interval x zone x role.
-- Written by an adopter forecasting pipeline (or the reference notebook).
-- gold_workforce_demand_forecast is the live heuristic computation.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${predops_schema}.workforce_demand_forecast (
  workforce_demand_forecast_sk BIGINT GENERATED ALWAYS AS IDENTITY
                                 COMMENT 'Surrogate key.',
  workforce_demand_forecast_id STRING NOT NULL
                                 COMMENT 'Durable business key for the forecast line.',

  workforce_optimization_run_id STRING COMMENT 'FK-like link to workforce_optimization_run.workforce_optimization_run_id.',
  store_sk              BIGINT COMMENT 'FK to store.store_sk.',
  store_id              STRING NOT NULL COMMENT 'Durable store business key.',
  business_date         DATE NOT NULL COMMENT 'Local business date being forecast (ISO 8601).',
  interval_start_ts     TIMESTAMP NOT NULL COMMENT 'Inclusive interval start (UTC, ISO 8601).',
  interval_end_ts       TIMESTAMP NOT NULL COMMENT 'Exclusive interval end (UTC, ISO 8601).',
  interval_minutes      INT NOT NULL COMMENT 'Interval length in minutes.',
  department_or_zone    STRING NOT NULL COMMENT 'Department or zone (storewide when unknown).',
  role_code             STRING NOT NULL
                          COMMENT 'Role. Allowed values: cashier, sales_associate, fulfillment, inventory, supervisor.',

  demand_driver         STRING NOT NULL
                          COMMENT 'Driver being forecast. Allowed values: transaction_count, foot_traffic, pickup_orders, receiving_units, store_open_coverage, minimum_coverage.',
  forecast_driver_units DECIMAL(18,4) NOT NULL COMMENT 'Forecasted driver units for the interval.',
  forecast_lower_bound  DECIMAL(18,4) COMMENT 'Lower uncertainty proxy bound.',
  forecast_upper_bound  DECIMAL(18,4) COMMENT 'Upper uncertainty proxy bound.',
  forecast_method       STRING NOT NULL
                          COMMENT 'Method. Allowed values: seasonal_rolling_avg, hierarchical_fallback, model, manual.',
  model_version         STRING COMMENT 'Version of the model that produced the row when forecast_method = model; NULL for heuristic rows.',
  forecast_horizon_days INT NOT NULL COMMENT 'Forward horizon in days this line belongs to.',
  forecast_origin_ts    TIMESTAMP NOT NULL COMMENT 'When the forecast was produced (UTC, ISO 8601).',

  record_source         STRING COMMENT 'Originating pipeline or system.',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_workforce_demand_forecast PRIMARY KEY (workforce_demand_forecast_sk)
)
USING DELTA
CLUSTER BY (store_id, business_date)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Workforce demand forecast fact at store x date x interval x zone x role grain.';

ALTER TABLE ${catalog}.${predops_schema}.workforce_demand_forecast SET TAGS ('dbx_data_type' = 'transactional');

ALTER TABLE ${catalog}.${predops_schema}.workforce_demand_forecast ADD CONSTRAINT chk_wdf_role CHECK (role_code IN ('cashier', 'sales_associate', 'fulfillment', 'inventory', 'supervisor'));
ALTER TABLE ${catalog}.${predops_schema}.workforce_demand_forecast ADD CONSTRAINT chk_wdf_driver CHECK (demand_driver IN ('transaction_count', 'foot_traffic', 'pickup_orders', 'receiving_units', 'store_open_coverage', 'minimum_coverage'));
ALTER TABLE ${catalog}.${predops_schema}.workforce_demand_forecast ADD CONSTRAINT chk_wdf_method CHECK (forecast_method IN ('seasonal_rolling_avg', 'hierarchical_fallback', 'model', 'manual'));
ALTER TABLE ${catalog}.${predops_schema}.workforce_demand_forecast ADD CONSTRAINT chk_wdf_interval CHECK (interval_end_ts > interval_start_ts AND interval_minutes > 0);
ALTER TABLE ${catalog}.${predops_schema}.workforce_demand_forecast ADD CONSTRAINT chk_wdf_units CHECK (forecast_driver_units >= 0);
ALTER TABLE ${catalog}.${predops_schema}.workforce_demand_forecast ADD CONSTRAINT chk_wdf_horizon CHECK (forecast_horizon_days > 0);
