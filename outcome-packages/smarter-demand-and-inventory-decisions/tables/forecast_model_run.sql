-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- Table: forecast_model_run
-- Layer: outcome package (extension table / reference)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Model training and scoring execution registry.
-- ============================================================


CREATE TABLE IF NOT EXISTS ${catalog}.${sdi_schema}.forecast_model_run (
  model_run_sk            BIGINT GENERATED ALWAYS AS IDENTITY
                            COMMENT 'Surrogate key.',
  model_run_id            STRING NOT NULL
                            COMMENT 'Durable business key for the model run.',

  model_name              STRING NOT NULL COMMENT 'Model algorithm name (e.g. lightgbm, prophet, arima).',
  model_version           STRING COMMENT 'Semantic version or artifact hash.',
  hierarchy_level         STRING COMMENT 'Forecast hierarchy level this run targets.',
  training_start_date     DATE COMMENT 'Training window start date.',
  training_end_date       DATE COMMENT 'Training window end date.',
  scored_at_timestamp     TIMESTAMP COMMENT 'When the model was scored (UTC).',
  is_champion             BOOLEAN COMMENT 'Whether this is the champion model for its hierarchy.',
  accuracy_score          DOUBLE COMMENT 'Holdout forecast accuracy (0-1).',
  bias_pct                DOUBLE COMMENT 'Holdout forecast bias percentage.',

  -- Audit / provenance (reference table block; standard §8)
  created_timestamp        TIMESTAMP COMMENT 'When the record was created (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified (UTC, ISO 8601).',
  record_source           STRING    COMMENT 'Originating system of record.',
  load_timestamp          TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_forecast_model_run PRIMARY KEY (model_run_sk)
)
USING DELTA
CLUSTER BY (model_run_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Registry of forecast model training and scoring runs.';

ALTER TABLE ${catalog}.${sdi_schema}.forecast_model_run SET TAGS ('dbx_data_type' = 'reference');
