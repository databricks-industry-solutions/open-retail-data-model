-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- View: gold_oos_preventability
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Classifies OOS episodes as preventable, partially preventable, or not preventable.
--
-- Preventability is judged AS OF the episode start (oos_start_date_key), NOT against
-- today's snapshot. Using the latest gold_inventory_health (which materializes only
-- the most recent date) would classify every historical episode against current
-- on-hand vs reorder point, making the verdict meaningless for any closed episode
-- and identical for every past episode of a product x store. Instead we join:
--   - inventory_position at date_key = oos_start_date_key (position when it happened),
--   - the inventory_policy version EFFECTIVE at oos_start_date_key (the ROP in force),
--   - the most recent forecast_accuracy bias known at oos_start_date_key.
--
-- Reconciliation: oos_event.is_preventable is the stored (source/planner) judgment;
-- preventability_class is this view's derived judgment. Both are surfaced plus a
-- preventability_agrees flag so the two sources of truth are explicit, not silently
-- divergent.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${sdi_schema}.gold_oos_preventability AS
WITH pos_at_start AS (
  -- inventory position on the first day of the episode
  SELECT ip.product_id, ip.store_id, ip.date_key, ip.units_on_hand_eod
  FROM ${catalog}.${inventory_schema}.inventory_position ip
),
policy_at_start AS (
  -- the store_sku inventory policy version effective on the episode start date
  SELECT pu.product_id, pu.store_id, pol.reorder_point_quantity,
         pol.effective_from_date, pol.effective_to_date
  FROM ${catalog}.${sdi_schema}.inventory_policy pol
  JOIN ${catalog}.${sdi_schema}.planning_unit pu
    ON pu.planning_unit_sk = pol.planning_unit_sk
   AND pu.grain_type = 'store_sku'
),
bias_candidates AS (
  -- forecast bias rows, keyed to product x store for an as-of pick per episode
  SELECT pu.product_id, pu.store_id, fac.forecast_date_key, fac.bias_pct
  FROM ${catalog}.${sdi_schema}.forecast_accuracy fac
  JOIN ${catalog}.${sdi_schema}.planning_unit pu
    ON pu.planning_unit_sk = fac.planning_unit_sk
   AND pu.grain_type = 'store_sku'
),
bias_as_of AS (
  -- most recent bias at or before each episode start (Spark-safe window pick,
  -- no correlated subquery)
  SELECT oos_event_id, bias_pct FROM (
    SELECT oe.oos_event_id, bc.bias_pct,
           ROW_NUMBER() OVER (PARTITION BY oe.oos_event_id
                              ORDER BY bc.forecast_date_key DESC) AS rn
    FROM ${catalog}.${sdi_schema}.oos_event oe
    JOIN bias_candidates bc
      ON bc.product_id = oe.product_id AND bc.store_id = oe.store_id
     AND bc.forecast_date_key <= oe.oos_start_date_key
  ) WHERE rn = 1
)
SELECT
  oe.oos_event_id,
  oe.product_id,
  oe.store_id,
  oe.oos_start_date_key,
  oe.oos_cause,
  pos.units_on_hand_eod AS units_on_hand_at_start,
  pol.reorder_point_quantity,
  bias.bias_pct AS forecast_bias_pct_at_start,
  oe.is_preventable AS stored_is_preventable,
  CASE
    WHEN pol.reorder_point_quantity IS NOT NULL AND pos.units_on_hand_eod IS NOT NULL
         AND pos.units_on_hand_eod < pol.reorder_point_quantity THEN 'preventable'
    -- forecast_accuracy.bias_pct is in WHOLE PERCENTAGE POINTS (see its column comment),
    -- so -5 means a 5% under-forecast. This is NOT the 0-1 fractional bias measure that
    -- mv_forecast_accuracy publishes under the same name; do not swap the scales.
    WHEN bias.bias_pct < -5 THEN 'partially_preventable'
    WHEN oe.oos_cause = 'demand_spike' THEN 'not_preventable'
    ELSE 'unknown'
  END AS preventability_class,
  CASE
    WHEN oe.is_preventable IS NULL THEN NULL
    WHEN oe.is_preventable = TRUE
         AND (pol.reorder_point_quantity IS NOT NULL AND pos.units_on_hand_eod IS NOT NULL
              AND pos.units_on_hand_eod < pol.reorder_point_quantity) THEN TRUE
    WHEN oe.is_preventable = FALSE AND oe.oos_cause = 'demand_spike' THEN TRUE
    ELSE FALSE
  END AS preventability_agrees
FROM ${catalog}.${sdi_schema}.oos_event oe
LEFT JOIN pos_at_start pos
  ON pos.product_id = oe.product_id AND pos.store_id = oe.store_id
 AND pos.date_key = oe.oos_start_date_key
LEFT JOIN policy_at_start pol
  ON pol.product_id = oe.product_id AND pol.store_id = oe.store_id
 AND pol.effective_from_date <= oe.oos_start_date_key
 AND (pol.effective_to_date IS NULL OR pol.effective_to_date > oe.oos_start_date_key)
LEFT JOIN bias_as_of bias
  ON bias.oos_event_id = oe.oos_event_id;
