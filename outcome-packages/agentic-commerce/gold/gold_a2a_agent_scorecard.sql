-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce
-- View: gold_a2a_agent_scorecard
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-02 by @shubhamp051991
-- ============================================================
-- Per-agent performance scorecard. Attributes each session to the agents on
-- both sides (initiating and responding), then aggregates outcome metrics per
-- agent: how many sessions it took part in, how many completed, its success
-- rate, and average time to completion. Joins the current a2a_agent version for
-- role/operator/trust context. Note: this measures start -> completed (the
-- terminal lifecycle timestamp on the session), NOT start -> acceptance event;
-- agreement (the acceptance event) can precede completion, so this is the wider
-- end-to-end duration, named accordingly.
--
-- An agent appears once per session it participated in (as initiator OR
-- responder), so a session with two agents contributes to both scorecards —
-- this is per-agent participation, intentionally not a session count.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${ac_schema}.gold_a2a_agent_scorecard AS
WITH participation AS (
  -- Unpivot the two agent roles on each session into one row per (agent, session).
  SELECT initiating_agent_id AS a2a_agent_id, 'initiator' AS participated_as,
         session_status, initiated_timestamp, completed_timestamp
  FROM ${catalog}.${ac_schema}.a2a_session
  WHERE initiating_agent_id IS NOT NULL
  UNION ALL
  SELECT responding_agent_id AS a2a_agent_id, 'responder' AS participated_as,
         session_status, initiated_timestamp, completed_timestamp
  FROM ${catalog}.${ac_schema}.a2a_session
  WHERE responding_agent_id IS NOT NULL
),
agg AS (
  SELECT
    a2a_agent_id,
    COUNT(*)                                                             AS sessions_participated,
    COUNT(*) FILTER (WHERE session_status = 'completed')                 AS sessions_completed,
    CAST(COUNT(*) FILTER (WHERE session_status = 'completed') AS DOUBLE)
      / NULLIF(COUNT(*), 0)                                              AS success_rate,
    AVG(DATEDIFF(SECOND, initiated_timestamp, completed_timestamp))
      FILTER (WHERE session_status = 'completed')                        AS avg_time_to_completion_seconds
  FROM participation
  GROUP BY a2a_agent_id
)
SELECT
  a.a2a_agent_id,
  ag_cur.agent_name,
  ag_cur.agent_role,
  ag_cur.operator_name,
  ag_cur.trust_status,
  a.sessions_participated,
  a.sessions_completed,
  a.success_rate,
  a.avg_time_to_completion_seconds
FROM agg a
LEFT JOIN ${catalog}.${ac_schema}.a2a_agent ag_cur
  ON ag_cur.a2a_agent_id = a.a2a_agent_id AND ag_cur.is_current = TRUE;
