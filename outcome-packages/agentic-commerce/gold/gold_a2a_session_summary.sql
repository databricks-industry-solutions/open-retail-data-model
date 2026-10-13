-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce
-- View: gold_a2a_session_summary
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-02 by @shubhamp051991
-- ============================================================
-- One row per A2A session with its negotiation outcome rolled up from the
-- append-only event log: how many steps, the first offer, the final agreed
-- price/quantity (from the acceptance event), whether a human was escalated
-- to, and the buyer/seller/agent context. This is the serving surface for
-- "what happened in this negotiation and how did it land".
--
-- The agreed terms come from the acceptance event, not the session row:
-- a2a_session holds current lifecycle state, a2a_negotiation_event holds the
-- immutable per-step history. Sessions with no acceptance have NULL agreed_*.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${ac_schema}.gold_a2a_session_summary AS
WITH event_rollup AS (
  SELECT
    a2a_session_sk,
    COUNT(*)                                                              AS event_count,
    COUNT(*) FILTER (WHERE event_type = 'counter_offer')                 AS counter_offer_count,
    COUNT(*) FILTER (WHERE event_type = 'escalation_to_human') > 0       AS escalated_to_human,
    -- The FIRST offer chronologically (by event_sequence), not the cheapest —
    -- price_concession_pct measures opening-price -> agreed drift, so it must be
    -- the opening offer. MIN_BY keeps the price at the lowest sequence among
    -- 'offer' events; MIN(price) would silently pick the cheapest offer instead.
    CAST(MIN_BY(proposed_price, event_sequence) FILTER (WHERE event_type = 'offer') AS DECIMAL(18,4)) AS first_offer_price,
    MAX(event_timestamp)                                                 AS last_event_timestamp
  FROM ${catalog}.${ac_schema}.a2a_negotiation_event
  GROUP BY a2a_session_sk
),
agreed AS (
  -- The accepted terms come from the acceptance event. A session should have at
  -- most one (asserted by a2a_negotiation_event_single_acceptance in checks.sql),
  -- but the view is made robust regardless: QUALIFY keeps the last acceptance by
  -- event_sequence so a duplicate can never fan out and double-count the session.
  SELECT
    a2a_session_sk,
    proposed_price     AS agreed_price,
    proposed_quantity  AS agreed_quantity,
    currency_code      AS agreed_currency_code
  FROM ${catalog}.${ac_schema}.a2a_negotiation_event
  WHERE event_type = 'acceptance'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a2a_session_sk ORDER BY event_sequence DESC, event_timestamp DESC) = 1
)
SELECT
  s.a2a_session_sk,
  s.a2a_session_id,
  s.session_status,
  s.communication_channel,
  s.initiator_type,
  s.buyer_profile_id,
  s.store_id,
  s.product_id,
  s.initiating_agent_id,
  s.responding_agent_id,
  s.initiated_timestamp,
  s.completed_timestamp,
  DATEDIFF(SECOND, s.initiated_timestamp, s.completed_timestamp)         AS duration_seconds,
  COALESCE(er.event_count, 0)                                            AS event_count,
  COALESCE(er.counter_offer_count, 0)                                    AS counter_offer_count,
  COALESCE(er.escalated_to_human, FALSE)                                 AS escalated_to_human,
  er.first_offer_price,
  ag.agreed_price,
  ag.agreed_quantity,
  ag.agreed_currency_code,
  -- Concession = (opening offer - agreed) / opening offer, anchored on the FIRST
  -- 'offer' event chronologically. In the A2A model the opening offer is the
  -- seller's quote (its ask), so a positive value = the seller came DOWN from its
  -- opening price; negative would mean the settled price rose above the opening.
  CASE
    WHEN er.first_offer_price IS NOT NULL AND ag.agreed_price IS NOT NULL AND er.first_offer_price <> 0
    THEN CAST(er.first_offer_price - ag.agreed_price AS DOUBLE) / er.first_offer_price
  END                                                                    AS price_concession_pct
FROM ${catalog}.${ac_schema}.a2a_session s
LEFT JOIN event_rollup er ON er.a2a_session_sk = s.a2a_session_sk
LEFT JOIN agreed       ag ON ag.a2a_session_sk = s.a2a_session_sk;
