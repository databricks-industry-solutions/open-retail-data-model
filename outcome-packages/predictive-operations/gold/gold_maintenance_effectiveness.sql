-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · In-Store Equipment Maintenance use case
-- View: gold_maintenance_effectiveness
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-15
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-29 by @sreekanthmunigati
-- ============================================================
-- Maintenance program effectiveness per equipment: preventive vs
-- corrective ratio, schedule compliance, cost analysis, and MTBF
-- (mean time between failures). Helps operations teams assess
-- whether their preventive maintenance program is effective.
-- Current-version equipment attributes are used (not as-of the
-- work order date); this is intentional for a current-state
-- effectiveness dashboard.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${predops_schema}.gold_maintenance_effectiveness AS
WITH completed_orders AS (
  SELECT
    wo.equipment_id,
    wo.work_order_type,
    wo.actual_cost,
    wo.actual_duration_hours,
    wo.downtime_hours,
    wo.completed_date,
    wo.created_date,
    wo.currency_code
  FROM ${catalog}.${predops_schema}.work_order wo
  WHERE wo.work_order_status = 'completed'
),
wo_stats AS (
  SELECT
    equipment_id,
    COUNT(*) AS total_completed_wo,
    SUM(CASE WHEN work_order_type = 'preventive' THEN 1 ELSE 0 END) AS preventive_count,
    SUM(CASE WHEN work_order_type = 'corrective' THEN 1 ELSE 0 END) AS corrective_count,
    SUM(CASE WHEN work_order_type = 'emergency' THEN 1 ELSE 0 END) AS emergency_count,
    SUM(COALESCE(actual_cost, 0)) AS total_maintenance_cost,
    SUM(CASE WHEN work_order_type = 'preventive' THEN COALESCE(actual_cost, 0) ELSE 0 END) AS preventive_cost,
    SUM(CASE WHEN work_order_type IN ('corrective', 'emergency') THEN COALESCE(actual_cost, 0) ELSE 0 END) AS corrective_cost,
    SUM(COALESCE(actual_duration_hours, 0)) AS total_labor_hours,
    SUM(COALESCE(downtime_hours, 0)) AS total_downtime_hours,
    AVG(DATEDIFF(completed_date, created_date)) AS avg_completion_days,
    MAX(currency_code) AS currency_code
  FROM completed_orders
  GROUP BY equipment_id
),
-- MTBF: mean calendar days between failure occurrences (created_date,
-- not completed_date, to reflect when the failure happened rather than
-- when the repair finished).
failure_intervals AS (
  SELECT
    equipment_id,
    created_date,
    LAG(created_date) OVER (PARTITION BY equipment_id ORDER BY created_date) AS prev_failure_date,
    DATEDIFF(created_date, LAG(created_date) OVER (PARTITION BY equipment_id ORDER BY created_date)) AS days_between_failures
  FROM completed_orders
  WHERE work_order_type IN ('corrective', 'emergency')
),
mtbf AS (
  SELECT
    equipment_id,
    ROUND(AVG(days_between_failures), 1) AS mtbf_days
  FROM failure_intervals
  WHERE days_between_failures IS NOT NULL
  GROUP BY equipment_id
),
schedule_compliance AS (
  SELECT
    ms.equipment_id,
    COUNT(*) AS active_schedules,
    SUM(CASE WHEN ms.next_due_date < CURRENT_DATE() THEN 1 ELSE 0 END) AS overdue_schedules,
    SUM(CASE
      WHEN ms.last_completed_date IS NOT NULL
        AND DATEDIFF(CURRENT_DATE(), ms.last_completed_date) <= ms.interval_days
      THEN 1 ELSE 0
    END) AS on_schedule_count
  FROM ${catalog}.${predops_schema}.maintenance_schedule ms
  WHERE ms.is_current = TRUE
    AND ms.is_active = TRUE
  GROUP BY ms.equipment_id
)
SELECT
  eq.equipment_sk,
  eq.equipment_id,
  eq.equipment_name,
  eq.equipment_type,
  eq.store_id,
  eq.criticality,
  -- Work order summary
  COALESCE(ws.total_completed_wo, 0) AS total_completed_wo,
  COALESCE(ws.preventive_count, 0) AS preventive_count,
  COALESCE(ws.corrective_count, 0) AS corrective_count,
  COALESCE(ws.emergency_count, 0) AS emergency_count,
  -- Preventive vs corrective ratio (higher = more proactive)
  CASE
    WHEN COALESCE(ws.corrective_count, 0) + COALESCE(ws.emergency_count, 0) > 0
    THEN ROUND(CAST(ws.preventive_count AS DOUBLE) / (ws.corrective_count + ws.emergency_count), 2)
    ELSE NULL
  END AS preventive_to_corrective_ratio,
  -- Cost analysis
  COALESCE(ws.total_maintenance_cost, 0) AS total_maintenance_cost,
  COALESCE(ws.preventive_cost, 0) AS preventive_cost,
  COALESCE(ws.corrective_cost, 0) AS corrective_cost,
  COALESCE(ws.total_labor_hours, 0) AS total_labor_hours,
  COALESCE(ws.total_downtime_hours, 0) AS total_downtime_hours,
  ROUND(ws.avg_completion_days, 1) AS avg_completion_days,
  -- MTBF
  m.mtbf_days,
  -- Schedule compliance
  COALESCE(sc.active_schedules, 0) AS active_schedules,
  COALESCE(sc.overdue_schedules, 0) AS overdue_schedules,
  CASE
    WHEN COALESCE(sc.active_schedules, 0) > 0
    THEN ROUND(CAST(sc.on_schedule_count AS DOUBLE) / sc.active_schedules, 3)
    ELSE NULL
  END AS schedule_compliance_rate,
  ws.currency_code
FROM ${catalog}.${equipment_schema}.equipment eq
LEFT JOIN wo_stats ws ON ws.equipment_id = eq.equipment_id
LEFT JOIN mtbf m ON m.equipment_id = eq.equipment_id
LEFT JOIN schedule_compliance sc ON sc.equipment_id = eq.equipment_id
WHERE eq.is_current = TRUE;
