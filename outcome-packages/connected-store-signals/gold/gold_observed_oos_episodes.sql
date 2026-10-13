-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_observed_oos_episodes
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Ideal Lakebase serving projection.
-- Version: 0.5
-- Generated: 2026-08-20
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-20
-- ============================================================
-- GRAIN: one row per observed out-of-stock EPISODE (store × position × product ×
-- episode start): a maximal run of consecutive usable out_of_stock observations,
-- closed by the next usable non-OOS observation (recovery) or ongoing (recovery NULL).
--
-- Serves the shelf-gap-dwell-time KPI (UC-RET-0204) — the episode-shaped quantity a
-- firing-shaped fact cannot answer — and shapes the SDI seam: column names mirror the
-- merged gold_rfid_oos_candidates precedent (detection_method / candidate_reason /
-- candidate_severity / data_quality_flag / evidence_at_ts / record_source) so
-- SDI-side pipelines ingest ONE shape from both use cases, with episode start/end/
-- duration added on top. SDI's chk_oe_detection already admits 'smart_shelf'; CSS
-- never writes ${sdi_schema} (ADR 0024).
--
-- Episode detection runs over USABLE observations only (valid-ish AND state known):
-- an unknown/invalid capture neither starts, sustains, nor closes an episode — it is
-- sensing silence, and the episode's evidence columns say how solid the run is.
-- Ongoing episodes age against the named clock ${shelf_as_of_ts} (ADR 0038 pattern).
--
-- Phantom-stock candidacy: episode overlaps positive EOD book stock on its start date
-- (core inventory_position, read-only) — the oos_cause enrichment SDI expects.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_observed_oos_episodes AS
WITH usable AS (
  SELECT
    o.*,
    CASE WHEN o.shelf_state = 'out_of_stock' THEN 1 ELSE 0 END AS is_oos
  FROM ${catalog}.${css_schema}.shelf_state_observation o
  WHERE COALESCE(o.measurement_validity, 'valid') <> 'invalid'
    AND o.shelf_state <> 'unknown'
), sequenced AS (
  SELECT
    *,
    LAG(is_oos) OVER (
      PARTITION BY store_zone_id, product_id
      ORDER BY observation_ts, ingest_timestamp, shelf_state_observation_id
    ) AS prev_is_oos,
    MIN(CASE WHEN is_oos = 0 THEN observation_ts END) OVER (
      PARTITION BY store_zone_id, product_id
      ORDER BY observation_ts, ingest_timestamp, shelf_state_observation_id
      ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING
    ) AS next_recovery_ts
  FROM usable
), grouped AS (
  SELECT
    *,
    SUM(CASE WHEN is_oos = 1 AND COALESCE(prev_is_oos, 0) = 0 THEN 1 ELSE 0 END) OVER (
      PARTITION BY store_zone_id, product_id
      ORDER BY observation_ts, ingest_timestamp, shelf_state_observation_id
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS episode_group
  FROM sequenced
), episodes AS (
  -- Grouped on DURABLE ids only (§A.16): an episode may span dimension re-versions, so
  -- no single version `_sk` truthfully represents it; consumers resolve dims as-of.
  SELECT
    store_id,
    store_zone_id,
    product_id,
    episode_group,
    MIN(observation_ts) AS episode_start_ts,
    MAX(observation_ts) AS last_oos_observed_ts,
    -- Every row in one episode shares the same next usable non-OOS instant.
    MIN(next_recovery_ts) AS episode_recovery_ts,
    MIN(trading_date) AS episode_start_date,
    COUNT(*) AS supporting_observation_count,
    COUNT(DISTINCT sensor_device_id) AS supporting_device_count,
    MIN(confidence_score) AS min_confidence_score,
    MAX(CASE WHEN COALESCE(measurement_validity, 'valid') <> 'valid' THEN 1 ELSE 0 END) AS has_degraded_evidence
  FROM grouped
  WHERE is_oos = 1
  GROUP BY store_id, store_zone_id, product_id, episode_group
)
SELECT
  concat_ws('|', e.store_zone_id, e.product_id, CAST(e.episode_start_ts AS STRING)) AS oos_episode_id,
  e.store_id,
  e.store_zone_id,
  e.product_id,
  e.episode_start_ts,
  e.episode_start_date,
  e.episode_recovery_ts,
  e.episode_recovery_ts IS NULL AS is_ongoing,
  -- Dwell: to recovery when closed; to the evaluation clock when ongoing.
  timestampdiff(MINUTE, e.episode_start_ts,
                COALESCE(e.episode_recovery_ts, ${shelf_as_of_ts})) AS episode_duration_minutes,
  e.last_oos_observed_ts,
  e.supporting_observation_count,
  e.supporting_device_count,
  e.min_confidence_score,

  -- SDI-ingestible candidate shape (gold_rfid_oos_candidates precedent).
  'smart_shelf' AS detection_method,
  CASE WHEN inv.units_on_hand_eod > 0 THEN 'phantom_stock' ELSE 'unknown' END AS candidate_reason,
  CASE
    WHEN timestampdiff(MINUTE, e.episode_start_ts,
                       COALESCE(e.episode_recovery_ts, ${shelf_as_of_ts})) >= 1440 THEN 'high'
    WHEN timestampdiff(MINUTE, e.episode_start_ts,
                       COALESCE(e.episode_recovery_ts, ${shelf_as_of_ts})) >= 240  THEN 'medium'
    ELSE 'low'
  END AS candidate_severity,
  e.has_degraded_evidence = 1 AS data_quality_flag,
  e.last_oos_observed_ts AS evidence_at_ts,
  inv.units_on_hand_eod AS book_units_eod_at_start,
  inv.units_on_hand_eod > 0 AS is_phantom_stock_candidate,
  'ordm.connected_store_signals.smart_shelf' AS record_source,
  CAST(${shelf_as_of_ts} AS TIMESTAMP) AS fresh_as_of_ts
FROM episodes e
LEFT JOIN ${catalog}.${inventory_schema}.inventory_position inv
  ON e.store_id = inv.store_id
 AND e.product_id = inv.product_id
 AND e.episode_start_date = inv.date_key;
