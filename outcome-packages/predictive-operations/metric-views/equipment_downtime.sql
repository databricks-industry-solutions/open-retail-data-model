-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · In-Store Equipment Maintenance use case
-- Metric View: equipment_downtime
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-07-15
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-29 by @sreekanthmunigati
-- ============================================================
-- Equipment downtime metric: measures total downtime hours and
-- downtime events per asset. Grained at equipment level;
-- aggregatable by store, equipment type, criticality, and time
-- period. Current-version equipment attributes are used
-- (not as-of the work order date).
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${predops_schema}.mv_equipment_downtime
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Equipment downtime measurement. Lower downtime = better asset performance."
source: >
  SELECT
    eq.equipment_sk,
    eq.equipment_id,
    eq.equipment_name,
    eq.equipment_type,
    eq.store_id,
    st.store_name,
    eq.criticality,
    eq.installation_zone,
    eq.equipment_status,
    wo.work_order_id,
    wo.work_order_type,
    wo.downtime_hours AS downtime_hours_raw,
    wo.created_date,
    wo.completed_date
  FROM ${catalog}.${equipment_schema}.equipment eq
  LEFT JOIN ${catalog}.${store_schema}.store st
    ON st.store_sk = eq.store_sk
  LEFT JOIN ${catalog}.${predops_schema}.work_order wo
    ON wo.equipment_id = eq.equipment_id
    AND wo.work_order_status != 'cancelled'
    AND wo.downtime_hours IS NOT NULL
  WHERE eq.is_current = TRUE
    AND eq.equipment_status != 'decommissioned'

fields:
  - name: equipment_id
    expr: equipment_id
    display_name: "Equipment ID"
    comment: "Durable business key for the equipment asset."
    synonyms: ["asset_id", "equipment", "asset"]

  - name: equipment_name
    expr: equipment_name
    display_name: "Equipment Name"
    comment: "Display name of the equipment."
    synonyms: ["asset_name", "name"]

  - name: equipment_type
    expr: equipment_type
    display_name: "Equipment Type"
    comment: "Category: refrigeration, hvac, pos_terminal, self_checkout, oven, etc."
    synonyms: ["type", "asset_type", "category"]

  - name: store_name
    expr: store_name
    display_name: "Store"
    comment: "Name of the store where the equipment is installed."
    synonyms: ["location", "store"]

  - name: criticality
    expr: criticality
    display_name: "Criticality"
    comment: "Impact level if the equipment fails: critical, high, medium, low."
    synonyms: ["priority", "importance"]

  - name: equipment_status
    expr: equipment_status
    display_name: "Status"
    comment: "Current operational status: operational, degraded, out_of_service."
    synonyms: ["status", "operational_status"]

  - name: created_date
    expr: created_date
    display_name: "Work Order Date"
    comment: "Date the associated work order was created."
    format:
      type: date
      date_format: year_month_day

measures:
  - name: total_downtime_hours
    expr: SUM(downtime_hours_raw)
    display_name: "Total Downtime (Hours)"
    comment: "Total equipment downtime in hours across work orders."
    synonyms: ["downtime", "total_downtime", "hours_down"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: avg_downtime_hours
    expr: AVG(downtime_hours_raw)
    display_name: "Avg Downtime per Event (Hours)"
    comment: "Average downtime per maintenance event in hours."
    synonyms: ["mean_downtime", "average_downtime"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: equipment_count
    expr: COUNT(DISTINCT equipment_id)
    display_name: "Equipment Count"
    comment: "Number of distinct equipment assets."
    synonyms: ["total_assets", "num_equipment", "asset_count"]

  - name: downtime_event_count
    expr: COUNT(DISTINCT work_order_id)
    display_name: "Downtime Events"
    comment: "Number of work orders that caused downtime."
    synonyms: ["outage_count", "incident_count"]
$$;
