-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce
-- Metric View: agent_performance
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-02 by @shubhamp051991
-- ============================================================
-- Per-agent performance metrics: sessions participated, success rate, and
-- average time to completion, sliced by agent role, operator, and trust status.
-- Grained at agent level via gold_a2a_agent_scorecard.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${ac_schema}.mv_agent_performance
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Per-agent performance for agent-to-agent commerce: participation, success rate, and time to completion by role, operator, and trust status."
source: >
  SELECT
    sc.a2a_agent_id,
    sc.agent_role,
    sc.operator_name,
    sc.trust_status,
    sc.sessions_participated,
    sc.sessions_completed,
    sc.success_rate,
    sc.avg_time_to_completion_seconds
  FROM ${catalog}.${ac_schema}.gold_a2a_agent_scorecard sc

fields:
  - name: a2a_agent_id
    expr: a2a_agent_id
    display_name: "Agent ID"
    comment: "Durable business key for the agent."
    synonyms: ["agent", "bot_id", "agent_id"]

  - name: agent_role
    expr: agent_role
    display_name: "Agent Role"
    comment: "Which side the agent acts for: buyer_agent or seller_agent."
    synonyms: ["role", "side", "party"]

  - name: operator_name
    expr: operator_name
    display_name: "Operator"
    comment: "Organization or platform operating the agent."
    synonyms: ["operator", "provider", "platform"]

  - name: trust_status
    expr: trust_status
    display_name: "Trust Status"
    comment: "Verification/trust state: unverified, verified, suspended, revoked."
    synonyms: ["trust", "verification_status", "trust_level"]

measures:
  - name: agent_count
    expr: COUNT(DISTINCT a2a_agent_id)
    display_name: "Agent Count"
    comment: "Number of distinct agents."
    synonyms: ["num_agents", "total_agents"]

  - name: total_sessions_participated
    expr: SUM(sessions_participated)
    display_name: "Sessions Participated"
    comment: "Total agent-session participations (a session with two agents counts for both)."
    synonyms: ["participations", "involvement_count"]

  - name: total_sessions_completed
    expr: SUM(sessions_completed)
    display_name: "Sessions Completed"
    comment: "Total participations that ended in a completed session."
    synonyms: ["completed_participations", "wins"]

  - name: success_rate
    expr: CAST(SUM(sessions_completed) AS DOUBLE) / NULLIF(SUM(sessions_participated), 0)
    display_name: "Success Rate (pooled)"
    comment: "Pooled success rate across the selected agents: total completed participations / total participations. Weights each session equally (a busy agent counts more), which is what most users expect from a rate."
    synonyms: ["win_rate", "completion_rate", "pooled_success_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: avg_success_rate_per_agent
    expr: AVG(success_rate)
    display_name: "Avg Success Rate (per-agent mean)"
    comment: "Mean of per-agent success rates — each agent weighs equally regardless of session volume, so a one-session agent counts as much as a 500-session one. Use success_rate for the pooled rate."
    synonyms: ["mean_success_rate", "macro_success_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: avg_time_to_completion_minutes
    expr: AVG(avg_time_to_completion_seconds) / 60.0
    display_name: "Avg Time to Completion (per-agent mean, min)"
    comment: "Mean of per-agent average minutes from session start to completion, on completed sessions — each agent weighs equally regardless of volume. Completion is the terminal lifecycle timestamp, which can trail the acceptance event."
    synonyms: ["avg_deal_time", "negotiation_speed"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1
$$;
