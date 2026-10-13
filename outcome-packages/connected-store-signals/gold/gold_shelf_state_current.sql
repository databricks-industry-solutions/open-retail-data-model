-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_shelf_state_current
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Ideal Lakebase serving projection.
-- Version: 0.5
-- Generated: 2026-08-20
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-20
-- ============================================================
-- GRAIN: one row per shelf-position zone × product — the LATEST capture, always.
--
-- LATEST-CAPTURE-WINS (H2): the newest observation is selected BEFORE any usability
-- judgment, and unknown/invalid/stale readings stay the current truth. Filtering
-- validity before ranking would resurrect an older good reading past a newer occluded
-- or unknown capture — a broken sensor masquerading as availability, the exact failure
-- OSA exists to catch. Usability is a FLAG (is_usable: validity <> invalid AND state <>
-- unknown); compliance flags are NULL on non-usable rows, never silently compliant.
--
-- Staleness is likewise a flag, evaluated against the named clock ${shelf_as_of_ts}
-- (ADR 0038 pattern, second consumer) with platform-dependent windows
-- (${shelf_fixed_freshness_minutes} fixed / ${shelf_mobile_freshness_minutes} mobile
-- starter minutes); the evaluation instant is propagated as fresh_as_of_ts so filtering
-- and freshness reporting cannot diverge.
--
-- Expected state resolves through the version-pinned assignment _sk the observation
-- captured at write (§A.16: plain equi-join on the SCD2 PRIMARY KEY, no is_current) —
-- compliance is judged against the contract IN EFFECT AT CAPTURE, not today's.
--
-- The four compliance dimensions (presence, position, facings, price tag) are computed
-- here once so gold_planogram_compliance_current and the metric views inherit ONE
-- definition. Ratios live downstream; this view stays row-grain.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_shelf_state_current AS
WITH ranked AS (
  -- Rank over every observation at or before the named evaluation clock: no validity
  -- or state filter may precede this (H2), and future evidence cannot become current.
  SELECT
    o.*,
    ROW_NUMBER() OVER (
      PARTITION BY o.store_zone_id, o.product_id
      ORDER BY o.observation_ts DESC, o.ingest_timestamp DESC, o.shelf_state_observation_id DESC
    ) AS state_rank
  FROM ${catalog}.${css_schema}.shelf_state_observation o
  JOIN (SELECT CAST(${shelf_as_of_ts} AS TIMESTAMP) AS as_of_ts) clock
    ON o.observation_ts <= clock.as_of_ts
), latest AS (
  -- Enrich only AFTER ranking. Even an orphaned latest device key must not cause the
  -- previous observation to masquerade as current; the DQ layer reports the orphan.
  SELECT r.*, d.is_mobile_platform
  FROM ranked r
  LEFT JOIN ${catalog}.${css_schema}.sensor_device d
    ON r.sensor_device_sk = d.sensor_device_sk
  WHERE r.state_rank = 1
)
SELECT
  l.store_sk,
  l.store_id,
  l.store_zone_sk,
  l.store_zone_id,
  l.product_sk,
  l.product_id,
  l.sensor_device_sk,
  l.sensor_device_id,
  l.is_mobile_platform,
  l.zone_source,
  l.source_capture_id,

  l.observation_ts,
  l.trading_date,
  l.shelf_state,
  l.observed_facing_count,
  l.estimated_unit_count,
  l.estimated_weight_grams,
  l.pick_count_since_prior,
  l.put_count_since_prior,
  l.min_facing_threshold,
  l.is_gap_detected,
  l.is_misplaced_detected,
  l.is_price_tag_mismatch_detected,
  l.measurement_validity,
  l.confidence_score,
  l.coverage_ratio,

  -- Usability of the CURRENT truth. FALSE does not hide the row; it tells the consumer
  -- the newest capture could not evaluate the shelf.
  COALESCE(l.measurement_validity, 'valid') <> 'invalid' AND l.shelf_state <> 'unknown' AS is_usable,

  -- Expected state, version-pinned to the assignment captured at observation time.
  l.shelf_position_assignment_id,
  a.expected_facing_count,
  a.min_facing_count,
  a.assignment_source,

  -- The four compliance dimensions, defined ONCE, evaluable only on usable rows.
  CASE WHEN COALESCE(l.measurement_validity, 'valid') = 'invalid' OR l.shelf_state = 'unknown'
       THEN CAST(NULL AS BOOLEAN)
       ELSE l.shelf_state IN ('in_stock', 'low_stock') END AS is_presence_compliant,
  CASE WHEN COALESCE(l.measurement_validity, 'valid') = 'invalid' OR l.shelf_state = 'unknown'
            OR l.is_misplaced_detected IS NULL
       THEN CAST(NULL AS BOOLEAN)
       ELSE NOT l.is_misplaced_detected END AS is_position_compliant,
  CASE WHEN COALESCE(l.measurement_validity, 'valid') = 'invalid' OR l.shelf_state = 'unknown'
            OR a.expected_facing_count IS NULL OR l.observed_facing_count IS NULL
       THEN CAST(NULL AS BOOLEAN)
       ELSE l.observed_facing_count >= a.expected_facing_count END AS is_facing_compliant,
  CASE WHEN COALESCE(l.measurement_validity, 'valid') = 'invalid' OR l.shelf_state = 'unknown'
            OR l.is_price_tag_mismatch_detected IS NULL
       THEN CAST(NULL AS BOOLEAN)
       ELSE NOT l.is_price_tag_mismatch_detected END AS is_price_tag_compliant,

  -- Freshness against the named evaluation clock; platform-dependent window.
  CAST(CASE
    WHEN l.is_mobile_platform THEN ${shelf_mobile_freshness_minutes}
    ELSE ${shelf_fixed_freshness_minutes}
  END AS INT) AS freshness_window_minutes,
  timestampdiff(MINUTE, l.observation_ts, ${shelf_as_of_ts}) AS freshness_age_minutes,
  timestampdiff(MINUTE, l.observation_ts, ${shelf_as_of_ts}) > CASE
    WHEN l.is_mobile_platform THEN ${shelf_mobile_freshness_minutes}
    ELSE ${shelf_fixed_freshness_minutes}
  END AS is_stale,
  CAST(${shelf_as_of_ts} AS TIMESTAMP) AS fresh_as_of_ts
FROM latest l
LEFT JOIN ${catalog}.${css_schema}.shelf_position_assignment a
  ON l.shelf_position_assignment_sk = a.shelf_position_assignment_sk;
