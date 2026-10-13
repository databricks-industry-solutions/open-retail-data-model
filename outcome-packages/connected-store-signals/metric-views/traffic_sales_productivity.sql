-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Metric View: traffic_sales_productivity
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-28
-- ============================================================
-- Traffic against sales at store × day -- the only grain where they can legitimately
-- meet, since canonical-core.transaction.sales is product × store × DAY with no zone
-- and no hour.
--
-- The honest measures name their observed denominator: entry for directional counters,
-- footfall for all people counters. Neither is a transaction conversion rate.
-- A conversion rate remains absent until canonical transaction or receipt count exists.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.mv_traffic_sales_productivity
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Store-day traffic against sales. Publishes sales and units per entry; no conversion rate is exposed until ORDM has canonical transaction or receipt count."
source: ${catalog}.${css_schema}.gold_traffic_sales_productivity_current

fields:
  - name: store_id
    expr: store_id
    display_name: "Store"
    comment: "Durable store business key."
    synonyms: ["store", "location", "site", "branch"]

  - name: trading_date
    expr: trading_date
    display_name: "Trading Date"
    comment: "Business date."
    synonyms: ["date", "business_date", "day"]

  - name: fiscal_year
    expr: fiscal_year
    display_name: "Fiscal Year"
    comment: "NRF 4-5-4 fiscal year."
    synonyms: ["retail_year", "year"]

  - name: fiscal_week_id
    expr: fiscal_week_id
    display_name: "Fiscal Week"
    comment: "NRF 4-5-4 week identifier."
    synonyms: ["retail_week", "week"]

  - name: day_of_week
    expr: day_of_week
    display_name: "Day of Week"
    comment: "ISO day of week (1 = Monday .. 7 = Sunday)."
    synonyms: ["weekday", "dow"]

  - name: is_holiday
    expr: is_holiday
    display_name: "Holiday"
    comment: "TRUE on a recognised retail holiday. Traffic comparisons across a holiday boundary are not like-for-like."
    synonyms: ["holiday_flag", "is_bank_holiday"]

  - name: promo_active_flag
    expr: promo_active_flag
    display_name: "Promotion Active"
    comment: "TRUE if any product at the store-day carried a real promotion (the NO_PROMO sentinel is excluded)."
    synonyms: ["on_promo", "promotion_running", "promo"]

  - name: counting_unit
    expr: counting_unit
    display_name: "Counting Unit"
    comment: "What one count represents: person, group, device or object."
    synonyms: ["count_basis", "count_unit"]

measures:
  - name: visits
    expr: SUM(entry_count)
    display_name: "Visits"
    comment: "Store entries -- the denominator for every per-visitor measure here."
    synonyms: ["traffic", "visitors", "entries", "footfall"]

  - name: net_sales
    expr: SUM(net_revenue)
    display_name: "Net Sales"
    comment: "Net revenue after discount, in the single reporting currency."
    synonyms: ["revenue", "sales", "net_revenue", "turnover"]

  - name: gross_sales
    expr: SUM(gross_revenue)
    display_name: "Gross Sales"
    comment: "Revenue before promotional discount."
    synonyms: ["gross_revenue", "gross"]

  - name: units_sold
    expr: SUM(units)
    display_name: "Units Sold"
    comment: "Units sold. NOTE this is an ITEM count, not a basket count -- which is exactly why it cannot stand in as the conversion numerator."
    synonyms: ["units", "quantity", "items_sold"]

  - name: sales_per_entry
    expr: SUM(net_revenue) / NULLIF(SUM(entry_count), 0)
    display_name: "Sales per Entry"
    comment: "Net revenue divided by measured entries."
    synonyms: ["revenue_per_entry", "spend_per_entry"]

  - name: units_per_entry
    expr: SUM(units) / NULLIF(SUM(entry_count), 0)
    display_name: "Units per Entry"
    comment: "Units divided by entries."
    synonyms: ["items_per_entry", "quantity_per_entry"]

  - name: sales_per_footfall
    expr: SUM(net_revenue) / NULLIF(SUM(footfall_count), 0)
    display_name: "Sales per Footfall"
    comment: "Net revenue divided by measured footfall. Available when entry direction is not observed."
    synonyms: ["revenue_per_footfall", "spend_per_footfall"]

  - name: units_per_footfall
    expr: SUM(units) / NULLIF(SUM(footfall_count), 0)
    display_name: "Units per Footfall"
    comment: "Units divided by measured footfall. Items are not transactions."
    synonyms: ["items_per_footfall", "quantity_per_footfall"]

  - name: avg_dwell_seconds
    expr: SUM(dwell_seconds_total) / NULLIF(SUM(dwell_count), 0)
    display_name: "Average Dwell (Seconds)"
    comment: "Mean dwell time, recomputed from the stored SUM and COUNT so it re-aggregates correctly at any grain. Not AVG(avg_dwell_seconds), which would average averages and give a near-empty store-day the same weight as a busy one."
    synonyms: ["dwell_time", "time_in_store"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 0

  - name: peak_occupancy
    expr: MAX(peak_occupancy)
    display_name: "Peak Occupancy"
    comment: "Highest simultaneous occupancy. Semi-additive -- a MAX, never a SUM."
    synonyms: ["max_occupancy", "busiest"]

  - name: traffic_vs_py
    expr: (SUM(footfall_count) - SUM(footfall_count_py)) / NULLIF(SUM(footfall_count_py), 0)
    display_name: "Traffic vs Prior Year"
    comment: "Footfall growth against the equivalent NRF fiscal week and weekday last year, not a calendar date shift."
    synonyms: ["traffic_growth", "yoy_traffic", "footfall_growth"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: discount_rate
    expr: SUM(discount_amount) / NULLIF(SUM(gross_revenue), 0)
    display_name: "Discount Rate"
    comment: "Promotional discount as a share of gross revenue. Pairs with promo_active_flag to read traffic lift against margin cost."
    synonyms: ["markdown_rate", "promo_depth"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: avg_coverage
    expr: SUM(avg_coverage_ratio * coverage_interval_minutes_total) / NULLIF(SUM(coverage_interval_minutes_total), 0)
    display_name: "Sensor Coverage"
    comment: "Mean share of expected sensors reporting, weighted by interval MINUTES so a store-day with little observed time cannot outvote a full one. A low-coverage day must not be compared against a complete one."
    synonyms: ["coverage", "completeness"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: store_day_count
    expr: COUNT(*)
    display_name: "Store Days"
    comment: "Number of store-days in the grouping."
    synonyms: ["days", "observation_count"]
$$;
