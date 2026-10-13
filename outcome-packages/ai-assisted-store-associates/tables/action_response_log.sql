-- ============================================================
-- ORDM · Outcome Package · AI-Assisted Store Associates
-- Table: action_response_log
-- Layer: outcome package (gold / append-only event fact)
-- Version: 0.5
-- Generated: 2026-08-29
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-29
-- ============================================================
-- How an associate interacted with a suggested action on their device: the
-- append-only lifecycle-transition log for suggested_action. One row per response
-- event; the row is never restated. This is the immutable half of the pair whose
-- current-state half (latest status/priority) lives on suggested_action.
--
-- Optimization value (source rationale): a run of "rejected | too_busy" responses
-- in one zone is a staffing signal; captured immutably here it also stops the engine
-- routing more work to an overwhelmed associate. Adopter-owned producer: ORDM ships
-- the schema + the DQ contract. Demo deployments include deterministic synthetic rows
-- derived from ORDM core synthetic data; adopters load their own in production.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${aasa_schema}.action_response_log (
  action_response_log_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per response event.',
  action_response_log_id STRING NOT NULL
                          COMMENT 'Durable business key for the response event.',

  suggested_action_sk   BIGINT NOT NULL COMMENT 'FK to suggested_action.suggested_action_sk — the action responded to.',
  suggested_action_id   STRING NOT NULL COMMENT 'Durable action business key.',
  associate_sk          BIGINT COMMENT 'FK to associate.associate_sk — the responding associate (version at response time).',
  associate_id          STRING COMMENT 'Durable associate business key. The SCD2-safe join/aggregation key.',

  response_timestamp    TIMESTAMP NOT NULL COMMENT 'When the associate responded (UTC, ISO 8601). The business event time.',
  response_type         STRING NOT NULL COMMENT 'How the associate acted on the prompt. Allowed values: accepted, rejected, deferred, completed, expired, reassigned.',
  reason_code           STRING COMMENT 'Optional reason the associate gave, esp. on reject/defer. Free STRING (operationally extensible); common values: too_busy, wrong_zone, not_qualified, customer_left, out_of_stock, already_handled, completed_successfully.',

  -- Audit / provenance (fact block; all timestamps UTC, ISO 8601)
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_action_response_log PRIMARY KEY (action_response_log_sk)
)
USING DELTA
CLUSTER BY (suggested_action_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'ORDM AI-Assisted Store Associates — append-only log of associate responses to suggested actions (accept/reject/defer/complete). Adopter-owned; schema + DQ contract.';

ALTER TABLE ${catalog}.${aasa_schema}.action_response_log SET TAGS ('dbx_data_type' = 'transactional');
