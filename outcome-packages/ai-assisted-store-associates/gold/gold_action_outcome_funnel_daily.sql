-- ============================================================
-- ORDM · Outcome Package · AI-Assisted Store Associates
-- View: gold_action_outcome_funnel_daily
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Promotable to a materialized view.
-- Version: 0.5
-- Generated: 2026-08-29
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-29
-- ============================================================
-- The Next Best Action feedback funnel, one row per store x zone x associate x trading
-- date x action_type: how many actions were generated, accepted, rejected, completed and
-- expired, the acceptance/completion rates, average time-to-first-response, and the
-- realized monetary outcome. This is the optimization surface — it turns the response and
-- outcome logs into the ROI signal and the labeled history for future models.
--
-- The associate and zone dimensions are carried (not collapsed): per-associate
-- effectiveness feeds mv_associate_action_performance, and the zone grain exposes the
-- "rejections concentrated in one zone = a staffing signal" question the response log is
-- designed to answer. associate_id / store_zone_id may be NULL (unrouted / no target zone),
-- which forms their own honest bucket.
--
-- Lifecycle counts are derived from the APPEND-ONLY action_response_log, not from a mutable
-- status: accepted/rejected/completed/expired each come from a response event, so the
-- funnel never depends on restating suggested_action.
--
-- SCD2 join contract (§A.16): only append-only facts are read (none are SCD2), and every
-- aggregation key is a DURABLE id plus the trading date — no version-specific `_sk` in a
-- GROUP BY or COUNT(DISTINCT). Currency is collapsed with MIN(), safe because
-- outcome_resolution is single-currency (or_single_currency in checks.sql).
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily AS
WITH actions AS (
  SELECT
    suggested_action_id,
    associate_id,
    store_id,
    store_zone_id,
    action_type,
    generated_timestamp,
    CAST(generated_timestamp AS DATE) AS trading_date
  FROM ${catalog}.${aasa_schema}.suggested_action
),
responses AS (
  SELECT
    suggested_action_id,
    MIN(response_timestamp) AS first_response_ts,
    MAX(CASE WHEN response_type = 'accepted'  THEN 1 ELSE 0 END) AS was_accepted,
    MAX(CASE WHEN response_type = 'rejected'  THEN 1 ELSE 0 END) AS was_rejected,
    MAX(CASE WHEN response_type = 'completed' THEN 1 ELSE 0 END) AS was_completed,
    MAX(CASE WHEN response_type = 'expired'   THEN 1 ELSE 0 END) AS was_expired
  FROM ${catalog}.${aasa_schema}.action_response_log
  GROUP BY suggested_action_id
),
outcomes AS (
  SELECT
    suggested_action_id,
    SUM(outcome_value_amount) AS realized_value,
    MIN(currency_code)        AS currency_code,
    SUM(CASE WHEN outcome_type = 'sale_closed' THEN 1 ELSE 0 END) AS sale_closed_count
  FROM ${catalog}.${aasa_schema}.outcome_resolution
  GROUP BY suggested_action_id
)
SELECT
  a.store_id,
  a.store_zone_id,
  a.associate_id,
  a.trading_date,
  a.action_type,
  COUNT(*)                                                                    AS actions_generated,
  SUM(COALESCE(r.was_accepted, 0))                                            AS actions_accepted,
  SUM(COALESCE(r.was_rejected, 0))                                            AS actions_rejected,
  SUM(COALESCE(r.was_completed, 0))                                           AS actions_completed,
  SUM(COALESCE(r.was_expired, 0))                                             AS actions_expired,
  ROUND(SUM(COALESCE(r.was_accepted, 0))  / NULLIF(COUNT(*), 0), 4)           AS acceptance_rate,
  ROUND(SUM(COALESCE(r.was_completed, 0)) / NULLIF(COUNT(*), 0), 4)           AS completion_rate,
  ROUND(AVG(CASE WHEN r.first_response_ts IS NOT NULL
                 THEN unix_timestamp(r.first_response_ts) - unix_timestamp(a.generated_timestamp) END), 1) AS avg_response_seconds,
  -- Additive components so the metric view can re-aggregate the average as SUM/SUM.
  SUM(CASE WHEN r.first_response_ts IS NOT NULL
           THEN unix_timestamp(r.first_response_ts) - unix_timestamp(a.generated_timestamp) ELSE 0 END) AS response_seconds_total,
  SUM(CASE WHEN r.first_response_ts IS NOT NULL THEN 1 ELSE 0 END)            AS responses_timed,
  SUM(COALESCE(o.sale_closed_count, 0))                                       AS sales_closed,
  SUM(COALESCE(o.realized_value, 0))                                          AS realized_outcome_value,
  MIN(o.currency_code)                                                        AS outcome_currency_code,
  current_timestamp() AS fresh_as_of_ts
FROM actions a
LEFT JOIN responses r ON a.suggested_action_id = r.suggested_action_id
LEFT JOIN outcomes  o ON a.suggested_action_id = o.suggested_action_id
GROUP BY a.store_id, a.store_zone_id, a.associate_id, a.trading_date, a.action_type;
