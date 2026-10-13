-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · Workforce Optimization
-- Table: workforce_schedule_recommendation
-- Layer: outcome package (extension table / transactional fact)
-- Version: 0.5
-- Generated: 2026-08-10
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-10
-- ============================================================
-- Recommended shifts from the scheduling engine. Deterministic for
-- identical inputs. Does not claim jurisdictional labor-law compliance.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${predops_schema}.workforce_schedule_recommendation (
  workforce_schedule_recommendation_sk BIGINT GENERATED ALWAYS AS IDENTITY
                                         COMMENT 'Surrogate key.',
  workforce_schedule_recommendation_id STRING NOT NULL
                                         COMMENT 'Durable recommendation / shift ID.',

  workforce_optimization_run_id STRING NOT NULL COMMENT 'workforce_optimization_run.workforce_optimization_run_id that produced this row.',
  employee_sk           BIGINT COMMENT 'FK to employee.employee_sk.',
  employee_id           STRING NOT NULL COMMENT 'Durable pseudonymous employee business key.',
  store_sk              BIGINT COMMENT 'FK to store.store_sk.',
  store_id              STRING NOT NULL COMMENT 'Durable store business key.',
  department_or_zone    STRING NOT NULL COMMENT 'Department or zone.',
  role_code             STRING NOT NULL
                          COMMENT 'Role. Allowed values: cashier, sales_associate, fulfillment, inventory, supervisor.',

  shift_start_ts        TIMESTAMP NOT NULL COMMENT 'Inclusive recommended shift start (UTC).',
  shift_end_ts          TIMESTAMP NOT NULL COMMENT 'Exclusive recommended shift end (UTC).',
  assigned_hours        DECIMAL(8,2) NOT NULL COMMENT 'Assigned hours (non-negative).',
  estimated_labor_cost  DECIMAL(18,2) COMMENT 'assigned_hours * hourly_labor_cost in base currency.',
  currency_code         STRING COMMENT 'ISO 4217 for estimated_labor_cost.',

  is_availability_ok    BOOLEAN NOT NULL COMMENT 'TRUE if assignment falls inside availability.',
  is_skill_ok           BOOLEAN NOT NULL COMMENT 'TRUE if employee has required skill/role.',
  is_store_eligible_ok  BOOLEAN NOT NULL COMMENT 'TRUE if employee is eligible for the store.',
  is_hours_cap_ok       BOOLEAN NOT NULL COMMENT 'TRUE if daily/weekly caps respected.',
  is_min_rest_ok        BOOLEAN NOT NULL COMMENT 'TRUE if minimum rest respected.',
  recommendation_status STRING NOT NULL
                          COMMENT 'Status. Allowed values: proposed, accepted, rejected, superseded.',
  optimizer_status      STRING NOT NULL
                          COMMENT 'Optimizer outcome for this assignment. Allowed values: optimal, feasible, heuristic, infeasible_partial.',

  record_source         STRING COMMENT 'Originating pipeline or system.',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_workforce_schedule_recommendation PRIMARY KEY (workforce_schedule_recommendation_sk)
)
USING DELTA
CLUSTER BY (store_id, shift_start_ts)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Recommended associate shifts from the Workforce Optimization scheduler.';

ALTER TABLE ${catalog}.${predops_schema}.workforce_schedule_recommendation SET TAGS ('dbx_data_type' = 'transactional');
ALTER TABLE ${catalog}.${predops_schema}.workforce_schedule_recommendation ALTER COLUMN employee_id SET TAGS ('dbx_pii_identifier' = 'true');

ALTER TABLE ${catalog}.${predops_schema}.workforce_schedule_recommendation ADD CONSTRAINT chk_wsr_role CHECK (role_code IN ('cashier', 'sales_associate', 'fulfillment', 'inventory', 'supervisor'));
ALTER TABLE ${catalog}.${predops_schema}.workforce_schedule_recommendation ADD CONSTRAINT chk_wsr_status CHECK (recommendation_status IN ('proposed', 'accepted', 'rejected', 'superseded'));
ALTER TABLE ${catalog}.${predops_schema}.workforce_schedule_recommendation ADD CONSTRAINT chk_wsr_opt CHECK (optimizer_status IN ('optimal', 'feasible', 'heuristic', 'infeasible_partial'));
ALTER TABLE ${catalog}.${predops_schema}.workforce_schedule_recommendation ADD CONSTRAINT chk_wsr_order CHECK (shift_end_ts > shift_start_ts);
ALTER TABLE ${catalog}.${predops_schema}.workforce_schedule_recommendation ADD CONSTRAINT chk_wsr_hours CHECK (assigned_hours >= 0);
ALTER TABLE ${catalog}.${predops_schema}.workforce_schedule_recommendation ADD CONSTRAINT chk_wsr_cost CHECK (estimated_labor_cost IS NULL OR estimated_labor_cost >= 0);
