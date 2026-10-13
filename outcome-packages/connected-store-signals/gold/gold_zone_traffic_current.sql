-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_zone_traffic_current
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Ideal Lakebase serving projection.
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-28
-- ============================================================
-- GRAIN: one row per store × zone × trading_date.
--
-- ADDITIVITY CONSTRAINT: reads aggregation_level = 'area' rows. These rows DO NOT SUM
-- TO A STORE TOTAL -- a shopper traversing five zones appears in five of them. For a
-- store total use gold_store_traffic_daily_current.
--
-- GRAIN GUARDRAIL: canonical-core sales is product × store × DAY with no zone and no
-- hour, so conversion, capture rate, and sales-per-visitor exist ONLY at store × day.
-- This view therefore exposes traffic, dwell, and occupancy and NEVER conversion.
-- Adding a sales join here would silently allocate store sales across zones.
--
-- SCD2-safe: each interval joins the version-specific store_zone_sk it carried, then
-- versions are consolidated to one durable store_zone_id × trading_date row. Floor area
-- is duration-weighted, so a mid-day refit neither duplicates the zone-day nor applies
-- today's layout to history.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_zone_traffic_current AS
WITH zone_daily AS (
  SELECT
    f.store_id,
    f.store_zone_id,
    f.trading_date,
    CAST(MAX_BY(f.store_zone_sk, f.interval_end_ts) AS BIGINT) AS latest_store_zone_sk,
    CAST(MAX_BY(z.zone_code, f.interval_end_ts) AS STRING) AS zone_code,
    CAST(MAX_BY(z.zone_name, f.interval_end_ts) AS STRING) AS zone_name,
    CAST(MAX_BY(z.zone_type, f.interval_end_ts) AS STRING) AS zone_type,
    CAST(MAX_BY(z.parent_zone_id, f.interval_end_ts) AS STRING) AS parent_zone_id,
    CAST(MAX_BY(z.hierarchy_depth, f.interval_end_ts) AS INT) AS hierarchy_depth,
    CAST(MAX_BY(z.is_sales_floor, f.interval_end_ts) AS BOOLEAN) AS is_sales_floor,
    SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
             THEN t.footfall_count END) AS footfall_count,
    SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
             THEN t.entry_count END) AS entry_count,
    SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
             THEN t.exit_count END) AS exit_count,
    SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
             THEN t.passersby_count END) AS passersby_count,
    MAX(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
             THEN t.occupancy_max END) AS peak_occupancy,
    SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
             THEN t.occupancy_avg * f.interval_minutes END)
      / NULLIF(
          SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
                    AND t.occupancy_avg IS NOT NULL
                   THEN f.interval_minutes ELSE 0 END),
          0
        ) AS avg_occupancy,
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
    SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
             THEN t.engaged_count END) AS engaged_count,
    SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
             THEN t.passing_count END) AS passing_count,
    -- DURATION-weighted, matching avg_occupancy: canonical series can use different
    -- cadences, so a plain AVG can give a short interval the same weight as a long one. A
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
    MIN(t.counting_unit)       AS counting_unit,
    MAX(t.staff_exclusion_enabled) AS staff_exclusion_enabled,
    SUM(z.area_sqm * f.interval_minutes) AS area_sqm_minutes,
    SUM(z.area_sqm * f.interval_minutes)
      / NULLIF(
          SUM(CASE WHEN z.area_sqm IS NOT NULL
                   THEN f.interval_minutes ELSE 0 END),
          0
        ) AS effective_area_sqm,
    SUM(CASE WHEN z.area_sqm IS NOT NULL
             THEN f.interval_minutes ELSE 0 END) AS area_interval_minutes_total,
    SUM(z.capacity_persons * f.interval_minutes)
      / NULLIF(
          SUM(CASE WHEN z.capacity_persons IS NOT NULL
                   THEN f.interval_minutes ELSE 0 END),
          0
        ) AS effective_capacity_persons,
    SUM(CASE WHEN z.capacity_persons IS NOT NULL
             THEN f.interval_minutes ELSE 0 END) AS capacity_interval_minutes_total,
    MAX(
      CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
           THEN t.occupancy_max / NULLIF(z.capacity_persons, 0)
      END
    ) AS peak_capacity_utilisation,
    SUM(CASE WHEN COALESCE(f.measurement_validity, 'valid') <> 'invalid'
             THEN t.footfall_count END) = 0
      AND MAX(CASE WHEN t.is_zero_observed THEN 1 ELSE 0 END) = 1 AS is_zero_observed,
    COUNT(*) AS interval_count,
    SUM(CASE WHEN f.measurement_validity = 'valid' THEN 1 ELSE 0 END)
      / NULLIF(COUNT(*), 0) AS valid_interval_share
  FROM ${catalog}.${css_schema}.sensor_report_interval f
  JOIN ${catalog}.${css_schema}.foot_traffic_interval_detail t
    ON f.sensor_report_interval_sk = t.sensor_report_interval_sk
  JOIN ${catalog}.${css_schema}.store_zone z
    ON f.store_zone_sk = z.store_zone_sk
  WHERE f.report_type = 'gs1:Count'
    AND f.subject_type = 'space'
    AND f.aggregation_level = 'area'
  GROUP BY f.store_id, f.store_zone_id, f.trading_date
)
SELECT
  zd.store_id,
  zd.store_zone_id,
  zd.latest_store_zone_sk,
  zd.zone_code,
  zd.zone_name,
  zd.zone_type,
  zd.parent_zone_id,
  zd.hierarchy_depth,
  zd.is_sales_floor,

  zd.trading_date,
  c.fiscal_year,
  c.fiscal_week_id,
  c.day_of_week,

  zd.footfall_count,
  zd.entry_count,
  zd.exit_count,
  zd.passersby_count,
  zd.peak_occupancy,
  zd.avg_occupancy,
  zd.dwell_seconds_total,
  zd.dwell_count,
  zd.avg_dwell_seconds,
  zd.engaged_count,
  zd.passing_count,

  -- Engagement rate: the share of observations that dwelled past the threshold. The
  -- denominator is the dwell observation count, not footfall, because not every counted
  -- shopper produces a dwell observation.
  zd.engaged_count / NULLIF(zd.dwell_count, 0) AS engagement_rate,

  -- Density measures, which are the reason a zone dimension with area and capacity is
  -- worth having at all. NULLIF guards zones with no recorded area.
  zd.area_sqm_minutes,
  zd.area_interval_minutes_total,
  zd.effective_area_sqm AS area_sqm,
  zd.effective_capacity_persons AS capacity_persons,
  zd.capacity_interval_minutes_total,
  zd.footfall_count / NULLIF(zd.effective_area_sqm, 0) AS footfall_per_sqm,
  zd.avg_occupancy / NULLIF(zd.effective_area_sqm, 0) AS occupancy_per_sqm,
  zd.peak_capacity_utilisation,

  zd.counting_unit,
  zd.staff_exclusion_enabled,
  zd.avg_uptime_ratio,
  zd.avg_coverage_ratio,
  zd.valid_interval_share,
  zd.is_zero_observed,
  zd.interval_count,
  zd.interval_minutes_total,
  zd.occupancy_interval_minutes_total,
  zd.uptime_interval_minutes_total,
  zd.coverage_interval_minutes_total,

  'area' AS aggregation_level,
  current_timestamp() AS fresh_as_of_ts
FROM zone_daily zd
LEFT JOIN ${catalog}.${calendar_schema}.fiscal_calendar c
  ON zd.trading_date = c.date_key;
