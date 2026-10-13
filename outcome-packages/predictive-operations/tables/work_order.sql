-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · In-Store Equipment Maintenance use case
-- Table: work_order
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-07-15
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-29 by @sreekanthmunigati
-- ============================================================
-- Maintenance work order header. Each work order represents a
-- maintenance task (preventive, corrective, or emergency) for
-- one equipment asset. Tracks the full lifecycle from creation
-- through completion or cancellation.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${predops_schema}.work_order (
  work_order_sk         BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  work_order_id         STRING NOT NULL
                          COMMENT 'Durable natural/business key for the work order.',

  equipment_sk          BIGINT COMMENT 'FK to equipment.equipment_sk (version-specific).',
  equipment_id          STRING NOT NULL COMMENT 'Durable equipment business key.',
  store_sk              BIGINT COMMENT 'FK to store.store_sk (version-specific).',
  store_id              STRING NOT NULL COMMENT 'Durable store business key.',

  work_order_type       STRING NOT NULL COMMENT 'Type of maintenance. Allowed values: preventive, corrective, emergency, inspection.',
  priority              STRING NOT NULL COMMENT 'Work order priority. Allowed values: critical, high, medium, low.',
  work_order_status     STRING NOT NULL COMMENT 'Lifecycle status. Allowed values: open, in_progress, on_hold, completed, cancelled.',

  title                 STRING COMMENT 'Short summary of the work order.',
  description           STRING COMMENT 'Detailed description of the maintenance task.',
  failure_code          STRING COMMENT 'Standardized failure/reason code triggering the work order.',
  assigned_to           STRING COMMENT 'Technician or team assigned to the work order.',
  vendor_name           STRING COMMENT 'External maintenance vendor, if outsourced.',

  created_date          DATE NOT NULL COMMENT 'Date the work order was created (ISO 8601).',
  scheduled_date        DATE COMMENT 'Planned date for the maintenance work (ISO 8601).',
  started_date          DATE COMMENT 'Date work actually began (ISO 8601).',
  completed_date        DATE COMMENT 'Date the work order was completed (ISO 8601).',

  estimated_duration_hours DECIMAL(6,1) COMMENT 'Estimated labor hours for the task.',
  actual_duration_hours    DECIMAL(6,1) COMMENT 'Actual labor hours spent.',
  estimated_cost        DECIMAL(12,2) COMMENT 'Estimated total cost (parts + labor) in base currency.',
  actual_cost           DECIMAL(12,2) COMMENT 'Actual total cost (parts + labor) in base currency.',

  currency_code         STRING NOT NULL COMMENT 'Reporting/base currency for cost columns, ISO 4217 alpha-3.',

  downtime_hours        DECIMAL(8,2) COMMENT 'Equipment downtime caused by this maintenance event, in hours.',
  root_cause            STRING COMMENT 'Root cause analysis notes after completion.',

  -- Audit / provenance
  record_source         STRING    COMMENT 'Originating system (CMMS, EAM, or manual entry).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_work_order PRIMARY KEY (work_order_sk)
)
USING DELTA
CLUSTER BY (equipment_id, created_date)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Maintenance work order header for in-store equipment. Tracks preventive, corrective, and emergency maintenance lifecycle.';

ALTER TABLE ${catalog}.${predops_schema}.work_order SET TAGS ('dbx_data_type' = 'transactional');
ALTER TABLE ${catalog}.${predops_schema}.work_order ALTER COLUMN assigned_to SET TAGS ('dbx_pii_name' = 'true');

ALTER TABLE ${catalog}.${predops_schema}.work_order ADD CONSTRAINT chk_wo_type CHECK (work_order_type IN ('preventive', 'corrective', 'emergency', 'inspection'));
ALTER TABLE ${catalog}.${predops_schema}.work_order ADD CONSTRAINT chk_wo_priority CHECK (priority IN ('critical', 'high', 'medium', 'low'));
ALTER TABLE ${catalog}.${predops_schema}.work_order ADD CONSTRAINT chk_wo_status CHECK (work_order_status IN ('open', 'in_progress', 'on_hold', 'completed', 'cancelled'));
