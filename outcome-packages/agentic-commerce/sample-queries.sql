-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce · sample queries
-- Version: 0.5
-- Generated: 2026-07-27
-- LLM-generated: true
-- Last reviewed: 2026-08-02
-- ============================================================
-- Replace ${catalog} and ${ac_schema} with your deployment values.
-- Covers both grains: conversational shopping / intent product discovery
-- and agent-to-agent (A2A) transactions.
-- ============================================================

-- ============================================================
-- Conversational Shopping + Intent Product Discovery
-- ============================================================

-- Journey question: Which shopper intents turn organic discovery into product selection?
SELECT
  intent_category,
  COUNT(*) AS returned_results,
  SUM(CASE WHEN selected_flag THEN 1 ELSE 0 END) AS selected_results,
  ROUND(SUM(CASE WHEN selected_flag THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 4) AS result_ctr
FROM ${catalog}.${ac_schema}.gold_intent_product_discovery_performance
GROUP BY intent_category
ORDER BY result_ctr DESC;

-- Journey question: Where is save-the-sale discovery exposing demand for unavailable products?
SELECT
  product_id,
  product_name,
  category,
  COUNT(*) AS returned_results,
  SUM(CASE WHEN selected_flag THEN 1 ELSE 0 END) AS selected_results,
  SUM(CASE WHEN NOT is_available_flag THEN 1 ELSE 0 END) AS unavailable_results
FROM ${catalog}.${ac_schema}.gold_intent_product_discovery_performance
GROUP BY product_id, product_name, category
HAVING selected_results > 0
ORDER BY unavailable_results DESC, selected_results DESC;

-- Journey question: Which categories and stores have enough active, buyable product candidates?
SELECT
  category,
  store_id,
  COUNT(*) AS active_candidates,
  SUM(CASE WHEN is_available_flag THEN 1 ELSE 0 END) AS available_candidates
FROM ${catalog}.${ac_schema}.gold_product_discovery_candidate_current
GROUP BY category, store_id
ORDER BY active_candidates DESC;

-- Journey question: Which assistant channels convert, hand off, or fall back?
SELECT
  started_date,
  entry_channel,
  resolution_type,
  SUM(conversation_sessions) AS conversation_sessions,
  ROUND(SUM(purchase_sessions) / NULLIF(SUM(conversation_sessions), 0), 4) AS assisted_conversion_rate,
  ROUND(SUM(handoff_sessions) / NULLIF(SUM(conversation_sessions), 0), 4) AS handoff_rate,
  ROUND(SUM(fallback_sessions) / NULLIF(SUM(conversation_sessions), 0), 4) AS fallback_rate,
  SUM(purchase_net_amount) AS purchase_net_amount
FROM ${catalog}.${ac_schema}.gold_conversational_shopping_performance
GROUP BY started_date, entry_channel, resolution_type
ORDER BY started_date, conversation_sessions DESC;

-- Journey question: Which guided shopping sessions take too long to reach product discovery?
SELECT
  conversation_session_id,
  started_date,
  entry_channel,
  primary_intent_category,
  total_turns,
  first_discovery_turn_number,
  selected_flag,
  added_to_cart_flag,
  purchased_flag
FROM ${catalog}.${ac_schema}.gold_conversational_shopping_session
WHERE first_discovery_turn_number IS NOT NULL
ORDER BY first_discovery_turn_number DESC, total_turns DESC;

-- Journey question: Where are shoppers getting zero-result discovery experiences?
SELECT
  i.event_date,
  i.discovery_channel,
  i.intent_category,
  COUNT(DISTINCT i.discovery_intent_event_id) AS intent_events,
  COUNT(DISTINCT r.discovery_result_event_id) AS returned_results,
  SUM(CASE WHEN r.discovery_result_event_id IS NULL THEN 1 ELSE 0 END) AS zero_result_intents,
  ROUND(SUM(CASE WHEN r.discovery_result_event_id IS NULL THEN 1.0 ELSE 0.0 END)
        / NULLIF(COUNT(DISTINCT i.discovery_intent_event_id), 0), 4) AS zero_result_rate
FROM ${catalog}.${ac_schema}.discovery_intent_event i
LEFT JOIN ${catalog}.${ac_schema}.discovery_result_event r
  ON i.discovery_intent_event_id = r.discovery_intent_event_id
GROUP BY i.event_date, i.discovery_channel, i.intent_category
ORDER BY zero_result_rate DESC, intent_events DESC;

-- Journey question: Which guided selling sessions need associate attention before conversion?
SELECT
  started_date,
  entry_channel,
  primary_intent_category,
  COUNT(*) AS conversation_sessions,
  SUM(CASE WHEN handoff_flag THEN 1 ELSE 0 END) AS handoff_sessions,
  SUM(CASE WHEN fallback_turns > 0 THEN 1 ELSE 0 END) AS fallback_sessions,
  SUM(CASE WHEN purchased_flag THEN 1 ELSE 0 END) AS purchased_sessions,
  ROUND(AVG(total_turns), 4) AS avg_total_turns
FROM ${catalog}.${ac_schema}.gold_conversational_shopping_session
WHERE handoff_flag OR fallback_turns > 0
GROUP BY started_date, entry_channel, primary_intent_category
ORDER BY handoff_sessions DESC, fallback_sessions DESC, conversation_sessions DESC;

-- ============================================================
-- Agent-to-Agent (A2A) transactions
-- ============================================================

-- 1. Session volume by status (how many sessions in each lifecycle state?)
SELECT session_status, COUNT(*) AS session_count
FROM ${catalog}.${ac_schema}.a2a_session
GROUP BY session_status
ORDER BY session_count DESC;

-- 2. Conversion funnel (what fraction of sessions reach each stage?).
-- Reads the gold funnel view, whose reached-stages come from the immutable
-- event log (a session that reached a stage then failed still counts there);
-- a raw status count on a2a_session would undercount those.
SELECT
  SUM(sessions_initiated)  AS total_sessions,
  SUM(reached_negotiating) AS reached_negotiation,
  SUM(reached_agreed)      AS reached_agreement,
  SUM(completed)           AS completed
FROM ${catalog}.${ac_schema}.gold_a2a_negotiation_funnel;

-- 3. Average session duration for completed sessions
SELECT
  communication_channel,
  COUNT(*) AS completed_sessions,
  AVG(UNIX_TIMESTAMP(completed_timestamp) - UNIX_TIMESTAMP(initiated_timestamp)) / 60.0 AS avg_duration_minutes
FROM ${catalog}.${ac_schema}.a2a_session
WHERE session_status = 'completed'
GROUP BY communication_channel
ORDER BY avg_duration_minutes;

-- 4. Sessions per store (which stores have the most agent activity?)
SELECT
  s.store_id,
  COUNT(*) AS session_count,
  COUNT(CASE WHEN s.session_status = 'completed' THEN 1 END) AS completed_count
FROM ${catalog}.${ac_schema}.a2a_session s
WHERE s.store_sk IS NOT NULL
GROUP BY s.store_id
ORDER BY session_count DESC
LIMIT 20;

-- 5. Daily session trend (session volume over time)
SELECT
  DATE(initiated_timestamp) AS session_date,
  COUNT(*) AS sessions_initiated,
  COUNT(CASE WHEN session_status = 'completed' THEN 1 END) AS sessions_completed,
  COUNT(CASE WHEN session_status IN ('abandoned', 'failed', 'expired') THEN 1 END) AS sessions_lost
FROM ${catalog}.${ac_schema}.a2a_session
GROUP BY DATE(initiated_timestamp)
ORDER BY session_date DESC;

-- 6. Buyer-initiated vs seller-initiated session outcomes
SELECT
  initiator_type,
  session_status,
  COUNT(*) AS session_count
FROM ${catalog}.${ac_schema}.a2a_session
GROUP BY initiator_type, session_status
ORDER BY initiator_type, session_count DESC;

-- 7. Negotiation intensity: events per session (how much back-and-forth?)
SELECT
  e.a2a_session_id,
  COUNT(*) AS event_count,
  COUNT(CASE WHEN e.event_type = 'counter_offer' THEN 1 END) AS counter_offers,
  COUNT(CASE WHEN e.event_type = 'escalation_to_human' THEN 1 END) AS escalations
FROM ${catalog}.${ac_schema}.a2a_negotiation_event e
GROUP BY e.a2a_session_id
ORDER BY event_count DESC
LIMIT 20;

-- 8. Price concession: first offer vs accepted price per session
WITH first_offer AS (
  SELECT a2a_session_id, proposed_price,
         ROW_NUMBER() OVER (PARTITION BY a2a_session_id ORDER BY event_sequence) AS rn
  FROM ${catalog}.${ac_schema}.a2a_negotiation_event
  WHERE event_type = 'offer' AND proposed_price IS NOT NULL
),
accepted AS (
  SELECT a2a_session_id, proposed_price AS accepted_price
  FROM ${catalog}.${ac_schema}.a2a_negotiation_event
  WHERE event_type = 'acceptance' AND proposed_price IS NOT NULL
)
SELECT
  f.a2a_session_id,
  f.proposed_price AS first_offer_price,
  a.accepted_price
FROM first_offer f
JOIN accepted a ON f.a2a_session_id = a.a2a_session_id
WHERE f.rn = 1;

-- 9. Agent activity and trust mix (current agent versions)
SELECT
  agent_role,
  trust_status,
  COUNT(*) AS agent_count
FROM ${catalog}.${ac_schema}.a2a_agent
WHERE is_current = true
GROUP BY agent_role, trust_status
ORDER BY agent_role, agent_count DESC;

-- 10. Session outcomes with agreed terms and concession (gold serving view)
SELECT
  a2a_session_id,
  session_status,
  first_offer_price,
  agreed_price,
  price_concession_pct,
  escalated_to_human,
  duration_seconds
FROM ${catalog}.${ac_schema}.gold_a2a_session_summary
WHERE session_status = 'completed'
ORDER BY price_concession_pct DESC NULLS LAST
LIMIT 20;

-- 11. Completion funnel by channel (gold funnel view rolled to channel)
SELECT
  communication_channel,
  SUM(sessions_initiated) AS initiated,
  SUM(reached_agreed)     AS agreed,
  SUM(completed)          AS completed,
  SUM(completed) / NULLIF(SUM(sessions_initiated), 0) AS completion_rate
FROM ${catalog}.${ac_schema}.gold_a2a_negotiation_funnel
GROUP BY communication_channel
ORDER BY completed DESC;

-- 12. Top buyer agents by success rate (min 5 sessions)
SELECT
  a2a_agent_id, agent_role, trust_status,
  sessions_participated, success_rate, avg_time_to_completion_seconds
FROM ${catalog}.${ac_schema}.gold_a2a_agent_scorecard
WHERE sessions_participated >= 5
ORDER BY success_rate DESC
LIMIT 20;

-- 13. Active mandates and their guardrails (current versions)
SELECT
  m.a2a_mandate_id,
  m.buyer_profile_id,
  m.a2a_agent_id,
  m.spend_ceiling_amount,
  m.per_transaction_limit_amount,
  m.approval_threshold_amount,
  m.allowed_categories
FROM ${catalog}.${ac_schema}.a2a_mandate m
WHERE m.is_current = true AND m.mandate_status = 'active'
ORDER BY m.spend_ceiling_amount DESC NULLS LAST;
