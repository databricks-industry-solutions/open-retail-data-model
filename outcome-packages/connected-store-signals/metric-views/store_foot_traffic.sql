-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Metric View: store_foot_traffic
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-28
-- ============================================================
-- Footfall, dwell and occupancy at STORE level, one row per store × trading date.
--
-- ONE LEVEL PER METRIC VIEW. An earlier draft UNION-ALLed the site and area gold views into
-- a single mv_foot_traffic and defended the join with a comment saying aggregation_level was
-- "mandatory". That does not hold: a metric view has no way to require a field, so the
-- shortest possible question -- SELECT footfall FROM mv_foot_traffic -- silently returned
-- the store total PLUS every zone total, roughly doubling it. Genie generates exactly that
-- shape of query. Non-additivity across levels has to be enforced by the OBJECT BOUNDARY,
-- not by a comment, so the two levels are now two views and the wrong number is unaskable.
-- The store total lives here; zone detail lives in mv_zone_foot_traffic.
--
-- SOURCED FROM THE GOLD VIEW, not from the shared envelope and traffic extension directly:
-- the object boundary keeps report type and aggregation level structural.
--
-- NO SALES JOIN HERE. sales is product × store × day with no zone and no hour, so
-- traffic-sales productivity belongs in mv_traffic_sales_productivity at store × day only.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.mv_store_foot_traffic
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "In-store footfall, dwell and occupancy at STORE level (one row per store per trading date). Store totals only -- zone detail is in mv_zone_foot_traffic, and the two must never be summed together because footfall does not sum across zones (a shopper traversing five zones is counted five times). Aggregate-only and never person-level."
source: >
  SELECT *
  FROM ${catalog}.${css_schema}.gold_store_traffic_daily_current
  WHERE aggregation_level = 'site'

fields:
  - name: store_id
    expr: store_id
    display_name: "Store"
    comment: "Durable store business key."
    synonyms: ["store", "location", "site", "branch"]

  - name: trading_date
    expr: trading_date
    display_name: "Trading Date"
    comment: "Business date of the measurement, derived from the UTC instant plus the store UTC offset."
    synonyms: ["date", "business_date", "day"]

  - name: fiscal_year
    expr: fiscal_year
    display_name: "Fiscal Year"
    comment: "NRF 4-5-4 fiscal year."
    synonyms: ["retail_year", "year"]

  - name: fiscal_week_id
    expr: fiscal_week_id
    display_name: "Fiscal Week"
    comment: "NRF 4-5-4 week identifier (fiscal_year * 100 + fiscal_week)."
    synonyms: ["retail_week", "week"]

  - name: day_of_week
    expr: day_of_week
    display_name: "Day of Week"
    comment: "ISO day of week (1 = Monday .. 7 = Sunday)."
    synonyms: ["weekday", "dow"]

  - name: counting_unit
    expr: counting_unit
    display_name: "Counting Unit"
    comment: "What one count represents: person, group, device or object. A footfall number is uninterpretable without this -- with group counting enabled, a count is of visitor GROUPS, not people."
    synonyms: ["count_basis", "count_unit"]

  - name: staff_exclusion_enabled
    expr: staff_exclusion_enabled
    display_name: "Staff Excluded"
    comment: "TRUE if staff are excluded from footfall. Rows with different values must not be compared without noting it."
    synonyms: ["excludes_staff", "staff_filtered"]

measures:
  - name: footfall
    expr: SUM(footfall_count)
    display_name: "Footfall"
    comment: "Store shopper count. Additive over time and across stores."
    synonyms: ["traffic", "visitors", "shoppers", "foot_traffic", "visits"]

  - name: entries
    expr: SUM(entry_count)
    display_name: "Entries"
    comment: "Measured entries."
    synonyms: ["traffic_in", "ins", "arrivals"]

  - name: exits
    expr: SUM(exit_count)
    display_name: "Exits"
    comment: "Measured exits. NULL for non-directional sensors, which cannot measure them -- not zero."
    synonyms: ["traffic_out", "outs", "departures"]

  - name: visitors_adjusted
    expr: SUM(visitor_count_adjusted)
    display_name: "Visitors (Staff Excluded)"
    comment: "Count after staff adjustment."
    synonyms: ["net_visitors", "customer_count"]

  - name: staff_count
    expr: SUM(staff_count)
    display_name: "Staff Detections"
    comment: "Staff detections identified and excluded."
    synonyms: ["employees_detected", "associates_detected"]

  - name: peak_occupancy
    expr: MAX(peak_occupancy)
    display_name: "Peak Occupancy"
    comment: "Highest simultaneous occupancy in the store. Semi-additive: a MAX over intervals, never a SUM."
    synonyms: ["max_occupancy", "peak_people", "busiest"]

  - name: avg_occupancy
    expr: SUM(avg_occupancy * occupancy_interval_minutes_total) / NULLIF(SUM(occupancy_interval_minutes_total), 0)
    display_name: "Average Occupancy"
    comment: "Mean simultaneous occupancy, weighted by canonical interval duration. Never average interval averages without their durations."
    synonyms: ["mean_occupancy", "typical_occupancy"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: avg_dwell_seconds
    expr: SUM(dwell_seconds_total) / NULLIF(SUM(dwell_count), 0)
    display_name: "Average Dwell (Seconds)"
    comment: "Mean dwell time. Computed from the stored SUM and COUNT so it re-aggregates correctly at any grain -- a pre-computed average could not."
    synonyms: ["dwell_time", "time_in_store", "linger_time"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 0

  - name: uptime
    expr: SUM(avg_uptime_ratio * uptime_interval_minutes_total) / NULLIF(SUM(uptime_interval_minutes_total), 0)
    display_name: "Sensor Uptime"
    comment: "Mean share of the interval the sensors were online, weighted by interval MINUTES so a 15-minute outage does not carry the same weight as an hour-long one. Read this before trusting a low count."
    synonyms: ["availability", "sensor_uptime", "online_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: avg_coverage
    expr: SUM(avg_coverage_ratio * coverage_interval_minutes_total) / NULLIF(SUM(coverage_interval_minutes_total), 0)
    display_name: "Sensor Coverage"
    comment: "Mean share of expected sensors that reported, weighted by interval MINUTES. A low value means the count is partial, not low."
    synonyms: ["coverage", "reporting_rate", "completeness"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: valid_interval_share
    expr: SUM(valid_interval_share * interval_count) / NULLIF(SUM(interval_count), 0)
    display_name: "Valid Interval Share"
    comment: "Share of intervals whose measurement was valid. Orthogonal to arrival completeness -- a sensor can be complete but invalid."
    synonyms: ["data_quality", "validity_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: interval_count
    expr: SUM(interval_count)
    display_name: "Interval Count"
    comment: "Number of source intervals behind the row. The denominator for coverage questions."
    synonyms: ["intervals", "periods", "observation_count"]
$$;
