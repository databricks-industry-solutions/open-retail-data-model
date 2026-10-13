-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_store_traffic_daily_current
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Ideal Lakebase serving projection.
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-28
-- ============================================================
-- GRAIN: one row per store × trading_date.
--
-- ADDITIVITY CONSTRAINT: reads ONLY aggregation_level = 'site' rows. A store total is
-- NOT a SUM over zone rows -- a shopper traversing five zones is counted five times.
-- At least one vendor ships three separate cubes for exactly this reason, and its site-level
-- definition is "main entrance only". No vendor publishes a zone-fusion reconciliation
-- method, because store-level uniqueness requires either entrance-only counting or
-- whole-store re-identification.
--
-- This is the complete operational surface. Valid zero and below-threshold counts stay
-- visible here; disclosure control belongs only to gold_store_traffic_daily_shared.
--
-- Local time is RENDERED here from the UTC instant plus utc_offset_minutes, because the
-- fact deliberately stores no local timestamp -- Databricks TIMESTAMP is TIMESTAMP_LTZ
-- and would shift per reader.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_store_traffic_daily_current AS
WITH daily AS (
  SELECT
    f.store_id,
    f.trading_date,
    -- Additive over intervals WITHIN a level; never across levels.
    SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
             THEN t.footfall_count END) AS footfall_count,
    SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
             THEN t.entry_count END) AS entry_count,
    SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
             THEN t.exit_count END) AS exit_count,
    SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
             THEN t.visitor_count_adjusted END) AS visitor_count_adjusted,
    SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
             THEN t.staff_count END) AS staff_count,
    SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
             THEN t.child_count END) AS child_count,
    -- Semi-additive: a peak is a MAX over intervals, never a SUM.
    MAX(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
             THEN t.occupancy_max END) AS peak_occupancy,
    -- DURATION-WEIGHTED mean, not AVG() of an average: intervals differ in length.
    SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
             THEN t.occupancy_avg * f.interval_minutes END)
      / NULLIF(
          SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
                    AND t.occupancy_avg IS NOT NULL
                   THEN f.interval_minutes ELSE 0 END),
          0
        ) AS avg_occupancy,
    -- Dwell as numerator / denominator so it re-aggregates correctly.
    SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
             THEN t.dwell_seconds_total END) AS dwell_seconds_total,
    SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
             THEN t.dwell_count END) AS dwell_count,
    SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
             THEN t.dwell_seconds_total END)
      / NULLIF(
          SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
                   THEN t.dwell_count END),
          0
        ) AS avg_dwell_seconds,
    -- Generic valid traffic duration plus the measure-specific duration that actually
    -- contributed to avg_occupancy. The two differ when occupancy is not reported.
    SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
             THEN f.interval_minutes ELSE 0 END) AS interval_minutes_total,
    SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
                  AND t.occupancy_avg IS NOT NULL
             THEN f.interval_minutes ELSE 0 END) AS occupancy_interval_minutes_total,
    -- Quality, so a consumer can decide whether to trust the day. DURATION-weighted for the
    -- same reason avg_occupancy is: different canonical series may use different interval
    -- lengths, so a plain AVG can give a short interval the same weight as a long one. A
    -- NULL ratio contributes neither numerator nor denominator: unknown is not zero.
    SUM(f.uptime_ratio * f.interval_minutes)
      / NULLIF(
          SUM(CASE WHEN f.uptime_ratio IS NOT NULL
                   THEN f.interval_minutes ELSE 0 END),
          0
        ) AS avg_uptime_ratio,
    SUM(f.coverage_ratio * f.interval_minutes)
      / NULLIF(
          SUM(CASE WHEN f.coverage_ratio IS NOT NULL
                   THEN f.interval_minutes ELSE 0 END),
          0
        ) AS avg_coverage_ratio,
    SUM(CASE WHEN f.uptime_ratio IS NOT NULL
             THEN f.interval_minutes ELSE 0 END) AS uptime_interval_minutes_total,
    SUM(CASE WHEN f.coverage_ratio IS NOT NULL
             THEN f.interval_minutes ELSE 0 END) AS coverage_interval_minutes_total,
    -- Invalid rows stay in this denominator even though their measures do not enter
    -- traffic totals.
    SUM(CASE WHEN f.measurement_validity = 'valid' THEN 1 ELSE 0 END)
      / NULLIF(COUNT(*), 0) AS valid_interval_share,
    SUM(CASE WHEN f.arrival_completeness = 'complete' THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) AS complete_interval_share,
    MAX(CASE WHEN f.is_imputed THEN 1 ELSE 0 END) = 1 AS has_imputed_intervals,
    SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
             THEN t.footfall_count END) = 0
      AND MAX(CASE WHEN t.is_zero_observed THEN 1 ELSE 0 END) = 1 AS is_zero_observed,
    COUNT(*)                     AS interval_count,
    -- Counting convention must travel with the number. MIN/MAX agree only when the
    -- convention is uniform, which sri_counting_convention_uniform enforces.
    MIN(t.counting_unit)         AS counting_unit,
    MAX(t.staff_exclusion_enabled) AS staff_exclusion_enabled,
    MAX(t.group_counting_enabled)  AS group_counting_enabled,
    MIN(f.time_mode)             AS time_mode
  FROM ${catalog}.${css_schema}.sensor_report_interval f
  JOIN ${catalog}.${css_schema}.foot_traffic_interval_detail t
    ON f.sensor_report_interval_sk = t.sensor_report_interval_sk
  WHERE f.report_type = 'gs1:Count'
    AND f.subject_type = 'space'
    AND f.aggregation_level = 'site'
  GROUP BY f.store_id, f.trading_date
)
SELECT
  d.store_id,
  d.trading_date,

  -- Fiscal calendar context, via the logical date_key join (not an FK -- see
  -- relationships.sql). Enables the PY fiscal-week compare below.
  c.fiscal_year,
  c.fiscal_period,
  c.fiscal_week,
  c.fiscal_week_id,
  c.fiscal_week_index,
  c.day_of_week,
  c.is_holiday,

  d.footfall_count,
  d.entry_count,
  d.exit_count,
  d.visitor_count_adjusted,
  d.staff_count,
  d.child_count,
  d.peak_occupancy,
  d.avg_occupancy,
  d.dwell_seconds_total,
  d.dwell_count,
  d.avg_dwell_seconds,

  -- Prior-year comparison on the FISCAL week and weekday, not the calendar date: retail
  -- compares like trading days (NRF 4-5-4), so a date-minus-364 shortcut misaligns in
  -- 53-week years. Joined on fiscal_week (not fiscal_week_id, which embeds the year and
  -- therefore cannot match across years).
  py.footfall_count AS footfall_count_py,
  d.footfall_count - py.footfall_count AS footfall_delta_py,
  (d.footfall_count - py.footfall_count) / NULLIF(py.footfall_count, 0) AS footfall_growth_py,

  d.counting_unit,
  d.staff_exclusion_enabled,
  d.group_counting_enabled,
  d.time_mode,

  d.avg_uptime_ratio,
  d.avg_coverage_ratio,
  d.valid_interval_share,
  d.complete_interval_share,
  d.has_imputed_intervals,
  d.is_zero_observed,
  d.interval_count,
  d.interval_minutes_total,
  d.occupancy_interval_minutes_total,
  d.uptime_interval_minutes_total,
  d.coverage_interval_minutes_total,

  'site' AS aggregation_level,
  current_timestamp() AS fresh_as_of_ts
FROM daily d
LEFT JOIN ${catalog}.${calendar_schema}.fiscal_calendar c
  ON d.trading_date = c.date_key
LEFT JOIN ${catalog}.${calendar_schema}.fiscal_calendar cpy
  ON cpy.fiscal_year = c.fiscal_year - 1
 AND cpy.fiscal_week = c.fiscal_week
 AND cpy.day_of_week = c.day_of_week
LEFT JOIN daily py
  ON py.store_id = d.store_id
 AND py.trading_date = cpy.date_key;
