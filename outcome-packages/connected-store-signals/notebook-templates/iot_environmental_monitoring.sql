-- Databricks notebook source
-- MAGIC %md
-- MAGIC # IoT Environmental Monitoring: cold-chain compliance and control-loop responsiveness
-- MAGIC
-- MAGIC Monitor refrigerated-asset compliance against cold-chain thresholds and measure
-- MAGIC control-loop effectiveness. This notebook uses the environmental compliance daily,
-- MAGIC excursion episodes, and rule effectiveness gold views to operationalize compliance
-- MAGIC reporting and automation diagnostics.
-- MAGIC
-- MAGIC Version: 0.5

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 1. Today's compliance status by device

-- COMMAND ----------

SELECT
  store_id,
  sensor_device_id,
  equipment_id,
  report_type,
  trading_date,
  reading_count,
  valid_reading_count,
  min_value,
  max_value,
  avg_value,
  is_compliant,
  breach_interval_count,
  minutes_outside_range,
  share_intervals_in_range,
  condition_operator,
  threshold_value,
  uom_code
FROM ${catalog}.${css_schema}.gold_css_environmental_compliance_daily
WHERE trading_date = (SELECT MAX(trading_date) FROM ${catalog}.${css_schema}.gold_css_environmental_compliance_daily)
ORDER BY
  CASE WHEN is_compliant = FALSE THEN 0 ELSE 1 END,
  share_intervals_in_range ASC,
  store_id,
  sensor_device_id;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2. Recent excursion episodes and response metrics
-- MAGIC
-- MAGIC Episodes still open at the dataset end are flagged separately so ongoing events
-- MAGIC can be distinguished from closed ones.

-- COMMAND ----------

SELECT
  sensor_device_id,
  equipment_id,
  evaluation_rule_id,
  episode_start_ts,
  episode_end_ts,
  trading_date_of_start,
  interval_count,
  duration_minutes,
  peak_value,
  peak_exceedance,
  firings,
  successful_firings,
  failed_firings,
  first_firing_ts,
  minutes_to_first_successful_action,
  has_successful_action,
  is_open_at_dataset_end
FROM ${catalog}.${css_schema}.gold_css_excursion_episodes
WHERE trading_date_of_start >= DATE_SUB((SELECT MAX(trading_date_of_start) FROM ${catalog}.${css_schema}.gold_css_excursion_episodes), 7)
ORDER BY
  is_open_at_dataset_end DESC,
  has_successful_action ASC,
  episode_start_ts DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3. Rule effectiveness: daily automation performance
-- MAGIC
-- MAGIC How many times each rule fired on the latest day, success rates, and responsiveness metrics.

-- COMMAND ----------

SELECT
  trading_date,
  evaluation_rule_id,
  store_id,
  firings,
  successful_firings,
  failed_firings,
  other_status_firings,
  distinct_actions,
  physical_command_firings,
  notification_firings,
  avg_latency_ms,
  max_latency_ms,
  CAST(success_rate_numerator / NULLIF(success_rate_denominator, 0) AS DOUBLE) AS success_rate
FROM ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily
WHERE trading_date = (SELECT MAX(trading_date) FROM ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily) - 1
ORDER BY
  firings DESC,
  success_rate ASC,
  store_id,
  evaluation_rule_id;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 4. Device health cross-check: sensors supporting compliance
-- MAGIC
-- MAGIC Join device health metrics to see if low compliance is correlated with
-- MAGIC sensor issues (stale data, calibration expiry, offline time).

-- COMMAND ----------

WITH device_today AS (
  SELECT DISTINCT
    sensor_device_id,
    store_id,
    equipment_id
  FROM ${catalog}.${css_schema}.gold_css_environmental_compliance_daily
  WHERE trading_date = (SELECT MAX(trading_date) FROM ${catalog}.${css_schema}.gold_css_environmental_compliance_daily)
)
SELECT
  d.store_id,
  d.sensor_device_id,
  d.equipment_id,
  dh.device_type,
  dh.battery_powered,
  dh.calibration_status,
  dh.feed_freshness_status,
  dh.valid_interval_share,
  dh.missing_observation_rate,
  dh.max_latency_seconds,
  dh.avg_uptime_ratio,
  cc.is_compliant,
  cc.share_intervals_in_range
FROM device_today d
LEFT JOIN ${catalog}.${css_schema}.gold_css_device_health dh
  ON d.sensor_device_id = dh.sensor_device_id
  AND dh.trading_date = (SELECT MAX(trading_date) FROM ${catalog}.${css_schema}.gold_css_environmental_compliance_daily)
  AND dh.report_type = 'gs1:Temperature'
LEFT JOIN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily cc
  ON d.sensor_device_id = cc.sensor_device_id
  AND cc.trading_date = (SELECT MAX(trading_date) FROM ${catalog}.${css_schema}.gold_css_environmental_compliance_daily)
  AND cc.report_type = 'gs1:Temperature'
ORDER BY
  dh.feed_freshness_status DESC,
  dh.calibration_status DESC,
  cc.is_compliant ASC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 5. Time to first successful action by episode
-- MAGIC
-- MAGIC For episodes where automation triggered, how quickly did the first successful
-- MAGIC action occur? Long delays may indicate a control-loop tuning issue.

-- COMMAND ----------

SELECT
  sensor_device_id,
  equipment_id,
  trading_date_of_start,
  episode_start_ts,
  episode_end_ts,
  duration_minutes,
  peak_value,
  firings,
  successful_firings,
  first_firing_ts,
  minutes_to_first_successful_action,
  has_successful_action
FROM ${catalog}.${css_schema}.gold_css_excursion_episodes
WHERE has_successful_action = TRUE
  AND trading_date_of_start >= DATE_SUB((SELECT MAX(trading_date_of_start) FROM ${catalog}.${css_schema}.gold_css_excursion_episodes), 30)
ORDER BY
  CASE WHEN minutes_to_first_successful_action IS NULL THEN 1 ELSE 0 END,
  minutes_to_first_successful_action DESC,
  episode_start_ts DESC;
