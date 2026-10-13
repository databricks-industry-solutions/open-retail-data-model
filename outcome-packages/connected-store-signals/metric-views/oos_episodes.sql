-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Metric View: oos_episodes
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-10-05
-- LLM-generated: true (maintainer-reviewed before release)
-- ============================================================
-- Out-of-stock episodes: shelf gaps detected and their duration, detection method,
-- severity, and support for investigation prioritization.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.mv_oos_episodes
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Out-of-stock shelf episodes: detection, duration, investigation candidate flags, and data quality. One row per episode with aggregated supporting evidence."
source: ${catalog}.${css_schema}.gold_observed_oos_episodes

fields:
  - name: store_id
    expr: store_id
    display_name: "Store"
    comment: "Durable store business key."
    synonyms: ["store", "site", "location"]

  - name: store_zone_id
    expr: store_zone_id
    display_name: "Zone"
    comment: "Durable shelf-position zone business key."
    synonyms: ["zone", "section", "location_id"]

  - name: product_id
    expr: product_id
    display_name: "Product"
    comment: "Durable product business key."
    synonyms: ["product", "sku", "item"]

  - name: detection_method
    expr: detection_method
    display_name: "Detection Method"
    comment: "How the episode was detected: smart_shelf or other sensing modality."
    synonyms: ["method", "source", "detection_source"]

  - name: candidate_reason
    expr: candidate_reason
    display_name: "Candidate Reason"
    comment: "phantom_stock when EOD book units were positive at episode start, otherwise unknown."
    synonyms: ["reason", "trigger", "investigation_reason"]

  - name: episode_start_date
    expr: episode_start_date
    display_name: "Episode Start Date"
    comment: "Store-local trading date the out-of-stock episode started."
    synonyms: ["date", "day", "start_date"]

  - name: candidate_severity
    expr: candidate_severity
    display_name: "Candidate Severity"
    comment: "Severity band by episode duration: high (24 hours or more), medium (4 hours or more), low otherwise."
    synonyms: ["severity", "priority", "severity_band"]

measures:
  - name: episode_count
    expr: COUNT(*)
    display_name: "Episode Count"
    comment: "Number of distinct out-of-stock episodes in the grouping."
    synonyms: ["episodes", "gaps", "oos_count"]

  - name: ongoing_episodes
    expr: COUNT(*) FILTER (WHERE is_ongoing)
    display_name: "Ongoing Episodes"
    comment: "Count of episodes still in progress at the evaluation clock."
    synonyms: ["active_episodes", "open_gaps"]

  - name: total_episode_duration_minutes
    expr: SUM(episode_duration_minutes)
    display_name: "Total Episode Duration (minutes)"
    comment: "Sum of all episode durations; useful for trend analysis."
    synonyms: ["total_duration", "cumulative_minutes"]

  - name: avg_episode_duration_minutes
    expr: SUM(episode_duration_minutes) / NULLIF(COUNT(*), 0)
    display_name: "Average Episode Duration (minutes)"
    comment: "Mean duration per episode; indicates typical gap length."
    synonyms: ["mean_duration", "avg_duration"]

  - name: max_episode_duration_minutes
    expr: MAX(episode_duration_minutes)
    display_name: "Maximum Episode Duration (minutes)"
    comment: "Duration of the longest single out-of-stock episode."
    synonyms: ["longest_duration", "max_duration"]

  - name: total_supporting_observations
    expr: SUM(supporting_observation_count)
    display_name: "Total Supporting Observations"
    comment: "Cumulative observation count across all episodes; volume of evidence."
    synonyms: ["total_observations", "evidence_count"]

  - name: avg_supporting_devices
    expr: CAST(SUM(supporting_device_count) AS DOUBLE) / NULLIF(COUNT(*), 0)
    display_name: "Average Supporting Devices"
    comment: "Mean number of distinct devices contributing evidence per episode."
    synonyms: ["avg_devices", "device_count"]

  - name: phantom_stock_candidate_count
    expr: COUNT(*) FILTER (WHERE is_phantom_stock_candidate)
    display_name: "Phantom Stock Candidate Episodes"
    comment: "Number of episodes also flagged as phantom stock candidates (positive book with zero observed)."
    synonyms: ["phantom_episodes", "phantom_count"]

  - name: high_severity_count
    expr: COUNT(*) FILTER (WHERE candidate_severity = 'high')
    display_name: "High Severity Episodes"
    comment: "Number of episodes at high severity (severity bands are high, medium, low)."
    synonyms: ["high_priority", "urgent_episodes"]

  - name: suspect_quality_count
    expr: COUNT(*) FILTER (WHERE data_quality_flag = TRUE)
    display_name: "Suspect Quality Episodes"
    comment: "Episodes with any degraded supporting observation; verify before acting."
    synonyms: ["low_quality", "needs_verification"]

  - name: min_confidence_score_avg
    expr: AVG(min_confidence_score)
    display_name: "Average Minimum Confidence"
    comment: "Mean of the minimum confidence scores across episodes; lower values indicate less certain observations."
    synonyms: ["avg_confidence", "quality_score"]
    format:
      type: percentage
      decimal_places: {type: exact, places: 1}
$$;
