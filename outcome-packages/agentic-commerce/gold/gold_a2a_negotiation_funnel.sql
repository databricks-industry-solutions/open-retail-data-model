-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce
-- View: gold_a2a_negotiation_funnel
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-02 by @shubhamp051991
-- ============================================================
-- The A2A negotiation funnel, aggregated by day x channel x product. Each
-- session is counted once at each stage it reached, so downstream can chart
-- initiated -> negotiated -> agreed -> completed conversion and the loss
-- (abandoned / failed / expired) by cut. Grain: one row per
-- (session_date, communication_channel, product_id). NOTE: product_id is
-- nullable on a2a_session (a session need not name a primary product), so all
-- product-less sessions for a given day x channel collapse into one row with a
-- NULL product_id — read that NULL bucket as "no primary product", not missing data.
--
-- Reached-stages are derived from the IMMUTABLE event log, not the mutable
-- session_status: a session that negotiated then failed still reached the
-- negotiating stage, and a session that agreed then expired still reached
-- agreed. Reading current status would undercount those (a fail/expire would
-- erase the earlier stages it passed through). session_status is used only for
-- the terminal cuts (completed / lost), which ARE current-state by definition.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${ac_schema}.gold_a2a_negotiation_funnel AS
WITH session_reached AS (
  -- What each session actually reached, from the event history.
  SELECT
    a2a_session_sk,
    COUNT(*) FILTER (WHERE event_type IN ('offer', 'counter_offer')) > 0  AS reached_negotiating,
    COUNT(*) FILTER (WHERE event_type = 'acceptance') > 0                 AS reached_agreed
  FROM ${catalog}.${ac_schema}.a2a_negotiation_event
  GROUP BY a2a_session_sk
)
SELECT
  DATE(s.initiated_timestamp)                                                  AS session_date,
  s.communication_channel,
  s.product_id,
  COUNT(*)                                                                     AS sessions_initiated,
  COUNT(*) FILTER (WHERE COALESCE(r.reached_negotiating, FALSE))               AS reached_negotiating,
  COUNT(*) FILTER (WHERE COALESCE(r.reached_agreed, FALSE))                    AS reached_agreed,
  COUNT(*) FILTER (WHERE s.session_status = 'completed')                       AS completed,
  COUNT(*) FILTER (WHERE s.session_status IN ('abandoned', 'failed', 'expired')) AS lost,
  CAST(COUNT(*) FILTER (WHERE s.session_status = 'completed') AS DOUBLE)
    / NULLIF(COUNT(*), 0)                                                      AS completion_rate
FROM ${catalog}.${ac_schema}.a2a_session s
LEFT JOIN session_reached r ON r.a2a_session_sk = s.a2a_session_sk
GROUP BY DATE(s.initiated_timestamp), s.communication_channel, s.product_id;
