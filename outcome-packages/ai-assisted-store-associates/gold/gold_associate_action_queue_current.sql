-- ============================================================
-- ORDM · Outcome Package · AI-Assisted Store Associates
-- View: gold_associate_action_queue_current
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Promotable to a materialized view
--   for serving latency; the definition is unchanged.
-- Version: 0.5
-- Generated: 2026-08-29
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-29
-- ============================================================
-- The live prioritized Next Best Action queue an associate sees: one row per OPEN,
-- non-expired suggested action, ranked within each associate by the time-decayed
-- Business Value Score. This is the "Associates Best Next Actions" serving surface.
--
-- LIFECYCLE IS DERIVED, NOT STORED. suggested_action is append-only (one row per action
-- generated); an action is OPEN when the append-only action_response_log holds no
-- TERMINAL response (rejected / completed / expired) for it and it has not passed its
-- expiration. current_state is the latest non-terminal response (pending if none). This
-- keeps the model free of mutable workflow write-state (§0).
--
-- SCORE IS DECAYED HERE. suggested_action.priority_score is the score at generation;
-- this view applies decay_type from generated_timestamp (linear / exponential; immediate
-- and none hold the generation score until nullified by an 'expired' response), so the
-- stored score is never rewritten. Formulas are the glossary's.
--
-- SCD2 join contract (§A.16): associate is SCD2, joined on its version-specific PK
-- surrogate (associate_sk = the version at dispatch) — an as-of-correct 1:1 equi-join
-- with NO `is_current` filter; the queue is partitioned/ranked on the DURABLE
-- associate_id so a re-versioned associate does not fragment their queue.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${aasa_schema}.gold_associate_action_queue_current AS
WITH resp AS (
  SELECT
    suggested_action_id,
    MAX(CASE WHEN response_type IN ('rejected', 'completed', 'expired') THEN 1 ELSE 0 END) AS has_terminal,
    max_by(response_type, response_timestamp) AS latest_response_type
  FROM ${catalog}.${aasa_schema}.action_response_log
  GROUP BY suggested_action_id
),
open_actions AS (
  SELECT
    sa.suggested_action_id,
    sa.associate_sk,
    sa.associate_id,
    sa.store_id,
    sa.store_zone_id,
    sa.profile_id,
    sa.product_id,
    sa.action_type,
    sa.trigger_source,
    sa.base_score,
    sa.priority_score,
    sa.decay_type,
    sa.context_payload,
    sa.generated_timestamp,
    sa.expiration_timestamp,
    COALESCE(r.latest_response_type, 'pending') AS current_state,
    (unix_timestamp(current_timestamp()) - unix_timestamp(sa.generated_timestamp)) / 60.0 AS elapsed_minutes,
    CASE WHEN sa.expiration_timestamp IS NULL THEN NULL
         ELSE (unix_timestamp(sa.expiration_timestamp) - unix_timestamp(current_timestamp())) / 60.0
    END AS minutes_to_expiry
  FROM ${catalog}.${aasa_schema}.suggested_action sa
  LEFT JOIN resp r ON sa.suggested_action_id = r.suggested_action_id
  WHERE COALESCE(r.has_terminal, 0) = 0
    AND (sa.expiration_timestamp IS NULL OR sa.expiration_timestamp > current_timestamp())
),
scored AS (
  SELECT
    o.*,
    CASE
      WHEN o.decay_type = 'linear'      THEN GREATEST(o.priority_score - o.elapsed_minutes * 0.5, 0)
      WHEN o.decay_type = 'exponential' THEN o.priority_score * pow(0.8, o.elapsed_minutes)
      ELSE o.priority_score
    END AS current_priority_score
  FROM open_actions o
)
SELECT
  s.associate_id,
  a.role                AS associate_role,
  a.skill_tags          AS associate_skill_tags,
  s.store_id,
  s.store_zone_id,
  s.suggested_action_id,
  s.action_type,
  s.trigger_source,
  s.base_score,
  s.priority_score,
  ROUND(s.current_priority_score, 2) AS current_priority_score,
  s.decay_type,
  s.current_state,
  s.profile_id,
  s.product_id,
  s.generated_timestamp,
  s.expiration_timestamp,
  ROUND(s.minutes_to_expiry, 1) AS minutes_to_expiry,
  ROW_NUMBER() OVER (PARTITION BY s.associate_id ORDER BY s.current_priority_score DESC, s.generated_timestamp) AS queue_rank,
  s.context_payload,
  current_timestamp() AS fresh_as_of_ts
FROM scored s
LEFT JOIN ${catalog}.${aasa_schema}.associate a
  ON s.associate_sk = a.associate_sk;
