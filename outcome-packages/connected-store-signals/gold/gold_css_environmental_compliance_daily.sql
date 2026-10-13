-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_css_environmental_compliance_daily
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Ideal Lakebase serving projection.
-- Version: 0.5
-- Generated: 2026-10-05
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-10-05
-- GRAIN: one row per store × sensor_device × measured subject (subject_type, subject_id) ×
-- equipment × report_type × current
-- evaluation_rule × trading_date. A device-property pair with no current rule yields one
-- row with evaluation_rule_id NULL and is_compliant NULL; a pair watched by two rules
-- (for example a high and a low limit) yields one row per rule.
--
-- Answers: for a device reporting a monitored property on a given day, did its valid
-- readings stay within the applicable rule? Only report types that some evaluation_rule
-- watches are included, so footfall counts never land here.
--
-- BREACH DEFINITION: a valid interval breaches when its value satisfies the rule firing
-- condition (condition_operator against threshold_value_numeric / threshold_value_upper).
-- This is evaluated from the readings, not inferred from execution_log, so compliance does
-- not depend on whether automation fired. gold_css_excursion_episodes uses the same
-- predicate; keep the two in sync. time_window_seconds (sustained-breach window) is carried
-- for context but not applied: a single breaching interval counts.
--
-- SERIES: one canonical series per device x property is read (device level, else
-- subject level, at the finest cadence), so rollups across levels never double-count.
-- One series is kept per device x property, not per subject: on a multi-channel device
-- whose subjects report the same property at different cadences, only the subjects on
-- the chosen (finest) cadence are evaluated; a subject at a coarser cadence drops out.
-- The choice is made once per device x property over ALL history, not per day: if a
-- device later changes cadence (for example a firmware move from 15 to 5 minutes) or
-- reporting level, its earlier readings fall outside the chosen series and drop out of
-- both IoT views. iot_series_excluded_valid_intervals counts every valid interval left
-- out: a coarser cadence, a lower-priority aggregation level, or a subject id absent
-- from the chosen series. iot_series_history_loss_intervals counts only the part from
-- subjects that also have rows on the chosen series (their own cadence or level
-- changed). Keep this choice identical in both views:
-- iot_breach_episode_reconciliation depends on it.
-- Rows are per rule, so reading and minute totals summed across rules count a reading
-- once per rule; group by evaluation_rule_id for per-device totals.
--
-- RULE SCOPE: only device-scoped rules (non-NULL sensor_device_sk) are evaluated. A rule
-- over a cross-device aggregate (NULL device, readings on the _ALL series) matches no
-- reading here; iot_cross_device_rules_unevaluated counts such rules. Rules carry no
-- subject or equipment scope, so every rule on a device applies to all of its subjects:
-- results are correct only when every subject on a device shares the same limits.
-- iot_multi_subject_ruled_series counts the device x property series where that matters.
--
-- UNITS: a rule whose uom_code differs from the reading uom is not evaluated (the interval
-- counts as not evaluated, never as a pass or a breach); ecd_rule_reading_uom_mismatch
-- reports it. A NULL unit on either side (rule or reading) is treated as compatible.
--
-- VALIDITY: reading_count counts every interval; all value statistics, the breach count
-- and the compliance share use measurement_validity = 'valid' intervals only. A NULL
-- validity is treated as not valid, the same as gold_css_excursion_episodes.
--
-- SCD2 JOIN DISCIPLINE (§A.16): evaluation_rule is an SCD2 master and this view joins its
-- CURRENT enabled version, answering "is the asset in spec with today's rule". Historical
-- as-of evaluation would use the rule version each execution_log firing carries.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_css_environmental_compliance_daily AS
WITH current_rules AS (
  SELECT
    er.sensor_device_id,
    er.report_type,
    er.evaluation_rule_id,
    er.condition_operator,
    er.threshold_value_numeric,
    er.threshold_value_upper,
    er.uom_code,
    er.time_window_seconds
  FROM ${catalog}.${css_schema}.evaluation_rule er
  WHERE er.is_current = TRUE
    AND COALESCE(er.is_enabled, TRUE) = TRUE
),
series AS (
  -- One canonical series per device x property, so rollups never double-count minutes
  -- or readings (never sum across aggregation_level). Preference: the device own rows,
  -- then the monitored subject (for example the equipment point), then any other level;
  -- within that level, the finest cadence.
  SELECT s.*
  FROM (
    SELECT
      sri.*,
      CASE sri.aggregation_level WHEN 'device' THEN 0 WHEN 'subject' THEN 1 ELSE 2 END * 100000
        + sri.interval_minutes AS series_key,
      MIN(CASE sri.aggregation_level WHEN 'device' THEN 0 WHEN 'subject' THEN 1 ELSE 2 END * 100000
        + sri.interval_minutes) OVER (PARTITION BY sri.sensor_device_id, sri.report_type) AS chosen_series_key
    FROM ${catalog}.${css_schema}.sensor_report_interval sri
  ) s
  WHERE s.series_key = s.chosen_series_key
),
evaluated AS (
  SELECT
    sri.store_id,
    sri.sensor_device_id,
    sri.subject_type,
    sri.subject_id,
    sri.equipment_id,
    sri.report_type,
    sri.trading_date,
    sri.value,
    sri.interval_minutes,
    COALESCE(sri.measurement_validity = 'valid', FALSE) AND sri.value IS NOT NULL AS is_valid,
    r.evaluation_rule_id,
    r.condition_operator,
    r.threshold_value_numeric,
    r.threshold_value_upper,
    r.uom_code,
    r.time_window_seconds,
    CASE
      WHEN NOT COALESCE(sri.measurement_validity = 'valid', FALSE) OR sri.value IS NULL
        OR r.condition_operator IS NULL THEN NULL
      WHEN r.uom_code IS NOT NULL AND sri.uom IS NOT NULL AND r.uom_code <> sri.uom THEN NULL
      WHEN r.condition_operator = 'greater_than' THEN sri.value > r.threshold_value_numeric
      WHEN r.condition_operator = 'greater_than_or_equal' THEN sri.value >= r.threshold_value_numeric
      WHEN r.condition_operator = 'less_than' THEN sri.value < r.threshold_value_numeric
      WHEN r.condition_operator = 'less_than_or_equal' THEN sri.value <= r.threshold_value_numeric
      WHEN r.condition_operator = 'equal' THEN sri.value = r.threshold_value_numeric
      WHEN r.condition_operator = 'not_equal' THEN sri.value <> r.threshold_value_numeric
      WHEN r.condition_operator = 'outside_range'
        THEN sri.value < r.threshold_value_numeric OR sri.value > r.threshold_value_upper
      WHEN r.condition_operator = 'inside_range'
        THEN sri.value >= r.threshold_value_numeric AND sri.value <= r.threshold_value_upper
    END AS is_breach
  FROM series sri
  LEFT JOIN current_rules r
    ON sri.sensor_device_id = r.sensor_device_id
    AND sri.report_type = r.report_type
  WHERE sri.report_type IN (
    SELECT DISTINCT report_type FROM ${catalog}.${css_schema}.evaluation_rule
    WHERE is_current = TRUE AND COALESCE(is_enabled, TRUE) = TRUE
  )
),
daily AS (
  SELECT
    store_id,
    sensor_device_id,
    subject_type,
    subject_id,
    equipment_id,
    report_type,
    trading_date,
    evaluation_rule_id,
    condition_operator,
    threshold_value_numeric,
    threshold_value_upper,
    uom_code,
    time_window_seconds,
    COUNT(*) AS reading_count,
    SUM(CASE WHEN is_valid THEN 1 ELSE 0 END) AS valid_reading_count,
    MIN(CASE WHEN is_valid THEN value END) AS min_value,
    MAX(CASE WHEN is_valid THEN value END) AS max_value,
    SUM(CASE WHEN is_valid THEN value END) AS value_sum,
    SUM(CASE WHEN is_breach IS NOT NULL THEN 1 ELSE 0 END) AS evaluated_count,
    SUM(CASE WHEN is_breach THEN 1 ELSE 0 END) AS breach_interval_count,
    SUM(CASE WHEN is_breach THEN interval_minutes ELSE 0 END) AS minutes_outside_range
  FROM evaluated
  GROUP BY store_id, sensor_device_id, subject_type, subject_id, equipment_id, report_type, trading_date,
           evaluation_rule_id, condition_operator, threshold_value_numeric,
           threshold_value_upper, uom_code, time_window_seconds
)
SELECT
  CAST(store_id AS STRING) AS store_id,
  CAST(sensor_device_id AS STRING) AS sensor_device_id,
  CAST(subject_type AS STRING) AS subject_type,
  CAST(subject_id AS STRING) AS subject_id,
  CAST(equipment_id AS STRING) AS equipment_id,
  CAST(report_type AS STRING) AS report_type,
  CAST(trading_date AS DATE) AS trading_date,
  CAST(reading_count AS BIGINT) AS reading_count,
  CAST(valid_reading_count AS BIGINT) AS valid_reading_count,
  CAST(min_value AS DOUBLE) AS min_value,
  CAST(max_value AS DOUBLE) AS max_value,
  CAST(CASE WHEN valid_reading_count > 0 THEN value_sum / valid_reading_count END AS DOUBLE) AS avg_value,
  CAST(value_sum AS DOUBLE) AS value_sum,
  CAST(valid_reading_count AS BIGINT) AS valid_reading_count_for_avg,
  CAST(evaluation_rule_id AS STRING) AS evaluation_rule_id,
  CAST(condition_operator AS STRING) AS condition_operator,
  CAST(threshold_value_numeric AS DOUBLE) AS threshold_value,
  CAST(threshold_value_upper AS DOUBLE) AS threshold_value_upper,
  CAST(uom_code AS STRING) AS uom_code,
  CAST(time_window_seconds AS INT) AS time_window_seconds,
  CAST(evaluated_count AS BIGINT) AS evaluated_interval_count,
  CAST(breach_interval_count AS BIGINT) AS breach_interval_count,
  CAST(minutes_outside_range AS BIGINT) AS minutes_outside_range,
  CAST(CASE WHEN evaluated_count > 0
            THEN (evaluated_count - breach_interval_count) / CAST(evaluated_count AS DOUBLE)
       END AS DOUBLE) AS share_intervals_in_range,
  CAST(CASE WHEN evaluation_rule_id IS NULL OR evaluated_count = 0 THEN NULL
            ELSE breach_interval_count = 0
       END AS BOOLEAN) AS is_compliant,
  CAST(CURRENT_TIMESTAMP() AS TIMESTAMP) AS fresh_as_of_ts
FROM daily;
