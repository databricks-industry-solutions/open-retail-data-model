-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_css_excursion_episodes
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Ideal Lakebase serving projection.
-- Version: 0.5
-- Generated: 2026-10-05
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-10-05
-- GRAIN: one row per excursion episode: a maximal run of contiguous breaching intervals
-- for one sensor_device × measured subject (subject_type, subject_id) × current
-- evaluation_rule. A multi-channel device reporting the same property for several
-- subjects (for example two cases on one logger) gets separate episodes per subject.
--
-- SERIES: the same canonical series as gold_css_environmental_compliance_daily (device
-- level, else subject level, at the finest cadence).
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
--
-- BREACH: a valid interval whose value satisfies the rule firing condition, the same
-- predicate as gold_css_environmental_compliance_daily (keep the two in sync). Episodes
-- are built from the readings, so an excursion the automation never reacted to still
-- appears, with firings = 0.
--
-- UNITS: as in gold_css_environmental_compliance_daily, a rule whose uom_code differs from
-- the reading uom is not evaluated, and a NULL unit on either side is treated as compatible.
--
-- CONTIGUITY: two breaching intervals belong to one episode only when the second starts
-- exactly where the first ended. A single in-range or missing interval ends the episode.
-- An interval with no recorded end (interval_end_ts is nullable) ends interval_minutes
-- after its start, so a feed without end times still forms episodes.
--
-- RESPONSE: firings are non-skipped execution_log rows for the episode rule whose
-- triggering interval (sensor_report_interval_sk) is one of the episode intervals. A
-- successful firing during an episode is evidence the loop responded, not proof that it
-- ended the excursion.
--
-- RULE SCOPE: only device-scoped rules (non-NULL sensor_device_sk) are evaluated, as in
-- gold_css_environmental_compliance_daily; iot_cross_device_rules_unevaluated counts the
-- cross-device rules (NULL device) that therefore produce no episodes. Rules carry no
-- subject or equipment scope, so every rule on a device applies to all of its subjects:
-- results are correct only when every subject on a device shares the same limits.
-- iot_multi_subject_ruled_series counts the device x property series where that matters.
--
-- peak_value is the worst reading in the direction of the rule (MAX for upper limits, MIN
-- for lower limits, the farther side for outside_range; MAX for equality and inside_range
-- rules, where peak_exceedance is NULL); peak_exceedance is how far it went past the limit, in the rule unit.
-- is_open_at_dataset_end compares against the latest interval the subject reported for
-- the property, not the wall clock, so it is meaningful on historical data.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_css_excursion_episodes AS
WITH current_rules AS (
  SELECT
    er.sensor_device_id,
    er.report_type,
    er.evaluation_rule_id,
    er.condition_operator,
    er.threshold_value_numeric,
    er.threshold_value_upper,
    er.uom_code
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
      COALESCE(sri.interval_end_ts, TIMESTAMPADD(MINUTE, sri.interval_minutes, sri.interval_start_ts))
        AS effective_end_ts,
      CASE sri.aggregation_level WHEN 'device' THEN 0 WHEN 'subject' THEN 1 ELSE 2 END * 100000
        + sri.interval_minutes AS series_key,
      MIN(CASE sri.aggregation_level WHEN 'device' THEN 0 WHEN 'subject' THEN 1 ELSE 2 END * 100000
        + sri.interval_minutes) OVER (PARTITION BY sri.sensor_device_id, sri.report_type) AS chosen_series_key
    FROM ${catalog}.${css_schema}.sensor_report_interval sri
  ) s
  WHERE s.series_key = s.chosen_series_key
),
breaching AS (
  SELECT
    sri.sensor_report_interval_sk,
    sri.store_id,
    sri.sensor_device_id,
    sri.subject_type,
    sri.subject_id,
    sri.equipment_id,
    sri.report_type,
    r.evaluation_rule_id,
    r.condition_operator,
    r.threshold_value_numeric,
    r.threshold_value_upper,
    sri.interval_start_ts,
    sri.effective_end_ts AS interval_end_ts,
    sri.trading_date,
    sri.value,
    sri.interval_minutes
  FROM series sri
  JOIN current_rules r
    ON sri.sensor_device_id = r.sensor_device_id
    AND sri.report_type = r.report_type
  WHERE sri.measurement_validity = 'valid'
    AND sri.value IS NOT NULL
    AND (r.uom_code IS NULL OR sri.uom IS NULL OR r.uom_code = sri.uom)
    AND CASE
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
      ELSE FALSE
    END
),
with_prev AS (
  SELECT
    b.*,
    LAG(b.interval_end_ts) OVER (
      PARTITION BY b.sensor_device_id, b.subject_type, b.subject_id, b.evaluation_rule_id
      ORDER BY b.interval_start_ts
    ) AS prev_end_ts
  FROM breaching b
),
flagged AS (
  SELECT
    w.*,
    CASE WHEN w.prev_end_ts IS NULL OR w.interval_start_ts <> w.prev_end_ts THEN 1 ELSE 0 END
      AS new_episode_flag
  FROM with_prev w
),
islands AS (
  SELECT
    f.*,
    SUM(f.new_episode_flag) OVER (
      PARTITION BY f.sensor_device_id, f.subject_type, f.subject_id, f.evaluation_rule_id
      ORDER BY f.interval_start_ts
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS episode_seq
  FROM flagged f
),
episodes AS (
  SELECT
    sensor_device_id,
    subject_type,
    subject_id,
    evaluation_rule_id,
    episode_seq,
    MAX(store_id) AS store_id,
    MAX(equipment_id) AS equipment_id,
    MAX(report_type) AS report_type,
    MAX(condition_operator) AS condition_operator,
    MAX(threshold_value_numeric) AS threshold_value_numeric,
    MAX(threshold_value_upper) AS threshold_value_upper,
    MIN(interval_start_ts) AS episode_start_ts,
    MAX(interval_end_ts) AS episode_end_ts,
    MIN(trading_date) AS trading_date_of_start,
    COUNT(*) AS interval_count,
    SUM(interval_minutes) AS duration_minutes,
    MAX(value) AS max_value,
    MIN(value) AS min_value
  FROM islands
  GROUP BY sensor_device_id, subject_type, subject_id, evaluation_rule_id, episode_seq
),
responses AS (
  -- Firings belong to the episode that contains their triggering interval (the causal
  -- key execution_log.sensor_report_interval_sk), so a firing that lands after the last
  -- breaching interval (latency) is still credited to its episode.
  SELECT
    i.sensor_device_id,
    i.subject_type,
    i.subject_id,
    i.evaluation_rule_id,
    i.episode_seq,
    COUNT(el.execution_log_id) AS firings,
    SUM(CASE WHEN el.execution_status = 'success' THEN 1 ELSE 0 END) AS successful_firings,
    SUM(CASE WHEN el.execution_status = 'failure' THEN 1 ELSE 0 END) AS failed_firings,
    MIN(el.triggered_at_timestamp) AS first_firing_ts,
    MIN(CASE WHEN el.execution_status = 'success' THEN el.triggered_at_timestamp END)
      AS first_success_ts
  FROM islands i
  JOIN ${catalog}.${css_schema}.execution_log el
    ON el.sensor_report_interval_sk = i.sensor_report_interval_sk
    AND el.evaluation_rule_id = i.evaluation_rule_id
    AND el.execution_status <> 'skipped'
  GROUP BY i.sensor_device_id, i.subject_type, i.subject_id, i.evaluation_rule_id, i.episode_seq
),
data_end AS (
  -- Latest interval of the same canonical series the episodes are built from, per subject,
  -- so a channel that stops reporting mid-excursion keeps its episode open.
  SELECT sensor_device_id, subject_type, subject_id, report_type,
    MAX(effective_end_ts) AS last_interval_end_ts
  FROM series
  GROUP BY sensor_device_id, subject_type, subject_id, report_type
)
SELECT
  CAST(e.store_id AS STRING) AS store_id,
  CAST(e.sensor_device_id AS STRING) AS sensor_device_id,
  CAST(e.subject_type AS STRING) AS subject_type,
  CAST(e.subject_id AS STRING) AS subject_id,
  CAST(e.equipment_id AS STRING) AS equipment_id,
  CAST(e.evaluation_rule_id AS STRING) AS evaluation_rule_id,
  CAST(e.report_type AS STRING) AS report_type,
  CAST(e.condition_operator AS STRING) AS condition_operator,
  CAST(e.episode_start_ts AS TIMESTAMP) AS episode_start_ts,
  CAST(e.episode_end_ts AS TIMESTAMP) AS episode_end_ts,
  CAST(e.trading_date_of_start AS DATE) AS trading_date_of_start,
  CAST(e.interval_count AS BIGINT) AS interval_count,
  CAST(e.duration_minutes AS BIGINT) AS duration_minutes,
  CAST(CASE
         WHEN e.condition_operator IN ('less_than', 'less_than_or_equal') THEN e.min_value
         WHEN e.condition_operator = 'outside_range'
           AND e.threshold_value_numeric - e.min_value > e.max_value - e.threshold_value_upper
           THEN e.min_value
         ELSE e.max_value
       END AS DOUBLE) AS peak_value,
  CAST(CASE
         WHEN e.condition_operator IN ('greater_than', 'greater_than_or_equal')
           THEN e.max_value - e.threshold_value_numeric
         WHEN e.condition_operator IN ('less_than', 'less_than_or_equal')
           THEN e.threshold_value_numeric - e.min_value
         WHEN e.condition_operator = 'outside_range'
           THEN GREATEST(e.threshold_value_numeric - e.min_value, e.max_value - e.threshold_value_upper)
       END AS DOUBLE) AS peak_exceedance,
  CAST(COALESCE(r.firings, 0) AS BIGINT) AS firings,
  CAST(COALESCE(r.successful_firings, 0) AS BIGINT) AS successful_firings,
  CAST(COALESCE(r.failed_firings, 0) AS BIGINT) AS failed_firings,
  CAST(r.first_firing_ts AS TIMESTAMP) AS first_firing_ts,
  CAST(TIMESTAMPDIFF(MINUTE, e.episode_start_ts, r.first_success_ts) AS INT)
    AS minutes_to_first_successful_action,
  CAST(r.first_success_ts IS NOT NULL AS BOOLEAN) AS has_successful_action,
  CAST(COALESCE(e.episode_end_ts >= d.last_interval_end_ts, FALSE) AS BOOLEAN) AS is_open_at_dataset_end,
  CAST(CURRENT_TIMESTAMP() AS TIMESTAMP) AS fresh_as_of_ts
FROM episodes e
LEFT JOIN responses r
  ON e.sensor_device_id = r.sensor_device_id
  AND e.subject_type = r.subject_type
  AND e.subject_id = r.subject_id
  AND e.evaluation_rule_id = r.evaluation_rule_id
  AND e.episode_seq = r.episode_seq
LEFT JOIN data_end d
  ON e.sensor_device_id = d.sensor_device_id
  AND e.subject_type = d.subject_type
  AND e.subject_id = d.subject_id
  AND e.report_type = d.report_type;
