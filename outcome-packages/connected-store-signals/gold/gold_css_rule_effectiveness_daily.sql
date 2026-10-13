-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_css_rule_effectiveness_daily
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Ideal Lakebase serving projection.
-- Version: 0.5
-- Generated: 2026-10-05
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-10-05
-- ============================================================
-- GRAIN: one row per store × evaluation_rule (durable id) × trading_date.
--
-- The rule effectiveness view answers: for a given control-loop rule on a given day, how
-- often did it fire, how many of those firings succeeded, and how responsive were the
-- actions? Aggregates execution_log (the realised firings) paired with their automation_
-- action definitions and metadata to assess the rule's operational impact and the control
-- loop's responsiveness.
--
-- Counts and latencies follow the append-only execution_log grain: one firing per row,
-- so the aggregates re-sum over the firing population. Distinct action counts use the
-- durable action_id, not the version-specific _sk (an action retuned mid-day is one
-- action, not two).
--
-- Latency is measured from the breaching observation to the firing (execution_log.latency_ms,
-- milliseconds from the sensor reading to the automation trigger), not from the rule
-- evaluation timestamp: this is automation-loop responsiveness, not data-ingestion freshness.
-- avg_latency_ms is a per-row mean; roll latency up as a ratio of sums,
-- SUM(latency_ms_sum) / SUM(latency_measured_firings), never as an average of daily averages.
--
-- Firings are non-skipped execution_log rows, the same definition as
-- gold_css_excursion_episodes. physical_command_firings target an actuator;
-- notification_firings target a role or person; external_system targets are in neither.
--
-- Firings are attributed to the store and trading date of the interval that triggered
-- them; a firing with no triggering interval (sensor_report_interval_sk NULL) has no
-- store or date and is excluded here (execution_log keeps it).
--
-- Success rate is a ratio-of-sums: success_rate_numerator (successful firings) /
-- success_rate_denominator (completed firings: success, failure, timeout; pending and
-- skipped are not outcomes yet).
-- This re-aggregates correctly when the measure is rolled up to any coarser grain (store,
-- date period, rule set), unlike an average of per-action rates.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily AS
WITH rule_firings AS (
  -- Aggregate execution_log by rule, store, and trading date. Pair each firing with its
  -- action, rule, and sensor metadata for classification.
  SELECT
    CAST(el.evaluation_rule_id AS STRING) AS evaluation_rule_id,
    CAST(sri.store_id AS STRING) AS store_id,
    CAST(sri.trading_date AS DATE) AS trading_date,
    CAST(el.execution_log_id AS STRING) AS execution_log_id,
    CAST(el.execution_status AS STRING) AS execution_status,
    CAST(aa.action_type AS STRING) AS action_type,
    CAST(aa.target_entity_type AS STRING) AS target_entity_type,
    CAST(aa.automation_action_id AS STRING) AS automation_action_id,
    CAST(el.latency_ms AS BIGINT) AS latency_ms
  FROM ${catalog}.${css_schema}.execution_log el
  LEFT JOIN ${catalog}.${css_schema}.automation_action aa
    ON el.automation_action_sk = aa.automation_action_sk
  JOIN ${catalog}.${css_schema}.sensor_report_interval sri
    ON el.sensor_report_interval_sk = sri.sensor_report_interval_sk
  WHERE el.execution_status <> 'skipped'
)
SELECT
  evaluation_rule_id,
  store_id,
  trading_date,
  CAST(COUNT(*) AS BIGINT) AS firings,
  CAST(SUM(CASE WHEN execution_status = 'success' THEN 1 ELSE 0 END) AS BIGINT) AS successful_firings,
  CAST(SUM(CASE WHEN execution_status = 'failure' THEN 1 ELSE 0 END) AS BIGINT) AS failed_firings,
  CAST(SUM(CASE WHEN execution_status NOT IN ('success', 'failure') THEN 1 ELSE 0 END) AS BIGINT) AS other_status_firings,
  CAST(COUNT(DISTINCT automation_action_id) AS BIGINT) AS distinct_actions,
  CAST(SUM(CASE WHEN target_entity_type = 'actuator' THEN 1 ELSE 0 END) AS BIGINT) AS physical_command_firings,
  CAST(SUM(CASE WHEN target_entity_type IN ('role', 'person') THEN 1 ELSE 0 END) AS BIGINT) AS notification_firings,
  CAST(AVG(latency_ms) AS DOUBLE) AS avg_latency_ms,
  CAST(SUM(latency_ms) AS BIGINT) AS latency_ms_sum,
  CAST(COUNT(latency_ms) AS BIGINT) AS latency_measured_firings,
  CAST(MAX(latency_ms) AS BIGINT) AS max_latency_ms,
  CAST(SUM(CASE WHEN execution_status = 'success' THEN 1 ELSE 0 END) AS BIGINT) AS success_rate_numerator,
  CAST(SUM(CASE WHEN execution_status IN ('success', 'failure', 'timeout') THEN 1 ELSE 0 END) AS BIGINT)
    AS success_rate_denominator,
  CAST(CURRENT_TIMESTAMP() AS TIMESTAMP) AS fresh_as_of_ts
FROM rule_firings
GROUP BY evaluation_rule_id, store_id, trading_date;
