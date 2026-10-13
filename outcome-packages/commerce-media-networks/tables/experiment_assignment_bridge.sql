-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- Table: experiment_assignment_bridge
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- Append-only, one row per assignment of a unit (user/household/geo/store/
-- device) to an experiment cell. Conforms the incrementality-testing brief's
-- fact_experiment_assignment. Together with the nullable experiment links on
-- media_event / conversion_event / attributed_outcome, this
-- removes the need for separate incrementality event/conversion/sale facts.
-- Person-level (hashed key), privacy-tiered.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${cmn_schema}.experiment_assignment_bridge (
  experiment_assignment_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  experiment_assignment_id STRING NOT NULL
                          COMMENT 'Durable natural/business key for the assignment.',

  experiment_sk         BIGINT COMMENT 'FK to cmn.experiment.experiment_sk.',
  experiment_id         STRING COMMENT 'Durable experiment business key.',
  experiment_cell_sk    BIGINT COMMENT 'FK to cmn.experiment_cell.experiment_cell_sk (treatment/control/holdout).',
  experiment_cell_id    STRING COMMENT 'Durable experiment cell business key.',
  profile_sk            BIGINT COMMENT 'FK to customer.profile.profile_sk when the assignment unit resolves to a customer.',
  profile_id            STRING COMMENT 'Durable customer business key (pseudonymous).',

  assignment_unit_type  STRING COMMENT 'Randomization unit. Allowed values: user, household, geo, store, device.',
  assignment_unit_key_hash STRING COMMENT 'Hashed/tokenized assignment-unit identifier (PII, never raw).',
  assignment_ts         TIMESTAMP NOT NULL COMMENT 'When the unit was assigned to the cell (UTC, ISO 8601).',

  -- Audit / provenance (append-only fact block; all timestamps UTC)
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_experiment_assignment_bridge PRIMARY KEY (experiment_assignment_sk)
)
USING DELTA
CLUSTER BY (experiment_id, experiment_cell_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Commerce Media Networks — experiment assignment bridge (unit x cell, append-only).';

ALTER TABLE ${catalog}.${cmn_schema}.experiment_assignment_bridge SET TAGS ('dbx_data_type' = 'association');

ALTER TABLE ${catalog}.${cmn_schema}.experiment_assignment_bridge ALTER COLUMN assignment_unit_key_hash SET TAGS ('dbx_pii_identifier' = 'true');
