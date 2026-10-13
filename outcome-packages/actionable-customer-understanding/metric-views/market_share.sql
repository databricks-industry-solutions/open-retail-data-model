-- ============================================================
-- ORDM · Outcome Package · Actionable Customer Understanding
-- Metric View: mv_market_share
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-08-24
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-24 by @saurabhshukla-db
-- License: see repository LICENSE.md
-- ============================================================
-- Market share is recomputed from additive subject/total sales amounts. Denominator-only
-- total-category input cells are not exposed by the source gold view. Consumers group by
-- subject when comparing banners/brands; period rollups are market-size-weighted
-- ratio-of-sums rather than averages of provider percentages.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${acu_schema}.mv_market_share
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Current restatement-resolved market share by provider market definition, geography, category, non-total subject and provider period. Total-category inputs are denominator-only and are not served. Licensed benchmark data remains internal-use-only by default."
source: ${catalog}.${acu_schema}.gold_market_share

fields:
  - name: record_source
    expr: record_source
    display_name: "Benchmark Source"
    comment: "Licensed source-system namespace; required to interpret methodology and usage rights."
    synonyms: ["measurement_source", "provider_source"]
  - name: market_definition
    expr: market_definition
    display_name: "Market Definition"
    comment: "Measured store/channel universe supplied by the benchmark source; always display with share."
    synonyms: ["measured_market", "market_universe"]
  - name: geography_level
    expr: geography_level
    display_name: "Geography Level"
    comment: "Provider geography hierarchy level."
    synonyms: ["market_level", "geo_level"]
  - name: geography_code
    expr: geography_code
    display_name: "Geography"
    comment: "Provider or adopter geography identifier at the stated level."
    synonyms: ["market_geography", "geo_code"]
  - name: category_ref
    expr: category_ref
    display_name: "Category"
    comment: "Adopter-owned mapping from the benchmark category to the own merchandising hierarchy."
    synonyms: ["merchandising_category", "benchmark_category"]
  - name: subject_type
    expr: subject_type
    display_name: "Subject Type"
    comment: "Served benchmark subject: own banner, competitor banner, brand, or private label. Total-category cells are denominator-only inputs."
    synonyms: ["share_subject_type", "entity_type"]
  - name: subject_id
    expr: subject_id
    display_name: "Subject"
    comment: "Source identifier for the served non-total subject."
    synonyms: ["banner_or_brand", "share_subject"]
  - name: competitor_id
    expr: competitor_id
    display_name: "Competitor ID"
    comment: "Durable competitor business key when a competitor-banner subject is mapped to BMV identity."
    synonyms: ["rival_id", "competitor"]
  - name: competitor_name
    expr: competitor_name
    display_name: "Competitor Name"
    comment: "Competitor display name effective at provider period end."
    synonyms: ["rival_name", "banner_name"]
  - name: period_type
    expr: period_type
    display_name: "Provider Period Type"
    comment: "Provider period vocabulary; it is not relabeled as an own fiscal period."
    synonyms: ["measurement_period_type", "benchmark_period_type"]
  - name: period_end_date
    expr: period_end_date
    display_name: "Provider Period End"
    comment: "Provider-defined period end date."
    synonyms: ["measurement_period_end", "benchmark_period_end"]
  - name: currency_code
    expr: currency_code
    display_name: "Currency"
    comment: "ISO 4217 reporting/base currency for additive sales measures."
    synonyms: ["reporting_currency", "base_currency"]
  - name: market_share_basis
    expr: market_share_basis
    display_name: "Market Share Basis"
    comment: "Subject sales divided by the matching total-category sales cell."
    synonyms: ["share_basis"]
  - name: license_posture
    expr: license_posture
    display_name: "License Posture"
    comment: "Default usage boundary for licensed benchmark cells and their derivatives."
    synonyms: ["data_usage_posture", "sharing_posture"]

measures:
  - name: market_share_pct
    expr: 100.0 * SUM(market_share_sales_amount) / NULLIF(SUM(market_size_sales_amount), 0)
    display_name: "Market Share %"
    comment: "Subject sales divided by matching total-category sales. Group by subject; period rollups are market-size-weighted ratio-of-sums."
    synonyms: ["share_of_market", "sales_share"]
    format: {type: number, decimal_places: {type: exact, places: 2}}
  - name: market_share_sales_amount
    expr: SUM(market_share_sales_amount)
    display_name: "Subject Sales"
    comment: "Additive measured sales for the selected subject cells."
    synonyms: ["benchmark_subject_sales", "share_numerator"]
    format: {type: number, decimal_places: {type: exact, places: 2}}
  - name: market_size_sales_amount
    expr: SUM(market_size_sales_amount)
    display_name: "Measured Market Sales"
    comment: "Matching total-category sales denominator. Group by subject before combining multiple subjects."
    synonyms: ["benchmark_market_size", "share_denominator"]
    format: {type: number, decimal_places: {type: exact, places: 2}}
  - name: subject_unit_volume
    expr: SUM(subject_unit_volume)
    display_name: "Subject Unit Volume"
    comment: "Additive measured unit volume for the selected subject cells."
    synonyms: ["benchmark_units", "subject_units"]
  - name: benchmark_cell_count
    expr: COUNT(benchmark_cell_id)
    display_name: "Benchmark Cells"
    comment: "Current logical benchmark cells represented by the selected dimensions."
    synonyms: ["market_cell_count", "measurement_cell_count"]
$$;
