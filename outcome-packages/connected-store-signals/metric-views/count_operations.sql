-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Metric View: count_operations
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-08-18
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-19
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.mv_count_operations
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "RFID count execution by store, method and scope: session cadence, duration, observed units and honest full-store zone coverage."
source: ${catalog}.${css_schema}.gold_count_session_summary

fields:
  - name: store_id
    expr: store_id
    display_name: "Store"
    comment: "Durable store business key."
    synonyms: ["store", "site", "location"]

  - name: count_method
    expr: count_method
    display_name: "Count Method"
    comment: "handheld_sweep, fixed_window or robot_sweep."
    synonyms: ["method", "count_type", "reader_mode"]

  - name: scope_type
    expr: scope_type
    display_name: "Scope Type"
    comment: "full_store has a derivable zone plan; partial makes no plan-completion claim."
    synonyms: ["scope", "count_scope"]

  - name: trading_date
    expr: trading_date
    display_name: "Trading Date"
    comment: "Business date on which the count session started."
    synonyms: ["date", "day", "business_date"]

measures:
  - name: count_session_count
    expr: COUNT(DISTINCT rfid_count_session_id)
    display_name: "Count Session Count"
    comment: "Distinct bounded RFID count sessions."
    synonyms: ["counts_completed", "session_count", "count_attempts"]

  - name: average_duration_minutes
    expr: AVG(duration_minutes)
    display_name: "Average Count Duration (Minutes)"
    comment: "Mean elapsed time from session start to end."
    synonyms: ["count_duration", "sweep_duration"]

  - name: units_observed
    expr: SUM(units_observed)
    display_name: "Units Observed"
    comment: "Serialized units observed across count sessions."
    synonyms: ["items_counted", "rfid_units"]

  - name: zones_covered
    expr: SUM(zones_covered)
    display_name: "Zones Covered"
    comment: "Observed zone-session combinations."
    synonyms: ["covered_zones", "zone_counts"]

  - name: full_store_zone_coverage_rate
    expr: SUM(zones_covered) FILTER (WHERE scope_type = 'full_store') / NULLIF(SUM(planned_zones) FILTER (WHERE scope_type = 'full_store'), 0)
    display_name: "Full-Store Zone Coverage"
    comment: "Covered zones divided by active planned zones for full-store sessions only. Partial sessions are excluded."
    synonyms: ["coverage_rate", "count_coverage", "zone_completion"]
    format:
      type: percentage
      decimal_places: {type: exact, places: 1}
$$;
