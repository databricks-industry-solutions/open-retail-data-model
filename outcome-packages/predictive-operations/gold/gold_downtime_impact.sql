-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · In-Store Equipment Maintenance use case
-- View: gold_downtime_impact
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-15
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-29 by @sreekanthmunigati
-- ============================================================
-- Downtime impact analysis: correlates equipment downtime with
-- product availability and potential spoilage exposure. Links
-- refrigeration/cold-chain equipment failures to inventory at
-- risk, helping operations teams quantify the business impact
-- of equipment outages.
--
-- Spoilage exposure design: inventory_at_risk is scoped to
-- perishable products (category ILIKE '%dairy%' OR '%frozen%'
-- OR '%produce%' OR '%meat%' OR '%deli%') in the
-- affected store. The inventory snapshot uses the latest available
-- date_key on or before the work order's created_date (handles
-- weekends, gaps, or recent events whose snapshot hasn't landed).
-- This is a proxy; adopters should refine the perishable filter
-- to match their product taxonomy.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${predops_schema}.gold_downtime_impact AS
WITH downtime_events AS (
  SELECT
    wo.work_order_sk,
    wo.work_order_id,
    wo.equipment_id,
    wo.store_id,
    wo.work_order_type,
    wo.priority,
    wo.title,
    wo.failure_code,
    wo.created_date,
    wo.completed_date,
    wo.downtime_hours,
    wo.actual_cost,
    wo.currency_code
  FROM ${catalog}.${predops_schema}.work_order wo
  WHERE wo.downtime_hours IS NOT NULL
    AND wo.downtime_hours > 0
    AND wo.work_order_status != 'cancelled'
),
equipment_context AS (
  SELECT
    eq.equipment_id,
    eq.equipment_name,
    eq.equipment_type,
    eq.criticality,
    eq.installation_zone,
    st.store_name
  FROM ${catalog}.${equipment_schema}.equipment eq
  LEFT JOIN ${catalog}.${store_schema}.store st ON st.store_sk = eq.store_sk
  WHERE eq.is_current = TRUE
),
-- For refrigeration equipment, estimate perishable inventory at risk.
-- Scoped to perishable product categories only; the inventory snapshot
-- is aligned to the event date (or latest available).
perishable_inventory AS (
  SELECT
    ip.store_id,
    ip.date_key,
    SUM(ip.units_on_hand_eod) AS perishable_units_at_risk,
    COUNT(DISTINCT ip.product_id) AS perishable_products_at_risk
  FROM ${catalog}.${inventory_schema}.inventory_position ip
  JOIN ${catalog}.${product_schema}.product p
    ON p.product_id = ip.product_id AND p.is_current = TRUE
  WHERE ip.units_on_hand_eod > 0
    AND (p.category ILIKE '%dairy%'
      OR p.category ILIKE '%frozen%'
      OR p.category ILIKE '%produce%'
      OR p.category ILIKE '%meat%'
      OR p.category ILIKE '%deli%')
  GROUP BY ip.store_id, ip.date_key
)
SELECT
  de.work_order_sk,
  de.work_order_id,
  de.equipment_id,
  ec.equipment_name,
  ec.equipment_type,
  ec.criticality,
  ec.installation_zone,
  de.store_id,
  ec.store_name,
  de.work_order_type,
  de.priority,
  de.title,
  de.failure_code,
  de.created_date,
  de.completed_date,
  de.downtime_hours,
  de.actual_cost,
  de.currency_code,
  -- Spoilage risk flag: refrigeration equipment with critical/high criticality
  CASE
    WHEN ec.equipment_type = 'refrigeration' AND ec.criticality IN ('critical', 'high')
    THEN TRUE
    ELSE FALSE
  END AS spoilage_risk_flag,
  -- Perishable inventory exposure (refrigeration only, aligned to event date).
  -- NOTE: this is a per-event store-level snapshot — non-additive across work
  -- orders. Use MAX(perishable_units_at_risk) per store/date, not SUM.
  CASE
    WHEN ec.equipment_type = 'refrigeration'
    THEN pi.perishable_units_at_risk
    ELSE NULL
  END AS perishable_units_at_risk,
  CASE
    WHEN ec.equipment_type = 'refrigeration'
    THEN pi.perishable_products_at_risk
    ELSE NULL
  END AS perishable_products_at_risk,
  -- Spoilage risk tier based on downtime duration
  -- >4h downtime on refrigeration = elevated spoilage risk
  CASE
    WHEN ec.equipment_type = 'refrigeration' AND de.downtime_hours > 4
    THEN 'high'
    WHEN ec.equipment_type = 'refrigeration' AND de.downtime_hours > 2
    THEN 'medium'
    WHEN ec.equipment_type = 'refrigeration'
    THEN 'low'
    ELSE 'none'
  END AS spoilage_risk_tier
FROM downtime_events de
LEFT JOIN equipment_context ec ON ec.equipment_id = de.equipment_id
LEFT JOIN LATERAL (
  SELECT pi2.perishable_units_at_risk, pi2.perishable_products_at_risk
  FROM perishable_inventory pi2
  WHERE pi2.store_id = de.store_id
    AND pi2.date_key <= de.created_date
  ORDER BY pi2.date_key DESC
  LIMIT 1
) pi ON TRUE;
