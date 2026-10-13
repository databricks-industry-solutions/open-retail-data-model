-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · relationships (all use cases)
-- File: relationships.sql
-- Version: 0.5
-- Generated: 2026-07-15
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-10
-- ============================================================
-- Cross-schema relationships for the package's extension tables (equipment
-- maintenance + store performance + Workforce Optimization / ADR 0043). UC
-- foreign keys are informational (NOT ENFORCED). Run AFTER the canonical-core
-- equipment, store, and labor domains exist.
-- ============================================================

-- work_order -> equipment (canonical core)
ALTER TABLE ${catalog}.${predops_schema}.work_order
  ADD CONSTRAINT fk_wo_equipment
  FOREIGN KEY (equipment_sk) REFERENCES ${catalog}.${equipment_schema}.equipment (equipment_sk);

-- work_order -> store (canonical core)
ALTER TABLE ${catalog}.${predops_schema}.work_order
  ADD CONSTRAINT fk_wo_store
  FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);

-- work_order_line -> work_order
ALTER TABLE ${catalog}.${predops_schema}.work_order_line
  ADD CONSTRAINT fk_wol_work_order
  FOREIGN KEY (work_order_sk) REFERENCES ${catalog}.${predops_schema}.work_order (work_order_sk);

-- maintenance_schedule -> equipment (canonical core)
ALTER TABLE ${catalog}.${predops_schema}.maintenance_schedule
  ADD CONSTRAINT fk_ms_equipment
  FOREIGN KEY (equipment_sk) REFERENCES ${catalog}.${equipment_schema}.equipment (equipment_sk);

-- store_risk_score -> store (canonical core) · Store Performance use case (ADR 0028)
ALTER TABLE ${catalog}.${predops_schema}.store_risk_score
  ADD CONSTRAINT fk_srs_store
  FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);

-- Workforce Optimization (ADR 0043) -> store (canonical core)
ALTER TABLE ${catalog}.${predops_schema}.workforce_demand_forecast
  ADD CONSTRAINT fk_wdf_store
  FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);

ALTER TABLE ${catalog}.${predops_schema}.workforce_labor_requirement
  ADD CONSTRAINT fk_wlr_store
  FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);

ALTER TABLE ${catalog}.${predops_schema}.workforce_schedule_recommendation
  ADD CONSTRAINT fk_wsr_store
  FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);

ALTER TABLE ${catalog}.${predops_schema}.workforce_coverage_exception
  ADD CONSTRAINT fk_wce_store
  FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);

-- workforce_schedule_recommendation -> labor.employee (informational; sk may be NULL)
ALTER TABLE ${catalog}.${predops_schema}.workforce_schedule_recommendation
  ADD CONSTRAINT fk_wsr_employee
  FOREIGN KEY (employee_sk) REFERENCES ${catalog}.${labor_schema}.employee (employee_sk);

-- ENFORCED Delta CHECK constraints
ALTER TABLE ${catalog}.${predops_schema}.work_order
  ADD CONSTRAINT chk_wo_duration
  CHECK (estimated_duration_hours IS NULL OR estimated_duration_hours >= 0);

ALTER TABLE ${catalog}.${predops_schema}.work_order
  ADD CONSTRAINT chk_wo_actual_duration
  CHECK (actual_duration_hours IS NULL OR actual_duration_hours >= 0);

ALTER TABLE ${catalog}.${predops_schema}.work_order
  ADD CONSTRAINT chk_wo_cost
  CHECK (estimated_cost IS NULL OR estimated_cost >= 0);

ALTER TABLE ${catalog}.${predops_schema}.work_order
  ADD CONSTRAINT chk_wo_actual_cost
  CHECK (actual_cost IS NULL OR actual_cost >= 0);

ALTER TABLE ${catalog}.${predops_schema}.work_order
  ADD CONSTRAINT chk_wo_downtime
  CHECK (downtime_hours IS NULL OR downtime_hours >= 0);

ALTER TABLE ${catalog}.${predops_schema}.work_order_line
  ADD CONSTRAINT chk_wol_quantity
  CHECK (quantity IS NULL OR quantity >= 0);

ALTER TABLE ${catalog}.${predops_schema}.work_order_line
  ADD CONSTRAINT chk_wol_cost
  CHECK (unit_cost IS NULL OR unit_cost >= 0);
