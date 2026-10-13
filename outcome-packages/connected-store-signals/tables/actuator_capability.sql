-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Table: actuator_capability
-- Layer: outcome package (gold / dimensional, master-tagged)
-- Version: 0.5
-- Generated: 2026-08-06
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-06
-- ============================================================
-- The active-control half of a connected device: what a device can be COMMANDED to do,
-- as opposed to what it can observe. It completes the sense -> evaluate -> act -> log
-- control loop for the package's IoT Sensor Monitoring use case, alongside
-- evaluation_rule, automation_action and execution_log.
--
-- Reuses, does not redefine, the existing device registry: an actuator is a capability
-- OF a sensor_device whose device_role is 'actuate' or 'both' (standards §A.2's
-- reuse-not-re-import rule). The original hardware `device_component` and
-- `sensor_definition` tables from the source model are already covered by sensor_device,
-- so only this control-side capability is added here rather than duplicating the registry
-- (standards §A.2, one owning file per entity).
--
-- SCD2 because an actuator's command surface changes over its life -- a firmware upgrade
-- adds a command_type, an acceptable range is retuned -- and an execution_log audit asks
-- for the capability that applied AT THE TIME the command fired, not the current one.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${css_schema}.actuator_capability (
  actuator_capability_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version.',
  actuator_capability_id STRING NOT NULL
                          COMMENT 'Durable natural/business key for the actuator capability. Stable across SCD2 versions and across firmware upgrades.',

  sensor_device_sk      BIGINT COMMENT 'FK to sensor_device.sensor_device_sk -- the device that exposes this command surface. The device_role of that device is actuate or both.',
  sensor_device_id      STRING COMMENT 'Durable device id. The SCD2-safe join key.',

  -- Optional link to the maintained asset the actuator drives (e.g. the refrigeration
  -- unit a compressor relay controls). NULL when the actuator drives ambient space or a
  -- purely digital surface such as an electronic shelf label.
  equipment_sk          BIGINT COMMENT 'FK to equipment.equipment_sk when the actuator controls a maintained asset. NULL for ambient or digital-only actuation.',
  equipment_id          STRING COMMENT 'Durable equipment business key. NULL for ambient or digital-only actuation.',

  command_type          STRING COMMENT 'What the actuator can be commanded to do. Allowed values: toggle_power, set_level, set_setpoint, open_close, dispense, display_message, reset.',
  acceptable_value_range STRING COMMENT 'Human-readable bound on a valid command payload for this actuator, e.g. "0,1" for a toggle or "2.0,8.0" for a setpoint in the device native unit. Free text: the shape varies by command_type, so it is a documented contract rather than a typed range.',
  unit_iri              STRING COMMENT 'QUDT unit IRI for a set_level / set_setpoint command value, e.g. http://qudt.org/vocab/unit/DEG_C. NULL for dimensionless commands such as toggle_power.',
  uom_code              STRING COMMENT 'UN/CEFACT Recommendation 20 common code for the command unit, e.g. CEL. The interchange form of unit_iri.',

  actuator_status       STRING COMMENT 'Allowed values: active, inactive, faulty, maintenance, decommissioned.',
  installed_date        DATE   COMMENT 'When the actuator capability became available.',
  decommissioned_date   DATE   COMMENT 'When the actuator was removed. NULL while in service.',

  -- SCD2 versioning (principle #8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version.',

  -- Audit / provenance
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_actuator_capability PRIMARY KEY (actuator_capability_sk)
)
USING DELTA
CLUSTER BY (actuator_capability_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Connected Store Signals -- actuator command-surface registry (SCD2). The active-control capability of a sensor_device; completes the automation loop with evaluation_rule, automation_action and execution_log.';

ALTER TABLE ${catalog}.${css_schema}.actuator_capability SET TAGS ('dbx_data_type' = 'master');
