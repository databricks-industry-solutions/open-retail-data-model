-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Table: execution_log
-- Layer: outcome package (gold / append-only event fact)
-- Version: 0.5
-- Generated: 2026-08-06
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-06
-- ============================================================
-- The downstream audit ledger of the automation loop: one row per realised firing of an
-- automation_action against an actuator. This is where sense -> evaluate -> act becomes
-- an auditable record of what actually happened.
--
-- APPEND-ONLY event fact, not a dimension: it is never restated and carries no SCD2
-- columns. Per standards §A.8 an append-only fact carries only the record_source +
-- load_timestamp audit block, not the created/source_updated pair a master carries. The
-- surrogate is a straight IDENTITY (moderate write volume -- rules fire far less often
-- than sensors observe, so the IDENTITY concurrency caveat that pushed
-- sensor_report_interval to a hash key does not bite here; ADR 0004 applies as written).
--
-- Both parent references are nullable, matching the source ON DELETE SET NULL intent: a
-- log row must survive the retirement of the action or actuator it references so the
-- audit trail is not erased when a rule is decommissioned.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${css_schema}.execution_log (
  execution_log_sk      BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key for the execution event.',
  execution_log_id      STRING NOT NULL
                          COMMENT 'Durable natural/business key for the execution event, from the source automation platform. Identifies the FIRING (the action that ran against its triggering observation), not merely the observation -- one breaching interval can fire several actions, so a key scoped to the interval alone would collide and defeat the one-row-per-firing grain (el_grain_unique).',

  automation_action_sk  BIGINT COMMENT 'FK to automation_action.automation_action_sk -- the action version that fired. NULL when the action has been retired (the log row outlives it).',
  automation_action_id  STRING COMMENT 'Durable action id. The SCD2-safe join key.',
  actuator_capability_sk BIGINT COMMENT 'FK to actuator_capability.actuator_capability_sk -- the actuator the command hit. NULL for a non-actuator action (notification, webhook) or a retired actuator.',
  actuator_capability_id STRING COMMENT 'Durable actuator id. The SCD2-safe join key. NULL for non-actuator actions.',
  evaluation_rule_sk    BIGINT COMMENT 'FK to evaluation_rule.evaluation_rule_sk -- the rule version whose breach triggered this run. Denormalised onto the fact so "which rule caused this action" survives the retirement of automation_action.',
  evaluation_rule_id    STRING COMMENT 'Durable rule id. The SCD2-safe join key.',
  sensor_report_interval_sk BIGINT COMMENT 'FK to sensor_report_interval.sensor_report_interval_sk -- the reading interval that breached the rule, closing the loop back to the observation that caused the action. NULL if the trigger was not a single canonical interval.',

  triggered_at_timestamp TIMESTAMP NOT NULL COMMENT 'When the action fired (UTC, ISO 8601). The ordering key for the ledger.',
  execution_status      STRING NOT NULL COMMENT 'Outcome of the run. Allowed values: success, failure, pending, timeout, skipped.',
  response_payload      STRING COMMENT 'Rendered response from the target, e.g. {"status_code": 200, "message": "Actuator triggered successfully"}. The realised counterpart to automation_action.payload_template.',
  latency_ms            BIGINT COMMENT 'Milliseconds between the triggering observation and this execution. Feeds automation responsiveness monitoring.',

  -- Audit / provenance (append-only fact block, standards §A.8: no created/source_updated pair)
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_execution_log PRIMARY KEY (execution_log_sk)
)
USING DELTA
CLUSTER BY (triggered_at_timestamp)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Connected Store Signals -- append-only audit ledger of realised automation firings. Closes the sense -> evaluate -> act loop back to the observation that triggered it.';

ALTER TABLE ${catalog}.${css_schema}.execution_log SET TAGS ('dbx_data_type' = 'transactional');
