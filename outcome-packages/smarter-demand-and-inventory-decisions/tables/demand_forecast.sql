-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- Table: demand_forecast
-- Layer: outcome package (extension table / transactional fact)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Forward-looking and backtest demand forecast lines at planning-unit grain.
-- ============================================================


CREATE TABLE IF NOT EXISTS ${catalog}.${sdi_schema}.demand_forecast (
  demand_forecast_sk      BIGINT GENERATED ALWAYS AS IDENTITY
                            COMMENT 'Surrogate key.',
  demand_forecast_id      STRING NOT NULL
                            COMMENT 'Durable business key for the forecast line.',

  model_run_sk            BIGINT COMMENT 'FK to forecast_model_run.model_run_sk.',
  model_run_id            STRING COMMENT 'Durable model run business key.',
  planning_unit_sk        BIGINT NOT NULL COMMENT 'FK to planning_unit.planning_unit_sk.',
  planning_unit_id        STRING NOT NULL COMMENT 'Durable planning unit business key.',

  forecast_date_key       DATE NOT NULL COMMENT 'Period being forecast (day or week start).',
  forecast_horizon_type   STRING NOT NULL
                            COMMENT 'Horizon bucket. Allowed values: short_term, mid_term, long_term, backtest.',
  forecast_lag_weeks      INT COMMENT 'Weeks between forecast origin and actuals availability.',
  forecast_origin_date_key DATE COMMENT 'Date the forecast was produced.',
  forecast_quantity       DECIMAL(12,3) NOT NULL COMMENT 'Forecasted demand quantity in UOM.',
  forecast_lower_bound    DECIMAL(12,3) COMMENT 'Lower prediction interval bound.',
  forecast_upper_bound    DECIMAL(12,3) COMMENT 'Upper prediction interval bound.',
  unit_of_measure         STRING COMMENT 'Unit of measure code.',

  record_source           STRING    COMMENT 'Originating system of record.',
  load_timestamp          TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_demand_forecast PRIMARY KEY (demand_forecast_sk)
)
USING DELTA
CLUSTER BY (forecast_date_key, planning_unit_sk)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Demand forecast fact at planning-unit x period grain.';

ALTER TABLE ${catalog}.${sdi_schema}.demand_forecast SET TAGS ('dbx_data_type' = 'transactional');
ALTER TABLE ${catalog}.${sdi_schema}.demand_forecast ADD CONSTRAINT chk_df_horizon CHECK (forecast_horizon_type IN ('short_term', 'mid_term', 'long_term', 'backtest'));
