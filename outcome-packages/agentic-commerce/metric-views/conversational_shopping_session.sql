-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce
-- Metric View: conversational_shopping_session
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-10-12
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-10-12
-- ============================================================
-- Session-level KPIs for Conversational Shopping Assistant: assisted conversion,
-- handoff occurrence, and fallback rates, sliced by channel, intent category, and
-- resolution type. Grain: one row per conversation session.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${ac_schema}.mv_conversational_shopping_session
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Session-level KPIs for Conversational Shopping Assistant: assisted conversion, handoff occurrence, and fallback rates by channel, intent category, and resolution type."
source: >
  SELECT
    started_date,
    entry_channel,
    primary_intent_category,
    resolution_type,
    known_customer_flag,
    personalization_eligible_flag,
    handoff_flag,
    fallback_turns,
    selected_flag,
    added_to_cart_flag,
    purchased_flag,
    total_turns
  FROM ${catalog}.${ac_schema}.gold_conversational_shopping_session

fields:
  - name: started_date
    expr: started_date
    display_name: "Session Start Date"
    comment: "Business date when the conversation session began."
    synonyms: ["date", "session_date"]

  - name: entry_channel
    expr: entry_channel
    display_name: "Channel"
    comment: "Surface where the shopper accessed the conversational assistant: web, mobile_app, kiosk, store_associate, voice, or api."
    synonyms: ["channel", "surface", "platform"]

  - name: primary_intent_category
    expr: COALESCE(primary_intent_category, 'unknown')
    display_name: "Primary Intent Category"
    comment: "Shopper need classification from the first discovery intent in the session: product_search, need_based, occasion, problem_solution, compatibility, style_fit, replenishment, comparison, or unknown."
    synonyms: ["intent", "intent_category", "shopper_need"]

  - name: resolution_type
    expr: COALESCE(resolution_type, 'no_resolution')
    display_name: "Resolution Type"
    comment: "How the session ended: product_selected, add_to_cart, purchase, handoff, no_resolution, or abandoned."
    synonyms: ["outcome", "resolution", "session_outcome"]

  - name: known_customer_flag
    expr: known_customer_flag
    display_name: "Known Customer"
    comment: "TRUE when the shopper resolved to a customer profile."
    synonyms: ["authenticated", "identified", "resolved_customer"]

  - name: personalization_eligible_flag
    expr: personalization_eligible_flag
    display_name: "Personalization Eligible"
    comment: "TRUE when personalized ranking was enabled during the session."
    synonyms: ["personalized", "personalization_enabled"]

measures:
  - name: conversation_session_count
    expr: COUNT(*)
    display_name: "Conversation Sessions"
    comment: "Number of conversation sessions in the grain."
    synonyms: ["conversation_sessions", "assistant_sessions"]

  - name: known_customer_session_count
    expr: SUM(CASE WHEN known_customer_flag THEN 1 ELSE 0 END)
    display_name: "Known Customer Sessions"
    comment: "Conversation sessions where the shopper resolved to a customer profile."
    synonyms: ["identified_sessions", "authenticated_sessions"]

  - name: personalization_eligible_session_count
    expr: SUM(CASE WHEN personalization_eligible_flag THEN 1 ELSE 0 END)
    display_name: "Personalization Eligible Sessions"
    comment: "Conversation sessions eligible for personalized product ranking."
    synonyms: ["personalized_sessions"]

  - name: selection_count
    expr: SUM(CASE WHEN selected_flag THEN 1 ELSE 0 END)
    display_name: "Selection Sessions"
    comment: "Sessions where the shopper selected (clicked on) a discovery result."
    synonyms: ["selected_sessions"]

  - name: add_to_cart_count
    expr: SUM(CASE WHEN added_to_cart_flag THEN 1 ELSE 0 END)
    display_name: "Add-to-Cart Sessions"
    comment: "Sessions where the shopper added a discovery result to cart."
    synonyms: ["cart_sessions"]

  - name: assisted_conversion_count
    expr: SUM(CASE WHEN purchased_flag THEN 1 ELSE 0 END)
    display_name: "Assisted Conversion Sessions"
    comment: "Sessions with a discovery-attributed purchase engagement (narrower than resolution_type='purchase')."
    synonyms: ["converted_sessions", "purchase_sessions"]

  - name: handoff_count
    expr: SUM(CASE WHEN handoff_flag THEN 1 ELSE 0 END)
    display_name: "Handoff Sessions"
    comment: "Sessions where a handoff to agent/human occurred (turn-derived handoff_flag OCCURRENCE, not terminal outcome)."
    synonyms: ["escalation_sessions", "agent_handoff_sessions"]

  - name: fallback_count
    expr: SUM(CASE WHEN fallback_turns > 0 THEN 1 ELSE 0 END)
    display_name: "Fallback Sessions"
    comment: "Sessions where the assistant used a fallback turn (not ideal path)."
    synonyms: ["fallback_sessions"]

  - name: session_selection_rate
    expr: CAST(SUM(CASE WHEN selected_flag THEN 1 ELSE 0 END) AS DOUBLE) / NULLIF(COUNT(*), 0)
    display_name: "Session Selection Rate"
    comment: "Fraction of sessions where the shopper selected a discovery result."
    synonyms: ["sessions_with_selection_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: session_add_to_cart_rate
    expr: CAST(SUM(CASE WHEN added_to_cart_flag THEN 1 ELSE 0 END) AS DOUBLE) / NULLIF(COUNT(*), 0)
    display_name: "Session Add-to-Cart Rate"
    comment: "Fraction of sessions where the shopper added a discovery result to cart."
    synonyms: ["session_cart_rate", "sessions_with_add_to_cart_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: assisted_conversion_rate
    expr: CAST(SUM(CASE WHEN purchased_flag THEN 1 ELSE 0 END) AS DOUBLE) / NULLIF(COUNT(*), 0)
    display_name: "Assisted Conversion Rate"
    comment: "Fraction of sessions with a discovery-attributed purchase. Narrower than resolution_type='purchase' because it counts only sessions where a discovery result had a purchase engagement."
    synonyms: ["assisted_purchase_rate", "session_conversion_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: handoff_rate
    expr: CAST(SUM(CASE WHEN handoff_flag THEN 1 ELSE 0 END) AS DOUBLE) / NULLIF(COUNT(*), 0)
    display_name: "Handoff Rate"
    comment: "Fraction of sessions where a handoff occurred (turn-derived OCCURRENCE flag, not terminal outcome). A session can hand off mid-flow yet resolve to purchase."
    synonyms: ["agent_handoff_rate", "assistant_handoff_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: fallback_rate
    expr: CAST(SUM(CASE WHEN fallback_turns > 0 THEN 1 ELSE 0 END) AS DOUBLE) / NULLIF(COUNT(*), 0)
    display_name: "Fallback Rate"
    comment: "Fraction of sessions that included an assistant fallback turn (not ideal path)."
    synonyms: ["fallback_frequency"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2

  - name: avg_turns
    expr: AVG(total_turns)
    display_name: "Average Turns"
    comment: "Mean number of conversation turns per session."
    synonyms: ["avg_turns_per_session", "mean_turns"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1
$$;
