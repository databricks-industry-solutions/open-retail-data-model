-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_css_automation_response
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Ideal Lakebase serving projection.
-- Version: 0.5
-- Generated: 2026-08-15
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-15
-- ============================================================
-- GRAIN: one row per realised automation firing (one execution_log row), decorated with
-- the action that ran, the rule that fired it, the actuator it hit (when the target is a
-- device), the observing device, and the sensor_report_interval whose reading breached
-- the threshold. This is the consumable that makes the sense -> evaluate -> act -> log
-- loop READ AS BUILT: it is the one row a responder, an auditor and a reliability review
-- all read, closing the loop from the firing back to the observation that caused it.
--
-- It is an ENRICHED FACT, not an aggregate: execution_log is append-only, so there is no
-- GROUP BY here -- the roll-ups (firings per rule, success rate, response latency) live in
-- mv_automation_response on top of this view. Keeping the base view at firing grain means
-- every measure downstream re-aggregates over a coherent denominator.
--
-- SCD2 JOIN DISCIPLINE (§A.16): every parent is an SCD2 master (automation_action,
-- evaluation_rule, actuator_capability, sensor_device), and execution_log carries the
-- ingest-resolved, version-specific `_sk` for each. So each join is a plain equi-join on
-- the parent PRIMARY KEY `_sk`, with NO is_current predicate: the `_sk` the fact carries
-- already pins the version that actually ran, which is both the as-of-correct join and
-- the cheap one. Joining on the durable `_id` plus is_current would instead decorate a
-- historical firing with today's rule threshold, payload template or actuator range --
-- silently defeating the reason these masters are SCD2 (the audit must recover the rule
-- version that fired, not today's tuning).
--
-- Every parent join is a LEFT JOIN because execution_log's parent keys are nullable by
-- design (execution_log.sql): a log row must survive the retirement of its action or
-- actuator, and the triggering interval is NULL when the trigger was not a single
-- canonical interval. A firing therefore always appears, even after its lineage is
-- decommissioned.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_css_automation_response AS
SELECT
  -- ---------- Store / device context (the observing device, from the triggering interval) ----------
  sd.store_id,
  sd.store_zone_id,
  sd.sensor_device_id,
  sd.device_type,
  sd.device_status,

  -- ---------- The firing (execution_log grain) ----------
  el.execution_log_id,
  el.triggered_at_timestamp,
  -- Business date of the breach that fired this run, taken ONLY from the triggering
  -- interval's already-resolved trading_date, and NULL when the trigger was not a single
  -- canonical interval (sensor_report_interval_sk IS NULL). Deliberately NOT derived by
  -- casting triggered_at_timestamp: TIMESTAMP is TIMESTAMP_LTZ, so a cast to DATE resolves
  -- in the reader's session timezone and would make this day-grain key reader-dependent --
  -- the exact non-determinism the package eliminates in epoch space (checks.sql). execution_log
  -- carries no UTC offset to resolve a firing instant deterministically, so a firing whose
  -- trigger is not a canonical interval has no reliable business date here. trading_date is
  -- the day-grain key downstream rollups group on.
  sri.trading_date AS trading_date,
  el.execution_status,
  el.latency_ms,
  -- Automation RESPONSE latency banding (ms from the breaching observation to the
  -- firing), NOT ingest freshness. Bands chosen for the loop's synthesised 50-1500 ms
  -- range; a slow band is a responsiveness concern, not a data-quality one.
  CASE
    WHEN el.latency_ms IS NULL      THEN 'unknown'
    WHEN el.latency_ms <= 250       THEN 'fast'
    WHEN el.latency_ms <= 1000      THEN 'normal'
    ELSE 'slow'
  END AS response_latency_band,
  el.response_payload,

  -- ---------- The action (intent that ran) ----------
  el.automation_action_id,
  aa.action_type,
  aa.target_entity_type,
  aa.target_entity_id,
  aa.is_enabled AS action_is_enabled,
  aa.payload_template,

  -- ---------- The rule (threshold that fired) ----------
  el.evaluation_rule_id,
  er.rule_name,
  er.report_type,
  er.condition_operator,
  er.severity,
  er.threshold_value_numeric,
  er.threshold_value_upper,
  er.time_window_seconds,
  er.uom_code AS rule_uom_code,

  -- ---------- The actuator (device commanded, when the target is a device) ----------
  el.actuator_capability_id,
  ac.command_type,
  ac.actuator_status,
  ac.equipment_id,

  -- ---------- The triggering observation (closes the loop back to the sense stage) ----------
  el.sensor_report_interval_sk,
  -- Durable interval id alongside the version-specific _sk, so lineage back to the
  -- observation survives independently of the SCD-agnostic surrogate.
  sri.sensor_report_interval_id,
  sri.value       AS breach_value,
  sri.uom         AS breach_uom,
  sri.interval_end_ts,
  -- Signed difference of the observed value from the rule threshold, in the rule unit:
  -- positive means the reading was ABOVE the threshold (the breach direction for the
  -- greater_than cold-chain rules). A general cross-operator breach magnitude is left to
  -- the consumer -- this is the raw exceedance the audit needs, not an operator-aware score.
  sri.value - er.threshold_value_numeric AS breach_margin,

  current_timestamp() AS fresh_as_of_ts
FROM ${catalog}.${css_schema}.execution_log el
-- All parents joined on the version-specific PK `_sk` the fact carries (§A.16); all LEFT
-- because those keys are nullable so a firing outlives its retired lineage.
LEFT JOIN ${catalog}.${css_schema}.automation_action aa
  ON el.automation_action_sk = aa.automation_action_sk
LEFT JOIN ${catalog}.${css_schema}.evaluation_rule er
  ON el.evaluation_rule_sk = er.evaluation_rule_sk
LEFT JOIN ${catalog}.${css_schema}.actuator_capability ac
  ON el.actuator_capability_sk = ac.actuator_capability_sk
LEFT JOIN ${catalog}.${css_schema}.sensor_report_interval sri
  ON el.sensor_report_interval_sk = sri.sensor_report_interval_sk
-- The observing device resolved from the triggering interval's version-in-effect `_sk`
-- (resolved as-of at ingest). This is the device that CAUSED the firing.
LEFT JOIN ${catalog}.${css_schema}.sensor_device sd
  ON sri.sensor_device_sk = sd.sensor_device_sk;
