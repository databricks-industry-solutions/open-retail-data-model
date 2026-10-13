-- ============================================================
-- ORDM · Outcome Package · Actionable Customer Understanding
-- View: gold_market_share
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-08-24
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-24 by @saurabhshukla-db
-- License: see repository LICENSE.md
-- ============================================================
-- Serving grain: record_source × market_definition × geography × category × non-total
-- subject × provider period, represented by one stable benchmark_cell_id. Total-category
-- cells supply denominators inside the view but are not published as subject rows.
-- Delivered versions remain append-only in market_benchmark. Current state is latest-wins:
-- provider update timestamp, observation timestamp, load timestamp, then version id.
-- Market share stays separate from category × competitor × fiscal-period competitive
-- position because provider market definitions/geographies are part of its meaning.
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${acu_schema}.gold_market_share AS
WITH ranked_versions AS (
  SELECT
    mb.*,
    ROW_NUMBER() OVER (
      PARTITION BY mb.benchmark_cell_id
      ORDER BY COALESCE(mb.provider_updated_at_ts, mb.observed_at_ts) DESC,
               mb.observed_at_ts DESC,
               mb.load_timestamp DESC,
               mb.market_benchmark_id DESC
    ) AS version_rank
  FROM ${catalog}.${acu_schema}.market_benchmark mb
),
current_cells AS (
  SELECT *
  FROM ranked_versions
  WHERE version_rank = 1
),
market_totals AS (
  SELECT
    record_source,
    market_definition,
    geography_level,
    geography_code,
    category_ref,
    period_type,
    period_end_date,
    sales_amount AS market_size_sales_amount,
    unit_volume AS market_size_unit_volume
  FROM current_cells
  WHERE subject_type = 'total_category'
),
current_with_totals AS (
  SELECT
    c.*,
    t.market_size_sales_amount,
    t.market_size_unit_volume
  FROM current_cells c
  LEFT JOIN market_totals t
    ON c.record_source = t.record_source
   AND c.market_definition = t.market_definition
   AND c.geography_level = t.geography_level
   AND c.geography_code = t.geography_code
   AND c.category_ref = t.category_ref
   AND c.period_type = t.period_type
   AND c.period_end_date = t.period_end_date
),
period_named AS (
  SELECT
    c.*,
    d.competitor_name,
    ROW_NUMBER() OVER (
      PARTITION BY c.benchmark_cell_id
      ORDER BY d.effective_from_date DESC, d.competitor_sk DESC
    ) AS competitor_name_rank
  FROM current_with_totals c
  LEFT JOIN ${catalog}.${bmv_schema}.competitor d
    ON c.competitor_id = d.competitor_id
   AND d.effective_from_date <= c.period_end_date
   AND (d.effective_to_date IS NULL OR d.effective_to_date > c.period_end_date)
)
SELECT
  benchmark_cell_id,
  market_benchmark_id,
  source_observation_id,
  record_source,
  market_definition,
  geography_level,
  geography_code,
  category_ref,
  subject_type,
  subject_id,
  competitor_id,
  competitor_name,
  period_type,
  period_end_date,
  currency_code,

  CAST(sales_amount AS DECIMAL(18,2)) AS market_share_sales_amount,
  CAST(market_size_sales_amount AS DECIMAL(18,2)) AS market_size_sales_amount,
  CAST(unit_volume AS DECIMAL(18,2)) AS subject_unit_volume,
  CAST(market_size_unit_volume AS DECIMAL(18,2)) AS market_size_unit_volume,
  CAST(
    100.0 * sales_amount / NULLIF(market_size_sales_amount, 0)
    AS DOUBLE
  ) AS market_share_pct,
  CAST(period_named.market_share_pct AS DOUBLE) AS provider_reported_market_share_pct,
  CAST(market_growth_rate_pct AS DOUBLE) AS provider_reported_market_growth_rate_pct,
  CAST(eq_volume AS DECIMAL(18,2)) AS eq_volume,
  CAST(acv_weighted_distribution_pct AS DOUBLE) AS acv_weighted_distribution_pct,
  CAST(numeric_distribution_pct AS DOUBLE) AS numeric_distribution_pct,
  CAST(tdp AS DECIMAL(18,4)) AS tdp,
  CAST(promo_sales_amount AS DECIMAL(18,2)) AS promo_sales_amount,
  CAST(base_sales_amount AS DECIMAL(18,2)) AS base_sales_amount,

  is_restatement,
  restates_market_benchmark_id,
  observed_at_ts,
  provider_updated_at_ts,
  load_timestamp,
  'subject_sales_amount_over_total_category_sales_amount' AS market_share_basis,
  'licensed_internal_use_only_by_default' AS license_posture
FROM period_named
WHERE competitor_name_rank = 1
  AND subject_type <> 'total_category'
CLUSTER BY (market_definition, geography_code, category_ref, period_end_date);
