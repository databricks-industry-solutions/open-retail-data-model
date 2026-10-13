-- ============================================================
-- ORDM · Canonical Core · Calendar domain · data-quality checks
-- Version: 0.5 · Generated: 2026-07-06 · LLM-generated: true · Reviewed: 2026-07-06
-- Each assertion SELECTs violating rows; 0 rows = PASS.
-- ============================================================

-- check: calendar_keys_not_null | severity: error
SELECT * FROM ${catalog}.${calendar_schema}.fiscal_calendar
WHERE date_sk IS NULL OR date_key IS NULL OR date_id IS NULL
   OR fiscal_week_id IS NULL OR fiscal_week_index IS NULL;

-- check: calendar_date_unique | severity: error
SELECT date_key, COUNT(*) AS rows
FROM ${catalog}.${calendar_schema}.fiscal_calendar
GROUP BY date_key
HAVING COUNT(*) > 1;

-- check: calendar_fiscal_ranges | severity: error
-- NRF 4-5-4 bounds: week 1-53, quarter 1-4, period 1-12.
SELECT * FROM ${catalog}.${calendar_schema}.fiscal_calendar
WHERE fiscal_week NOT BETWEEN 1 AND 53
   OR fiscal_quarter NOT BETWEEN 1 AND 4
   OR fiscal_period NOT BETWEEN 1 AND 12;

-- check: calendar_fiscal_season_matches_period | severity: error
-- fiscal_season is derived from fiscal_period: spring = periods 1-6 (H1), fall = 7-12 (H2).
-- Catches a season that disagrees with its period (derivation drift), plus any value
-- outside the two-season domain.
SELECT * FROM ${catalog}.${calendar_schema}.fiscal_calendar
WHERE fiscal_season IS NOT NULL
  AND ( fiscal_season NOT IN ('spring', 'fall')
     OR (fiscal_season = 'spring' AND fiscal_period NOT BETWEEN 1 AND 6)
     OR (fiscal_season = 'fall'   AND fiscal_period NOT BETWEEN 7 AND 12) );

-- check: calendar_week_date_order | severity: warn
SELECT * FROM ${catalog}.${calendar_schema}.fiscal_calendar
WHERE fiscal_week_end_date < fiscal_week_start_date;

-- check: calendar_weeks_per_year_4_5_4 | severity: warn
-- NRF 4-5-4 allows 52 or 53 weeks per fiscal year. This flags any fiscal year
-- with MORE than 53 weeks (a calendar bug). Partial leading/trailing years in a
-- bounded synthetic span are expected and not flagged. NOTE: the synthetic
-- generator models 52-week years only (no NRF 53rd leap week) — see
-- runtime/synthetic-data/generators/trade_promotion.py.
SELECT fiscal_year, COUNT(DISTINCT fiscal_week) AS weeks_in_year
FROM ${catalog}.${calendar_schema}.fiscal_calendar
GROUP BY fiscal_year
HAVING COUNT(DISTINCT fiscal_week) > 53;

-- ------------------------------------------------------------
-- fx_rate (currency-normalization reference)
-- ------------------------------------------------------------

-- check: fx_rate_keys_not_null | severity: error
SELECT * FROM ${catalog}.${calendar_schema}.fx_rate
WHERE fx_rate_sk IS NULL OR fx_rate_id IS NULL OR date_key IS NULL
   OR from_currency_code IS NULL OR to_currency_code IS NULL OR rate IS NULL;

-- check: fx_rate_id_unique | severity: error
-- One rate per (date, from, to).
SELECT date_key, from_currency_code, to_currency_code, COUNT(*) AS rows
FROM ${catalog}.${calendar_schema}.fx_rate
GROUP BY date_key, from_currency_code, to_currency_code
HAVING COUNT(*) > 1;

-- check: fx_rate_positive | severity: error
-- FX rates must be strictly positive.
SELECT * FROM ${catalog}.${calendar_schema}.fx_rate
WHERE rate <= 0;

-- check: fx_rate_base_self_rate | severity: error
-- The base->base self-rate must be exactly 1 (identity conversion).
SELECT * FROM ${catalog}.${calendar_schema}.fx_rate
WHERE from_currency_code = to_currency_code AND rate <> 1;

-- check: fx_rate_calendar_coverage | severity: warn
-- Every rate date should exist in the fiscal calendar.
SELECT fx.date_key FROM ${catalog}.${calendar_schema}.fx_rate fx
LEFT JOIN ${catalog}.${calendar_schema}.fiscal_calendar c ON fx.date_key = c.date_key
WHERE c.date_key IS NULL
GROUP BY fx.date_key;

-- check: fx_rate_single_base | severity: error
-- The canonical core normalizes to ONE reporting currency: every row must
-- convert TO the same base currency.
SELECT COUNT(DISTINCT to_currency_code) AS distinct_base
FROM ${catalog}.${calendar_schema}.fx_rate
HAVING COUNT(DISTINCT to_currency_code) > 1;
