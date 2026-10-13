-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce
-- View: gold_conversational_shopping_session
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-27
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-27
-- ============================================================
-- Session-level performance surface for Conversational Shopping Assistant.
-- Joins structured session and turn events to discovery outcomes while excluding
-- raw prompt text, hashes, session identifiers, conversation identifiers, and
-- customer IDs from the gold output.
--
-- Handoff has TWO distinct, intentionally non-equal signals; do not conflate them:
--   * handoff_flag (here) = OCCURRENCE — a handoff happened at some point in the
--     session (turn_type='handoff' OR is_handoff_flag). This is the authoritative
--     "did a handoff occur" measure and the basis for handoff_rate downstream.
--   * resolution_type='handoff' (from conversation_session) = TERMINAL OUTCOME — the
--     session ENDED in a handoff. A session can hand off mid-flow (handoff_flag=TRUE)
--     yet still resolve to a purchase (resolution_type='purchase'), so the two can and
--     do diverge by design. session_status='escalated' mirrors the terminal-handoff
--     resolution, not the occurrence.
--
-- Purchase likewise has TWO signals, and the assisted-conversion KPI uses the narrower
-- one on purpose:
--   * purchased_flag (here) = DISCOVERY-ATTRIBUTED — a purchase engagement landed on a
--     discovery result linked to the session. This drives assisted_conversion_rate
--     downstream, so that KPI counts only discovery-attributed conversions.
--   * resolution_type='purchase' (from conversation_session) = TERMINAL OUTCOME — the
--     session resolved to a purchase. A session can resolve to a purchase with no
--     tracked discovery-result purchase engagement, so purchased_flag can be FALSE while
--     resolution_type='purchase'. See glossary "Assisted Conversion Rate".
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${ac_schema}.gold_conversational_shopping_session AS
WITH turn_rollup AS (
  SELECT
    conversation_session_sk,
    COUNT(*) AS total_turns,
    SUM(CASE WHEN actor_type = 'shopper' THEN 1 ELSE 0 END) AS shopper_turns,
    SUM(CASE WHEN actor_type = 'assistant' THEN 1 ELSE 0 END) AS assistant_turns,
    SUM(CASE WHEN turn_type = 'recommendation' THEN 1 ELSE 0 END) AS recommendation_turns,
    SUM(CASE WHEN turn_type = 'fallback' OR is_fallback_flag THEN 1 ELSE 0 END) AS fallback_turns,
    MAX(CASE WHEN turn_type = 'handoff' OR is_handoff_flag THEN 1 ELSE 0 END) AS handoff_flag_int,
    MIN(event_ts) AS first_turn_ts,
    MAX(event_ts) AS last_turn_ts,
    MIN(CASE WHEN discovery_intent_event_id IS NOT NULL THEN turn_sequence_number END) AS first_discovery_turn_number
  FROM ${catalog}.${ac_schema}.assistant_turn_event
  GROUP BY conversation_session_sk
),
intent_ranked AS (
  SELECT
    conversation_session_sk,
    intent_category,
    ROW_NUMBER() OVER (
      PARTITION BY conversation_session_sk
      ORDER BY event_ts, discovery_intent_event_sk
    ) AS intent_rank
  FROM ${catalog}.${ac_schema}.discovery_intent_event
  WHERE conversation_session_sk IS NOT NULL
),
intent_rollup AS (
  SELECT
    conversation_session_sk,
    COUNT(*) AS discovery_intent_count,
    MAX(CASE WHEN intent_rank = 1 THEN intent_category END) AS primary_intent_category
  FROM intent_ranked
  GROUP BY conversation_session_sk
),
engagement_rollup AS (
  SELECT
    i.conversation_session_sk,
    MAX(CASE WHEN e.engagement_type = 'select' THEN 1 ELSE 0 END) AS selected_flag_int,
    MAX(CASE WHEN e.engagement_type = 'add_to_cart' THEN 1 ELSE 0 END) AS added_to_cart_flag_int,
    MAX(CASE WHEN e.engagement_type = 'purchase' THEN 1 ELSE 0 END) AS purchased_flag_int
  FROM ${catalog}.${ac_schema}.discovery_intent_event i
  JOIN ${catalog}.${ac_schema}.discovery_engagement_event e
    ON i.discovery_intent_event_id = e.discovery_intent_event_id
  WHERE i.conversation_session_sk IS NOT NULL
  GROUP BY i.conversation_session_sk
),
purchase_attribution AS (
  SELECT
    i.conversation_session_sk,
    e.quantity,
    e.net_amount,
    e.currency_code,
    ROW_NUMBER() OVER (
      PARTITION BY
        i.conversation_session_sk,
        COALESCE(CAST(e.order_line_sk AS STRING), e.order_line_id, e.discovery_engagement_event_id)
      ORDER BY e.engagement_ts, e.discovery_engagement_event_sk
    ) AS attribution_rn
  FROM ${catalog}.${ac_schema}.discovery_intent_event i
  JOIN ${catalog}.${ac_schema}.discovery_engagement_event e
    ON i.discovery_intent_event_id = e.discovery_intent_event_id
  WHERE i.conversation_session_sk IS NOT NULL
    AND e.engagement_type = 'purchase'
),
purchase_rollup AS (
  SELECT
    conversation_session_sk,
    SUM(COALESCE(quantity, 0)) AS purchased_units,
    SUM(COALESCE(net_amount, 0)) AS purchase_net_amount,
    -- Single currency is enforced upstream (dee_single_currency); MAX picks the
    -- session's reporting currency, NULL when the session had no purchase.
    MAX(currency_code) AS currency_code
  FROM purchase_attribution
  WHERE attribution_rn = 1
  GROUP BY conversation_session_sk
)
SELECT
  s.conversation_session_id,
  s.started_date,
  s.started_ts,
  s.ended_ts,
  s.entry_channel,
  s.locale_code,
  s.jurisdiction_code,
  s.profile_sk IS NOT NULL AS known_customer_flag,
  s.store_id,
  s.session_status,
  s.resolution_type,
  s.personalization_eligible_flag,
  s.consent_status,
  COALESCE(t.total_turns, 0) AS total_turns,
  COALESCE(t.shopper_turns, 0) AS shopper_turns,
  COALESCE(t.assistant_turns, 0) AS assistant_turns,
  COALESCE(t.recommendation_turns, 0) AS recommendation_turns,
  COALESCE(t.fallback_turns, 0) AS fallback_turns,
  COALESCE(t.handoff_flag_int, 0) = 1 AS handoff_flag,
  t.first_turn_ts,
  t.last_turn_ts,
  t.first_discovery_turn_number,
  COALESCE(i.discovery_intent_count, 0) AS discovery_intent_count,
  i.primary_intent_category,
  COALESCE(e.selected_flag_int, 0) = 1 AS selected_flag,
  COALESCE(e.added_to_cart_flag_int, 0) = 1 AS added_to_cart_flag,
  COALESCE(e.purchased_flag_int, 0) = 1 AS purchased_flag,
  COALESCE(pr.purchased_units, 0) AS purchased_units,
  COALESCE(pr.purchase_net_amount, 0) AS purchase_net_amount,
  pr.currency_code
FROM ${catalog}.${ac_schema}.conversation_session s
LEFT JOIN turn_rollup t
  ON s.conversation_session_sk = t.conversation_session_sk
LEFT JOIN intent_rollup i
  ON s.conversation_session_sk = i.conversation_session_sk
LEFT JOIN engagement_rollup e
  ON s.conversation_session_sk = e.conversation_session_sk
LEFT JOIN purchase_rollup pr
  ON s.conversation_session_sk = pr.conversation_session_sk;
