-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · In-Store Equipment Maintenance use case
-- Metric View: maintenance_cost
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-07-15
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-29 by @sreekanthmunigati
-- ============================================================
-- Maintenance cost metric: tracks spending on parts, labor, and
-- services. Supports analysis of preventive vs corrective cost
-- allocation and cost-per-asset trends. Current-version equipment
-- attributes are used (not as-of the work order date).
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${predops_schema}.mv_maintenance_cost
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Maintenance cost tracking per work order. Supports cost breakdown by type, equipment, and store."
source: >
  SELECT
    wo.work_order_sk,
    wo.work_order_id,
    wo.equipment_id,
    eq.equipment_name,
    eq.equipment_type,
    wo.store_id,
    st.store_name,
    eq.criticality,
    wo.work_order_type,
    wo.priority,
    wo.actual_cost AS cost_raw,
    wo.actual_duration_hours AS labor_hours_raw,
    wo.currency_code,
    wo.created_date,
    wo.completed_date
  FROM ${catalog}.${predops_schema}.work_order wo
  LEFT JOIN ${catalog}.${equipment_schema}.equipment eq
    ON eq.equipment_id = wo.equipment_id AND eq.is_current = TRUE
  LEFT JOIN ${catalog}.${store_schema}.store st
    ON st.store_sk = wo.store_sk
  WHERE wo.work_order_status = 'completed'

fields:
  - name: work_order_id
    expr: work_order_id
    display_name: "Work Order ID"
    comment: "Durable business key for the work order."
    synonyms: ["wo_id", "work_order", "ticket"]

  - name: equipment_name
    expr: equipment_name
    display_name: "Equipment"
    comment: "Name of the equipment asset."
    synonyms: ["asset", "equipment"]

  - name: equipment_type
    expr: equipment_type
    display_name: "Equipment Type"
    comment: "Category of equipment."
    synonyms: ["type", "asset_type"]

  - name: store_name
    expr: store_name
    display_name: "Store"
    comment: "Store where the maintenance was performed."
    synonyms: ["location", "store"]

  - name: work_order_type
    expr: work_order_type
    display_name: "Maintenance Type"
    comment: "Type of maintenance: preventive, corrective, emergency, inspection."
    synonyms: ["type", "maintenance_category"]

  - name: priority
    expr: priority
    display_name: "Priority"
    comment: "Work order priority: critical, high, medium, low."
    synonyms: ["urgency"]

  - name: currency_code
    expr: currency_code
    display_name: "Currency"
    comment: "ISO currency code for cost amounts."
    synonyms: ["currency"]

  - name: created_date
    expr: created_date
    display_name: "Created Date"
    comment: "Date the work order was created."
    format:
      type: date
      date_format: year_month_day

  - name: completed_date
    expr: completed_date
    display_name: "Completed Date"
    comment: "Date the work order was completed."
    format:
      type: date
      date_format: year_month_day

measures:
  - name: total_cost
    expr: SUM(cost_raw)
    display_name: "Total Cost"
    comment: "Total maintenance cost in base currency."
    synonyms: ["total_spend", "maintenance_spend"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: avg_cost_per_wo
    expr: AVG(cost_raw)
    display_name: "Avg Cost per Work Order"
    comment: "Average cost per completed work order."
    synonyms: ["mean_cost", "cost_per_ticket"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: total_labor_hours
    expr: SUM(labor_hours_raw)
    display_name: "Total Labor Hours"
    comment: "Total labor hours spent on maintenance."
    synonyms: ["labor_hours", "work_hours"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: work_order_count
    expr: COUNT(DISTINCT work_order_id)
    display_name: "Work Orders"
    comment: "Number of completed work orders."
    synonyms: ["wo_count", "ticket_count"]
$$;
