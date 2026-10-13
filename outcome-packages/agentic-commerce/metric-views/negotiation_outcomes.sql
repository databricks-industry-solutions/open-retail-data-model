-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce
-- Metric View: negotiation_outcomes
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-02 by @shubhamp051991
-- ============================================================
-- Negotiation outcome metrics per A2A session: completion rate,
-- human-escalation rate, and time to completion. Grained at session level via
-- gold_a2a_session_summary; aggregatable by channel, product, and date.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${ac_schema}.mv_negotiation_outcomes
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Agent-to-agent negotiation outcomes per session: completion rate, human-escalation rate, and time to completion."
source: >
  SELECT
    s.a2a_session_id,
    s.session_status,
    s.communication_channel,
    s.product_id,
    s.initiated_timestamp,
    CAST(s.initiated_timestamp AS DATE) AS session_date,
    s.escalated_to_human,
    s.event_count,
    s.counter_offer_count,
    s.duration_seconds,
    CASE WHEN s.session_status = 'completed' THEN 1 ELSE 0 END AS is_completed
  FROM ${catalog}.${ac_schema}.gold_a2a_session_summary s

fields:
  - name: a2a_session_id
    expr: a2a_session_id
    display_name: "Session ID"
    comment: "Durable business key for the agent-to-agent session."
    synonyms: ["session", "negotiation_id", "session_id"]

  - name: session_status
    expr: session_status
    display_name: "Session Status"
    comment: "Lifecycle status: initiated, negotiating, agreed, completed, abandoned, failed, expired."
    synonyms: ["status", "state", "outcome"]

  - name: communication_channel
    expr: communication_channel
    display_name: "Channel"
    comment: "Communication channel between the agents: api, marketplace, direct, voice."
    synonyms: ["channel", "medium", "interface"]

  - name: product_id
    expr: product_id
    display_name: "Product ID"
    comment: "Durable business key for the primary product under negotiation."
    synonyms: ["SKU", "item_id", "product"]

  - name: session_date
    expr: session_date
    display_name: "Session Date"
    comment: "Calendar date the session started."
    synonyms: ["date", "day", "initiated_date"]
    format:
      type: date
      date_format: year_month_day

measures:
  - name: session_count
    expr: COUNT(*)
    display_name: "Session Count"
    comment: "Number of agent-to-agent sessions."
    synonyms: ["negotiations", "total_sessions", "num_sessions"]

  - name: completed_count
    expr: SUM(is_completed)
    display_name: "Completed Sessions"
    comment: "Number of sessions that reached completed status."
    synonyms: ["wins", "closed_deals", "successful_sessions"]

  - name: completion_rate
    expr: CAST(SUM(is_completed) AS DOUBLE) / NULLIF(COUNT(*), 0)
    display_name: "Completion Rate"
    comment: "Fraction of sessions that completed (reached a transaction)."
    synonyms: ["win_rate", "conversion_rate", "session_completion_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: human_escalation_rate
    expr: CAST(COUNT(*) FILTER (WHERE escalated_to_human = TRUE) AS DOUBLE) / NULLIF(COUNT(*), 0)
    display_name: "Human Escalation Rate"
    comment: "Fraction of sessions that escalated to a human. Lower = more autonomous."
    synonyms: ["escalation_rate", "handoff_rate", "human_in_loop_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: avg_time_to_completion_minutes
    expr: AVG(duration_seconds) FILTER (WHERE session_status = 'completed') / 60.0
    display_name: "Avg Time to Completion (min)"
    comment: "Average minutes from session start to completion, for completed sessions. Completion is the terminal lifecycle timestamp, which can trail the acceptance event."
    synonyms: ["time_to_close", "negotiation_duration", "avg_deal_time"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: avg_counter_offers
    expr: AVG(counter_offer_count)
    display_name: "Avg Counter-Offers"
    comment: "Average number of counter-offers per session (negotiation intensity)."
    synonyms: ["avg_rounds", "negotiation_rounds", "back_and_forth"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1
$$;
