-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · sample queries (all use cases)
-- Version: 0.5
-- Generated: 2026-07-15
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-29 by @sreekanthmunigati
-- ============================================================

-- 1. Equipment health dashboard: assets at risk or worse
-- Primary triage query for store operations — shows equipment
-- needing attention, ordered by health score (worst first).
SELECT
    eh.equipment_name,
    eh.equipment_type,
    eh.store_id,
    eh.store_name,
    eh.criticality,
    eh.equipment_status,
    eh.health_score,
    eh.health_tier,
    eh.anomaly_count_7d,
    eh.error_count_7d,
    eh.corrective_wo_count_90d,
    eh.total_downtime_hours_90d,
    eh.latest_temperature,
    eh.last_reading_timestamp
FROM ${catalog}.${predops_schema}.gold_equipment_health eh
WHERE eh.health_tier IN ('at_risk', 'degraded', 'failed')
ORDER BY eh.health_score ASC, eh.criticality ASC
LIMIT 20;

-- 2. Maintenance effectiveness by equipment type
-- Compares preventive-to-corrective ratio, MTBF, and cost across
-- equipment types to identify where the PM program is weakest.
SELECT
    me.equipment_type,
    COUNT(*) AS equipment_count,
    ROUND(AVG(me.preventive_to_corrective_ratio), 2) AS avg_pm_ratio,
    ROUND(AVG(me.mtbf_days), 1) AS avg_mtbf_days,
    SUM(me.total_maintenance_cost) AS total_cost,
    SUM(me.total_downtime_hours) AS total_downtime_hours,
    ROUND(AVG(me.schedule_compliance_rate), 3) AS avg_schedule_compliance,
    SUM(me.overdue_schedules) AS total_overdue_schedules
FROM ${catalog}.${predops_schema}.gold_maintenance_effectiveness me
GROUP BY me.equipment_type
ORDER BY avg_mtbf_days ASC;

-- 3. Open work orders by priority with equipment health context
-- Shows the current work order backlog enriched with equipment
-- health information for prioritization.
SELECT
    wo.work_order_id,
    wo.priority,
    wo.work_order_type,
    wo.title,
    wo.equipment_id,
    eh.equipment_name,
    eh.health_score,
    eh.health_tier,
    eh.criticality,
    wo.store_id,
    wo.created_date,
    wo.scheduled_date,
    wo.assigned_to
FROM ${catalog}.${predops_schema}.work_order wo
LEFT JOIN ${catalog}.${predops_schema}.gold_equipment_health eh
  ON eh.equipment_id = wo.equipment_id
WHERE wo.work_order_status IN ('open', 'in_progress')
ORDER BY
  CASE wo.priority WHEN 'critical' THEN 1 WHEN 'high' THEN 2 WHEN 'medium' THEN 3 ELSE 4 END,
  wo.created_date ASC;

-- 4. Refrigeration downtime events with spoilage risk
-- Identifies refrigeration outages that pose spoilage risk,
-- showing perishable inventory exposure for impact assessment.
SELECT
    di.work_order_id,
    di.equipment_name,
    di.store_name,
    di.criticality,
    di.downtime_hours,
    di.spoilage_risk_tier,
    di.perishable_units_at_risk,
    di.perishable_products_at_risk,
    di.failure_code,
    di.created_date,
    di.completed_date,
    di.actual_cost,
    di.currency_code
FROM ${catalog}.${predops_schema}.gold_downtime_impact di
WHERE di.spoilage_risk_flag = TRUE
ORDER BY di.downtime_hours DESC
LIMIT 20;

-- 5. Overdue maintenance schedules
-- Finds equipment with preventive maintenance past due,
-- prioritized by criticality and days overdue.
SELECT
    ms.equipment_id,
    eq.equipment_name,
    eq.equipment_type,
    eq.criticality,
    eq.store_id,
    ms.schedule_name,
    ms.frequency,
    ms.last_completed_date,
    ms.next_due_date,
    DATEDIFF(CURRENT_DATE(), ms.next_due_date) AS days_overdue
FROM ${catalog}.${predops_schema}.maintenance_schedule ms
JOIN ${catalog}.${equipment_schema}.equipment eq
  ON eq.equipment_id = ms.equipment_id AND eq.is_current = TRUE
WHERE ms.is_current = TRUE
  AND ms.is_active = TRUE
  AND ms.next_due_date < CURRENT_DATE()
ORDER BY
  CASE eq.criticality WHEN 'critical' THEN 1 WHEN 'high' THEN 2 WHEN 'medium' THEN 3 ELSE 4 END,
  days_overdue DESC;

-- ============================================================
-- Store Performance use case — Store Operational Risk Score
-- ============================================================

-- 6. Stores ranked by operational risk (the executive triage view)
-- "Which stores are becoming at-risk?" — the headline Store Performance
-- query. Shows the composite score, tier, and the diagnosing top domains.
-- The score is a HEURISTIC INDEX (0-100), not a probability (ADR 0028).
SELECT
    sor.store_id,
    sor.store_name,
    sor.region,
    sor.operational_risk_score,
    sor.operational_risk_tier,
    sor.top_risk_domains,
    sor.domains_scored,
    sor.inventory_risk,
    sor.supply_chain_risk,
    sor.sales_margin_risk,
    sor.equipment_risk,
    sor.labor_risk
FROM ${catalog}.${predops_schema}.gold_store_operational_risk sor
ORDER BY sor.operational_risk_score DESC NULLS LAST
LIMIT 20;

-- 7. The framework's blind-spot case: stores flagged HIGH+ despite a
-- calm blended score — surfaced by the non-compensatory escalators
-- (any single domain critical, or a steep sales decline). This is the
-- "102% of target but sliding" store traditional reporting misses.
SELECT
    sor.store_id,
    sor.store_name,
    sor.operational_risk_score,
    sor.operational_risk_tier,
    sor.top_risk_domains,
    GREATEST(
      COALESCE(sor.inventory_risk, 0), COALESCE(sor.supply_chain_risk, 0),
      COALESCE(sor.sales_margin_risk, 0), COALESCE(sor.equipment_risk, 0),
      COALESCE(sor.labor_risk, 0)
    ) AS worst_domain_score
FROM ${catalog}.${predops_schema}.gold_store_operational_risk sor
WHERE sor.operational_risk_tier IN ('HIGH', 'CRITICAL')
  AND sor.operational_risk_score < 50   -- blend looks calm, but an escalator fired
ORDER BY worst_domain_score DESC;

-- 8. Regional risk roll-up via the metric view
-- Aggregates the Store Operational Risk Score by region so operations
-- leadership can see where risk is concentrating.
SELECT
    region,
    MEASURE(store_count)                AS store_count,
    MEASURE(high_risk_store_count)      AS high_risk_store_count,
    MEASURE(avg_operational_risk_score) AS avg_operational_risk_score,
    MEASURE(max_operational_risk_score) AS max_operational_risk_score,
    MEASURE(avg_inventory_risk)         AS avg_inventory_risk,
    MEASURE(avg_supply_chain_risk)      AS avg_supply_chain_risk,
    MEASURE(avg_sales_margin_risk)      AS avg_sales_margin_risk,
    MEASURE(avg_equipment_risk)         AS avg_equipment_risk,
    MEASURE(avg_labor_risk)             AS avg_labor_risk
FROM ${catalog}.${predops_schema}.mv_store_risk
GROUP BY region
ORDER BY high_risk_store_count DESC, avg_operational_risk_score DESC;

-- 9. Score history for one store (from the append-only scored-output fact)
-- Trends the store's risk over time and shows whether a currently-healthy
-- store is deteriorating — the leading-vs-lagging distinction.
SELECT
    srs.as_of_date,
    srs.operational_risk_score,
    srs.operational_risk_tier,
    srs.top_risk_domains,
    srs.score_method,
    srs.predicted_impact_amount,
    srs.currency_code
FROM ${catalog}.${predops_schema}.store_risk_score srs
WHERE srs.store_id = 'STORE-0001'   -- replace with a store of interest
ORDER BY srs.as_of_date DESC
LIMIT 30;

-- 10. Workforce demand forecast (next 7 days) by store and role
SELECT
    f.store_id,
    f.role_code,
    f.business_date,
    ROUND(SUM(f.forecast_driver_units), 2) AS driver_units,
    MIN(f.forecast_method) AS forecast_method
FROM ${catalog}.${predops_schema}.gold_workforce_demand_forecast f
WHERE f.business_date BETWEEN current_date() AND date_add(current_date(), 6)
GROUP BY f.store_id, f.role_code, f.business_date
ORDER BY f.store_id, f.role_code, f.business_date
LIMIT 100;

-- 11. Labor requirements vs coverage shortfalls
SELECT
    g.store_id,
    g.role_code,
    g.shortfall_severity,
    COUNT(*) AS intervals,
    ROUND(SUM(g.required_labor_hours), 2) AS required_hours,
    ROUND(SUM(g.shortfall_hours), 2) AS shortfall_hours
FROM ${catalog}.${predops_schema}.gold_workforce_coverage_gap g
WHERE g.business_date BETWEEN current_date() AND date_add(current_date(), 6)
  AND g.shortfall_hours > 0
GROUP BY g.store_id, g.role_code, g.shortfall_severity
ORDER BY shortfall_hours DESC
LIMIT 50;

-- 12. Labor risk triage (feeds Store Operational Risk Score)
SELECT
    lr.store_id,
    lr.labor_risk,
    ROUND(lr.avg_coverage_pct, 3) AS avg_coverage_pct,
    lr.critical_intervals,
    lr.shortfall_hours_7d
FROM ${catalog}.${predops_schema}.gold_labor_risk lr
ORDER BY lr.labor_risk DESC
LIMIT 50;

-- 13. Workforce forecast accuracy (MAPE / bias) when actuals exist
SELECT
    ROUND(AVG(ape), 4) AS forecast_mape,
    ROUND(AVG(forecast_error), 4) AS forecast_bias,
    COUNT(*) AS n_pairs,
    demand_driver
FROM ${catalog}.${predops_schema}.gold_workforce_forecast_accuracy
WHERE actual_driver_units IS NOT NULL
GROUP BY demand_driver
ORDER BY n_pairs DESC;
