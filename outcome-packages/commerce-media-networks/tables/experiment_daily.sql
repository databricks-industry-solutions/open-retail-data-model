-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- Table: experiment_daily
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- Append-only daily rollup per experiment × cell × date × analysis slice. The
-- intermediate aggregate feeding incrementality_result (kept separate from
-- campaign_day because the grain is experiment-cell, not campaign-delivery).
-- Aggregate; not person-level.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${cmn_schema}.experiment_daily (
  experiment_daily_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  experiment_daily_id STRING NOT NULL
                          COMMENT 'Durable natural/business key (grain hash).',

  experiment_sk         BIGINT COMMENT 'FK to cmn.experiment.experiment_sk.',
  experiment_id         STRING COMMENT 'Durable experiment business key.',
  experiment_cell_sk    BIGINT COMMENT 'FK to cmn.experiment_cell.experiment_cell_sk.',
  experiment_cell_id    STRING COMMENT 'Durable experiment cell business key.',

  metric_date           DATE NOT NULL COMMENT 'Business date of the aggregate (cluster key).',
  analysis_level        STRING COMMENT 'Slice level. Allowed values: overall, store, geo, product, category, vendor.',
  exposed_units         BIGINT COMMENT 'Count of assignment units exposed to media in the cell.',
  converted_units       BIGINT COMMENT 'Count of assignment units that converted in the cell.',
  sales_amount          DECIMAL(18,2) COMMENT 'Cell sales, in the reporting/base currency.',
  media_spend_amount    DECIMAL(18,2) COMMENT 'Cell media spend, in the reporting/base currency.',
  currency_code         STRING COMMENT 'Amount currency, ISO 4217 alpha-3 (single reporting currency).',

  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_experiment_daily PRIMARY KEY (experiment_daily_sk)
)
USING DELTA
CLUSTER BY (metric_date, experiment_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Commerce Media Networks — experiment×cell×day aggregate feeding the incrementality readout.';

ALTER TABLE ${catalog}.${cmn_schema}.experiment_daily SET TAGS ('dbx_data_type' = 'transactional');
