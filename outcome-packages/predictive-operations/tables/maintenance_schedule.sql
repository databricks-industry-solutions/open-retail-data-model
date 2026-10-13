-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · In-Store Equipment Maintenance use case
-- Table: maintenance_schedule
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-07-15
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-29 by @sreekanthmunigati
-- ============================================================
-- Preventive maintenance schedule (SCD2): recurring maintenance plans
-- for equipment assets. Versioned so schedule changes (frequency,
-- cost, active/inactive transitions) are historically auditable.
-- Drives the gold_maintenance_effectiveness view by defining what
-- maintenance SHOULD happen and when.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${predops_schema}.maintenance_schedule (
  maintenance_schedule_sk BIGINT GENERATED ALWAYS AS IDENTITY
                           COMMENT 'Surrogate key. Unique per SCD2 version; the join/FK target.',
  maintenance_schedule_id STRING NOT NULL
                           COMMENT 'Durable natural/business key for the schedule entry.',

  equipment_sk          BIGINT COMMENT 'FK to equipment.equipment_sk (version-specific).',
  equipment_id          STRING NOT NULL COMMENT 'Durable equipment business key.',

  schedule_name         STRING NOT NULL COMMENT 'Name of the maintenance schedule (e.g. "Quarterly HVAC Filter Change").',
  task_description      STRING COMMENT 'Description of the preventive maintenance task.',
  frequency             STRING NOT NULL COMMENT 'How often the task recurs. Allowed values: daily, weekly, biweekly, monthly, quarterly, semi_annual, annual.',
  interval_days         INT NOT NULL COMMENT 'Number of calendar days between scheduled occurrences.',

  next_due_date         DATE COMMENT 'Next scheduled maintenance date (ISO 8601).',
  last_completed_date   DATE COMMENT 'Date the task was last completed (ISO 8601).',
  is_active             BOOLEAN NOT NULL COMMENT 'Whether this schedule is currently active.',

  estimated_duration_hours DECIMAL(6,1) COMMENT 'Estimated labor hours per occurrence.',
  estimated_cost        DECIMAL(12,2) COMMENT 'Estimated cost per occurrence in base currency.',
  currency_code         STRING NOT NULL COMMENT 'Reporting/base currency for cost columns, ISO 4217 alpha-3.',

  -- SCD2 versioning (standard A.8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version.',

  -- Audit / provenance (master audit block)
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system (CMMS, EAM, or manual entry).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_maintenance_schedule PRIMARY KEY (maintenance_schedule_sk)
)
USING DELTA
CLUSTER BY (equipment_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Preventive maintenance schedules for in-store equipment (SCD2). Defines recurring maintenance tasks and their cadence. Versioned so schedule changes are historically auditable.';

ALTER TABLE ${catalog}.${predops_schema}.maintenance_schedule SET TAGS ('dbx_data_type' = 'master');

ALTER TABLE ${catalog}.${predops_schema}.maintenance_schedule ADD CONSTRAINT chk_ms_frequency CHECK (frequency IN ('daily', 'weekly', 'biweekly', 'monthly', 'quarterly', 'semi_annual', 'annual'));
ALTER TABLE ${catalog}.${predops_schema}.maintenance_schedule ADD CONSTRAINT chk_ms_interval CHECK (interval_days > 0);
