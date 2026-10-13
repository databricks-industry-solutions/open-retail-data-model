-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Metric View: on_shelf_availability
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-08-20
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-20
-- ============================================================
-- Reads gold, never the fact (§13). Every ratio is recomputed from summed counts over
-- the gold's unique store × date × category grain, so no grouping can fan-out-inflate
-- it (IoT-review M1 lesson). Availability denominators are KNOWN positions only; the
-- coverage measures publish how much of the expected estate that knowledge covers (H2).
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.mv_on_shelf_availability
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Observed on-shelf availability from shelf sensing: expected-vs-observed positions, OSA %, full-OOS vs low-stock split, intraday floor, and denominator honesty (coverage and known-state rates)."
source: ${catalog}.${css_schema}.gold_osa_daily_current

fields:
  - name: store_id
    expr: store_id
    display_name: "Store"
    comment: "Durable store business key."
    synonyms: ["store", "site", "location"]

  - name: trading_date
    expr: trading_date
    display_name: "Trading Date"
    comment: "Business date of the shelf observations."
    synonyms: ["date", "day", "business_date"]

  - name: category
    expr: category
    display_name: "Category"
    comment: "Merchandising category of the expected product. NULL groups positions whose product carries no category."
    synonyms: ["product_category", "merch_category"]

measures:
  - name: expected_positions
    expr: SUM(expected_positions)
    display_name: "Expected Positions"
    comment: "Shelf positions with an assignment effective on the trading date - the OSA denominator universe."
    synonyms: ["assigned_positions", "planned_positions"]

  - name: observed_positions
    expr: SUM(observed_positions)
    display_name: "Observed Positions"
    comment: "Expected positions with at least one capture that day."
    synonyms: ["covered_positions"]

  - name: positions_unobserved
    expr: SUM(positions_unobserved)
    display_name: "Unobserved Positions"
    comment: "Expected positions with no capture that day - a coverage gap, never counted as available or unavailable."
    synonyms: ["uncovered_positions", "coverage_gap"]

  - name: positions_unknown
    expr: SUM(positions_unknown)
    display_name: "Unknown-State Positions"
    comment: "Observed positions whose day's LAST capture was unknown or invalid. The newest capture wins; an unknown reading is the current truth, never replaced by an older good one."
    synonyms: ["unevaluable_positions"]

  - name: on_shelf_availability_pct
    expr: SUM(positions_available_eod) / NULLIF(SUM(positions_known), 0)
    display_name: "On-Shelf Availability %"
    comment: "Positions in stock or low stock at the day's last known reading, over KNOWN positions only. Unknown and unobserved positions never inflate this."
    synonyms: ["osa", "osa_pct", "availability", "shelf_availability"]
    format:
      type: percentage
      decimal_places: {type: exact, places: 1}

  - name: full_oos_positions
    expr: SUM(positions_oos_eod)
    display_name: "Out-of-Stock Positions"
    comment: "Positions fully out of stock at the day's last known reading. Kept separate from low stock - two failure classes, not one boolean."
    synonyms: ["oos_positions", "stockouts", "empty_positions"]

  - name: low_stock_positions
    expr: SUM(positions_low_stock_eod)
    display_name: "Low-Stock Positions"
    comment: "Positions below their minimum facing threshold but not empty at the day's last known reading."
    synonyms: ["near_oos_positions", "below_min_positions"]

  - name: osa_intraday_floor_pct
    expr: (SUM(positions_known) - SUM(positions_known_oos_any_time)) / NULLIF(SUM(positions_known), 0)
    display_name: "OSA Intraday Floor %"
    comment: "Known positions never observed out of stock at ANY point in the day. The gap between this and end-of-day OSA is the intraday masking a daily average hides."
    synonyms: ["worst_case_osa", "intraday_osa"]
    format:
      type: percentage
      decimal_places: {type: exact, places: 1}

  - name: observation_coverage_pct
    expr: SUM(observed_positions) / NULLIF(SUM(expected_positions), 0)
    display_name: "Observation Coverage %"
    comment: "Share of expected positions captured at least once that day (the compliance-audit-coverage KPI's sensing half)."
    synonyms: ["audit_coverage", "sensing_coverage"]
    format:
      type: percentage
      decimal_places: {type: exact, places: 1}

  - name: known_state_pct
    expr: SUM(positions_known) / NULLIF(SUM(observed_positions), 0)
    display_name: "Known-State %"
    comment: "Share of observed positions whose day's last capture was usable. Publishes the honesty of the OSA denominator."
    synonyms: ["usable_reading_rate", "evaluable_rate"]
    format:
      type: percentage
      decimal_places: {type: exact, places: 1}
$$;
