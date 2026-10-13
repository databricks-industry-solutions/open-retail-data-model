-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- Table: forecast_accuracy
-- Layer: outcome package (extension table / transactional fact)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Lag-based forecast accuracy snapshot at planning-unit x period grain.
-- ============================================================


CREATE TABLE IF NOT EXISTS ${catalog}.${sdi_schema}.forecast_accuracy (
  forecast_accuracy_sk    BIGINT GENERATED ALWAYS AS IDENTITY
                            COMMENT 'Surrogate key.',
  forecast_accuracy_id    STRING NOT NULL
                            COMMENT 'Durable business key.',

  planning_unit_sk        BIGINT NOT NULL COMMENT 'FK to planning_unit.planning_unit_sk.',
  planning_unit_id        STRING NOT NULL COMMENT 'Durable planning unit business key.',
  forecast_date_key       DATE NOT NULL COMMENT 'Forecast period evaluated.',

  actual_quantity         DECIMAL(12,3) COMMENT 'Actual demand from sales or shipments.',
  forecast_quantity       DECIMAL(12,3) COMMENT 'Statistical forecast at lag.',
  effective_forecast_quantity DECIMAL(12,3) COMMENT 'Forecast after planner adjustments.',
  lag_weeks               INT COMMENT 'Lag in weeks between forecast and actuals.',
  accuracy_pct            DOUBLE COMMENT 'Forecast accuracy percentage.',
  bias_pct                DOUBLE COMMENT 'Forecast bias in WHOLE PERCENTAGE POINTS (e.g. -5.0 = 5% under-forecast), NOT a 0-1 fraction. Downstream thresholds (e.g. gold_oos_preventability) read this points scale. Note: mv_forecast_accuracy publishes a DIFFERENT, volume-weighted bias measure on a 0-1 fraction; same word, different object and scale.',
  mape                    DOUBLE COMMENT 'Mean absolute percentage error.',
  is_stockout_censored    BOOLEAN COMMENT 'TRUE when actual period had a stockout.',

  record_source           STRING    COMMENT 'Originating system of record.',
  load_timestamp          TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_forecast_accuracy PRIMARY KEY (forecast_accuracy_sk)
)
USING DELTA
CLUSTER BY (forecast_date_key, planning_unit_sk)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Forecast accuracy and bias at planning-unit x period grain.';

ALTER TABLE ${catalog}.${sdi_schema}.forecast_accuracy SET TAGS ('dbx_data_type' = 'transactional');
