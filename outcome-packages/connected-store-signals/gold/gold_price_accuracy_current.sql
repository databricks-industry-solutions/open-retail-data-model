-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_price_accuracy_current
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Ideal Lakebase serving projection.
-- Version: 0.5
-- Generated: 2026-08-20
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-20
-- ============================================================
-- GRAIN: one row per store × trading_date × displayed currency.
--
-- Label-level accuracy uses the day's LAST price observation per label (any source):
-- match_rate answers "how many labels ended the day displaying the right price", the
-- HB130-style question. Overcharge (displayed > record) and undercharge are split and
-- never netted — regulators treat them asymmetrically. Signed deltas are never averaged
-- across labels; magnitudes are reported as absolute values (IoT-review M2 lesson).
-- A comparison is evaluable only when displayed and price-of-record currencies agree;
-- malformed cross-currency evidence stays observable but fails closed out of every
-- match, direction, correction-time, and mismatch-amount KPI.
--
-- Sync latency percentiles cover platform_ack rows only (the only source that measures
-- of-record-effective -> displayed), and inherit the B1 caveat: latency is only as good
-- as the captured price_of_record_effective_ts granularity.
--
-- Mismatch aging is INTRA-DAY: for labels with both a mismatch and a later match that
-- day, hours from first mismatch to first subsequent match (time-to-correct evidence);
-- max_open_mismatch_hours reports mismatches still open at the day's last observation,
-- aged to the end of their evidence, not to the reader's wall clock.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_price_accuracy_current AS
WITH currency_safe_obs AS (
  SELECT
    o.*,
    CASE
      WHEN o.displayed_price IS NOT NULL
       AND o.price_of_record IS NOT NULL
       AND o.displayed_currency_code = o.price_of_record_currency_code
      THEN o.is_price_match
    END AS comparable_is_price_match
  FROM ${catalog}.${css_schema}.esl_price_observation o
), obs AS (
  SELECT
    o.*,
    ROW_NUMBER() OVER (
      PARTITION BY o.esl_label_id, o.trading_date
      ORDER BY o.observed_at_ts DESC, o.ingest_timestamp DESC, o.esl_price_observation_id DESC
    ) AS day_rank_desc,
    MIN(CASE WHEN o.comparable_is_price_match = FALSE THEN o.observed_at_ts END) OVER (
      PARTITION BY o.esl_label_id, o.trading_date
    ) AS first_mismatch_ts_w,
    MAX(CASE WHEN o.comparable_is_price_match = TRUE THEN o.observed_at_ts END) OVER (
      PARTITION BY o.esl_label_id, o.trading_date
    ) AS last_match_ts_w
  FROM currency_safe_obs o
), label_day AS (
  SELECT
    store_id,
    trading_date,
    esl_label_id,
    -- Day's last observation per label decides the label's end-of-day accuracy state.
    MAX(CASE WHEN day_rank_desc = 1 THEN comparable_is_price_match END) AS eod_is_match,
    MAX(CASE WHEN day_rank_desc = 1 THEN displayed_currency_code END) AS currency_code,
    MAX(CASE WHEN day_rank_desc = 1 AND comparable_is_price_match = FALSE
              AND displayed_price > price_of_record THEN TRUE ELSE FALSE END) AS eod_is_overcharge,
    MAX(CASE WHEN day_rank_desc = 1 AND comparable_is_price_match = FALSE
              AND displayed_price < price_of_record THEN TRUE ELSE FALSE END) AS eod_is_undercharge,
    MAX(CASE WHEN day_rank_desc = 1 AND comparable_is_price_match = FALSE
             THEN abs(displayed_price - price_of_record) END) AS eod_mismatch_abs_amount,
    MIN(CASE WHEN comparable_is_price_match = FALSE THEN observed_at_ts END) AS first_mismatch_ts,
    MAX(observed_at_ts) AS last_observed_ts,
    -- Corrected-within-day: the first match observed AFTER the first mismatch.
    MIN(CASE WHEN comparable_is_price_match = TRUE AND observed_at_ts > first_mismatch_ts_w
             THEN observed_at_ts END) AS corrected_at_ts,
    -- If a corrected label mismatches again, age only the currently open episode:
    -- the first mismatch after the most recent match, not the day's first mismatch.
    MIN(CASE WHEN comparable_is_price_match = FALSE
                  AND (last_match_ts_w IS NULL OR observed_at_ts > last_match_ts_w)
             THEN observed_at_ts END) AS open_mismatch_start_ts,
    COUNT(*) AS observations,
    COUNT(CASE WHEN observation_source = 'platform_ack' THEN 1 END) AS ack_observations,
    COUNT(CASE WHEN observation_source = 'shelf_cv' THEN 1 END) AS cv_observations,
    COUNT(CASE WHEN observation_source = 'manual_audit' THEN 1 END) AS audit_observations
  FROM obs
  GROUP BY store_id, trading_date, esl_label_id
), latency AS (
  SELECT
    store_id,
    trading_date,
    percentile_approx(display_sync_latency_seconds, 0.5) AS sync_latency_p50_seconds,
    percentile_approx(display_sync_latency_seconds, 0.95) AS sync_latency_p95_seconds,
    MAX(display_sync_latency_seconds) AS sync_latency_max_seconds
  FROM ${catalog}.${css_schema}.esl_price_observation
  WHERE observation_source = 'platform_ack' AND display_sync_latency_seconds IS NOT NULL
  GROUP BY store_id, trading_date
)
SELECT
  ld.store_id,
  ld.trading_date,
  ld.currency_code,
  COUNT(*) AS labels_observed,
  SUM(ld.observations) AS price_observations,
  SUM(ld.ack_observations) AS ack_observations,
  SUM(ld.cv_observations) AS cv_observations,
  SUM(ld.audit_observations) AS audit_observations,
  COUNT(ld.eod_is_match) AS labels_evaluable,
  SUM(CASE WHEN ld.eod_is_match THEN 1 ELSE 0 END) AS labels_matched_eod,
  SUM(CASE WHEN ld.eod_is_match = FALSE THEN 1 ELSE 0 END) AS labels_mismatched_eod,
  SUM(CASE WHEN ld.eod_is_match THEN 1 ELSE 0 END)
    / NULLIF(COUNT(ld.eod_is_match), 0) AS price_match_rate_eod,
  SUM(CASE WHEN ld.eod_is_overcharge THEN 1 ELSE 0 END) AS labels_overcharging_eod,
  SUM(CASE WHEN ld.eod_is_undercharge THEN 1 ELSE 0 END) AS labels_undercharging_eod,
  AVG(ld.eod_mismatch_abs_amount) AS avg_mismatch_abs_amount,
  MAX(ld.eod_mismatch_abs_amount) AS max_mismatch_abs_amount,
  -- Time-to-correct evidence (intra-day): first mismatch -> first subsequent match.
  AVG(CASE WHEN ld.corrected_at_ts IS NOT NULL
           THEN timestampdiff(MINUTE, ld.first_mismatch_ts, ld.corrected_at_ts) / 60.0 END)
    AS avg_correction_hours,
  SUM(CASE WHEN ld.corrected_at_ts IS NOT NULL
           THEN timestampdiff(MINUTE, ld.first_mismatch_ts, ld.corrected_at_ts) / 60.0 END)
    AS correction_hours_total,
  SUM(CASE WHEN ld.corrected_at_ts IS NOT NULL THEN 1 ELSE 0 END) AS labels_corrected,
  -- Mismatches still open at the day's last evidence, aged to that evidence.
  MAX(CASE WHEN ld.eod_is_match = FALSE AND ld.open_mismatch_start_ts IS NOT NULL
           THEN timestampdiff(MINUTE, ld.open_mismatch_start_ts, ld.last_observed_ts) / 60.0 END)
    AS max_open_mismatch_hours,
  lt.sync_latency_p50_seconds,
  lt.sync_latency_p95_seconds,
  lt.sync_latency_max_seconds,
  CAST(${shelf_as_of_ts} AS TIMESTAMP) AS fresh_as_of_ts
FROM label_day ld
LEFT JOIN latency lt
  ON ld.store_id = lt.store_id AND ld.trading_date = lt.trading_date
GROUP BY ld.store_id, ld.trading_date, ld.currency_code,
         lt.sync_latency_p50_seconds, lt.sync_latency_p95_seconds, lt.sync_latency_max_seconds;
