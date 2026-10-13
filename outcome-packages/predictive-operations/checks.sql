-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · data-quality checks (all use cases)
-- Version: 0.5 · Generated: 2026-07-15 · LLM-generated: true · Reviewed: 2026-08-10
-- Each assertion SELECTs violating rows; 0 rows = PASS. `metric` checks report
-- a value and never fail the run.
-- ============================================================

-- ========== work_order ==========

-- check: wo_pk_unique | severity: error
SELECT work_order_sk
FROM ${catalog}.${predops_schema}.work_order
GROUP BY work_order_sk
HAVING COUNT(*) > 1;

-- check: wo_equipment_fk_orphan | severity: error
SELECT wo.* FROM ${catalog}.${predops_schema}.work_order wo
LEFT JOIN ${catalog}.${equipment_schema}.equipment eq ON wo.equipment_sk = eq.equipment_sk
WHERE eq.equipment_sk IS NULL AND wo.equipment_sk IS NOT NULL;

-- check: wo_store_fk_orphan | severity: error
SELECT wo.* FROM ${catalog}.${predops_schema}.work_order wo
LEFT JOIN ${catalog}.${store_schema}.store st ON wo.store_sk = st.store_sk
WHERE st.store_sk IS NULL AND wo.store_sk IS NOT NULL;

-- check: wo_completed_has_date | severity: error
SELECT * FROM ${catalog}.${predops_schema}.work_order
WHERE work_order_status = 'completed' AND completed_date IS NULL;

-- check: wo_completed_after_created | severity: error
SELECT * FROM ${catalog}.${predops_schema}.work_order
WHERE completed_date IS NOT NULL AND completed_date < created_date;

-- check: wo_cost_nonnegative | severity: error
SELECT * FROM ${catalog}.${predops_schema}.work_order
WHERE actual_cost IS NOT NULL AND actual_cost < 0;

-- check: wo_downtime_nonnegative | severity: error
SELECT * FROM ${catalog}.${predops_schema}.work_order
WHERE downtime_hours IS NOT NULL AND downtime_hours < 0;

-- check: wo_single_currency | severity: error
SELECT 'work_order' AS table_name, COUNT(DISTINCT currency_code) AS currencies
FROM ${catalog}.${predops_schema}.work_order
HAVING COUNT(DISTINCT currency_code) > 1 OR COUNT(CASE WHEN currency_code IS NULL THEN 1 END) > 0;

-- check: wo_store_equipment_mismatch | severity: warn
SELECT wo.work_order_id, wo.store_sk AS wo_store_sk, eq.store_sk AS eq_store_sk
FROM ${catalog}.${predops_schema}.work_order wo
JOIN ${catalog}.${equipment_schema}.equipment eq
  ON eq.equipment_sk = wo.equipment_sk
WHERE wo.store_sk != eq.store_sk;

-- check: wo_rowcount | severity: metric
SELECT COUNT(*) AS work_order_rows FROM ${catalog}.${predops_schema}.work_order;

-- check: wo_status_distribution | severity: metric
SELECT work_order_status, COUNT(*) AS status_count
FROM ${catalog}.${predops_schema}.work_order
GROUP BY work_order_status;

-- check: wo_type_distribution | severity: metric
SELECT work_order_type, COUNT(*) AS type_count
FROM ${catalog}.${predops_schema}.work_order
GROUP BY work_order_type;

-- check: wo_open_count | severity: metric
SELECT COUNT(*) AS open_work_orders
FROM ${catalog}.${predops_schema}.work_order
WHERE work_order_status IN ('open', 'in_progress');

-- ========== work_order_line ==========

-- check: wol_pk_unique | severity: error
SELECT work_order_line_sk
FROM ${catalog}.${predops_schema}.work_order_line
GROUP BY work_order_line_sk
HAVING COUNT(*) > 1;

-- check: wol_wo_fk_orphan | severity: error
SELECT wol.* FROM ${catalog}.${predops_schema}.work_order_line wol
LEFT JOIN ${catalog}.${predops_schema}.work_order wo ON wol.work_order_sk = wo.work_order_sk
WHERE wo.work_order_sk IS NULL AND wol.work_order_sk IS NOT NULL;

-- check: wol_rowcount | severity: metric
SELECT COUNT(*) AS work_order_line_rows FROM ${catalog}.${predops_schema}.work_order_line;

-- check: wol_type_distribution | severity: metric
SELECT line_type, COUNT(*) AS line_count
FROM ${catalog}.${predops_schema}.work_order_line
GROUP BY line_type;

-- check: wol_single_currency | severity: error
SELECT 'work_order_line' AS table_name, COUNT(DISTINCT currency_code) AS currencies
FROM ${catalog}.${predops_schema}.work_order_line
HAVING COUNT(DISTINCT currency_code) > 1 OR COUNT(CASE WHEN currency_code IS NULL THEN 1 END) > 0;

-- check: wol_wo_currency_match | severity: error
SELECT wol.work_order_line_id, wol.currency_code AS line_currency, wo.currency_code AS wo_currency
FROM ${catalog}.${predops_schema}.work_order_line wol
JOIN ${catalog}.${predops_schema}.work_order wo ON wol.work_order_sk = wo.work_order_sk
WHERE wol.currency_code != wo.currency_code;

-- ========== maintenance_schedule ==========

-- check: ms_pk_unique | severity: error
SELECT maintenance_schedule_sk
FROM ${catalog}.${predops_schema}.maintenance_schedule
GROUP BY maintenance_schedule_sk
HAVING COUNT(*) > 1;

-- check: ms_scd2_current_open | severity: error
SELECT * FROM ${catalog}.${predops_schema}.maintenance_schedule
WHERE is_current = TRUE AND effective_to_date IS NOT NULL;

-- check: ms_scd2_noncurrent_closed | severity: error
SELECT * FROM ${catalog}.${predops_schema}.maintenance_schedule
WHERE is_current = FALSE AND effective_to_date IS NULL;

-- check: ms_scd2_start_before_end | severity: error
SELECT * FROM ${catalog}.${predops_schema}.maintenance_schedule
WHERE effective_to_date IS NOT NULL AND effective_from_date > effective_to_date;

-- check: ms_equipment_fk_orphan | severity: error
SELECT ms.* FROM ${catalog}.${predops_schema}.maintenance_schedule ms
LEFT JOIN ${catalog}.${equipment_schema}.equipment eq ON ms.equipment_sk = eq.equipment_sk
WHERE eq.equipment_sk IS NULL AND ms.equipment_sk IS NOT NULL;

-- check: ms_single_currency | severity: error
SELECT 'maintenance_schedule' AS table_name, COUNT(DISTINCT currency_code) AS currencies
FROM ${catalog}.${predops_schema}.maintenance_schedule
HAVING COUNT(DISTINCT currency_code) > 1 OR COUNT(CASE WHEN currency_code IS NULL THEN 1 END) > 0;

-- check: ms_interval_positive | severity: error
SELECT * FROM ${catalog}.${predops_schema}.maintenance_schedule
WHERE interval_days <= 0;

-- check: ms_rowcount | severity: metric
SELECT COUNT(*) AS schedule_rows FROM ${catalog}.${predops_schema}.maintenance_schedule;

-- check: ms_overdue_count | severity: metric
SELECT COUNT(*) AS overdue_schedules
FROM ${catalog}.${predops_schema}.maintenance_schedule
WHERE is_active = TRUE AND next_due_date < CURRENT_DATE();

-- ========== gold_equipment_health ==========

-- check: health_score_range | severity: error
SELECT * FROM ${catalog}.${predops_schema}.gold_equipment_health
WHERE health_score NOT BETWEEN 0 AND 100;

-- check: health_tier_domain | severity: error
SELECT * FROM ${catalog}.${predops_schema}.gold_equipment_health
WHERE health_tier NOT IN ('healthy', 'at_risk', 'degraded', 'failed');

-- check: health_rowcount | severity: metric
SELECT COUNT(*) AS health_rows FROM ${catalog}.${predops_schema}.gold_equipment_health;

-- check: health_at_risk_count | severity: metric
SELECT COUNT(*) AS at_risk_or_worse
FROM ${catalog}.${predops_schema}.gold_equipment_health
WHERE health_tier IN ('at_risk', 'degraded', 'failed');

-- ========== gold_maintenance_effectiveness ==========

-- check: effectiveness_rowcount | severity: metric
SELECT COUNT(*) AS effectiveness_rows FROM ${catalog}.${predops_schema}.gold_maintenance_effectiveness;

-- check: effectiveness_avg_mtbf | severity: metric
SELECT ROUND(AVG(mtbf_days), 1) AS avg_mtbf_days
FROM ${catalog}.${predops_schema}.gold_maintenance_effectiveness
WHERE mtbf_days IS NOT NULL;

-- ========== store_risk_score (Store Performance use case) ==========

-- check: srs_pk_unique | severity: error
SELECT store_risk_score_sk
FROM ${catalog}.${predops_schema}.store_risk_score
GROUP BY store_risk_score_sk
HAVING COUNT(*) > 1;

-- check: srs_grain_unique | severity: error
-- Grain is store x as_of_date x score_method; a duplicate is a double-write.
SELECT store_id, as_of_date, score_method
FROM ${catalog}.${predops_schema}.store_risk_score
GROUP BY store_id, as_of_date, score_method
HAVING COUNT(*) > 1;

-- check: srs_store_fk_orphan | severity: error
SELECT srs.* FROM ${catalog}.${predops_schema}.store_risk_score srs
LEFT JOIN ${catalog}.${store_schema}.store st ON srs.store_sk = st.store_sk
WHERE st.store_sk IS NULL AND srs.store_sk IS NOT NULL;

-- check: srs_score_range | severity: error
SELECT * FROM ${catalog}.${predops_schema}.store_risk_score
WHERE operational_risk_score IS NOT NULL AND operational_risk_score NOT BETWEEN 0 AND 100;

-- check: srs_tier_domain | severity: error
SELECT * FROM ${catalog}.${predops_schema}.store_risk_score
WHERE operational_risk_tier NOT IN ('UNKNOWN', 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL');

-- check: srs_method_domain | severity: error
SELECT * FROM ${catalog}.${predops_schema}.store_risk_score
WHERE score_method NOT IN ('heuristic', 'model');

-- check: srs_subscore_range | severity: error
-- Every present sub-score must be 0-100.
SELECT * FROM ${catalog}.${predops_schema}.store_risk_score
WHERE (inventory_risk    IS NOT NULL AND inventory_risk    NOT BETWEEN 0 AND 100)
   OR (supply_chain_risk IS NOT NULL AND supply_chain_risk NOT BETWEEN 0 AND 100)
   OR (sales_margin_risk IS NOT NULL AND sales_margin_risk NOT BETWEEN 0 AND 100)
   OR (equipment_risk    IS NOT NULL AND equipment_risk    NOT BETWEEN 0 AND 100)
   OR (labor_risk        IS NOT NULL AND labor_risk        NOT BETWEEN 0 AND 100)
   OR (cx_risk           IS NOT NULL AND cx_risk           NOT BETWEEN 0 AND 100);

-- check: srs_deferred_subscores_null | severity: error
-- ADR 0043: labor_risk is live; only cx_risk remains deferred and must be NULL.
SELECT * FROM ${catalog}.${predops_schema}.store_risk_score
WHERE cx_risk IS NOT NULL;

-- check: srs_impact_currency_paired | severity: error
-- A predicted impact amount requires a currency, and vice versa.
SELECT * FROM ${catalog}.${predops_schema}.store_risk_score
WHERE (predicted_impact_amount IS NULL) != (currency_code IS NULL);

-- check: srs_impact_single_currency | severity: error
SELECT 'store_risk_score' AS table_name, COUNT(DISTINCT currency_code) AS currencies
FROM ${catalog}.${predops_schema}.store_risk_score
WHERE currency_code IS NOT NULL
HAVING COUNT(DISTINCT currency_code) > 1;

-- check: srs_horizon_positive | severity: error
SELECT * FROM ${catalog}.${predops_schema}.store_risk_score
WHERE horizon_days <= 0;

-- check: srs_rowcount | severity: metric
SELECT COUNT(*) AS store_risk_score_rows FROM ${catalog}.${predops_schema}.store_risk_score;

-- check: srs_tier_distribution | severity: metric
SELECT operational_risk_tier, COUNT(*) AS tier_count
FROM ${catalog}.${predops_schema}.store_risk_score
GROUP BY operational_risk_tier;

-- ========== gold_store_operational_risk ==========

-- check: sor_score_range | severity: error
SELECT * FROM ${catalog}.${predops_schema}.gold_store_operational_risk
WHERE operational_risk_score IS NOT NULL AND operational_risk_score NOT BETWEEN 0 AND 100;

-- check: sor_tier_domain | severity: error
SELECT * FROM ${catalog}.${predops_schema}.gold_store_operational_risk
WHERE operational_risk_tier NOT IN ('UNKNOWN', 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL');

-- check: sor_rowcount | severity: metric
SELECT COUNT(*) AS store_operational_risk_rows FROM ${catalog}.${predops_schema}.gold_store_operational_risk;

-- check: sor_high_or_worse_count | severity: metric
SELECT COUNT(*) AS high_or_worse_stores
FROM ${catalog}.${predops_schema}.gold_store_operational_risk
WHERE operational_risk_tier IN ('HIGH', 'CRITICAL');

-- ========== labor_standard (Workforce Optimization · ADR 0043) ==========

-- check: ls_keys_not_null | severity: error
SELECT * FROM ${catalog}.${predops_schema}.labor_standard
WHERE labor_standard_sk IS NULL OR labor_standard_id IS NULL
   OR standard_version IS NULL OR role_code IS NULL OR demand_driver IS NULL
   OR interval_minutes IS NULL OR driver_units_per_labor_hour IS NULL
   OR minimum_headcount IS NULL OR coverage_rationale IS NULL
   OR is_active IS NULL OR effective_from_date IS NULL OR is_current IS NULL;

-- check: ls_pk_unique | severity: error
SELECT labor_standard_sk
FROM ${catalog}.${predops_schema}.labor_standard
GROUP BY labor_standard_sk
HAVING COUNT(*) > 1;

-- check: ls_id_unique | severity: error
SELECT labor_standard_id, COUNT(*) AS n
FROM ${catalog}.${predops_schema}.labor_standard
WHERE is_current = TRUE
GROUP BY labor_standard_id
HAVING COUNT(*) > 1;

-- check: ls_active_key_unique | severity: error
-- gold_workforce_labor_requirement INNER JOINs the demand forecast to the ACTIVE
-- standards on (role_code, demand_driver, department_or_zone). ls_id_unique only
-- constrains labor_standard_id, so nothing yet stops TWO concurrently-active
-- standards sharing one join key -- which would fan the requirement out past its
-- declared store x date x interval x zone x role grain and inflate the SUMs feeding
-- gold_labor_risk and, through it, gold_store_operational_risk.labor_risk. A NULL
-- zone means storewide (the view COALESCEs it), so it is normalized the same way here.
SELECT role_code,
       demand_driver,
       COALESCE(department_or_zone, 'storewide') AS department_or_zone,
       COUNT(*) AS n
FROM ${catalog}.${predops_schema}.labor_standard
WHERE is_current = TRUE AND is_active = TRUE
GROUP BY role_code, demand_driver, COALESCE(department_or_zone, 'storewide')
HAVING COUNT(*) > 1;

-- check: ls_role_domain | severity: error
SELECT * FROM ${catalog}.${predops_schema}.labor_standard
WHERE role_code NOT IN ('cashier', 'sales_associate', 'fulfillment', 'inventory', 'supervisor');

-- check: ls_driver_domain | severity: error
SELECT * FROM ${catalog}.${predops_schema}.labor_standard
WHERE demand_driver NOT IN (
  'transaction_count', 'foot_traffic', 'pickup_orders',
  'receiving_units', 'store_open_coverage', 'minimum_coverage'
);

-- check: ls_positive_standard | severity: error
SELECT * FROM ${catalog}.${predops_schema}.labor_standard
WHERE driver_units_per_labor_hour <= 0 OR interval_minutes <= 0 OR minimum_headcount < 0;

-- check: ls_scd2_current_open | severity: error
SELECT * FROM ${catalog}.${predops_schema}.labor_standard
WHERE is_current = TRUE AND effective_to_date IS NOT NULL;

-- check: ls_rowcount | severity: metric
SELECT COUNT(*) AS labor_standard_rows FROM ${catalog}.${predops_schema}.labor_standard;

-- ========== workforce_demand_forecast ==========

-- check: wdf_keys_not_null | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_demand_forecast
WHERE workforce_demand_forecast_sk IS NULL OR workforce_demand_forecast_id IS NULL
   OR store_id IS NULL OR business_date IS NULL
   OR interval_start_ts IS NULL OR interval_end_ts IS NULL
   OR interval_minutes IS NULL OR department_or_zone IS NULL
   OR role_code IS NULL OR demand_driver IS NULL
   OR forecast_driver_units IS NULL OR forecast_method IS NULL
   OR forecast_horizon_days IS NULL OR forecast_origin_ts IS NULL;

-- check: wdf_pk_unique | severity: error
SELECT workforce_demand_forecast_sk
FROM ${catalog}.${predops_schema}.workforce_demand_forecast
GROUP BY workforce_demand_forecast_sk
HAVING COUNT(*) > 1;

-- check: wdf_id_unique | severity: error
SELECT workforce_demand_forecast_id
FROM ${catalog}.${predops_schema}.workforce_demand_forecast
GROUP BY workforce_demand_forecast_id
HAVING COUNT(*) > 1;

-- check: wdf_store_fk_orphan | severity: error
SELECT t.* FROM ${catalog}.${predops_schema}.workforce_demand_forecast t
LEFT JOIN ${catalog}.${store_schema}.store st ON t.store_sk = st.store_sk
WHERE st.store_sk IS NULL AND t.store_sk IS NOT NULL;

-- check: wdf_run_fk_orphan | severity: error
SELECT t.* FROM ${catalog}.${predops_schema}.workforce_demand_forecast t
LEFT JOIN ${catalog}.${predops_schema}.workforce_optimization_run r
  ON t.workforce_optimization_run_id = r.workforce_optimization_run_id
WHERE r.workforce_optimization_run_id IS NULL AND t.workforce_optimization_run_id IS NOT NULL;

-- check: wdf_interval_order | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_demand_forecast
WHERE interval_end_ts <= interval_start_ts OR interval_minutes <= 0;

-- check: wdf_units_nonnegative | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_demand_forecast
WHERE forecast_driver_units < 0;

-- check: wdf_role_domain | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_demand_forecast
WHERE role_code NOT IN ('cashier', 'sales_associate', 'fulfillment', 'inventory', 'supervisor');

-- check: wdf_driver_domain | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_demand_forecast
WHERE demand_driver NOT IN (
  'transaction_count', 'foot_traffic', 'pickup_orders',
  'receiving_units', 'store_open_coverage', 'minimum_coverage'
);

-- check: wdf_method_domain | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_demand_forecast
WHERE forecast_method NOT IN ('seasonal_rolling_avg', 'hierarchical_fallback', 'model', 'manual');

-- check: wdf_rowcount | severity: metric
SELECT COUNT(*) AS workforce_demand_forecast_rows
FROM ${catalog}.${predops_schema}.workforce_demand_forecast;

-- ========== workforce_labor_requirement ==========

-- check: wlr_keys_not_null | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_labor_requirement
WHERE workforce_labor_requirement_sk IS NULL OR workforce_labor_requirement_id IS NULL
   OR store_id IS NULL OR business_date IS NULL
   OR interval_start_ts IS NULL OR interval_end_ts IS NULL
   OR interval_minutes IS NULL OR department_or_zone IS NULL
   OR role_code IS NULL OR demand_driver IS NULL
   OR forecast_driver_units IS NULL OR labor_standard_id IS NULL
   OR labor_standard_version IS NULL OR applied_labor_standard IS NULL
   OR required_labor_hours IS NULL OR required_headcount IS NULL
   OR minimum_headcount IS NULL OR coverage_rationale IS NULL;

-- check: wlr_pk_unique | severity: error
SELECT workforce_labor_requirement_sk
FROM ${catalog}.${predops_schema}.workforce_labor_requirement
GROUP BY workforce_labor_requirement_sk
HAVING COUNT(*) > 1;

-- check: wlr_id_unique | severity: error
SELECT workforce_labor_requirement_id
FROM ${catalog}.${predops_schema}.workforce_labor_requirement
GROUP BY workforce_labor_requirement_id
HAVING COUNT(*) > 1;

-- check: wlr_store_fk_orphan | severity: error
SELECT t.* FROM ${catalog}.${predops_schema}.workforce_labor_requirement t
LEFT JOIN ${catalog}.${store_schema}.store st ON t.store_sk = st.store_sk
WHERE st.store_sk IS NULL AND t.store_sk IS NOT NULL;

-- check: wlr_run_fk_orphan | severity: error
SELECT t.* FROM ${catalog}.${predops_schema}.workforce_labor_requirement t
LEFT JOIN ${catalog}.${predops_schema}.workforce_optimization_run r
  ON t.workforce_optimization_run_id = r.workforce_optimization_run_id
WHERE r.workforce_optimization_run_id IS NULL AND t.workforce_optimization_run_id IS NOT NULL;

-- check: wlr_labor_standard_fk_orphan | severity: error
SELECT t.* FROM ${catalog}.${predops_schema}.workforce_labor_requirement t
LEFT JOIN (
  SELECT DISTINCT labor_standard_id
  FROM ${catalog}.${predops_schema}.labor_standard
) ls ON t.labor_standard_id = ls.labor_standard_id
WHERE ls.labor_standard_id IS NULL AND t.labor_standard_id IS NOT NULL;

-- check: wlr_interval_order | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_labor_requirement
WHERE interval_end_ts <= interval_start_ts OR interval_minutes <= 0;

-- check: wlr_hours_nonnegative | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_labor_requirement
WHERE required_labor_hours < 0 OR required_headcount < 0
   OR minimum_headcount < 0 OR forecast_driver_units < 0
   OR applied_labor_standard <= 0;

-- check: wlr_role_domain | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_labor_requirement
WHERE role_code NOT IN ('cashier', 'sales_associate', 'fulfillment', 'inventory', 'supervisor');

-- check: wlr_driver_domain | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_labor_requirement
WHERE demand_driver NOT IN (
  'transaction_count', 'foot_traffic', 'pickup_orders',
  'receiving_units', 'store_open_coverage', 'minimum_coverage'
);

-- check: wlr_forecast_missing_standard | severity: error
-- Every (role, driver, zone) the demand forecast produces must resolve to a CURRENT
-- labor standard; an unmatched combination is silently dropped by the requirement
-- step, understating required hours rather than erroring. A standard scoped
-- storewide (department_or_zone NULL or 'storewide') covers every zone.
SELECT f.role_code, f.demand_driver, f.department_or_zone
FROM (
  SELECT DISTINCT role_code, demand_driver, department_or_zone
  FROM ${catalog}.${predops_schema}.workforce_demand_forecast
) f
LEFT JOIN (
  SELECT DISTINCT role_code, demand_driver, department_or_zone
  FROM ${catalog}.${predops_schema}.labor_standard
  WHERE is_current = TRUE
) s
  ON  s.role_code = f.role_code
  AND s.demand_driver = f.demand_driver
  AND (s.department_or_zone IS NULL
       OR s.department_or_zone = 'storewide'
       OR s.department_or_zone = f.department_or_zone)
WHERE s.role_code IS NULL;

-- check: wlr_rowcount | severity: metric
SELECT COUNT(*) AS workforce_labor_requirement_rows
FROM ${catalog}.${predops_schema}.workforce_labor_requirement;

-- ========== workforce_schedule_recommendation ==========

-- check: wsr_keys_not_null | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_schedule_recommendation
WHERE workforce_schedule_recommendation_sk IS NULL
   OR workforce_schedule_recommendation_id IS NULL
   OR workforce_optimization_run_id IS NULL OR employee_id IS NULL OR store_id IS NULL
   OR department_or_zone IS NULL OR role_code IS NULL
   OR shift_start_ts IS NULL OR shift_end_ts IS NULL OR assigned_hours IS NULL
   OR is_availability_ok IS NULL OR is_skill_ok IS NULL
   OR is_store_eligible_ok IS NULL OR is_hours_cap_ok IS NULL OR is_min_rest_ok IS NULL
   OR recommendation_status IS NULL OR optimizer_status IS NULL;

-- check: wsr_pk_unique | severity: error
SELECT workforce_schedule_recommendation_sk
FROM ${catalog}.${predops_schema}.workforce_schedule_recommendation
GROUP BY workforce_schedule_recommendation_sk
HAVING COUNT(*) > 1;

-- check: wsr_id_unique | severity: error
SELECT workforce_schedule_recommendation_id
FROM ${catalog}.${predops_schema}.workforce_schedule_recommendation
GROUP BY workforce_schedule_recommendation_id
HAVING COUNT(*) > 1;

-- check: wsr_store_fk_orphan | severity: error
SELECT t.* FROM ${catalog}.${predops_schema}.workforce_schedule_recommendation t
LEFT JOIN ${catalog}.${store_schema}.store st ON t.store_sk = st.store_sk
WHERE st.store_sk IS NULL AND t.store_sk IS NOT NULL;

-- check: wsr_run_fk_orphan | severity: error
SELECT t.* FROM ${catalog}.${predops_schema}.workforce_schedule_recommendation t
LEFT JOIN ${catalog}.${predops_schema}.workforce_optimization_run r
  ON t.workforce_optimization_run_id = r.workforce_optimization_run_id
WHERE r.workforce_optimization_run_id IS NULL AND t.workforce_optimization_run_id IS NOT NULL;

-- check: wsr_employee_fk_orphan | severity: error
SELECT wsr.* FROM ${catalog}.${predops_schema}.workforce_schedule_recommendation wsr
LEFT JOIN ${catalog}.${labor_schema}.employee emp ON wsr.employee_sk = emp.employee_sk
WHERE emp.employee_sk IS NULL AND wsr.employee_sk IS NOT NULL;

-- check: wsr_interval_order | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_schedule_recommendation
WHERE shift_end_ts <= shift_start_ts;

-- check: wsr_hours_nonnegative | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_schedule_recommendation
WHERE assigned_hours < 0
   OR (estimated_labor_cost IS NOT NULL AND estimated_labor_cost < 0);

-- check: wsr_cost_single_currency | severity: error
-- estimated_labor_cost is nullable; only cost-bearing rows carry a currency.
SELECT 'workforce_schedule_recommendation' AS table_name, COUNT(DISTINCT currency_code) AS currencies
FROM ${catalog}.${predops_schema}.workforce_schedule_recommendation
WHERE estimated_labor_cost IS NOT NULL
HAVING COUNT(DISTINCT currency_code) > 1
    OR COUNT(CASE WHEN currency_code IS NULL THEN 1 END) > 0;

-- check: wsr_role_domain | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_schedule_recommendation
WHERE role_code NOT IN ('cashier', 'sales_associate', 'fulfillment', 'inventory', 'supervisor');

-- check: wsr_status_domain | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_schedule_recommendation
WHERE recommendation_status NOT IN ('proposed', 'accepted', 'rejected', 'superseded')
   OR optimizer_status NOT IN ('optimal', 'feasible', 'heuristic', 'infeasible_partial');

-- check: wsr_single_currency | severity: error
SELECT 'workforce_schedule_recommendation' AS table_name, COUNT(DISTINCT currency_code) AS currencies
FROM ${catalog}.${predops_schema}.workforce_schedule_recommendation
HAVING COUNT(DISTINCT currency_code) > 1
    OR COUNT(CASE WHEN estimated_labor_cost IS NOT NULL AND currency_code IS NULL THEN 1 END) > 0;

-- check: wsr_rowcount | severity: metric
SELECT COUNT(*) AS workforce_schedule_recommendation_rows
FROM ${catalog}.${predops_schema}.workforce_schedule_recommendation;

-- ========== workforce_coverage_exception ==========

-- check: wce_keys_not_null | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_coverage_exception
WHERE workforce_coverage_exception_sk IS NULL OR workforce_coverage_exception_id IS NULL
   OR workforce_optimization_run_id IS NULL OR store_id IS NULL OR business_date IS NULL
   OR interval_start_ts IS NULL OR interval_end_ts IS NULL
   OR department_or_zone IS NULL OR role_code IS NULL
   OR required_headcount IS NULL OR scheduled_headcount IS NULL OR shortfall_headcount IS NULL
   OR severity IS NULL OR exception_explanation IS NULL OR suggested_action IS NULL;

-- check: wce_pk_unique | severity: error
SELECT workforce_coverage_exception_sk
FROM ${catalog}.${predops_schema}.workforce_coverage_exception
GROUP BY workforce_coverage_exception_sk
HAVING COUNT(*) > 1;

-- check: wce_id_unique | severity: error
SELECT workforce_coverage_exception_id
FROM ${catalog}.${predops_schema}.workforce_coverage_exception
GROUP BY workforce_coverage_exception_id
HAVING COUNT(*) > 1;

-- check: wce_store_fk_orphan | severity: error
SELECT t.* FROM ${catalog}.${predops_schema}.workforce_coverage_exception t
LEFT JOIN ${catalog}.${store_schema}.store st ON t.store_sk = st.store_sk
WHERE st.store_sk IS NULL AND t.store_sk IS NOT NULL;

-- check: wce_run_fk_orphan | severity: error
SELECT t.* FROM ${catalog}.${predops_schema}.workforce_coverage_exception t
LEFT JOIN ${catalog}.${predops_schema}.workforce_optimization_run r
  ON t.workforce_optimization_run_id = r.workforce_optimization_run_id
WHERE r.workforce_optimization_run_id IS NULL AND t.workforce_optimization_run_id IS NOT NULL;

-- check: wce_interval_order | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_coverage_exception
WHERE interval_end_ts <= interval_start_ts;

-- check: wce_counts_nonnegative | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_coverage_exception
WHERE required_headcount < 0 OR scheduled_headcount < 0 OR shortfall_headcount < 0;

-- check: wce_role_domain | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_coverage_exception
WHERE role_code NOT IN ('cashier', 'sales_associate', 'fulfillment', 'inventory', 'supervisor');

-- check: wce_severity_domain | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_coverage_exception
WHERE severity NOT IN ('low', 'medium', 'high', 'critical');

-- check: wce_action_domain | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_coverage_exception
WHERE suggested_action NOT IN (
  'call_in', 'transfer', 'shorten_interval_service', 'overtime', 'accept_risk', 'hire_temp'
);

-- check: wce_rowcount | severity: metric
SELECT COUNT(*) AS workforce_coverage_exception_rows
FROM ${catalog}.${predops_schema}.workforce_coverage_exception;

-- ========== workforce_optimization_run ==========

-- check: wor_keys_not_null | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_optimization_run
WHERE workforce_optimization_run_sk IS NULL OR workforce_optimization_run_id IS NULL
   OR forecast_horizon_days IS NULL OR interval_minutes IS NULL
   OR forecast_method IS NULL OR optimizer_method IS NULL
   OR optimization_status IS NULL OR run_started_ts IS NULL;

-- check: wor_pk_unique | severity: error
SELECT workforce_optimization_run_sk
FROM ${catalog}.${predops_schema}.workforce_optimization_run
GROUP BY workforce_optimization_run_sk
HAVING COUNT(*) > 1;

-- check: wor_run_id_unique | severity: error
SELECT workforce_optimization_run_id
FROM ${catalog}.${predops_schema}.workforce_optimization_run
GROUP BY workforce_optimization_run_id
HAVING COUNT(*) > 1;

-- check: wor_positive_params | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_optimization_run
WHERE forecast_horizon_days <= 0 OR interval_minutes <= 0;

-- check: wor_method_domain | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_optimization_run
WHERE forecast_method NOT IN ('seasonal_rolling_avg', 'hierarchical_fallback', 'model', 'manual')
   OR optimizer_method NOT IN ('greedy_heuristic', 'ortools', 'pulp', 'other')
   OR optimization_status NOT IN ('success', 'success_partial', 'infeasible', 'failed');

-- check: wor_counts_nonnegative | severity: error
SELECT * FROM ${catalog}.${predops_schema}.workforce_optimization_run
WHERE COALESCE(input_employee_count, 0) < 0
   OR COALESCE(input_demand_intervals, 0) < 0
   OR COALESCE(rejected_quality_count, 0) < 0
   OR COALESCE(forecast_line_count, 0) < 0
   OR COALESCE(requirement_line_count, 0) < 0
   OR COALESCE(recommended_shift_count, 0) < 0
   OR COALESCE(exception_count, 0) < 0
   OR COALESCE(scheduled_hours_total, 0) < 0
   OR COALESCE(required_hours_total, 0) < 0
   OR COALESCE(unfilled_demand_hours, 0) < 0
   OR COALESCE(estimated_labor_cost, 0) < 0;

-- check: wor_single_currency | severity: error
SELECT 'workforce_optimization_run' AS table_name, COUNT(DISTINCT currency_code) AS currencies
FROM ${catalog}.${predops_schema}.workforce_optimization_run
HAVING COUNT(DISTINCT currency_code) > 1
    OR COUNT(CASE WHEN estimated_labor_cost IS NOT NULL AND currency_code IS NULL THEN 1 END) > 0;

-- check: wor_rowcount | severity: metric
SELECT COUNT(*) AS workforce_optimization_run_rows
FROM ${catalog}.${predops_schema}.workforce_optimization_run;
