-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- File: checks.sql
-- Version: 0.5
-- Generated: 2026-07-21
-- ============================================================
-- Each assertion SELECTs violating rows; 0 rows = PASS. `metric` checks
-- report a value and never fail the run.
-- ============================================================

-- ========== domain / range ==========

-- check: planning_unit_grain_type | severity: error
SELECT * FROM ${catalog}.${sdi_schema}.planning_unit
WHERE grain_type NOT IN ('store_sku', 'account_product_region', 'dc_product');

-- check: demand_forecast_quantity_positive | severity: error
SELECT * FROM ${catalog}.${sdi_schema}.demand_forecast
WHERE forecast_quantity < 0;

-- check: forecast_accuracy_range | severity: error
SELECT * FROM ${catalog}.${sdi_schema}.forecast_accuracy
WHERE accuracy_pct IS NOT NULL AND accuracy_pct NOT BETWEEN 0 AND 1;

-- check: oos_event_dates | severity: error
SELECT * FROM ${catalog}.${sdi_schema}.oos_event
WHERE oos_end_date_key IS NOT NULL AND oos_end_date_key < oos_start_date_key;

-- check: lost_sales_non_negative | severity: error
SELECT * FROM ${catalog}.${sdi_schema}.lost_sales_estimate
WHERE lost_units < 0;

-- check: lost_sales_confidence_range | severity: error
-- confidence_score is documented as 0-1.
SELECT * FROM ${catalog}.${sdi_schema}.lost_sales_estimate
WHERE confidence_score IS NOT NULL AND confidence_score NOT BETWEEN 0 AND 1;

-- check: lost_sales_not_exceeding_demand | severity: error
-- Lost units cannot exceed expected unconstrained demand for the day.
SELECT * FROM ${catalog}.${sdi_schema}.lost_sales_estimate
WHERE lost_units IS NOT NULL AND expected_units_demand IS NOT NULL
  AND lost_units > expected_units_demand;

-- check: oos_event_duration_consistency | severity: error
-- When both dates are present, stored duration must match the date span (inclusive).
SELECT * FROM ${catalog}.${sdi_schema}.oos_event
WHERE oos_end_date_key IS NOT NULL AND oos_duration_days IS NOT NULL
  AND oos_duration_days <> DATEDIFF(oos_end_date_key, oos_start_date_key) + 1;

-- check: oos_event_stockout_pct_range | severity: error
SELECT * FROM ${catalog}.${sdi_schema}.oos_event
WHERE stockout_pct_total IS NOT NULL AND stockout_pct_total NOT BETWEEN 0 AND 1;

-- check: oos_recovery_recoverability_range | severity: error
SELECT * FROM ${catalog}.${sdi_schema}.oos_recovery_action
WHERE recoverability_probability IS NOT NULL AND recoverability_probability NOT BETWEEN 0 AND 1;

-- check: lost_sales_margin_non_negative | severity: error
SELECT * FROM ${catalog}.${sdi_schema}.lost_sales_estimate
WHERE lost_margin IS NOT NULL AND lost_margin < 0;

-- check: forecast_component_decomposition_integrity | severity: warn
-- Component quantities should sum to the parent forecast (within rounding).
-- WARN, not error: some deployments decompose only a subset of drivers.
SELECT fc.demand_forecast_sk,
       SUM(fc.component_quantity) AS component_total,
       MAX(df.forecast_quantity)  AS forecast_quantity
FROM ${catalog}.${sdi_schema}.forecast_component fc
JOIN ${catalog}.${sdi_schema}.demand_forecast df ON df.demand_forecast_sk = fc.demand_forecast_sk
GROUP BY fc.demand_forecast_sk
HAVING ABS(SUM(fc.component_quantity) - MAX(df.forecast_quantity)) > 0.5;

-- check: forecast_accuracy_bias_range | severity: metric
-- Bias has no hard bound, but track the spread to catch runaway values.
SELECT MIN(bias_pct) AS min_bias_pct, MAX(bias_pct) AS max_bias_pct
FROM ${catalog}.${sdi_schema}.forecast_accuracy;

-- check: inventory_policy_current_open | severity: error
SELECT planning_unit_sk, COUNT(*) AS cnt
FROM ${catalog}.${sdi_schema}.inventory_policy
WHERE is_current = TRUE
GROUP BY planning_unit_sk
HAVING COUNT(*) > 1;

-- ========== SCD2 integrity (versioned reference tables) ==========

-- check: inventory_policy_noncurrent_closed | severity: error
-- A superseded (is_current = FALSE) version must have a closing date.
SELECT * FROM ${catalog}.${sdi_schema}.inventory_policy
WHERE is_current = FALSE AND effective_to_date IS NULL;

-- check: inventory_policy_effective_order | severity: error
-- effective_from_date must not fall after effective_to_date.
SELECT * FROM ${catalog}.${sdi_schema}.inventory_policy
WHERE effective_to_date IS NOT NULL AND effective_to_date < effective_from_date;

-- check: service_level_target_current_single | severity: error
-- At most one current version per (abc_class, xyz_class) segment; NULL segments
-- are the default, compared with null-safe equality.
SELECT abc_class, xyz_class, COUNT(*) AS cnt
FROM ${catalog}.${sdi_schema}.service_level_target
WHERE is_current = TRUE
GROUP BY abc_class, xyz_class
HAVING COUNT(*) > 1;

-- check: service_level_target_noncurrent_closed | severity: error
SELECT * FROM ${catalog}.${sdi_schema}.service_level_target
WHERE is_current = FALSE AND effective_to_date IS NULL;

-- check: service_level_target_effective_order | severity: error
SELECT * FROM ${catalog}.${sdi_schema}.service_level_target
WHERE effective_to_date IS NOT NULL AND effective_to_date < effective_from_date;

-- ========== single reporting currency (monetary facts) ==========

-- check: lost_sales_single_currency | severity: error
SELECT 1 FROM ${catalog}.${sdi_schema}.lost_sales_estimate
HAVING COUNT(DISTINCT currency_code) > 1 OR COUNT(CASE WHEN currency_code IS NULL THEN 1 END) > 0;

-- check: oos_recovery_single_currency | severity: error
SELECT 1 FROM ${catalog}.${sdi_schema}.oos_recovery_action
HAVING COUNT(DISTINCT currency_code) > 1 OR COUNT(CASE WHEN currency_code IS NULL THEN 1 END) > 0;

-- ========== FK-orphan (facts) ==========

-- check: planning_unit_product_fk_orphan | severity: error
SELECT pu.* FROM ${catalog}.${sdi_schema}.planning_unit pu
LEFT JOIN ${catalog}.${product_schema}.product p ON p.product_sk = pu.product_sk
WHERE pu.product_sk IS NOT NULL AND p.product_sk IS NULL;

-- check: planning_unit_store_fk_orphan | severity: error
SELECT pu.* FROM ${catalog}.${sdi_schema}.planning_unit pu
LEFT JOIN ${catalog}.${store_schema}.store st ON st.store_sk = pu.store_sk
WHERE pu.store_sk IS NOT NULL AND st.store_sk IS NULL;

-- check: planning_unit_segment_fk_orphan | severity: error
SELECT seg.* FROM ${catalog}.${sdi_schema}.planning_unit_segment seg
LEFT JOIN ${catalog}.${sdi_schema}.planning_unit pu ON pu.planning_unit_sk = seg.planning_unit_sk
WHERE seg.planning_unit_sk IS NOT NULL AND pu.planning_unit_sk IS NULL;

-- check: demand_forecast_planning_unit_fk_orphan | severity: error
SELECT df.* FROM ${catalog}.${sdi_schema}.demand_forecast df
LEFT JOIN ${catalog}.${sdi_schema}.planning_unit pu ON pu.planning_unit_sk = df.planning_unit_sk
WHERE df.planning_unit_sk IS NOT NULL AND pu.planning_unit_sk IS NULL;

-- check: demand_forecast_model_run_fk_orphan | severity: error
SELECT df.* FROM ${catalog}.${sdi_schema}.demand_forecast df
LEFT JOIN ${catalog}.${sdi_schema}.forecast_model_run mr ON mr.model_run_sk = df.model_run_sk
WHERE df.model_run_sk IS NOT NULL AND mr.model_run_sk IS NULL;

-- check: forecast_component_fk_orphan | severity: error
SELECT fc.* FROM ${catalog}.${sdi_schema}.forecast_component fc
LEFT JOIN ${catalog}.${sdi_schema}.demand_forecast df ON df.demand_forecast_sk = fc.demand_forecast_sk
WHERE fc.demand_forecast_sk IS NOT NULL AND df.demand_forecast_sk IS NULL;

-- check: forecast_adjustment_fk_orphan | severity: error
SELECT fa.* FROM ${catalog}.${sdi_schema}.forecast_adjustment fa
LEFT JOIN ${catalog}.${sdi_schema}.planning_unit pu ON pu.planning_unit_sk = fa.planning_unit_sk
WHERE fa.planning_unit_sk IS NOT NULL AND pu.planning_unit_sk IS NULL;

-- check: forecast_accuracy_fk_orphan | severity: error
SELECT fac.* FROM ${catalog}.${sdi_schema}.forecast_accuracy fac
LEFT JOIN ${catalog}.${sdi_schema}.planning_unit pu ON pu.planning_unit_sk = fac.planning_unit_sk
WHERE fac.planning_unit_sk IS NOT NULL AND pu.planning_unit_sk IS NULL;

-- check: order_forecast_planning_unit_fk_orphan | severity: error
SELECT ofc.* FROM ${catalog}.${sdi_schema}.order_forecast ofc
LEFT JOIN ${catalog}.${sdi_schema}.planning_unit pu ON pu.planning_unit_sk = ofc.planning_unit_sk
WHERE ofc.planning_unit_sk IS NOT NULL AND pu.planning_unit_sk IS NULL;

-- check: order_forecast_demand_fk_orphan | severity: error
SELECT ofc.* FROM ${catalog}.${sdi_schema}.order_forecast ofc
LEFT JOIN ${catalog}.${sdi_schema}.demand_forecast df ON df.demand_forecast_sk = ofc.demand_forecast_sk
WHERE ofc.demand_forecast_sk IS NOT NULL AND df.demand_forecast_sk IS NULL;

-- check: inventory_policy_planning_unit_fk_orphan | severity: error
SELECT ip.* FROM ${catalog}.${sdi_schema}.inventory_policy ip
LEFT JOIN ${catalog}.${sdi_schema}.planning_unit pu ON pu.planning_unit_sk = ip.planning_unit_sk
WHERE ip.planning_unit_sk IS NOT NULL AND pu.planning_unit_sk IS NULL;

-- check: inventory_policy_slt_fk_orphan | severity: error
SELECT ip.* FROM ${catalog}.${sdi_schema}.inventory_policy ip
LEFT JOIN ${catalog}.${sdi_schema}.service_level_target slt ON slt.service_level_target_sk = ip.service_level_target_sk
WHERE ip.service_level_target_sk IS NOT NULL AND slt.service_level_target_sk IS NULL;

-- check: inventory_policy_calculation_fk_orphan | severity: error
SELECT ipc.* FROM ${catalog}.${sdi_schema}.inventory_policy_calculation ipc
LEFT JOIN ${catalog}.${sdi_schema}.inventory_policy ip ON ip.inventory_policy_sk = ipc.inventory_policy_sk
WHERE ipc.inventory_policy_sk IS NOT NULL AND ip.inventory_policy_sk IS NULL;

-- check: inventory_recommendation_fk_orphan | severity: error
SELECT ir.* FROM ${catalog}.${sdi_schema}.inventory_recommendation ir
LEFT JOIN ${catalog}.${sdi_schema}.planning_unit pu ON pu.planning_unit_sk = ir.planning_unit_sk
WHERE ir.planning_unit_sk IS NOT NULL AND pu.planning_unit_sk IS NULL;

-- check: oos_event_product_fk_orphan | severity: error
SELECT oe.* FROM ${catalog}.${sdi_schema}.oos_event oe
LEFT JOIN ${catalog}.${product_schema}.product p ON p.product_sk = oe.product_sk
WHERE oe.product_sk IS NOT NULL AND p.product_sk IS NULL;

-- check: oos_event_store_fk_orphan | severity: error
SELECT oe.* FROM ${catalog}.${sdi_schema}.oos_event oe
LEFT JOIN ${catalog}.${store_schema}.store st ON st.store_sk = oe.store_sk
WHERE oe.store_sk IS NOT NULL AND st.store_sk IS NULL;

-- check: lost_sales_estimate_fk_orphan | severity: error
SELECT lse.* FROM ${catalog}.${sdi_schema}.lost_sales_estimate lse
LEFT JOIN ${catalog}.${sdi_schema}.oos_event oe ON oe.oos_event_sk = lse.oos_event_sk
WHERE lse.oos_event_sk IS NOT NULL AND oe.oos_event_sk IS NULL;

-- check: demand_sensing_signal_fk_orphan | severity: error
SELECT dss.* FROM ${catalog}.${sdi_schema}.demand_sensing_signal dss
LEFT JOIN ${catalog}.${sdi_schema}.oos_event oe ON oe.oos_event_sk = dss.linked_oos_event_sk
WHERE dss.linked_oos_event_sk IS NOT NULL AND oe.oos_event_sk IS NULL;

-- check: oos_recovery_action_fk_orphan | severity: error
SELECT ora.* FROM ${catalog}.${sdi_schema}.oos_recovery_action ora
LEFT JOIN ${catalog}.${sdi_schema}.oos_event oe ON oe.oos_event_sk = ora.oos_event_sk
WHERE ora.oos_event_sk IS NOT NULL AND oe.oos_event_sk IS NULL;

-- ========== grain uniqueness (business keys) ==========

-- check: planning_unit_grain_unique | severity: error
SELECT planning_unit_id FROM ${catalog}.${sdi_schema}.planning_unit
GROUP BY planning_unit_id HAVING COUNT(*) > 1;

-- check: planning_unit_segment_grain_unique | severity: error
SELECT segment_id FROM ${catalog}.${sdi_schema}.planning_unit_segment
GROUP BY segment_id HAVING COUNT(*) > 1;

-- check: forecast_model_run_grain_unique | severity: error
SELECT model_run_id FROM ${catalog}.${sdi_schema}.forecast_model_run
GROUP BY model_run_id HAVING COUNT(*) > 1;

-- check: demand_forecast_grain_unique | severity: error
SELECT demand_forecast_id FROM ${catalog}.${sdi_schema}.demand_forecast
GROUP BY demand_forecast_id HAVING COUNT(*) > 1;

-- check: forecast_component_grain_unique | severity: error
SELECT forecast_component_id FROM ${catalog}.${sdi_schema}.forecast_component
GROUP BY forecast_component_id HAVING COUNT(*) > 1;

-- check: forecast_adjustment_grain_unique | severity: error
SELECT forecast_adjustment_id FROM ${catalog}.${sdi_schema}.forecast_adjustment
GROUP BY forecast_adjustment_id HAVING COUNT(*) > 1;

-- check: forecast_accuracy_grain_unique | severity: error
SELECT forecast_accuracy_id FROM ${catalog}.${sdi_schema}.forecast_accuracy
GROUP BY forecast_accuracy_id HAVING COUNT(*) > 1;

-- check: service_level_target_grain_unique | severity: error
SELECT service_level_target_id FROM ${catalog}.${sdi_schema}.service_level_target
GROUP BY service_level_target_id HAVING COUNT(*) > 1;

-- check: service_level_z_grain_unique | severity: error
SELECT service_level_z_id FROM ${catalog}.${sdi_schema}.service_level_z
GROUP BY service_level_z_id HAVING COUNT(*) > 1;

-- check: service_level_z_pct_range | severity: error
SELECT * FROM ${catalog}.${sdi_schema}.service_level_z
WHERE service_level_pct NOT BETWEEN 0 AND 1;

-- check: service_level_z_score_valid | severity: error
-- z_score is multiplied directly into every safety-stock recommendation, so a NULL
-- or negative seeded value silently mis-sizes stock. A standard-normal quantile at a
-- service level >= 0.5 is non-negative.
SELECT * FROM ${catalog}.${sdi_schema}.service_level_z
WHERE z_score IS NULL OR z_score < 0;

-- check: inventory_policy_grain_unique | severity: error
SELECT inventory_policy_id FROM ${catalog}.${sdi_schema}.inventory_policy
GROUP BY inventory_policy_id HAVING COUNT(*) > 1;

-- check: inventory_policy_calculation_grain_unique | severity: error
SELECT policy_calculation_id FROM ${catalog}.${sdi_schema}.inventory_policy_calculation
GROUP BY policy_calculation_id HAVING COUNT(*) > 1;

-- check: inventory_recommendation_grain_unique | severity: error
SELECT inventory_recommendation_id FROM ${catalog}.${sdi_schema}.inventory_recommendation
GROUP BY inventory_recommendation_id HAVING COUNT(*) > 1;

-- check: order_forecast_grain_unique | severity: error
SELECT order_forecast_id FROM ${catalog}.${sdi_schema}.order_forecast
GROUP BY order_forecast_id HAVING COUNT(*) > 1;

-- check: oos_event_grain_unique | severity: error
SELECT oos_event_id FROM ${catalog}.${sdi_schema}.oos_event
GROUP BY oos_event_id HAVING COUNT(*) > 1;

-- check: lost_sales_estimate_grain_unique | severity: error
SELECT lost_sales_estimate_id FROM ${catalog}.${sdi_schema}.lost_sales_estimate
GROUP BY lost_sales_estimate_id HAVING COUNT(*) > 1;

-- check: demand_sensing_signal_grain_unique | severity: error
SELECT demand_sensing_signal_id FROM ${catalog}.${sdi_schema}.demand_sensing_signal
GROUP BY demand_sensing_signal_id HAVING COUNT(*) > 1;

-- check: oos_recovery_action_grain_unique | severity: error
SELECT oos_recovery_action_id FROM ${catalog}.${sdi_schema}.oos_recovery_action
GROUP BY oos_recovery_action_id HAVING COUNT(*) > 1;

-- ========== metric (row counts / distributions) ==========

-- check: demand_forecast_rowcount | severity: metric
SELECT COUNT(*) AS demand_forecast_rows FROM ${catalog}.${sdi_schema}.demand_forecast;

-- check: oos_event_rowcount | severity: metric
SELECT COUNT(*) AS oos_event_rows FROM ${catalog}.${sdi_schema}.oos_event;

-- check: lost_sales_revenue_total | severity: metric
SELECT COALESCE(SUM(lost_revenue), 0) AS total_lost_revenue FROM ${catalog}.${sdi_schema}.lost_sales_estimate;
