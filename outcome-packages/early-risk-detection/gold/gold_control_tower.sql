-- ============================================================
-- ORDM · Outcome Package · Early Risk Detection
-- View: gold_control_tower
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-06-30
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-30 by @sreekanthmunigati
-- ============================================================
-- Control tower serving view: a single pane of glass over active
-- disruptions, shipment status, and inventory risk. Joins the
-- disruption_alert lifecycle with shipment current state and
-- inventory position to give the operations team everything they
-- need for triage. Filters to open/acknowledged alerts only.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${risk_schema}.gold_control_tower AS
WITH open_alerts AS (
  SELECT
    da.disruption_alert_sk,
    da.disruption_alert_id,
    da.alert_type,
    da.severity,
    da.alert_status,
    da.alert_title,
    da.alert_description,
    da.assigned_to,
    da.shipment_id,
    da.supplier_id,
    da.product_id,
    da.store_id,
    da.created_timestamp,
    da.acknowledged_timestamp,
    dr.rule_name,
    dr.metric_name,
    dr.threshold_value       AS rule_threshold
  FROM ${catalog}.${risk_schema}.disruption_alert da
  LEFT JOIN ${catalog}.${risk_schema}.disruption_rule dr
    ON da.disruption_rule_sk = dr.disruption_rule_sk
  WHERE da.alert_status IN ('open', 'acknowledged')
),
shipment_state AS (
  SELECT
    shipment_id,
    current_status,
    current_eta_date,
    eta_slip_days,
    transit_elapsed_days,
    planned_transit_days,
    last_event_timestamp,
    last_known_location,
    carrier_name,
    supplier_name
  FROM ${catalog}.${risk_schema}.gold_shipment_current_state
),
inventory AS (
  SELECT
    ip.product_id,
    ip.store_id,
    ip.units_on_hand_eod,
    ip.units_in_transit,
    ip.is_stockout,
    ip.date_key AS inventory_date
  FROM ${catalog}.${inventory_schema}.inventory_position ip
  WHERE ip.date_key = (
    SELECT MAX(date_key) FROM ${catalog}.${inventory_schema}.inventory_position
  )
)
SELECT
  oa.disruption_alert_sk,
  oa.disruption_alert_id,
  oa.alert_type,
  oa.severity,
  oa.alert_status,
  oa.alert_title,
  oa.alert_description,
  oa.assigned_to,
  oa.rule_name,
  oa.metric_name,
  oa.rule_threshold,
  oa.created_timestamp,
  oa.acknowledged_timestamp,
  -- Shipment context
  oa.shipment_id,
  ss.current_status       AS shipment_current_status,
  ss.current_eta_date     AS shipment_current_eta,
  ss.eta_slip_days        AS shipment_eta_slip_days,
  ss.transit_elapsed_days AS shipment_transit_elapsed_days,
  ss.planned_transit_days AS shipment_planned_transit_days,
  ss.last_event_timestamp AS shipment_last_event,
  ss.last_known_location  AS shipment_last_location,
  ss.carrier_name         AS shipment_carrier,
  -- Supplier context
  COALESCE(ss.supplier_name, sup.supplier_name) AS supplier_name,
  oa.supplier_id,
  pr.risk_tier            AS supplier_risk_tier,
  pr.composite_current    AS supplier_composite_score,
  -- Product / inventory context
  oa.product_id,
  oa.store_id,
  inv.units_on_hand_eod   AS inventory_on_hand,
  inv.units_in_transit    AS inventory_in_transit,
  inv.is_stockout         AS inventory_is_stockout
FROM open_alerts oa
LEFT JOIN shipment_state ss ON ss.shipment_id = oa.shipment_id
LEFT JOIN ${catalog}.${supplier_schema}.supplier sup
  ON sup.supplier_id = oa.supplier_id AND sup.is_current = TRUE
LEFT JOIN ${catalog}.${risk_schema}.gold_procurement_risk pr
  ON pr.supplier_id = oa.supplier_id
LEFT JOIN inventory inv
  ON inv.product_id = oa.product_id AND inv.store_id = oa.store_id;
