-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · Workforce Optimization
-- Table: workforce_optimization_run
-- Layer: outcome package (extension table / transactional fact)
-- Version: 0.5
-- Generated: 2026-08-10
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-10
-- ============================================================
-- Run-level metrics and diagnostics for a forecast + schedule
-- optimization execution. Failures must not publish partial curated
-- outputs as successful — record optimization_status explicitly.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${predops_schema}.workforce_optimization_run (
  workforce_optimization_run_sk BIGINT GENERATED ALWAYS AS IDENTITY
                                  COMMENT 'Surrogate key.',
  workforce_optimization_run_id STRING NOT NULL COMMENT 'Durable run business key (UUID or deterministic stamp).',

  forecast_horizon_days INT NOT NULL COMMENT 'Forward horizon in days.',
  interval_minutes      INT NOT NULL COMMENT 'Planning interval length in minutes.',
  forecast_method       STRING NOT NULL
                          COMMENT 'Forecast method used. Allowed values: seasonal_rolling_avg, hierarchical_fallback, model, manual.',
  optimizer_method      STRING NOT NULL
                          COMMENT 'Scheduler method. Allowed values: greedy_heuristic, ortools, pulp, other.',

  input_employee_count  INT COMMENT 'Employees considered.',
  input_demand_intervals INT COMMENT 'Demand intervals considered.',
  rejected_quality_count INT COMMENT 'Input rows rejected by quality checks.',
  forecast_line_count   INT COMMENT 'Forecast lines produced.',
  requirement_line_count INT COMMENT 'Labor requirement lines produced.',
  recommended_shift_count INT COMMENT 'Recommended shifts produced.',
  exception_count       INT COMMENT 'Coverage exceptions produced.',

  scheduled_hours_total DECIMAL(18,2) COMMENT 'Total recommended scheduled hours.',
  required_hours_total  DECIMAL(18,2) COMMENT 'Total required labor hours.',
  coverage_pct          DOUBLE COMMENT 'scheduled_hours_total / required_hours_total (0-1+).',
  unfilled_demand_hours DECIMAL(18,2) COMMENT 'Hours of unmet demand.',
  estimated_labor_cost  DECIMAL(18,2) COMMENT 'Estimated labor cost of recommendations.',
  currency_code         STRING COMMENT 'ISO 4217 for estimated_labor_cost.',
  fairness_score        DOUBLE COMMENT 'Workload balance proxy (e.g. 1 - CV of assigned hours); higher is fairer.',

  forecast_mape         DOUBLE COMMENT 'MAPE vs actuals when available; NULL otherwise.',
  forecast_bias         DOUBLE COMMENT 'Mean forecast error when actuals available; NULL otherwise.',

  optimization_status   STRING NOT NULL
                          COMMENT 'Run status. Allowed values: success, success_partial, infeasible, failed.',
  diagnostics_json      STRING COMMENT 'Structured diagnostics (JSON string) for debugging.',
  data_version          STRING COMMENT 'Input data version / watermark label.',
  run_started_ts        TIMESTAMP NOT NULL COMMENT 'Run start (UTC, ISO 8601).',
  run_completed_ts      TIMESTAMP COMMENT 'Run completion (UTC, ISO 8601).',
  stage_durations_json  STRING COMMENT 'Per-stage durations in seconds (JSON string).',

  record_source         STRING COMMENT 'Originating pipeline or system.',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_workforce_optimization_run PRIMARY KEY (workforce_optimization_run_sk)
)
USING DELTA
CLUSTER BY (workforce_optimization_run_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Run-level metrics for Workforce Optimization forecast and schedule executions.';

ALTER TABLE ${catalog}.${predops_schema}.workforce_optimization_run SET TAGS ('dbx_data_type' = 'transactional');

ALTER TABLE ${catalog}.${predops_schema}.workforce_optimization_run ADD CONSTRAINT chk_wor_forecast_method CHECK (forecast_method IN ('seasonal_rolling_avg', 'hierarchical_fallback', 'model', 'manual'));
ALTER TABLE ${catalog}.${predops_schema}.workforce_optimization_run ADD CONSTRAINT chk_wor_opt_method CHECK (optimizer_method IN ('greedy_heuristic', 'ortools', 'pulp', 'other'));
ALTER TABLE ${catalog}.${predops_schema}.workforce_optimization_run ADD CONSTRAINT chk_wor_status CHECK (optimization_status IN ('success', 'success_partial', 'infeasible', 'failed'));
ALTER TABLE ${catalog}.${predops_schema}.workforce_optimization_run ADD CONSTRAINT chk_wor_horizon CHECK (forecast_horizon_days > 0 AND interval_minutes > 0);
