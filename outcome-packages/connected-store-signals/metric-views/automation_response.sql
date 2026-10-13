-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Metric View: automation_response
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-08-15
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-15
-- ============================================================
-- The IoT Sensor Monitoring outcome measured: how the automation control loop is
-- behaving. One firing per row in the source (gold_css_automation_response), rolled up
-- here to the questions an operations reliability review actually asks -- how many rules
-- fired, on which devices, how fast the response was, and how often it succeeded.
--
-- Source is the firing-grain gold view, so every ratio here re-aggregates over a coherent
-- denominator (COUNT over the append-only execution_log grain). Counts of entities use
-- the durable `_id`, never the version-specific `_sk`: an SCD2 rule retuned mid-window is
-- ONE rule, not two (§A.16).
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.mv_automation_response
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Connected Store Signals automation control loop: firings, success rate, response latency and breach magnitude across the sense -> evaluate -> act -> log loop, dimensioned by device, rule, action target and severity."
source: ${catalog}.${css_schema}.gold_css_automation_response

fields:
  - name: store_id
    expr: store_id
    display_name: "Store"
    comment: "Durable store business key of the device that fired the loop."
    synonyms: ["store", "location", "site", "branch"]

  - name: sensor_device_id
    expr: sensor_device_id
    display_name: "Device"
    comment: "Durable business key of the observing device whose reading breached the rule."
    synonyms: ["device", "sensor", "probe"]

  - name: store_zone_id
    expr: store_zone_id
    display_name: "Zone"
    comment: "Durable id of the zone the observing device is installed in."
    synonyms: ["zone", "area", "location_in_store"]

  - name: device_type
    expr: device_type
    display_name: "Device Type"
    comment: "Kind of device that triggered the firing, e.g. temperature for the cold-chain excursion loop."
    synonyms: ["sensor_type", "device_kind"]

  - name: evaluation_rule_id
    expr: evaluation_rule_id
    display_name: "Rule"
    comment: "Durable business key of the rule whose breach fired the action."
    synonyms: ["rule", "threshold", "alert_rule"]

  - name: rule_name
    expr: rule_name
    display_name: "Rule Name"
    comment: "Human-readable rule name, e.g. an over-temperature excursion on a named device."
    synonyms: ["rule_label", "condition_name"]

  - name: report_type
    expr: report_type
    display_name: "Report Type"
    comment: "The GS1 CBV property the rule watches, e.g. gs1:Temperature. Shared vocabulary with sensor_report_interval, so a rule and the readings it evaluates speak the same language."
    synonyms: ["measurement_type", "signal_type", "property"]

  - name: severity
    expr: severity
    display_name: "Severity"
    comment: "Operational severity of a breach: info, warning or critical."
    synonyms: ["priority", "criticality"]

  - name: condition_operator
    expr: condition_operator
    display_name: "Condition"
    comment: "The comparison the rule applied to the observed value, e.g. greater_than."
    synonyms: ["operator", "comparison"]

  - name: action_type
    expr: action_type
    display_name: "Action Type"
    comment: "What kind of action fired: system_command, notification, webhook, ticket or log_only. One breach can fan out to several action types."
    synonyms: ["action_kind", "response_type"]

  - name: target_entity_type
    expr: target_entity_type
    display_name: "Target Type"
    comment: "The kind of thing the action targeted -- actuator, role, person or external_system. Only the actuator target carries a typed actuator FK (§A.5)."
    synonyms: ["target_kind", "recipient_type"]

  - name: command_type
    expr: command_type
    display_name: "Command Type"
    comment: "What the actuator was commanded to do, e.g. toggle_power. NULL for a non-actuator action such as a notification."
    synonyms: ["actuator_command", "device_command"]

  - name: actuator_capability_id
    expr: actuator_capability_id
    display_name: "Actuator"
    comment: "Durable id of the actuator the command hit. NULL for non-actuator actions."
    synonyms: ["actuator", "relay", "controller"]

  - name: execution_status
    expr: execution_status
    display_name: "Execution Status"
    comment: "Outcome of the firing: success, failure, pending, timeout or skipped."
    synonyms: ["status", "outcome", "result"]

  - name: response_latency_band
    expr: response_latency_band
    display_name: "Response Latency Band"
    comment: "Automation responsiveness band from the firing latency: fast (<= 250 ms), normal (<= 1000 ms), slow (> 1000 ms), or unknown. This is act-response latency, NOT ingest freshness."
    synonyms: ["latency_band", "responsiveness"]

  - name: trading_date
    expr: trading_date
    display_name: "Trading Date"
    comment: "Business date of the breach that fired the loop."
    synonyms: ["date", "day", "business_date"]

measures:
  - name: firing_count
    expr: COUNT(*)
    display_name: "Firings"
    comment: "Realised automation firings in the grouping -- one per execution_log row. The primary volume measure."
    synonyms: ["executions", "firings", "triggers"]

  - name: rules_fired
    expr: COUNT(DISTINCT evaluation_rule_id)
    display_name: "Rules Fired"
    comment: "Distinct rules that fired, counted on the durable rule id so a rule retuned mid-window counts once."
    synonyms: ["distinct_rules", "active_rules"]

  - name: devices_with_firings
    expr: COUNT(DISTINCT sensor_device_id)
    display_name: "Devices With Firings"
    comment: "Distinct observing devices whose readings fired a rule, on the durable device id."
    synonyms: ["devices", "affected_devices"]

  - name: success_count
    expr: COUNT(*) FILTER (WHERE execution_status = 'success')
    display_name: "Successful Firings"
    comment: "Firings whose target reported success."
    synonyms: ["successes", "completed_firings"]

  - name: failure_count
    expr: COUNT(*) FILTER (WHERE execution_status = 'failure')
    display_name: "Failed Firings"
    comment: "Firings whose target reported failure."
    synonyms: ["failures", "errors"]

  - name: success_rate
    expr: COUNT(*) FILTER (WHERE execution_status = 'success') / NULLIF(COUNT(*), 0)
    display_name: "Success Rate"
    comment: "Successful firings / all logged firings (every execution_status, including pending, timeout and skipped), from summed counts."
    synonyms: ["success_percentage", "firing_success_share"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: actuator_firing_count
    expr: COUNT(*) FILTER (WHERE target_entity_type = 'actuator')
    display_name: "Actuator Firings"
    comment: "Firings that drove a physical actuator (the typed-FK branch of the polymorphic target), as opposed to a notification or webhook."
    synonyms: ["physical_commands", "device_firings"]

  - name: notification_count
    expr: COUNT(*) FILTER (WHERE action_type = 'notification')
    display_name: "Notifications"
    comment: "Firings that raised a notification to a role or person rather than commanding a device."
    synonyms: ["alerts_sent", "notifications"]

  - name: critical_firing_count
    expr: COUNT(*) FILTER (WHERE severity = 'critical')
    display_name: "Critical Firings"
    comment: "Firings from a rule marked critical, e.g. a cold-chain over-temperature excursion."
    synonyms: ["critical_alerts", "severe_firings"]

  - name: avg_response_latency_ms
    expr: AVG(latency_ms)
    display_name: "Avg Response Latency (ms)"
    comment: "Mean milliseconds from the breaching observation to the firing. Automation responsiveness, NOT ingest latency."
    synonyms: ["latency", "response_time", "responsiveness"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 0

  - name: max_response_latency_ms
    expr: MAX(latency_ms)
    display_name: "Max Response Latency (ms)"
    comment: "Worst-case response latency observed in the grouping."
    synonyms: ["peak_latency", "worst_response"]

  - name: slow_response_count
    expr: COUNT(*) FILTER (WHERE response_latency_band = 'slow')
    display_name: "Slow Responses"
    comment: "Firings that took longer than 1000 ms to respond -- a responsiveness concern worth isolating."
    synonyms: ["slow_firings", "laggy_responses"]

  - name: avg_breach_margin
    expr: AVG(breach_margin)
    display_name: "Avg Breach Margin"
    comment: "Mean signed difference of the observed value from the rule threshold, in the rule unit. Positive means above threshold -- how far past the limit the readings that fired were, on average."
    synonyms: ["avg_exceedance", "avg_overshoot"]

  - name: max_breach_value
    expr: MAX(breach_value)
    display_name: "Max Breach Value"
    comment: "Highest observed value that fired a rule in the grouping, e.g. the peak temperature during a cold-chain excursion."
    synonyms: ["peak_reading", "worst_reading"]
$$;
