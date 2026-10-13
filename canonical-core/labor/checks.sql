-- ============================================================
-- ORDM · Canonical Core · Labor domain · data-quality checks
-- Version: 0.5 · Generated: 2026-08-10 · LLM-generated: true · Reviewed: 2026-08-10
-- Each assertion SELECTs violating rows; 0 rows = PASS. `metric` checks report
-- a value and never fail the run.
-- ============================================================

-- ========== employee ==========

-- check: employee_keys_not_null | severity: error
SELECT * FROM ${catalog}.${labor_schema}.employee
WHERE employee_sk IS NULL OR employee_id IS NULL OR home_store_id IS NULL
   OR primary_role_code IS NULL OR employment_status IS NULL
   OR max_daily_hours IS NULL OR max_weekly_hours IS NULL OR min_rest_hours IS NULL
   OR effective_from_date IS NULL OR is_current IS NULL;

-- check: employee_pk_unique | severity: error
SELECT employee_sk
FROM ${catalog}.${labor_schema}.employee
GROUP BY employee_sk
HAVING COUNT(*) > 1;

-- check: employee_scd2_current_open | severity: error
SELECT * FROM ${catalog}.${labor_schema}.employee
WHERE is_current = TRUE AND effective_to_date IS NOT NULL;

-- check: employee_scd2_noncurrent_closed | severity: error
SELECT * FROM ${catalog}.${labor_schema}.employee
WHERE is_current = FALSE AND effective_to_date IS NULL;

-- check: employee_scd2_start_before_end | severity: error
SELECT * FROM ${catalog}.${labor_schema}.employee
WHERE effective_to_date IS NOT NULL AND effective_from_date > effective_to_date;

-- check: employee_current_id_unique | severity: error
SELECT employee_id, COUNT(*) AS n
FROM ${catalog}.${labor_schema}.employee
WHERE is_current = TRUE
GROUP BY employee_id
HAVING COUNT(*) > 1;

-- check: employee_store_fk_orphan | severity: error
SELECT e.* FROM ${catalog}.${labor_schema}.employee e
LEFT JOIN ${catalog}.${store_schema}.store st ON e.home_store_sk = st.store_sk
WHERE st.store_sk IS NULL AND e.home_store_sk IS NOT NULL;

-- check: employee_cost_single_currency | severity: error
-- hourly_labor_cost is nullable; only cost-bearing rows carry a currency. Mirrors
-- wsr_cost_single_currency: a costed row with no currency is a violation, not a pass.
SELECT 'employee' AS table_name, COUNT(DISTINCT currency_code) AS currencies
FROM ${catalog}.${labor_schema}.employee
WHERE hourly_labor_cost IS NOT NULL
HAVING COUNT(DISTINCT currency_code) > 1
    OR COUNT(CASE WHEN currency_code IS NULL THEN 1 END) > 0;

-- check: employee_rowcount | severity: metric
SELECT COUNT(*) AS employee_rows FROM ${catalog}.${labor_schema}.employee;

-- check: employee_role_distribution | severity: metric
SELECT primary_role_code, COUNT(*) AS role_count
FROM ${catalog}.${labor_schema}.employee
WHERE is_current = TRUE
GROUP BY primary_role_code;

-- ========== employee_skill ==========

-- check: employee_skill_keys_not_null | severity: error
SELECT * FROM ${catalog}.${labor_schema}.employee_skill
WHERE employee_skill_sk IS NULL OR employee_skill_id IS NULL
   OR employee_id IS NULL OR skill_code IS NULL OR is_active IS NULL
   OR effective_from_date IS NULL;

-- check: employee_skill_pk_unique | severity: error
SELECT employee_skill_sk
FROM ${catalog}.${labor_schema}.employee_skill
GROUP BY employee_skill_sk
HAVING COUNT(*) > 1;

-- check: employee_skill_biz_key_unique | severity: error
SELECT employee_skill_id, COUNT(*) AS n
FROM ${catalog}.${labor_schema}.employee_skill
GROUP BY employee_skill_id
HAVING COUNT(*) > 1;

-- check: employee_skill_fk_orphan | severity: error
SELECT s.* FROM ${catalog}.${labor_schema}.employee_skill s
LEFT JOIN ${catalog}.${labor_schema}.employee e ON s.employee_sk = e.employee_sk
WHERE e.employee_sk IS NULL AND s.employee_sk IS NOT NULL;

-- check: employee_skill_rowcount | severity: metric
SELECT COUNT(*) AS employee_skill_rows FROM ${catalog}.${labor_schema}.employee_skill;

-- ========== employee_availability ==========

-- check: employee_availability_keys_not_null | severity: error
SELECT * FROM ${catalog}.${labor_schema}.employee_availability
WHERE employee_availability_sk IS NULL OR employee_availability_id IS NULL
   OR employee_id IS NULL OR availability_date IS NULL
   OR available_start_ts IS NULL OR available_end_ts IS NULL OR is_available IS NULL;

-- check: employee_availability_pk_unique | severity: error
SELECT employee_availability_sk
FROM ${catalog}.${labor_schema}.employee_availability
GROUP BY employee_availability_sk
HAVING COUNT(*) > 1;

-- check: employee_availability_biz_key_unique | severity: error
SELECT employee_availability_id, COUNT(*) AS n
FROM ${catalog}.${labor_schema}.employee_availability
GROUP BY employee_availability_id
HAVING COUNT(*) > 1;

-- check: employee_availability_end_after_start | severity: error
SELECT * FROM ${catalog}.${labor_schema}.employee_availability
WHERE available_end_ts <= available_start_ts;

-- check: employee_availability_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${labor_schema}.employee_availability a
LEFT JOIN ${catalog}.${labor_schema}.employee e ON a.employee_sk = e.employee_sk
WHERE e.employee_sk IS NULL AND a.employee_sk IS NOT NULL;

-- check: employee_availability_rowcount | severity: metric
SELECT COUNT(*) AS employee_availability_rows FROM ${catalog}.${labor_schema}.employee_availability;

-- ========== employee_store_eligibility ==========

-- check: employee_store_eligibility_keys_not_null | severity: error
SELECT * FROM ${catalog}.${labor_schema}.employee_store_eligibility
WHERE employee_store_eligibility_sk IS NULL OR employee_store_eligibility_id IS NULL
   OR employee_id IS NULL OR store_id IS NULL OR is_primary IS NULL OR is_active IS NULL
   OR effective_from_date IS NULL;

-- check: employee_store_eligibility_pk_unique | severity: error
SELECT employee_store_eligibility_sk
FROM ${catalog}.${labor_schema}.employee_store_eligibility
GROUP BY employee_store_eligibility_sk
HAVING COUNT(*) > 1;

-- check: employee_store_eligibility_biz_key_unique | severity: error
SELECT employee_store_eligibility_id, COUNT(*) AS n
FROM ${catalog}.${labor_schema}.employee_store_eligibility
GROUP BY employee_store_eligibility_id
HAVING COUNT(*) > 1;

-- check: employee_store_eligibility_store_fk_orphan | severity: error
SELECT x.* FROM ${catalog}.${labor_schema}.employee_store_eligibility x
LEFT JOIN ${catalog}.${store_schema}.store st ON x.store_sk = st.store_sk
WHERE st.store_sk IS NULL AND x.store_sk IS NOT NULL;

-- check: employee_store_eligibility_employee_fk_orphan | severity: error
SELECT x.* FROM ${catalog}.${labor_schema}.employee_store_eligibility x
LEFT JOIN ${catalog}.${labor_schema}.employee e ON x.employee_sk = e.employee_sk
WHERE e.employee_sk IS NULL AND x.employee_sk IS NOT NULL;

-- check: employee_store_eligibility_rowcount | severity: metric
SELECT COUNT(*) AS employee_store_eligibility_rows FROM ${catalog}.${labor_schema}.employee_store_eligibility;

-- ========== labor_schedule ==========

-- check: labor_schedule_keys_not_null | severity: error
SELECT * FROM ${catalog}.${labor_schema}.labor_schedule
WHERE labor_schedule_sk IS NULL OR labor_schedule_id IS NULL
   OR employee_id IS NULL OR store_id IS NULL OR role_code IS NULL
   OR business_date IS NULL OR shift_start_ts IS NULL OR shift_end_ts IS NULL
   OR scheduled_hours IS NULL OR schedule_status IS NULL;

-- check: labor_schedule_end_after_start | severity: error
SELECT * FROM ${catalog}.${labor_schema}.labor_schedule
WHERE shift_end_ts <= shift_start_ts;

-- check: labor_schedule_hours_nonnegative | severity: error
SELECT * FROM ${catalog}.${labor_schema}.labor_schedule
WHERE scheduled_hours < 0;

-- check: labor_schedule_pk_unique | severity: error
SELECT labor_schedule_sk
FROM ${catalog}.${labor_schema}.labor_schedule
GROUP BY labor_schedule_sk
HAVING COUNT(*) > 1;

-- check: labor_schedule_biz_key_unique | severity: error
SELECT labor_schedule_id, COUNT(*) AS n
FROM ${catalog}.${labor_schema}.labor_schedule
GROUP BY labor_schedule_id
HAVING COUNT(*) > 1;

-- check: labor_schedule_employee_fk_orphan | severity: error
SELECT s.* FROM ${catalog}.${labor_schema}.labor_schedule s
LEFT JOIN ${catalog}.${labor_schema}.employee e ON s.employee_sk = e.employee_sk
WHERE e.employee_sk IS NULL AND s.employee_sk IS NOT NULL;

-- check: labor_schedule_store_fk_orphan | severity: error
SELECT s.* FROM ${catalog}.${labor_schema}.labor_schedule s
LEFT JOIN ${catalog}.${store_schema}.store st ON s.store_sk = st.store_sk
WHERE st.store_sk IS NULL AND s.store_sk IS NOT NULL;

-- check: labor_schedule_rowcount | severity: metric
SELECT COUNT(*) AS labor_schedule_rows FROM ${catalog}.${labor_schema}.labor_schedule;

-- ========== labor_actuals ==========

-- check: labor_actuals_keys_not_null | severity: error
SELECT * FROM ${catalog}.${labor_schema}.labor_actuals
WHERE labor_actuals_sk IS NULL OR labor_actuals_id IS NULL
   OR employee_id IS NULL OR store_id IS NULL OR role_code IS NULL
   OR business_date IS NULL OR clock_in_ts IS NULL OR clock_out_ts IS NULL
   OR worked_hours IS NULL OR actuals_status IS NULL;

-- check: labor_actuals_pk_unique | severity: error
SELECT labor_actuals_sk
FROM ${catalog}.${labor_schema}.labor_actuals
GROUP BY labor_actuals_sk
HAVING COUNT(*) > 1;

-- check: labor_actuals_biz_key_unique | severity: error
SELECT labor_actuals_id, COUNT(*) AS n
FROM ${catalog}.${labor_schema}.labor_actuals
GROUP BY labor_actuals_id
HAVING COUNT(*) > 1;

-- check: labor_actuals_end_after_start | severity: error
SELECT * FROM ${catalog}.${labor_schema}.labor_actuals
WHERE clock_out_ts <= clock_in_ts;

-- check: labor_actuals_hours_nonnegative | severity: error
SELECT * FROM ${catalog}.${labor_schema}.labor_actuals
WHERE worked_hours < 0;

-- check: labor_actuals_employee_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${labor_schema}.labor_actuals a
LEFT JOIN ${catalog}.${labor_schema}.employee e ON a.employee_sk = e.employee_sk
WHERE e.employee_sk IS NULL AND a.employee_sk IS NOT NULL;

-- check: labor_actuals_store_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${labor_schema}.labor_actuals a
LEFT JOIN ${catalog}.${store_schema}.store st ON a.store_sk = st.store_sk
WHERE st.store_sk IS NULL AND a.store_sk IS NOT NULL;

-- check: labor_actuals_schedule_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${labor_schema}.labor_actuals a
LEFT JOIN ${catalog}.${labor_schema}.labor_schedule s ON a.labor_schedule_sk = s.labor_schedule_sk
WHERE s.labor_schedule_sk IS NULL AND a.labor_schedule_sk IS NOT NULL;

-- check: labor_actuals_rowcount | severity: metric
SELECT COUNT(*) AS labor_actuals_rows FROM ${catalog}.${labor_schema}.labor_actuals;
