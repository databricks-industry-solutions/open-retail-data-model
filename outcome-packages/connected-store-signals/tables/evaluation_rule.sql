-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Table: evaluation_rule
-- Layer: outcome package (gold / dimensional, master-tagged)
-- Version: 0.5
-- Generated: 2026-08-06
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-06
-- ============================================================
-- The threshold framework of the automation loop: the standing condition that, when a
-- sensor's readings satisfy it over a time window, fires one or more automation_action
-- rows. This is the "evaluate" stage between sensing (sensor_report_interval) and acting
-- (automation_action -> execution_log).
--
-- A rule is defined AGAINST the observed property of a sensor, not against one physical
-- device, so it survives a sensor swap. It therefore references the sensor_device
-- registry (the observer) plus the GS1 CBV report_type the rule watches, which is the
-- same discriminator sensor_report_interval carries -- so a rule and the readings it
-- evaluates speak the same vocabulary.
--
-- SCD2 because a threshold is retuned over the life of a deployment (a cold-chain limit
-- tightened, a window lengthened to debounce), and an execution_log audit must recover
-- the rule version that actually fired, not today's tuning.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${css_schema}.evaluation_rule (
  evaluation_rule_sk    BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version.',
  evaluation_rule_id    STRING NOT NULL
                          COMMENT 'Durable natural/business key for the rule. Stable across SCD2 versions as the threshold is retuned.',

  sensor_device_sk      BIGINT COMMENT 'FK to sensor_device.sensor_device_sk -- the observing device whose readings this rule evaluates. NULL for a rule that evaluates a cross-device aggregate.',
  sensor_device_id      STRING COMMENT 'Durable device id. The SCD2-safe join key.',

  rule_name             STRING COMMENT 'Human-readable rule name, e.g. "Vaccine fridge over 8C for 10 minutes".',
  report_type           STRING COMMENT 'GS1 CBV sensor-property CURIE the rule watches, matching sensor_report_interval.report_type. Allowed values: gs1:Count, gs1:Temperature, gs1:RelativeHumidity, gs1:Power, gs1:Energy, gs1:Mass, gs1:Illuminance, gs1:VolumeFraction.',
  condition_operator    STRING COMMENT 'Comparison applied to the observed value. Allowed values: greater_than, greater_than_or_equal, less_than, less_than_or_equal, equal, not_equal, outside_range, inside_range.',
  threshold_value_numeric DOUBLE COMMENT 'Threshold the observed value is compared against, in the rule unit. NULL for a purely categorical rule. DOUBLE, not DECIMAL: this is a non-monetary continuous physical quantity (temperature, humidity, power) compared directly against sensor_report_interval.value, which is DOUBLE -- matching the two avoids precision/comparison surprises, and DECIMAL(18,x) is reserved for stored money (standards §A.6).',
  threshold_value_upper DOUBLE COMMENT 'Upper bound for the inside_range / outside_range operators; NULL otherwise. threshold_value_numeric is the lower bound in that case. DOUBLE for the same reason as threshold_value_numeric.',
  unit_iri              STRING COMMENT 'QUDT unit IRI for the threshold, e.g. http://qudt.org/vocab/unit/DEG_C. NULL for a dimensionless (count) rule.',
  uom_code              STRING COMMENT 'UN/CEFACT Recommendation 20 common code for the threshold unit, e.g. CEL. The interchange form of unit_iri.',
  time_window_seconds   INT COMMENT 'Sustained-breach window in seconds: the condition must hold this long before the rule fires, which debounces a single transient reading. 0 means fire on the first breaching observation.',

  severity              STRING COMMENT 'Operational severity of a breach. Allowed values: info, warning, critical.',
  is_enabled            BOOLEAN COMMENT 'TRUE if the rule is live. Replaces the source CHAR(1) Y/N flag with a native BOOLEAN per strict-typing (standards §A.6).',

  -- SCD2 versioning (principle #8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version.',

  -- Audit / provenance
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_evaluation_rule PRIMARY KEY (evaluation_rule_sk)
)
USING DELTA
CLUSTER BY (evaluation_rule_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Connected Store Signals -- threshold framework for the automation loop (SCD2). A standing condition on a sensor observed property that fires automation_action rows.';

ALTER TABLE ${catalog}.${css_schema}.evaluation_rule SET TAGS ('dbx_data_type' = 'master');
