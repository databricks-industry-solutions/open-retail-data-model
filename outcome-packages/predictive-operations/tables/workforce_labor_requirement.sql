-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · Workforce Optimization
-- Table: workforce_labor_requirement
-- Layer: outcome package (extension table / transactional fact)
-- Version: 0.5
-- Generated: 2026-08-10
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-10
-- ============================================================
-- Required labor hours and headcount derived from forecasted drivers
-- and labor_standard rules, with an explanation of why the requirement
-- was generated.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${predops_schema}.workforce_labor_requirement (
  workforce_labor_requirement_sk BIGINT GENERATED ALWAYS AS IDENTITY
                                   COMMENT 'Surrogate key.',
  workforce_labor_requirement_id STRING NOT NULL
                                   COMMENT 'Durable business key for the requirement line.',

  workforce_optimization_run_id STRING COMMENT 'Link to workforce_optimization_run.workforce_optimization_run_id.',
  store_sk              BIGINT COMMENT 'FK to store.store_sk.',
  store_id              STRING NOT NULL COMMENT 'Durable store business key.',
  business_date         DATE NOT NULL COMMENT 'Local business date (ISO 8601).',
  interval_start_ts     TIMESTAMP NOT NULL COMMENT 'Inclusive interval start (UTC).',
  interval_end_ts       TIMESTAMP NOT NULL COMMENT 'Exclusive interval end (UTC).',
  interval_minutes      INT NOT NULL COMMENT 'Interval length in minutes.',
  department_or_zone    STRING NOT NULL COMMENT 'Department or zone.',
  role_code             STRING NOT NULL
                          COMMENT 'Role. Allowed values: cashier, sales_associate, fulfillment, inventory, supervisor.',

  demand_driver         STRING NOT NULL COMMENT 'Driver applied. Allowed values: transaction_count, foot_traffic, pickup_orders, receiving_units, store_open_coverage, minimum_coverage.',
  forecast_driver_units DECIMAL(18,4) NOT NULL COMMENT 'Forecasted workload units.',
  labor_standard_id     STRING NOT NULL COMMENT 'labor_standard.labor_standard_id applied.',
  labor_standard_version STRING NOT NULL COMMENT 'labor_standard.standard_version applied.',
  applied_labor_standard DECIMAL(18,6) NOT NULL COMMENT 'Hours per driver unit (or equivalent) used.',
  required_labor_hours  DECIMAL(18,4) NOT NULL COMMENT 'Required labor hours for the interval.',
  required_headcount    DECIMAL(18,4) NOT NULL COMMENT 'Required headcount (hours / interval length in hours), ceil-ready.',
  minimum_headcount     INT NOT NULL COMMENT 'Minimum coverage headcount from the standard.',
  coverage_rationale    STRING NOT NULL COMMENT 'Explanation of why this requirement was generated.',

  record_source         STRING COMMENT 'Originating pipeline or system.',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_workforce_labor_requirement PRIMARY KEY (workforce_labor_requirement_sk)
)
USING DELTA
CLUSTER BY (store_id, business_date)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Required labor hours/headcount from forecast drivers and versioned labor standards.';

ALTER TABLE ${catalog}.${predops_schema}.workforce_labor_requirement SET TAGS ('dbx_data_type' = 'transactional');

ALTER TABLE ${catalog}.${predops_schema}.workforce_labor_requirement ADD CONSTRAINT chk_wlr_role CHECK (role_code IN ('cashier', 'sales_associate', 'fulfillment', 'inventory', 'supervisor'));
ALTER TABLE ${catalog}.${predops_schema}.workforce_labor_requirement ADD CONSTRAINT chk_wlr_driver CHECK (demand_driver IN ('transaction_count', 'foot_traffic', 'pickup_orders', 'receiving_units', 'store_open_coverage', 'minimum_coverage'));
ALTER TABLE ${catalog}.${predops_schema}.workforce_labor_requirement ADD CONSTRAINT chk_wlr_interval CHECK (interval_end_ts > interval_start_ts AND interval_minutes > 0);
ALTER TABLE ${catalog}.${predops_schema}.workforce_labor_requirement ADD CONSTRAINT chk_wlr_hours CHECK (required_labor_hours >= 0 AND required_headcount >= 0 AND minimum_headcount >= 0 AND forecast_driver_units >= 0 AND applied_labor_standard > 0);
