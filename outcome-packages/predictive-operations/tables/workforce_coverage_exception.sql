-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · Workforce Optimization
-- Table: workforce_coverage_exception
-- Layer: outcome package (extension table / transactional fact)
-- Version: 0.5
-- Generated: 2026-08-10
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-10
-- ============================================================
-- Unfilled demand / understaffing exceptions. Never silently drop
-- uncovered demand — emit an exception with severity and action.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${predops_schema}.workforce_coverage_exception (
  workforce_coverage_exception_sk BIGINT GENERATED ALWAYS AS IDENTITY
                                    COMMENT 'Surrogate key.',
  workforce_coverage_exception_id STRING NOT NULL
                                    COMMENT 'Durable business key for the exception.',

  workforce_optimization_run_id STRING NOT NULL COMMENT 'workforce_optimization_run.workforce_optimization_run_id.',
  store_sk              BIGINT COMMENT 'FK to store.store_sk.',
  store_id              STRING NOT NULL COMMENT 'Durable store business key.',
  business_date         DATE NOT NULL COMMENT 'Local business date (ISO 8601).',
  interval_start_ts     TIMESTAMP NOT NULL COMMENT 'Inclusive understaffed interval start (UTC).',
  interval_end_ts       TIMESTAMP NOT NULL COMMENT 'Exclusive understaffed interval end (UTC).',
  department_or_zone    STRING NOT NULL COMMENT 'Department or zone.',
  role_code             STRING NOT NULL
                          COMMENT 'Role. Allowed values: cashier, sales_associate, fulfillment, inventory, supervisor.',

  required_headcount    DECIMAL(18,4) NOT NULL COMMENT 'Required headcount for the interval.',
  scheduled_headcount   DECIMAL(18,4) NOT NULL COMMENT 'Scheduled / recommended headcount for the interval.',
  shortfall_headcount   DECIMAL(18,4) NOT NULL COMMENT 'required - scheduled (positive when understaffed).',
  severity              STRING NOT NULL
                          COMMENT 'Severity. Allowed values: low, medium, high, critical.',
  exception_explanation STRING NOT NULL COMMENT 'Why coverage could not be met.',
  suggested_action      STRING NOT NULL
                          COMMENT 'Suggested action. Allowed values: call_in, transfer, shorten_interval_service, overtime, accept_risk, hire_temp.',

  record_source         STRING COMMENT 'Originating pipeline or system.',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_workforce_coverage_exception PRIMARY KEY (workforce_coverage_exception_sk)
)
USING DELTA
CLUSTER BY (store_id, business_date)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Unfilled workforce demand exceptions with severity and suggested operational action.';

ALTER TABLE ${catalog}.${predops_schema}.workforce_coverage_exception SET TAGS ('dbx_data_type' = 'transactional');

ALTER TABLE ${catalog}.${predops_schema}.workforce_coverage_exception ADD CONSTRAINT chk_wce_role CHECK (role_code IN ('cashier', 'sales_associate', 'fulfillment', 'inventory', 'supervisor'));
ALTER TABLE ${catalog}.${predops_schema}.workforce_coverage_exception ADD CONSTRAINT chk_wce_severity CHECK (severity IN ('low', 'medium', 'high', 'critical'));
ALTER TABLE ${catalog}.${predops_schema}.workforce_coverage_exception ADD CONSTRAINT chk_wce_action CHECK (suggested_action IN ('call_in', 'transfer', 'shorten_interval_service', 'overtime', 'accept_risk', 'hire_temp'));
ALTER TABLE ${catalog}.${predops_schema}.workforce_coverage_exception ADD CONSTRAINT chk_wce_interval CHECK (interval_end_ts > interval_start_ts);
ALTER TABLE ${catalog}.${predops_schema}.workforce_coverage_exception ADD CONSTRAINT chk_wce_counts CHECK (required_headcount >= 0 AND scheduled_headcount >= 0 AND shortfall_headcount >= 0);
