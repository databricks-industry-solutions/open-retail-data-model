-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Table: automation_action
-- Layer: outcome package (gold / dimensional, master-tagged)
-- Version: 0.5
-- Generated: 2026-08-06
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-06
-- ============================================================
-- The intent definition of the automation loop: WHAT should happen when an
-- evaluation_rule fires. One rule can own several actions (notify a manager AND toggle a
-- compressor), so this is a child of evaluation_rule and the parent of the append-only
-- execution_log.
--
-- The action target is modelled polymorphically (target_entity_type + target_entity_id),
-- exactly as the source model expresses it, because an action can target more than one
-- kind of thing -- an actuator_capability for a physical command, a person/role for a
-- notification, an external system for a webhook. Standards §A.5 names polymorphic
-- references as an adjudicated exception to FK-COMPLETENESS: they carry no single _sk to
-- declare an FK on. The common actuator case additionally carries a typed
-- actuator_capability_sk so the physical-command path IS a declared FK.
--
-- SCD2 because the intent is retuned (a payload template changes, a target moves) and the
-- execution_log audit needs the action version that actually ran.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${css_schema}.automation_action (
  automation_action_sk  BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version.',
  automation_action_id  STRING NOT NULL
                          COMMENT 'Durable natural/business key for the action. Stable across SCD2 versions.',

  evaluation_rule_sk    BIGINT COMMENT 'FK to evaluation_rule.evaluation_rule_sk -- the rule whose firing triggers this action.',
  evaluation_rule_id    STRING COMMENT 'Durable rule id. The SCD2-safe join key.',

  action_type           STRING COMMENT 'What kind of action this is. Allowed values: system_command, notification, webhook, ticket, log_only.',
  target_entity_type    STRING COMMENT 'The kind of thing the action targets -- the discriminator of a polymorphic reference (standards §A.5). Allowed values: actuator, role, person, external_system, none.',
  target_entity_id      STRING COMMENT 'Durable id of the target, interpreted per target_entity_type. For target_entity_type = actuator this is the actuator_capability_id and actuator_capability_sk carries the typed FK.',

  -- Typed FK for the common physical-command path. NULL when target_entity_type is not
  -- actuator (a notification or webhook has no actuator), which is why the polymorphic
  -- id pair above is retained for the other target kinds.
  actuator_capability_sk BIGINT COMMENT 'FK to actuator_capability.actuator_capability_sk when target_entity_type = actuator. NULL for non-actuator targets.',
  actuator_capability_id STRING COMMENT 'Durable actuator id. The SCD2-safe join key. NULL for non-actuator targets.',

  payload_template      STRING COMMENT 'Templated command or message payload sent when the action fires, e.g. {"command": "start_cooling", "power_level": "max"}. A template, not a rendered instance -- the rendered form is on execution_log.response_payload.',
  is_enabled            BOOLEAN COMMENT 'TRUE if the action is live. A disabled action leaves its rule firing but takes no effect.',

  -- SCD2 versioning (principle #8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version.',

  -- Audit / provenance
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_automation_action PRIMARY KEY (automation_action_sk)
)
USING DELTA
CLUSTER BY (automation_action_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Connected Store Signals -- intent definition for the automation loop (SCD2). What happens when an evaluation_rule fires; realised runs are recorded append-only in execution_log.';

ALTER TABLE ${catalog}.${css_schema}.automation_action SET TAGS ('dbx_data_type' = 'master');
