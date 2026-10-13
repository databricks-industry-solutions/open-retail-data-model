-- ============================================================
-- ORDM · Outcome Package · AI-Assisted Store Associates
-- Table: outcome_resolution
-- Layer: outcome package (gold / append-only event fact)
-- Version: 0.5
-- Generated: 2026-08-29
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-29
-- ============================================================
-- What actually happened in the real world after a suggested action: did the
-- prompt close a sale, get the shelf restocked, or come to nothing? One append-only
-- row per resolved action. This is the dataset that makes NBA ROI measurable and
-- provides the labeled history to train future expected-value models (replacing
-- hand-tuned rules).
--
-- outcome_value_amount is the only monetary column in the package, so it carries an
-- explicit currency_code and a single-reporting-currency DQ check (standards §A.12).
-- Adopter-owned producer: ORDM ships the schema + the DQ contract. Demo deployments
-- include deterministic synthetic rows derived from ORDM core synthetic data; adopters
-- load their own in production.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${aasa_schema}.outcome_resolution (
  outcome_resolution_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per resolution.',
  outcome_resolution_id STRING NOT NULL
                          COMMENT 'Durable business key for the resolution.',

  suggested_action_sk   BIGINT NOT NULL COMMENT 'FK to suggested_action.suggested_action_sk — the action resolved.',
  suggested_action_id   STRING NOT NULL COMMENT 'Durable action business key.',

  resolution_timestamp  TIMESTAMP NOT NULL COMMENT 'When the real-world outcome was recorded (UTC, ISO 8601).',
  outcome_type          STRING NOT NULL COMMENT 'What happened. Allowed values: sale_closed, item_restocked, customer_assisted, issue_resolved, task_abandoned, no_outcome.',
  outcome_value_amount  DECIMAL(18,2) COMMENT 'Realized monetary value attributable to the action (e.g. closed-sale amount), in currency_code. NULL for non-monetary outcomes.',
  currency_code         STRING COMMENT 'ISO 4217 currency of outcome_value_amount. Required whenever outcome_value_amount is present (paired by CHECK).',
  units_affected        INT    COMMENT 'Non-monetary outcome magnitude where it applies, e.g. units restocked. NULL when not applicable.',

  -- Audit / provenance (fact block; all timestamps UTC, ISO 8601)
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_outcome_resolution PRIMARY KEY (outcome_resolution_sk)
)
USING DELTA
CLUSTER BY (suggested_action_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'ORDM AI-Assisted Store Associates — append-only real-world outcome of a suggested action (sale, restock, resolution) for ROI and model training. Adopter-owned; schema + DQ contract.';

ALTER TABLE ${catalog}.${aasa_schema}.outcome_resolution SET TAGS ('dbx_data_type' = 'transactional');
