-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Metric View: zone_foot_traffic
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-28
-- ============================================================
-- Footfall, dwell, occupancy and density at ZONE level, one row per zone × trading date.
--
-- ONE LEVEL PER METRIC VIEW, and this is the level where it matters most. Zone footfall does
-- NOT sum to a store total: a shopper traversing five zones is counted five times, so a SUM
-- over zone rows overstates the store by the mean number of zones visited. Keeping the two
-- levels in separate views is what makes that number unaskable rather than merely
-- documented -- see the header of mv_store_foot_traffic for why the earlier single
-- UNION-ALLed view could not enforce it.
--
-- A store total therefore comes from mv_store_foot_traffic. What zone rows ARE good for is
-- comparing zones to each other, ranking them, and dividing by area or capacity.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.mv_zone_foot_traffic
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "In-store footfall, dwell, occupancy and density at ZONE level (one row per zone per trading date). ZONE FOOTFALL DOES NOT SUM TO A STORE TOTAL -- a shopper traversing five zones is counted five times, so use mv_store_foot_traffic for store totals and use this view to compare zones with each other. Aggregate-only and never person-level."
source: >
  SELECT *
  FROM ${catalog}.${css_schema}.gold_zone_traffic_current
  WHERE aggregation_level = 'area'

fields:
  - name: store_id
    expr: store_id
    display_name: "Store"
    comment: "Durable store business key."
    synonyms: ["store", "location", "site", "branch"]

  - name: store_zone_id
    expr: store_zone_id
    display_name: "Zone"
    comment: "Durable in-store zone id."
    synonyms: ["zone", "area", "department", "in_store_area"]

  - name: zone_type
    expr: zone_type
    display_name: "Zone Type"
    comment: "Depth in the spatial hierarchy: entrance, area, department, aisle, bay, shelf_position, queue, fitting_room."
    synonyms: ["zone_kind", "area_type", "space_type"]

  - name: trading_date
    expr: trading_date
    display_name: "Trading Date"
    comment: "Business date of the measurement, derived from the UTC instant plus the store UTC offset."
    synonyms: ["date", "business_date", "day"]

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
  - name: zone_footfall
    expr: SUM(footfall_count)
    display_name: "Zone Footfall"
    comment: "Zone shopper count. Additive over TIME within one zone. NOT additive across zones -- summing zones overstates the store, because one shopper appears in every zone entered."
    synonyms: ["zone_traffic", "zone_visitors", "zone_shoppers"]

  - name: entries
    expr: SUM(entry_count)
    display_name: "Zone Entries"
    comment: "Measured entries into the zone."
    synonyms: ["zone_ins", "arrivals"]

  - name: exits
    expr: SUM(exit_count)
    display_name: "Zone Exits"
    comment: "Measured exits from the zone. NULL for non-directional sensors, which cannot measure them -- not zero."
    synonyms: ["zone_outs", "departures"]

  - name: passersby
    expr: SUM(passersby_count)
    display_name: "Pass-by Traffic"
    comment: "Traffic passing the zone without entering. Interpretation depends on the row's pass-by convention -- vendors define this two opposite ways, one including entrants and one excluding them."
    synonyms: ["outside_traffic", "walk_by", "pass_by"]

  - name: capture_rate
    expr: SUM(footfall_count) / NULLIF(SUM(passersby_count), 0)
    display_name: "Capture Rate"
    comment: "Share of pass-by traffic that entered the zone. Only meaningful where the pass-by convention is uniform across the grouped rows."
    synonyms: ["draw_rate", "pull_in_rate", "walk_in_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: peak_occupancy
    expr: MAX(peak_occupancy)
    display_name: "Peak Occupancy"
    comment: "Highest simultaneous occupancy in the zone. Semi-additive: a MAX over intervals, never a SUM. A store peak comes from mv_store_foot_traffic, not a MAX over zones -- zones peak at different moments."
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
    comment: "Mean dwell time in the zone. Computed from the stored SUM and COUNT so it re-aggregates correctly at any grain -- a pre-computed average could not."
    synonyms: ["dwell_time", "time_in_zone", "linger_time"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 0

  - name: engagement_rate
    expr: SUM(engaged_count) / NULLIF(SUM(dwell_count), 0)
    display_name: "Engagement Rate"
    comment: "Share of dwell observations exceeding the engagement threshold. The denominator is dwell observations, not footfall, because not every counted shopper produces a dwell observation."
    synonyms: ["engaged_share", "interaction_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: avg_daily_footfall_per_sqm
    expr: SUM(footfall_count) / NULLIF(SUM(area_sqm), 0)
    display_name: "Avg Daily Footfall per m2"
    comment: "Traffic density, per zone-DAY. The denominator is the sum of area over the grouped zone-days, so grouping a week of one zone gives that zone's AVERAGE DAILY density, not its weekly total density -- which is why the measure is named for the day. Requires a recorded zone area."
    synonyms: ["traffic_density", "footfall_density", "density"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: area_sqm_days
    expr: SUM(area_sqm)
    display_name: "Area m2-Days"
    comment: "The explicit denominator behind the density measure: zone area summed over the grouped zone-days. Published so the weighting is visible rather than implied."
    synonyms: ["area_days", "density_denominator"]

  - name: peak_capacity_utilisation
    expr: MAX(peak_capacity_utilisation)
    display_name: "Peak Capacity Utilisation"
    comment: "Peak occupancy as a share of the zone's recorded capacity. A MAX, never averaged across zones of different capacity."
    synonyms: ["capacity_used", "utilisation", "crowding"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

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

  - name: interval_count
    expr: SUM(interval_count)
    display_name: "Interval Count"
    comment: "Number of source intervals behind the row. The denominator for coverage questions."
    synonyms: ["intervals", "periods", "observation_count"]
$$;
