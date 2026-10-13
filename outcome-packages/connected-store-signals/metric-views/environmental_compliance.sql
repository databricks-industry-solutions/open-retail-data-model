-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Metric View: environmental_compliance
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-10-05
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-10-05
-- ============================================================
-- Environmental and cold-chain compliance measurement: whether refrigerated stock stayed
-- in range according to the applicable control rules. Aggregates the environmental_compliance
-- daily gold view to answer how many devices are compliant, what the breach rate is, and
-- how readings are distributed across time.
--
-- Source is the daily gold view, so all ratios re-aggregate correctly when rolled up to
-- any coarser grain (store, device, period). The share_intervals_in_range is already a
-- pre-computed ratio carried on the fact, available for binning or filtering; for a rolled-up
-- share use the compliance_rate measure (ratio of sums), not an average of daily shares.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.mv_environmental_compliance
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Environmental and cold-chain compliance: readings in range, breach counts and compliance share against the configured control rule across monitored assets."
source: ${catalog}.${css_schema}.gold_css_environmental_compliance_daily

fields:
  - name: store_id
    expr: store_id
    display_name: "Store"
    comment: "Durable store business key."
    synonyms: ["store", "location", "site", "branch"]

  - name: sensor_device_id
    expr: sensor_device_id
    display_name: "Device"
    comment: "Durable business key of the temperature or environmental sensor."
    synonyms: ["device", "probe", "sensor", "temperature_probe"]

  - name: subject_id
    expr: subject_id
    display_name: "Measured Subject"
    comment: "Measured subject within the device, interpreted per subject_type (for example one case on a multi-channel logger). Slices a multi-channel device by channel."
    synonyms: ["subject", "channel", "monitored_point"]

  - name: equipment_id
    expr: equipment_id
    display_name: "Equipment"
    comment: "Durable business key of the refrigeration or maintained asset the sensor monitors. NULL for ambient sensing."
    synonyms: ["asset", "unit", "equipment", "refrigeration_unit"]

  - name: report_type
    expr: report_type
    display_name: "Report Type"
    comment: "The environmental property measured, e.g. gs1:Temperature. Shared vocabulary with evaluation_rule, so a reading and its rule speak the same language."
    synonyms: ["measurement_type", "sensor_type", "property"]

  - name: trading_date
    expr: trading_date
    display_name: "Trading Date"
    comment: "Business date of the compliance observation."
    synonyms: ["date", "day", "business_date"]

  - name: evaluation_rule_id
    expr: evaluation_rule_id
    display_name: "Rule"
    comment: "Rule the row is evaluated against. Reading and minute measures are per rule: a device watched by two rules contributes its readings once per rule, so filter or group by rule when comparing devices."
    synonyms: ["control_rule", "threshold_rule"]

  - name: condition_operator
    expr: condition_operator
    display_name: "Rule Operator"
    comment: "The comparison the applicable rule applies: greater_than, less_than, inside_range, outside_range, etc."
    synonyms: ["operator", "comparison", "rule_type"]

  - name: threshold_value
    expr: threshold_value
    display_name: "Threshold Value"
    comment: "The lower bound or single threshold from the control rule, in the measurement unit."
    synonyms: ["limit", "setpoint", "threshold"]

  - name: uom_code
    expr: uom_code
    display_name: "Unit"
    comment: "UN/CEFACT Recommendation 20 unit code, e.g. CEL for Celsius."
    synonyms: ["unit", "unit_of_measure"]

  - name: is_compliant
    expr: is_compliant
    display_name: "Compliant"
    comment: "TRUE when no valid reading breached the rule on the day, FALSE when one did, NULL when no rule applies or no valid reading was evaluated."
    synonyms: ["in_range", "meets_threshold", "passes_check"]

measures:
  - name: reading_count
    expr: SUM(reading_count)
    display_name: "Total Readings"
    comment: "Total intervals, counted once per rule: a device watched by two rules contributes its readings twice. Filter or group by evaluation_rule_id for a per-device count."
    synonyms: ["observations", "intervals", "data_points"]

  - name: valid_reading_count
    expr: SUM(valid_reading_count)
    display_name: "Valid Readings"
    comment: "Valid intervals, counted once per rule (see Total Readings). Denominator of the average reading; the compliance rate divides by evaluated intervals."
    synonyms: ["valid_observations", "valid_intervals"]

  - name: min_reading
    expr: MIN(min_value)
    display_name: "Min Reading"
    comment: "Lowest value observed during the day."
    synonyms: ["minimum", "low_point"]

  - name: max_reading
    expr: MAX(max_value)
    display_name: "Max Reading"
    comment: "Highest value observed during the day. For cold-chain, this is the peak excursion."
    synonyms: ["maximum", "peak_reading", "high_point"]

  - name: avg_reading
    expr: SUM(value_sum) / NULLIF(SUM(valid_reading_count_for_avg), 0)
    display_name: "Average Reading"
    comment: "Mean valid reading across the grouping, computed as a ratio of sums so it re-aggregates correctly."
    synonyms: ["mean", "average", "center"]

  - name: breach_count
    expr: SUM(breach_interval_count)
    display_name: "Breaching Intervals"
    comment: "Valid intervals whose value breached the rule limit. Evaluated from readings, independent of automation firings."
    synonyms: ["excursions", "violations", "out_of_range_intervals"]

  - name: minutes_out_of_range
    expr: SUM(minutes_outside_range)
    display_name: "Minutes Out of Range"
    comment: "Minutes beyond the rule limit, summed per rule: minutes where two rules both breach are counted for each rule."
    synonyms: ["breach_duration", "excursion_time"]

  - name: compliance_rate
    expr: 1 - SUM(breach_interval_count) / NULLIF(SUM(evaluated_interval_count), 0)
    display_name: "Compliance Rate"
    comment: "Share of evaluated valid intervals in range across the grouping (ratio of sums, not an average of daily shares)."
    synonyms: ["in_range_rate", "share_in_range"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: compliant_device_rule_days
    expr: COUNT(CASE WHEN is_compliant = TRUE THEN 1 END)
    display_name: "Compliant Device-Rule-Days"
    comment: "Count of device x rule x day rows with is_compliant = TRUE. A device watched by two rules contributes one row per rule."
    synonyms: ["devices_fully_compliant", "compliant_count"]

  - name: breaching_device_rule_days
    expr: COUNT(CASE WHEN is_compliant = FALSE THEN 1 END)
    display_name: "Device-Rule-Days With Breaches"
    comment: "Count of device x rule x day rows with is_compliant = FALSE. A device can appear here for one rule and as compliant for another."
    synonyms: ["devices_with_breaches", "non_compliant_count"]

  - name: compliance_status_known_count
    expr: COUNT(CASE WHEN is_compliant IS NOT NULL THEN 1 END)
    display_name: "Device-Rule-Days Evaluated"
    comment: "Count of device-day-rule rows with a current rule and at least one valid reading (is_compliant is not NULL)."
    synonyms: ["assessed_devices", "devices_with_rules"]
$$;
