-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Metric View: excursion_episodes
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-10-05
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-10-05
-- ============================================================
-- Excursion episode analysis: characterising control-loop events when multiple consecutive
-- sensor readings breach a threshold. Groups excursion_episodes to examine duration,
-- response speed, successful-action share and device-level or rule-level patterns.
--
-- An excursion episode is a maximal contiguous run of breaching intervals (see
-- gold_css_excursion_episodes). The metric view counts episodes, aggregates their duration,
-- and measures how quickly the automation control loop responded. Minutes to first successful action is the
-- mean over episodes that had a successful firing (episodes without one are excluded, and
-- counted separately by episodes_without_successful_action).
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.mv_excursion_episodes
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Excursion episodes: characterising cold-chain breaches as contiguous events and measuring how the control loop responded. A successful firing shows the loop responded; it is not proof that it ended the excursion."
source: ${catalog}.${css_schema}.gold_css_excursion_episodes

fields:
  - name: store_id
    expr: store_id
    display_name: "Store"
    comment: "Durable store business key."
    synonyms: ["store", "site", "location"]

  - name: sensor_device_id
    expr: sensor_device_id
    display_name: "Device"
    comment: "Durable business key of the temperature sensor that detected the excursion."
    synonyms: ["device", "probe", "sensor"]

  - name: subject_id
    expr: subject_id
    display_name: "Measured Subject"
    comment: "Measured subject within the device, interpreted per subject_type (for example one case on a multi-channel logger). Slices a multi-channel device by channel."
    synonyms: ["subject", "channel", "monitored_point"]

  - name: equipment_id
    expr: equipment_id
    display_name: "Equipment"
    comment: "Durable business key of the refrigeration unit or maintained asset experiencing the excursion."
    synonyms: ["asset", "unit", "equipment"]

  - name: evaluation_rule_id
    expr: evaluation_rule_id
    display_name: "Rule"
    comment: "Durable id of the rule whose breach defined this episode."
    synonyms: ["rule", "threshold", "control_rule"]

  - name: trading_date_of_start
    expr: trading_date_of_start
    display_name: "Episode Start Date"
    comment: "Business date when the episode began (first breaching interval)."
    synonyms: ["date", "day", "start_date"]

  - name: report_type
    expr: report_type
    display_name: "Report Type"
    comment: "Monitored property of the episode, for example gs1:Temperature."
    synonyms: ["property", "measurement_type"]

  - name: has_successful_action
    expr: has_successful_action
    display_name: "Has Successful Action"
    comment: "TRUE when a firing triggered by one of the episode intervals succeeded (the firing may land after the last breaching interval). Evidence the loop responded, not proof that it ended the excursion."
    synonyms: ["action_succeeded", "loop_responded"]

  - name: is_open_at_dataset_end
    expr: is_open_at_dataset_end
    display_name: "Open at Data End"
    comment: "TRUE if the episode was still ongoing at the end of available data (has not yet ended). Use to exclude ongoing episodes from analysis of completed events."
    synonyms: ["ongoing", "in_progress", "unfinished"]

measures:
  - name: episode_count
    expr: COUNT(*)
    display_name: "Episodes"
    comment: "Number of distinct excursion episodes in the grouping."
    synonyms: ["excursions", "events", "breaches"]

  - name: episodes_with_successful_action
    expr: COUNT(CASE WHEN has_successful_action = TRUE THEN 1 END)
    display_name: "Episodes With Successful Action"
    comment: "Count of episodes with at least one successful firing triggered by an episode interval."
    synonyms: ["answered_episodes"]

  - name: episodes_without_successful_action
    expr: COUNT(CASE WHEN has_successful_action = FALSE THEN 1 END)
    display_name: "Episodes Without Successful Action"
    comment: "Count of episodes with no successful firing triggered by an episode interval."
    synonyms: ["unanswered_episodes"]

  - name: avg_episode_duration_minutes
    expr: AVG(duration_minutes)
    display_name: "Avg Episode Duration (min)"
    comment: "Mean duration of episodes in the grouping, from first to last breaching interval."
    synonyms: ["avg_excursion_time", "mean_duration"]

  - name: max_episode_duration_minutes
    expr: MAX(duration_minutes)
    display_name: "Max Episode Duration (min)"
    comment: "Longest-running excursion in the grouping."
    synonyms: ["longest_episode", "worst_duration"]

  - name: total_breach_intervals
    expr: SUM(interval_count)
    display_name: "Breach Intervals"
    comment: "Total number of individual breaching intervals across all episodes. A measure of total breach volume."
    synonyms: ["total_intervals", "cumulative_breaches"]

  - name: avg_intervals_per_episode
    expr: AVG(CAST(interval_count AS DOUBLE))
    display_name: "Avg Intervals per Episode"
    comment: "Mean number of consecutive intervals per episode."
    synonyms: ["avg_run_length", "mean_intervals"]

  - name: peak_excursion_value
    expr: MAX(peak_value)
    display_name: "Peak Excursion Value"
    comment: "Worst reading across episodes in the direction of the rule limit. For a cold-chain upper limit, the highest excursion temperature. Only meaningful within one evaluation_rule_id (or one report_type with same-direction rules): MAX across upper- and lower-limit rules hides the worst low excursion."
    synonyms: ["worst_reading", "maximum_breach"]

  - name: avg_peak_excursion_magnitude
    expr: AVG(peak_exceedance)
    display_name: "Avg Peak Exceedance"
    comment: "Mean distance past the rule limit at the worst reading of each episode, in the rule unit. Indicates typical excursion severity. Only meaningful within one report_type: averaging across properties mixes units (for example degrees and percent humidity)."
    synonyms: ["avg_overshoot", "mean_margin"]

  - name: firings_in_episodes
    expr: SUM(firings)
    display_name: "Control-Loop Firings"
    comment: "Total automation firings triggered by breaches in the episodes."
    synonyms: ["automation_events", "control_actions"]

  - name: successful_firings
    expr: SUM(successful_firings)
    display_name: "Successful Firings"
    comment: "Automation actions that completed with execution_status = 'success'."
    synonyms: ["completed_actions", "successful_controls"]

  - name: action_success_rate
    expr: SUM(successful_firings) / NULLIF(SUM(firings), 0)
    display_name: "Episode Firing Success Share"
    comment: "Share of firings credited to episodes that succeeded: successful / all non-skipped firings (pending, failure and timeout count as not successful), ratio of sums. Not the completion success rate of gold_css_rule_effectiveness_daily, which divides by completed firings only (success, failure, timeout)."
    synonyms: ["episode_firing_success_share", "share_of_episode_firings_successful"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: avg_minutes_to_first_successful_action
    expr: AVG(CAST(minutes_to_first_successful_action AS DOUBLE))
    display_name: "Avg Minutes to First Successful Action"
    comment: "Mean time from episode start to the first successful automation action. NULL episodes (those with no successful action) are excluded from the average."
    synonyms: ["avg_response_time", "time_to_first_success"]

  - name: avg_first_response_time_minutes
    expr: AVG(CASE WHEN first_firing_ts IS NOT NULL THEN CAST(TIMESTAMPDIFF(MINUTE, episode_start_ts, first_firing_ts) AS DOUBLE) ELSE NULL END)
    display_name: "Avg First Response Time (min)"
    comment: "Mean time from episode start to the very first firing (successful or not). Measures automation trigger speed."
    synonyms: ["avg_response_delay", "mean_detection_time"]
$$;
