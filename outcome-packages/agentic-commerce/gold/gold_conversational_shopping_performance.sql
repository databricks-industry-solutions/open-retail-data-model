-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce
-- View: gold_conversational_shopping_performance
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-27
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-27
-- ============================================================
-- KPI-ready aggregate surface for the consolidated Conversational Shopping
-- Assistant use case. Grain: started date x channel x primary intent category x
-- resolution type.
--
-- handoff_sessions / handoff_rate count the OCCURRENCE of a handoff (the turn-derived
-- handoff_flag), which is NOT the same as the resolution_type='handoff' grain column:
-- a session can hand off mid-flow yet resolve to a purchase, so within a
-- resolution_type='purchase' row handoff_sessions may be > 0. See the session view
-- header and glossary "Handoff" for the authoritative definitions.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${ac_schema}.gold_conversational_shopping_performance AS
SELECT
  started_date,
  entry_channel,
  COALESCE(primary_intent_category, 'unknown') AS primary_intent_category,
  COALESCE(resolution_type, 'no_resolution') AS resolution_type,
  COUNT(*) AS conversation_sessions,
  SUM(CASE WHEN known_customer_flag THEN 1 ELSE 0 END) AS known_customer_sessions,
  SUM(CASE WHEN personalization_eligible_flag THEN 1 ELSE 0 END) AS personalization_eligible_sessions,
  SUM(CASE WHEN selected_flag THEN 1 ELSE 0 END) AS selected_sessions,
  SUM(CASE WHEN added_to_cart_flag THEN 1 ELSE 0 END) AS add_to_cart_sessions,
  SUM(CASE WHEN purchased_flag THEN 1 ELSE 0 END) AS purchase_sessions,
  SUM(CASE WHEN handoff_flag THEN 1 ELSE 0 END) AS handoff_sessions,
  SUM(CASE WHEN fallback_turns > 0 THEN 1 ELSE 0 END) AS fallback_sessions,
  SUM(CASE WHEN first_discovery_turn_number IS NOT NULL THEN 1 ELSE 0 END) AS sessions_reaching_discovery,
  SUM(purchased_units) AS purchased_units,
  SUM(purchase_net_amount) AS purchase_net_amount,
  -- Single currency is enforced upstream (dee_single_currency); MAX surfaces the
  -- reporting currency for purchase_net_amount, NULL when no purchases in the grain.
  MAX(currency_code) AS currency_code,
  ROUND(AVG(total_turns), 4) AS avg_total_turns,
  -- Averaged ONLY over sessions that reached discovery (SQL AVG skips NULL
  -- first_discovery_turn_number), unlike the rate columns below whose denominator is
  -- COUNT(*) over all sessions. Read as "avg turns to first discovery, among sessions
  -- that reached discovery" -- not an all-session average.
  ROUND(AVG(first_discovery_turn_number), 4) AS avg_turns_to_first_discovery,
  ROUND(SUM(CASE WHEN selected_flag THEN 1.0 ELSE 0.0 END) / NULLIF(COUNT(*), 0), 4) AS selection_rate,
  ROUND(SUM(CASE WHEN added_to_cart_flag THEN 1.0 ELSE 0.0 END) / NULLIF(COUNT(*), 0), 4) AS add_to_cart_rate,
  ROUND(SUM(CASE WHEN purchased_flag THEN 1.0 ELSE 0.0 END) / NULLIF(COUNT(*), 0), 4) AS assisted_conversion_rate,
  ROUND(SUM(CASE WHEN handoff_flag THEN 1.0 ELSE 0.0 END) / NULLIF(COUNT(*), 0), 4) AS handoff_rate,
  ROUND(SUM(CASE WHEN fallback_turns > 0 THEN 1.0 ELSE 0.0 END) / NULLIF(COUNT(*), 0), 4) AS fallback_rate
FROM ${catalog}.${ac_schema}.gold_conversational_shopping_session
GROUP BY started_date, entry_channel, COALESCE(primary_intent_category, 'unknown'), COALESCE(resolution_type, 'no_resolution');
