-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- View: gold_oos_current
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Ongoing out-of-stock episodes with cumulative lost sales.
--
-- "Current" here means the EPISODE is ongoing (oos_end_date_key IS NULL) — NOT
-- merely that the product x store happens to be stocked out on the latest
-- snapshot. A closed episode must not reappear as current just because an
-- unrelated later stockout exists for the same product x store. The latest
-- snapshot's is_stockout is carried as the separate `is_stocked_out_now` flag
-- for context, never as a membership filter.
--
-- Each one-to-many child (lost_sales_estimate, oos_recovery_action) and the
-- planning-unit segment lookup is PRE-AGGREGATED to one row per join key
-- BEFORE joining, so lost units/revenue are never inflated by the cross-product
-- of independent children (grain: one row per ongoing oos_event).
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${sdi_schema}.gold_oos_current AS
WITH latest_date AS (
  SELECT MAX(date_key) AS max_date FROM ${catalog}.${inventory_schema}.inventory_position
),
inv AS (
  SELECT ip.product_id, ip.store_id, ip.units_on_hand_eod, ip.is_stockout
  FROM ${catalog}.${inventory_schema}.inventory_position ip
  JOIN latest_date ld ON ip.date_key = ld.max_date
),
lost AS (
  SELECT oos_event_sk,
         SUM(lost_units)   AS lost_units_to_date,
         SUM(lost_revenue) AS lost_revenue_to_date
  FROM ${catalog}.${sdi_schema}.lost_sales_estimate
  GROUP BY oos_event_sk
),
recovery AS (
  SELECT oos_event_sk,
         COUNT(DISTINCT oos_recovery_action_id) AS open_recovery_actions
  FROM ${catalog}.${sdi_schema}.oos_recovery_action
  WHERE action_status IN ('recommended', 'approved')
  GROUP BY oos_event_sk
),
segment_ranked AS (
  SELECT planning_unit_sk, abc_class,
         ROW_NUMBER() OVER (PARTITION BY planning_unit_sk ORDER BY fiscal_period_key DESC) AS rn
  FROM ${catalog}.${sdi_schema}.planning_unit_segment
),
pu_seg AS (
  -- one row per product x store: the store_sku planning unit's latest segment
  SELECT product_id, store_id, abc_class FROM (
    SELECT pu.product_id, pu.store_id, s.abc_class,
           ROW_NUMBER() OVER (PARTITION BY pu.product_id, pu.store_id
                              ORDER BY pu.planning_unit_sk) AS rn
    FROM ${catalog}.${sdi_schema}.planning_unit pu
    LEFT JOIN segment_ranked s ON s.planning_unit_sk = pu.planning_unit_sk AND s.rn = 1
    WHERE pu.grain_type = 'store_sku'
  ) WHERE rn = 1
)
SELECT
  oe.oos_event_sk,
  oe.oos_event_id,
  oe.product_id,
  oe.store_id,
  p.product_name,
  st.store_name,
  oe.oos_start_date_key,
  oe.oos_end_date_key,
  oe.oos_duration_days,
  oe.detection_method,
  oe.oos_cause,
  oe.oos_severity,
  oe.is_preventable,
  inv.units_on_hand_eod,
  COALESCE(inv.is_stockout, FALSE) AS is_stocked_out_now,
  COALESCE(lost.lost_units_to_date, 0)   AS lost_units_to_date,
  COALESCE(lost.lost_revenue_to_date, 0) AS lost_revenue_to_date,
  pu_seg.abc_class,
  COALESCE(recovery.open_recovery_actions, 0) AS open_recovery_actions
FROM ${catalog}.${sdi_schema}.oos_event oe
JOIN ${catalog}.${product_schema}.product p ON p.product_id = oe.product_id AND p.is_current = TRUE
JOIN ${catalog}.${store_schema}.store st ON st.store_id = oe.store_id AND st.is_current = TRUE
LEFT JOIN inv ON inv.product_id = oe.product_id AND inv.store_id = oe.store_id
LEFT JOIN lost ON lost.oos_event_sk = oe.oos_event_sk
LEFT JOIN recovery ON recovery.oos_event_sk = oe.oos_event_sk
LEFT JOIN pu_seg ON pu_seg.product_id = oe.product_id AND pu_seg.store_id = oe.store_id
WHERE oe.oos_end_date_key IS NULL;
