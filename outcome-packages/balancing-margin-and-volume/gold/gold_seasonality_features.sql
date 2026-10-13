-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- View: gold_seasonality_features
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-06-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================
-- Seasonal and cyclical encodings for baseline models.
--
-- Definitions (Seasonality):
--   month_sin / month_cos          = Cyclical encodings for the calendar month.
--   day_of_year_sin / day_of_year_cos = Cyclical encodings for the day of the year.
--   is_weekend_flag                = Boolean indicating if the date falls on a weekend.
--   is_public_holiday              = Boolean indicating if the date is a public holiday.
--   is_peak_shopping_season        = Boolean indicating if the date falls in a high-demand retail period.
--   days_to_next_holiday           = Days remaining until the next public holiday.
--   days_since_last_holiday        = Days elapsed since the previous public holiday.
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${bmv_schema}.gold_seasonality_features AS
WITH calendar_base AS (
  SELECT
    date_key,
    calendar_month,
    DAYOFYEAR(date_key) AS day_of_year_num,
    is_weekend,
    COALESCE(is_holiday, FALSE) AS is_holiday
  FROM ${catalog}.${calendar_schema}.fiscal_calendar
),
holiday_distances AS (
  SELECT
    date_key,
    calendar_month,
    day_of_year_num,
    is_weekend,
    is_holiday,
    -- Simple mock for peak shopping season (Nov/Dec)
    CASE WHEN calendar_month IN (11, 12) THEN TRUE ELSE FALSE END AS is_peak_shopping_season
  FROM calendar_base
)
SELECT
  CAST(date_key AS DATE) AS date_key,

  -- ============================================================
  -- Goal: Elastic Modelling
  -- ============================================================
  -- Cyclical Encodings
  CAST(SIN(2 * PI() * calendar_month / 12) AS DECIMAL(10,6)) AS month_sin,
  CAST(COS(2 * PI() * calendar_month / 12) AS DECIMAL(10,6)) AS month_cos,
  CAST(SIN(2 * PI() * day_of_year_num / 365) AS DECIMAL(10,6)) AS day_of_year_sin,
  CAST(COS(2 * PI() * day_of_year_num / 365) AS DECIMAL(10,6)) AS day_of_year_cos,

  -- Flags
  CAST(is_weekend AS BOOLEAN) AS is_weekend_flag,
  CAST(is_holiday AS BOOLEAN) AS is_public_holiday,
  CAST(is_peak_shopping_season AS BOOLEAN) AS is_peak_shopping_season,

  -- Proximity Metrics
  CAST(NULL AS INT) AS days_to_next_holiday,
  CAST(NULL AS INT) AS days_since_last_holiday

FROM holiday_distances
CLUSTER BY (date_key);
