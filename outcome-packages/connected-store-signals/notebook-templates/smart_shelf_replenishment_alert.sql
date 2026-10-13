-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Smart Shelf replenishment-alert walkthrough
-- MAGIC
-- MAGIC Start from `gold_shelf_state_current`: the newest capture always wins. Keep unusable
-- MAGIC or stale rows visible as sensing exceptions; do not treat them as available stock.
-- MAGIC This notebook identifies operational candidates only. It creates no task or price action.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 1. Inspect current shelf gaps and low-stock positions

-- COMMAND ----------

SELECT
  store_id,
  store_zone_id,
  product_id,
  shelf_state,
  observed_facing_count,
  min_facing_threshold,
  estimated_unit_count,
  is_gap_detected,
  is_misplaced_detected,
  observation_ts,
  freshness_age_minutes,
  is_stale,
  confidence_score,
  source_capture_id
FROM ${catalog}.${css_schema}.gold_shelf_state_current
WHERE is_usable
  AND NOT is_stale
  AND shelf_state IN ('low_stock', 'out_of_stock')
ORDER BY
  CASE shelf_state WHEN 'out_of_stock' THEN 0 ELSE 1 END,
  observed_facing_count,
  confidence_score DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2. Route unknown or stale positions to sensing triage
-- MAGIC
-- MAGIC These rows are not replenishment candidates yet. A newer unknown/invalid capture is
-- MAGIC current truth and must never be replaced with an older good reading.

-- COMMAND ----------

SELECT
  store_id,
  store_zone_id,
  product_id,
  shelf_state,
  measurement_validity,
  coverage_ratio,
  confidence_score,
  observation_ts,
  freshness_age_minutes,
  is_stale,
  sensor_device_id
FROM ${catalog}.${css_schema}.gold_shelf_state_current
WHERE NOT is_usable OR is_stale
ORDER BY is_stale DESC, freshness_age_minutes DESC, store_id, store_zone_id;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3. Prioritize fresh shelf gaps with same-day book evidence
-- MAGIC
-- MAGIC Positive book stock with a fresh OOS shelf state is a phantom-stock investigation
-- MAGIC candidate. It does not prove units are in the backroom, and it does not update inventory.

-- COMMAND ----------

WITH current_gap AS (
  SELECT
    store_id,
    trading_date,
    store_zone_id,
    product_id,
    shelf_state,
    observed_facing_count,
    min_facing_threshold,
    confidence_score,
    observation_ts
  FROM ${catalog}.${css_schema}.gold_shelf_state_current
  WHERE is_usable
    AND NOT is_stale
    AND shelf_state IN ('low_stock', 'out_of_stock')
)
SELECT
  g.store_id,
  g.trading_date,
  g.store_zone_id,
  g.product_id,
  g.shelf_state,
  g.observed_facing_count,
  g.min_facing_threshold,
  v.observed_units_on_shelf,
  v.book_units_eod,
  v.unit_variance,
  v.is_phantom_stock,
  g.confidence_score,
  g.observation_ts,
  CASE
    WHEN g.shelf_state = 'out_of_stock' AND v.is_phantom_stock THEN 'investigate_backroom_or_record'
    WHEN g.shelf_state = 'out_of_stock' THEN 'replenish_or_verify_inventory'
    ELSE 'replenish_low_stock'
  END AS recommended_triage
FROM current_gap g
LEFT JOIN ${catalog}.${css_schema}.gold_shelf_vs_system_variance_daily v
  ON g.store_id = v.store_id
 AND g.trading_date = v.trading_date
 AND g.product_id = v.product_id
ORDER BY
  CASE
    WHEN g.shelf_state = 'out_of_stock' AND v.is_phantom_stock THEN 0
    WHEN g.shelf_state = 'out_of_stock' THEN 1
    ELSE 2
  END,
  ABS(v.unit_variance) DESC,
  g.confidence_score DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 4. Review open OOS episode duration before operational dispatch

-- COMMAND ----------

SELECT
  store_id,
  store_zone_id,
  product_id,
  episode_start_ts,
  episode_duration_minutes,
  supporting_observation_count,
  supporting_device_count,
  candidate_reason,
  candidate_severity,
  data_quality_flag,
  book_units_eod_at_start
FROM ${catalog}.${css_schema}.gold_observed_oos_episodes
WHERE is_ongoing
ORDER BY episode_duration_minutes DESC, store_id, store_zone_id, product_id;
