-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Foot Traffic Analysis walkthrough
-- MAGIC
-- MAGIC Store traffic is NOT a sum of zone traffic. A shopper traversing five zones is counted
-- MAGIC five times in zone footfall but once in store footfall. Use `aggregation_level` to select
-- MAGIC the right grain. Device health matters: check uptime, coverage, and freshness before
-- MAGIC trusting a low count.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 1. Store daily traffic and prior-year comparison

-- COMMAND ----------

SELECT
  store_id,
  trading_date,
  day_of_week,
  footfall_count,
  entry_count,
  exit_count,
  peak_occupancy,
  avg_occupancy,
  avg_dwell_seconds,
  footfall_count_py,
  footfall_growth_py,
  counting_unit,
  staff_exclusion_enabled,
  avg_coverage_ratio,
  valid_interval_share
FROM ${catalog}.${css_schema}.gold_store_traffic_daily_current
WHERE trading_date >= current_date() - INTERVAL 28 DAYS
ORDER BY store_id, trading_date DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2. Zone ranking by traffic density, not raw count
-- MAGIC
-- MAGIC Zone footfall is NOT additive across zones. Rank by traffic density (footfall per
-- MAGIC square meter) or engagement rate instead.

-- COMMAND ----------

SELECT
  store_id,
  store_zone_id,
  zone_name,
  zone_type,
  SUM(footfall_count) AS total_footfall,
  SUM(area_sqm * interval_minutes_total) / NULLIF(SUM(interval_minutes_total), 0) AS avg_area_sqm,
  SUM(footfall_count) / NULLIF(SUM(area_sqm * interval_minutes_total) / NULLIF(SUM(interval_minutes_total), 0), 0) AS footfall_per_sqm,
  SUM(dwell_seconds_total) / NULLIF(SUM(dwell_count), 0) AS avg_dwell_seconds,
  SUM(engaged_count) / NULLIF(SUM(dwell_count), 0) AS engagement_rate,
  COUNT(*) AS days_observed
FROM ${catalog}.${css_schema}.gold_zone_traffic_current
WHERE trading_date >= current_date() - INTERVAL 14 DAYS
GROUP BY store_id, store_zone_id, zone_name, zone_type
ORDER BY store_id, footfall_per_sqm DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3. Sales productivity: revenue and units per entry (or per footfall)
-- MAGIC
-- MAGIC Entry-based measures (per_entry) are preferred when entry direction is observable.
-- MAGIC Fall back to footfall-based measures when directionality is unavailable.
-- MAGIC Conversion rate is intentionally absent per design decision D3.

-- COMMAND ----------

SELECT
  store_id,
  trading_date,
  entry_count,
  footfall_count,
  units,
  net_revenue,
  CASE WHEN entry_count > 0
       THEN net_revenue / entry_count ELSE NULL END AS sales_per_entry,
  CASE WHEN entry_count > 0
       THEN units / entry_count ELSE NULL END AS units_per_entry,
  CASE WHEN footfall_count > 0
       THEN net_revenue / footfall_count ELSE NULL END AS sales_per_footfall,
  CASE WHEN footfall_count > 0
       THEN units / footfall_count ELSE NULL END AS units_per_footfall,
  promo_active_flag,
  active_promo_count
FROM ${catalog}.${css_schema}.gold_traffic_sales_productivity_current
WHERE trading_date >= current_date() - INTERVAL 14 DAYS
ORDER BY store_id, trading_date DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 4. Device quality: uptime, coverage, and freshness
-- MAGIC
-- MAGIC A low footfall count with degraded coverage might be a sensor outage, not low traffic.
-- MAGIC Check the quality fields before investigating or acting on traffic anomalies.

-- COMMAND ----------

SELECT
  store_id,
  device_type,
  trading_date,
  COUNT(DISTINCT sensor_device_id) AS devices,
  SUM(observations_received) / NULLIF(SUM(observations_expected), 0) AS observation_capture_rate,
  AVG(avg_uptime_ratio) AS mean_uptime_ratio,
  AVG(avg_coverage_ratio) AS mean_coverage_ratio,
  SUM(sequence_gap_count) AS lost_messages,
  SUM(duplicate_delivery_count) AS duplicate_deliveries,
  SUM(capped_intervals) AS detection_ceiling_hits,
  COUNT(DISTINCT sensor_device_id)
    FILTER (WHERE feed_freshness_status = 'stale') AS stale_devices
FROM ${catalog}.${css_schema}.gold_css_device_health
WHERE trading_date >= current_date() - INTERVAL 7 DAYS
GROUP BY store_id, device_type, trading_date
ORDER BY store_id, trading_date DESC, mean_coverage_ratio;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 5. Verify shared view respects suppression policy
-- MAGIC
-- MAGIC The shared views apply k-threshold and dependent-measure suppression. Ensure
-- MAGIC shared rows are not double-suppressed if publishing externally.

-- COMMAND ----------

SELECT
  store_id,
  trading_date,
  footfall_count,
  entry_count,
  peak_occupancy,
  avg_occupancy,
  disclosure_suppressed_flag,
  sensing_disclosure_policy_id
FROM ${catalog}.${css_schema}.gold_store_traffic_daily_shared
WHERE trading_date >= current_date() - INTERVAL 7 DAYS
  AND disclosure_suppressed_flag = TRUE
ORDER BY store_id, trading_date DESC;
