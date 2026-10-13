-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- View: gold_external_signals
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-06-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================
-- External macro factors, weather, and footfall confounders.
--
-- Definitions (Macro and Environmental Confounders):
--   local_footfall_index           = Index representing overall traffic volume in the specific store/location.
--   temp_max_celsius               = Maximum recorded temperature for the day at the store location.
--   rainfall_mm                    = Total rainfall in millimeters for the day.
--   is_heatwave                    = Boolean flag triggered when temperatures exceed specific regional thresholds.
--   cpi_category_monthly_index     = The macroeconomic Consumer Price Index specific to the subcategory.
--   fuel_price_index               = Macroeconomic tracking of fuel prices, influencing discretionary spending.
--   is_state_election_day          = Boolean flag for local/state election events impacting shopping behavior.
--   is_major_sporting_event_local  = Boolean flag for local major sporting events driving specific traffic patterns.
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${bmv_schema}.gold_external_signals AS
WITH daily_sales AS (
  SELECT
    product_sk,
    store_sk,
    product_id,
    store_id,
    date_key
  FROM ${catalog}.${bmv_schema}.gold_sales_actuals
),
weather AS (
  -- Placeholder for external weather data
  SELECT 
    store_sk,
    store_id, 
    date_key,
    CAST(NULL AS DECIMAL(5,2)) AS temp_max_celsius,
    CAST(NULL AS DECIMAL(8,2)) AS rainfall_mm,
    CAST(NULL AS BOOLEAN) AS is_heatwave
  FROM daily_sales
  GROUP BY store_sk, store_id, date_key
),
macro AS (
  -- Placeholder for external macroeconomic data
  SELECT 
    date_key,
    CAST(NULL AS DECIMAL(8,4)) AS cpi_category_monthly_index,
    CAST(NULL AS DECIMAL(8,4)) AS fuel_price_index
  FROM daily_sales
  GROUP BY date_key
),
events AS (
  -- Placeholder for external local events data
  SELECT 
    store_sk,
    store_id, 
    date_key,
    CAST(NULL AS BOOLEAN) AS is_state_election_day,
    CAST(NULL AS BOOLEAN) AS is_major_sporting_event_local,
    CAST(NULL AS DECIMAL(8,4)) AS local_footfall_index
  FROM daily_sales
  GROUP BY store_sk, store_id, date_key
)
SELECT
  s.product_sk,
  s.store_sk,
  s.product_id,
  s.store_id,
  CAST(s.date_key AS DATE) AS date_key,

  -- ============================================================
  -- Goal: Price Optimization
  -- ============================================================
  -- (Primarily elastic modelling, but useful for context)
  CAST(e.local_footfall_index AS DECIMAL(8,4)) AS local_footfall_index,

  -- ============================================================
  -- Goal: Elastic Modelling
  -- ============================================================
  CAST(w.temp_max_celsius AS DECIMAL(5,2)) AS temp_max_celsius,
  CAST(w.rainfall_mm AS DECIMAL(8,2)) AS rainfall_mm,
  CAST(w.is_heatwave AS BOOLEAN) AS is_heatwave,
  CAST(m.cpi_category_monthly_index AS DECIMAL(8,4)) AS cpi_category_monthly_index,
  CAST(m.fuel_price_index AS DECIMAL(8,4)) AS fuel_price_index,
  CAST(e.is_state_election_day AS BOOLEAN) AS is_state_election_day,
  CAST(e.is_major_sporting_event_local AS BOOLEAN) AS is_major_sporting_event_local

FROM daily_sales s
LEFT JOIN weather w ON s.store_sk = w.store_sk AND s.date_key = w.date_key
LEFT JOIN macro m ON s.date_key = m.date_key
LEFT JOIN events e ON s.store_sk = e.store_sk AND s.date_key = e.date_key
CLUSTER BY (product_sk, store_sk, date_key);
