-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals · sample queries
-- Version: 0.5 · Generated: 2026-07-28 · LLM-generated: true · Reviewed: 2026-07-28
-- ============================================================

-- 1. Operational store traffic: complete truth for authorized operations users.
SELECT
  store_id,
  trading_date,
  day_of_week,
  footfall_count,
  footfall_count_py,
  footfall_growth_py,
  avg_dwell_seconds,
  peak_occupancy,
  avg_coverage_ratio,
  valid_interval_share
FROM ${catalog}.${css_schema}.gold_store_traffic_daily_current
WHERE fiscal_week_id = 202605
ORDER BY store_id, trading_date;


-- 2. Explicitly shared zone traffic: effective policy suppression is already applied.
-- Do not substitute the operational view for an external or partner export.
SELECT
  store_id,
  store_zone_id,
  zone_name,
  trading_date,
  footfall_count,
  avg_dwell_seconds,
  disclosure_suppressed_flag,
  sensing_disclosure_policy_id
FROM ${catalog}.${css_schema}.gold_zone_traffic_shared
WHERE trading_date >= current_date() - INTERVAL 7 DAYS
ORDER BY store_id, store_zone_id, trading_date;


-- 3. Busiest zones by traffic density, not raw count.
-- area_sqm is already duration-weighted for any zone-version changes within the day.
SELECT
  store_id,
  store_zone_id,
  zone_name,
  SUM(footfall_count) / NULLIF(SUM(area_sqm), 0) AS avg_daily_footfall_per_sqm,
  SUM(dwell_seconds_total) / NULLIF(SUM(dwell_count), 0) AS avg_dwell_seconds,
  SUM(engaged_count) / NULLIF(SUM(dwell_count), 0) AS engagement_rate
FROM ${catalog}.${css_schema}.gold_zone_traffic_current
WHERE trading_date >= current_date() - INTERVAL 28 DAYS
  AND is_sales_floor = TRUE
GROUP BY store_id, store_zone_id, zone_name
ORDER BY avg_daily_footfall_per_sqm DESC
LIMIT 20;


-- 4. A store total comes from site-level measurement.
SELECT store_id, trading_date, footfall_count AS store_footfall
FROM ${catalog}.${css_schema}.gold_store_traffic_daily_current
WHERE trading_date = current_date() - INTERVAL 1 DAY;

-- WRONG: zone rows are not additive to a store total because one shopper can traverse
-- several zones.
-- SELECT store_id, trading_date, SUM(footfall_count)
-- FROM ${catalog}.${css_schema}.gold_zone_traffic_current
-- GROUP BY store_id, trading_date;


-- 5. Traffic-sales productivity. Use per-footfall when entry direction is unavailable.
-- A conversion rate is absent until canonical transaction or receipt count exists.
SELECT
  store_id,
  trading_date,
  entry_count,
  units,
  net_revenue,
  sales_per_entry,
  units_per_entry,
  sales_per_footfall,
  units_per_footfall,
  promo_active_flag
FROM ${catalog}.${css_schema}.gold_traffic_sales_productivity_current
WHERE trading_date >= current_date() - INTERVAL 14 DAYS
ORDER BY sales_per_entry DESC;


-- 6. Promotion context against traffic productivity.
SELECT
  promo_active_flag,
  COUNT(*) AS store_days,
  AVG(entry_count) AS avg_entries,
  AVG(net_revenue) AS avg_net_sales,
  AVG(sales_per_entry) AS avg_sales_per_entry
FROM ${catalog}.${css_schema}.gold_traffic_sales_productivity_current
WHERE is_holiday = FALSE
GROUP BY promo_active_flag;


-- 7. Fleet triage. Observation completeness follows source cadence, never footfall.
SELECT
  device_type,
  COUNT(DISTINCT sensor_device_id) AS devices,
  1 - SUM(observations_received) / NULLIF(SUM(observations_expected), 0)
    AS missing_observation_rate,
  SUM(sequence_gap_count) AS lost_messages,
  SUM(duplicate_delivery_count) AS duplicate_deliveries,
  COUNT(*) FILTER (WHERE had_session_restart) AS session_restarts,
  COUNT(DISTINCT sensor_device_id)
    FILTER (WHERE feed_freshness_status = 'stale') AS stale_devices,
  COUNT(DISTINCT sensor_device_id)
    FILTER (WHERE calibration_status = 'expired') AS expired_calibrations
FROM ${catalog}.${css_schema}.gold_css_device_health
WHERE trading_date >= current_date() - INTERVAL 7 DAYS
GROUP BY device_type
ORDER BY missing_observation_rate DESC;


-- 8. Investigate a quiet operational interval without confusing zero with missing.
SELECT
  f.store_id,
  f.store_zone_id,
  f.interval_start_ts,
  f.interval_end_ts,
  t.footfall_count,
  t.is_zero_observed,
  f.source_observation_count,
  f.expected_observation_count,
  f.measurement_validity,
  f.arrival_completeness
FROM ${catalog}.${css_schema}.sensor_report_interval f
JOIN ${catalog}.${css_schema}.foot_traffic_interval_detail t
  ON f.sensor_report_interval_sk = t.sensor_report_interval_sk
WHERE f.report_type = 'gs1:Count'
  AND f.subject_type = 'space'
  AND f.trading_date = current_date() - INTERVAL 1 DAY
ORDER BY f.store_id, f.store_zone_id, f.interval_start_ts;


-- 9. Compare only traffic captured under the same counting convention.
SELECT
  f.store_id,
  t.counting_unit,
  t.group_counting_enabled,
  t.staff_exclusion_enabled,
  t.staff_exclusion_method,
  t.staff_exclusion_stage,
  t.passby_convention,
  t.directionality,
  COUNT(*) AS intervals
FROM ${catalog}.${css_schema}.sensor_report_interval f
JOIN ${catalog}.${css_schema}.foot_traffic_interval_detail t
  ON f.sensor_report_interval_sk = t.sensor_report_interval_sk
WHERE f.report_type = 'gs1:Count'
  AND f.subject_type = 'space'
GROUP BY
  f.store_id,
  t.counting_unit,
  t.group_counting_enabled,
  t.staff_exclusion_enabled,
  t.staff_exclusion_method,
  t.staff_exclusion_stage,
  t.passby_convention,
  t.directionality
ORDER BY f.store_id;


-- 10. Generic environmental seam over the same reusable envelope.
-- Type-specific compliance rules belong in a future keyed extension, not in Foot Traffic.
SELECT
  f.store_id,
  f.subject_type,
  f.subject_id,
  f.report_type,
  f.trading_date,
  MIN(f.min_value) AS minimum_value,
  MAX(f.max_value) AS maximum_value,
  SUM(f.source_observation_count) AS observations_received,
  SUM(f.expected_observation_count) AS observations_expected
FROM ${catalog}.${css_schema}.sensor_report_interval f
WHERE f.report_type IN ('gs1:Temperature', 'gs1:RelativeHumidity')
GROUP BY f.store_id, f.subject_type, f.subject_id, f.report_type, f.trading_date;


-- 11. Audit the automation loop end to end: sense -> evaluate -> act -> log.
-- Each execution_log row is one FIRING, so a single breaching interval that drives both
-- a compressor command and a manager notification shows as TWO rows here -- which is why
-- the ledger keys on the action, not on the interval alone.
-- The SCD2 rule/action joins are on the version-specific _sk the fact carries (the FK),
-- so each firing resolves to the exact rule and action version that ran, with no fan-out.
SELECT
  l.triggered_at_timestamp,
  r.rule_name,
  r.report_type,
  r.threshold_value_numeric AS threshold,
  f.value                   AS observed_value,     -- the reading that breached the rule
  a.action_type,
  a.target_entity_type,
  a.target_entity_id,
  l.execution_status,
  l.latency_ms                                     -- automation-response latency, not ingest lag
FROM ${catalog}.${css_schema}.execution_log l
JOIN ${catalog}.${css_schema}.automation_action a
  ON l.automation_action_sk = a.automation_action_sk
JOIN ${catalog}.${css_schema}.evaluation_rule r
  ON l.evaluation_rule_sk = r.evaluation_rule_sk
LEFT JOIN ${catalog}.${css_schema}.sensor_report_interval f
  ON l.sensor_report_interval_sk = f.sensor_report_interval_sk
ORDER BY l.triggered_at_timestamp DESC, r.rule_name, a.action_type;


-- 12. Inventory accuracy is basis-aware. The latest projection prevents repeated
-- sessions on the same date and basis from repeating the same EOD book quantity.
SELECT
  store_id,
  reconciliation_date,
  reconciliation_basis,
  SUM(observed_units) AS observed_units,
  SUM(book_units_eod) AS book_units_eod,
  SUM(absolute_unit_variance) AS absolute_unit_variance,
  CASE WHEN reconciliation_basis = 'aligned_eod' THEN
    GREATEST(0.0, 1.0 - SUM(absolute_unit_variance) /
      NULLIF(GREATEST(SUM(ABS(book_units_eod)), SUM(observed_units)), 0))
  END AS inventory_accuracy_pct,
  CASE WHEN reconciliation_basis = 'misaligned' THEN
    GREATEST(0.0, 1.0 - SUM(absolute_unit_variance) /
      NULLIF(GREATEST(SUM(ABS(book_units_eod)), SUM(observed_units)), 0))
  END AS observed_to_book_agreement_pct
FROM ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest
WHERE reconciliation_date >= current_date() - INTERVAL 7 DAYS
GROUP BY store_id, reconciliation_date, reconciliation_basis
ORDER BY store_id, reconciliation_date, reconciliation_basis;


-- 13. Current fresh presence by zone and product. Stray reads are already excluded.
SELECT
  store_id,
  store_zone_id,
  product_id,
  units_present,
  newest_supporting_event_ts,
  max_freshness_age_minutes
FROM ${catalog}.${css_schema}.gold_zone_item_presence_current
ORDER BY units_present DESC
LIMIT 100;


-- 14. Count execution. Partial sessions intentionally have no plan-completion metrics.
SELECT
  store_id,
  rfid_count_session_id,
  count_method,
  scope_type,
  duration_minutes,
  planned_zones,
  zones_covered,
  zones_missed,
  zone_coverage_rate,
  units_observed
FROM ${catalog}.${css_schema}.gold_count_session_summary
WHERE trading_date >= current_date() - INTERVAL 30 DAYS
ORDER BY started_at_ts DESC;


-- 15. Receiving evidence. Only linked_shipment rows support over/short verification.
SELECT
  verification_tier,
  shipment_id,
  shipment_line_id,
  store_id,
  product_id,
  expected_units,
  observed_units,
  unit_variance,
  verification_status
FROM ${catalog}.${css_schema}.gold_receiving_verification
ORDER BY window_start_ts DESC;


-- 16. Item-side exit exceptions. This surface has no person, basket, receipt, or video link.
SELECT
  store_id,
  trading_date,
  product_id,
  COUNT(DISTINCT tagged_item_id) AS serialized_items
FROM ${catalog}.${css_schema}.gold_unaccounted_exits
WHERE trading_date >= current_date() - INTERVAL 7 DAYS
GROUP BY store_id, trading_date, product_id
ORDER BY serialized_items DESC;


-- 17. OSA with denominator honesty. Use the certified gold ratios and retain the
-- coverage columns; an unknown or unobserved position is not available stock.
SELECT
  store_id,
  trading_date,
  category,
  expected_positions,
  positions_known,
  positions_unknown,
  positions_unobserved,
  osa_pct_eod,
  osa_pct_intraday_floor,
  observation_coverage_pct,
  known_state_pct
FROM ${catalog}.${css_schema}.gold_osa_daily_current
WHERE trading_date >= current_date() - INTERVAL 7 DAYS
ORDER BY trading_date DESC, osa_pct_eod, observation_coverage_pct;


-- 18. Four-dimensional planogram compliance. NULL percentages mean the dimension
-- was not evaluable; BMV divergence is allocation-vs-execution context, not a repair.
SELECT
  store_id,
  trading_date,
  product_id,
  positions_expected,
  positions_unknown,
  positions_unobserved,
  presence_compliance_pct,
  position_compliance_pct,
  facing_compliance_pct,
  price_tag_compliance_pct,
  overall_compliance_pct,
  bmv_allocated_facings,
  expected_facings_total,
  is_allocation_divergent
FROM ${catalog}.${css_schema}.gold_planogram_compliance_current
WHERE trading_date >= current_date() - INTERVAL 7 DAYS
ORDER BY trading_date DESC, overall_compliance_pct, store_id, product_id;


-- 19. Price-display accuracy. Overcharges and undercharges stay separate and every
-- row retains its currency; do not net signed price differences across labels.
SELECT
  store_id,
  trading_date,
  currency_code,
  labels_evaluable,
  labels_matched_eod,
  labels_mismatched_eod,
  price_match_rate_eod,
  labels_overcharging_eod,
  labels_undercharging_eod,
  avg_correction_hours,
  sync_latency_p50_seconds,
  sync_latency_p95_seconds
FROM ${catalog}.${css_schema}.gold_price_accuracy_current
WHERE trading_date >= current_date() - INTERVAL 7 DAYS
ORDER BY trading_date DESC, price_match_rate_eod, store_id, currency_code;


-- 20. Same-date shelf-vs-book variance for replenishment investigation. This is
-- directional evidence: visible facings may be a floor when no unit estimate exists.
SELECT
  store_id,
  trading_date,
  product_id,
  observed_positions,
  known_positions,
  positions_oos,
  observed_units_on_shelf,
  book_units_eod,
  unit_variance,
  is_phantom_stock,
  is_over_book
FROM ${catalog}.${css_schema}.gold_shelf_vs_system_variance_daily
WHERE trading_date >= current_date() - INTERVAL 7 DAYS
  AND (is_phantom_stock OR is_over_book OR absolute_unit_variance > 0)
ORDER BY trading_date DESC, absolute_unit_variance DESC, store_id, product_id;

-- 21. Current shelf state with usability and freshness. Newest capture always wins;
-- do not filter unknown or stale rows out, as they represent the actual current truth.
SELECT
  store_id,
  store_zone_id,
  product_id,
  shelf_state,
  observed_facing_count,
  expected_facing_count,
  confidence_score,
  is_usable,
  is_stale,
  is_presence_compliant,
  is_position_compliant,
  is_facing_compliant,
  is_price_tag_compliant,
  freshness_age_minutes,
  observation_ts
FROM ${catalog}.${css_schema}.gold_shelf_state_current
WHERE is_usable AND NOT is_stale
ORDER BY store_id, store_zone_id, is_presence_compliant, confidence_score DESC;


-- 22. RFID out-of-stock candidates: latest aligned phantom-stock evidence.
-- These are investigation signals only, not proof of stockout.
SELECT
  store_id,
  product_id,
  reconciliation_date,
  eligible_tagged_units,
  observed_units,
  book_units_eod,
  absolute_unit_variance,
  candidate_reason,
  candidate_severity,
  data_quality_flag,
  rfid_count_session_id
FROM ${catalog}.${css_schema}.gold_rfid_oos_candidates
WHERE reconciliation_date >= current_date() - INTERVAL 7 DAYS
  AND candidate_reason = 'phantom_stock'
ORDER BY reconciliation_date DESC, store_id, absolute_unit_variance DESC;


-- 23. Share of shelf by category and brand. Shares are not additive across
-- categories or stores, and they represent a snapshot at the evaluation instant.
SELECT
  store_id,
  category,
  brand,
  brand_facing_count,
  category_facing_count,
  share_of_shelf_pct,
  ROW_NUMBER() OVER (PARTITION BY store_id, category ORDER BY share_of_shelf_pct DESC) AS brand_rank
FROM ${catalog}.${css_schema}.gold_share_of_shelf_current
WHERE category IS NOT NULL
ORDER BY store_id, category, share_of_shelf_pct DESC;


-- 24. RFID zone count coverage: when zones were last counted and adherence to cadence.
-- Zones missing recent counts are candidates for scheduling.
SELECT
  store_id,
  store_zone_id,
  zone_code,
  zone_type,
  target_cadence_days,
  last_counted_date,
  count_sessions_in_lookback,
  DATEDIFF(CURRENT_DATE, last_counted_date) AS days_since_last_count,
  CASE WHEN DATEDIFF(CURRENT_DATE, last_counted_date) > target_cadence_days
       THEN 'overdue' ELSE 'current' END AS cadence_status
FROM ${catalog}.${css_schema}.gold_zone_count_coverage
ORDER BY store_id, days_since_last_count DESC;


-- 25. Observed OOS episodes: detection, duration, and investigation candidate flags.
-- Keep ongoing episodes separate and filter on severity/quality as needed.
SELECT
  store_id,
  store_zone_id,
  product_id,
  episode_start_ts,
  episode_duration_minutes,
  is_ongoing,
  supporting_observation_count,
  supporting_device_count,
  detection_method,
  candidate_reason,
  candidate_severity,
  is_phantom_stock_candidate,
  data_quality_flag,
  min_confidence_score
FROM ${catalog}.${css_schema}.gold_observed_oos_episodes
WHERE is_ongoing OR episode_duration_minutes >= 60
ORDER BY is_ongoing DESC, episode_duration_minutes DESC, store_id, store_zone_id;


-- 26. Current RFID item state: latest attribution, disposition, and freshness.
-- Stray-suspected reads are excluded from current presence.
SELECT
  store_id,
  store_zone_id,
  product_id,
  tagged_item_id,
  derived_presence_state,
  derived_disposition_uri,
  attribution_confidence,
  latest_event_ts,
  freshness_age_minutes,
  zone_source,
  is_mobile_platform
FROM ${catalog}.${css_schema}.gold_item_current_state
WHERE derived_presence_state = 'present'
ORDER BY store_id, store_zone_id, attribution_confidence DESC;


-- 27. Automation loop response ledger: all firings end-to-end from sense to act.
-- Query the gold view for exact versions that ran, not today's configuration.
SELECT
  triggered_at_timestamp,
  store_id,
  device_type,
  rule_name,
  report_type,
  breach_value,
  threshold_value_numeric,
  breach_margin,
  action_type,
  execution_status,
  latency_ms,
  response_latency_band
FROM ${catalog}.${css_schema}.gold_css_automation_response
WHERE triggered_at_timestamp >= current_timestamp() - INTERVAL 7 DAYS
ORDER BY triggered_at_timestamp DESC;


-- 28. RFID item visibility quality: read volume, deduplication, and attribution confidence.
-- Stray and unregistered reads are captured separately so quality can be diagnosed.
SELECT
  store_id,
  product_id,
  trading_date,
  read_event_count,
  distinct_items_read,
  unregistered_read_count,
  stray_read_count,
  duplicate_delivery_count,
  avg_attribution_confidence,
  arrival_lag_seconds_p95,
  freshness_age_minutes
FROM ${catalog}.${css_schema}.gold_item_visibility_daily
WHERE trading_date >= current_date() - INTERVAL 7 DAYS
ORDER BY trading_date DESC, read_event_count DESC;

-- ---- IoT environmental monitoring ----

-- 29. Latest day non-compliant devices: which refrigeration units are out of spec?
SELECT
  store_id,
  equipment_id,
  sensor_device_id,
  max_value,
  threshold_value,
  share_intervals_in_range,
  breach_interval_count
FROM ${catalog}.${css_schema}.gold_css_environmental_compliance_daily
WHERE trading_date = (SELECT MAX(trading_date) FROM ${catalog}.${css_schema}.gold_css_environmental_compliance_daily)
  AND is_compliant = FALSE
ORDER BY
  share_intervals_in_range ASC,
  max_value DESC;

-- 30. Excursion episodes in the last 7 days: find ones with no successful automation action
SELECT
  sensor_device_id,
  equipment_id,
  episode_start_ts,
  episode_end_ts,
  duration_minutes,
  peak_value,
  has_successful_action,
  is_open_at_dataset_end,
  minutes_to_first_successful_action
FROM ${catalog}.${css_schema}.gold_css_excursion_episodes
WHERE trading_date_of_start >= DATE_SUB((SELECT MAX(trading_date_of_start) FROM ${catalog}.${css_schema}.gold_css_excursion_episodes), 7)
  AND has_successful_action = FALSE
ORDER BY
  episode_start_ts DESC;

-- 31. Control-loop responsiveness: rules with slow response times
SELECT
  store_id,
  evaluation_rule_id,
  trading_date,
  firings,
  successful_firings,
  avg_latency_ms,
  max_latency_ms,
  CAST(successful_firings / CAST(NULLIF(firings, 0) AS DOUBLE) AS DECIMAL(5, 2)) AS success_rate
FROM ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily
WHERE trading_date >= DATE_SUB((SELECT MAX(trading_date) FROM ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily), 3)
  AND avg_latency_ms > 500
ORDER BY
  avg_latency_ms DESC;

-- 32. Compliance trend: rolling 7-day compliance rate by device
SELECT
  sensor_device_id,
  equipment_id,
  CAST(AVG(share_intervals_in_range) AS DECIMAL(5, 2)) AS rolling_compliance_rate,
  CAST(COUNT(*) AS BIGINT) AS days_observed
FROM ${catalog}.${css_schema}.gold_css_environmental_compliance_daily
WHERE trading_date >= DATE_SUB((SELECT MAX(trading_date) FROM ${catalog}.${css_schema}.gold_css_environmental_compliance_daily), 7)
  AND report_type = 'gs1:Temperature'
GROUP BY
  sensor_device_id,
  equipment_id
ORDER BY
  rolling_compliance_rate ASC;

-- 33. Control-loop response: what share of episodes had a successful automation action?
SELECT
  CAST(COUNT(CASE WHEN has_successful_action = TRUE THEN 1 END)
       / CAST(NULLIF(COUNT(*), 0) AS DOUBLE) AS DECIMAL(5, 2)) AS successful_action_share,
  CAST(AVG(CASE WHEN minutes_to_first_successful_action IS NOT NULL
                THEN minutes_to_first_successful_action
                ELSE NULL END) AS INT) AS avg_minutes_to_first_successful_action,
  CAST(COUNT(*) AS BIGINT) AS total_episodes
FROM ${catalog}.${css_schema}.gold_css_excursion_episodes
WHERE trading_date_of_start >= DATE_SUB((SELECT MAX(trading_date_of_start) FROM ${catalog}.${css_schema}.gold_css_excursion_episodes), 30)
  AND is_open_at_dataset_end = FALSE;
