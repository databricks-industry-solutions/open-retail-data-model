-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce
-- File: relationships.sql
-- Version: 0.5
-- Generated: 2026-07-27
-- LLM-generated: true
-- Last reviewed: 2026-08-02
-- ============================================================
-- Cross-schema relationships and enum constraints for Agentic Commerce.
-- This package spans two independent grains that share the schema but never a
-- spine table: the human-to-assistant conversational-shopping tables
-- (conversation_session / assistant_turn_event / discovery_*) and the
-- autonomous agent-to-agent tables (a2a_*). See README "Scope".
-- UC foreign keys are informational (NOT ENFORCED); data quality checks provide
-- the operational integrity signal.
-- ============================================================

-- ============================================================
-- Conversational Shopping + Intent Product Discovery
-- ============================================================

-- conversation_session -> canonical core
ALTER TABLE ${catalog}.${ac_schema}.conversation_session
  ADD CONSTRAINT fk_conversation_session_profile
  FOREIGN KEY (profile_sk) REFERENCES ${catalog}.${customer_schema}.profile (profile_sk);

ALTER TABLE ${catalog}.${ac_schema}.conversation_session
  ADD CONSTRAINT fk_conversation_session_store
  FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);

-- assistant_turn_event -> conversation_session / discovery_intent_event
ALTER TABLE ${catalog}.${ac_schema}.assistant_turn_event
  ADD CONSTRAINT fk_assistant_turn_event_session
  FOREIGN KEY (conversation_session_sk) REFERENCES ${catalog}.${ac_schema}.conversation_session (conversation_session_sk);

ALTER TABLE ${catalog}.${ac_schema}.assistant_turn_event
  ADD CONSTRAINT fk_assistant_turn_event_intent
  FOREIGN KEY (discovery_intent_event_sk) REFERENCES ${catalog}.${ac_schema}.discovery_intent_event (discovery_intent_event_sk);

-- discovery_intent_event -> conversation_session / canonical core
ALTER TABLE ${catalog}.${ac_schema}.discovery_intent_event
  ADD CONSTRAINT fk_discovery_intent_event_session
  FOREIGN KEY (conversation_session_sk) REFERENCES ${catalog}.${ac_schema}.conversation_session (conversation_session_sk);

ALTER TABLE ${catalog}.${ac_schema}.discovery_intent_event
  ADD CONSTRAINT fk_discovery_intent_event_profile
  FOREIGN KEY (profile_sk) REFERENCES ${catalog}.${customer_schema}.profile (profile_sk);

ALTER TABLE ${catalog}.${ac_schema}.discovery_intent_event
  ADD CONSTRAINT fk_discovery_intent_event_store
  FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);

-- discovery_result_event -> intent / canonical core
ALTER TABLE ${catalog}.${ac_schema}.discovery_result_event
  ADD CONSTRAINT fk_discovery_result_event_intent
  FOREIGN KEY (discovery_intent_event_sk) REFERENCES ${catalog}.${ac_schema}.discovery_intent_event (discovery_intent_event_sk);

ALTER TABLE ${catalog}.${ac_schema}.discovery_result_event
  ADD CONSTRAINT fk_discovery_result_event_product
  FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);

ALTER TABLE ${catalog}.${ac_schema}.discovery_result_event
  ADD CONSTRAINT fk_discovery_result_event_store
  FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);

-- discovery_engagement_event -> result / intent / canonical core
ALTER TABLE ${catalog}.${ac_schema}.discovery_engagement_event
  ADD CONSTRAINT fk_discovery_engagement_event_result
  FOREIGN KEY (discovery_result_event_sk) REFERENCES ${catalog}.${ac_schema}.discovery_result_event (discovery_result_event_sk);

ALTER TABLE ${catalog}.${ac_schema}.discovery_engagement_event
  ADD CONSTRAINT fk_discovery_engagement_event_intent
  FOREIGN KEY (discovery_intent_event_sk) REFERENCES ${catalog}.${ac_schema}.discovery_intent_event (discovery_intent_event_sk);

ALTER TABLE ${catalog}.${ac_schema}.discovery_engagement_event
  ADD CONSTRAINT fk_discovery_engagement_event_profile
  FOREIGN KEY (profile_sk) REFERENCES ${catalog}.${customer_schema}.profile (profile_sk);

ALTER TABLE ${catalog}.${ac_schema}.discovery_engagement_event
  ADD CONSTRAINT fk_discovery_engagement_event_product
  FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);

ALTER TABLE ${catalog}.${ac_schema}.discovery_engagement_event
  ADD CONSTRAINT fk_discovery_engagement_event_store
  FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);

ALTER TABLE ${catalog}.${ac_schema}.discovery_engagement_event
  ADD CONSTRAINT fk_discovery_engagement_event_order_line
  FOREIGN KEY (order_line_sk) REFERENCES ${catalog}.${order_schema}.customer_order_line (order_line_sk);

-- Enum and range constraints
ALTER TABLE ${catalog}.${ac_schema}.conversation_session
  ADD CONSTRAINT chk_conversation_session_entry_channel
  CHECK (entry_channel IN ('web', 'mobile_app', 'kiosk', 'store_associate', 'voice', 'api'));

ALTER TABLE ${catalog}.${ac_schema}.conversation_session
  ADD CONSTRAINT chk_conversation_session_status
  CHECK (session_status IN ('active', 'completed', 'abandoned', 'escalated'));

ALTER TABLE ${catalog}.${ac_schema}.conversation_session
  ADD CONSTRAINT chk_conversation_session_resolution_type
  CHECK (resolution_type IN ('product_selected', 'add_to_cart', 'purchase', 'handoff', 'no_resolution', 'abandoned'));

ALTER TABLE ${catalog}.${ac_schema}.conversation_session
  ADD CONSTRAINT chk_conversation_session_consent_status
  CHECK (consent_status IN ('granted', 'denied', 'unknown'));

ALTER TABLE ${catalog}.${ac_schema}.conversation_session
  ADD CONSTRAINT chk_conversation_session_time_order
  CHECK (ended_ts IS NULL OR ended_ts >= started_ts);

ALTER TABLE ${catalog}.${ac_schema}.assistant_turn_event
  ADD CONSTRAINT chk_assistant_turn_event_sequence_positive
  CHECK (turn_sequence_number > 0);

ALTER TABLE ${catalog}.${ac_schema}.assistant_turn_event
  ADD CONSTRAINT chk_assistant_turn_event_actor_type
  CHECK (actor_type IN ('shopper', 'assistant', 'associate', 'system'));

ALTER TABLE ${catalog}.${ac_schema}.assistant_turn_event
  ADD CONSTRAINT chk_assistant_turn_event_turn_type
  CHECK (turn_type IN ('intent_capture', 'recommendation', 'product_comparison', 'availability_check', 'cart_action', 'handoff', 'fallback', 'clarification', 'other'));

ALTER TABLE ${catalog}.${ac_schema}.assistant_turn_event
  ADD CONSTRAINT chk_assistant_turn_event_action_type
  CHECK (assistant_action_type IN ('none', 'search_products', 'recommend_products', 'compare_products', 'check_availability', 'add_to_cart', 'handoff_to_associate', 'answer_question', 'clarify_intent'));

ALTER TABLE ${catalog}.${ac_schema}.assistant_turn_event
  ADD CONSTRAINT chk_assistant_turn_event_intent_category
  CHECK (intent_category IS NULL OR intent_category IN ('product_search', 'need_based', 'occasion', 'problem_solution', 'compatibility', 'style_fit', 'replenishment', 'comparison', 'unknown'));

ALTER TABLE ${catalog}.${ac_schema}.assistant_turn_event
  ADD CONSTRAINT chk_assistant_turn_event_confidence_score
  CHECK (intent_confidence_score IS NULL OR (intent_confidence_score >= 0.0 AND intent_confidence_score <= 1.0));

ALTER TABLE ${catalog}.${ac_schema}.discovery_intent_event
  ADD CONSTRAINT chk_discovery_intent_event_channel
  CHECK (discovery_channel IN ('web', 'mobile_app', 'kiosk', 'store_associate', 'voice', 'api'));

ALTER TABLE ${catalog}.${ac_schema}.discovery_intent_event
  ADD CONSTRAINT chk_discovery_intent_event_intent_category
  CHECK (intent_category IS NULL OR intent_category IN ('product_search', 'need_based', 'occasion', 'problem_solution', 'compatibility', 'style_fit', 'replenishment', 'comparison', 'unknown'));

ALTER TABLE ${catalog}.${ac_schema}.discovery_intent_event
  ADD CONSTRAINT chk_discovery_intent_event_consent_status
  CHECK (consent_status IN ('granted', 'denied', 'unknown'));

ALTER TABLE ${catalog}.${ac_schema}.discovery_intent_event
  ADD CONSTRAINT chk_discovery_intent_event_confidence_score
  CHECK (intent_confidence_score IS NULL OR (intent_confidence_score >= 0.0 AND intent_confidence_score <= 1.0));

ALTER TABLE ${catalog}.${ac_schema}.discovery_result_event
  ADD CONSTRAINT chk_discovery_result_event_rank_positive
  CHECK (result_rank > 0);

ALTER TABLE ${catalog}.${ac_schema}.discovery_result_event
  ADD CONSTRAINT chk_discovery_result_event_scores
  CHECK ((retrieval_score IS NULL OR (retrieval_score >= 0.0 AND retrieval_score <= 1.0))
     AND (ranking_score IS NULL OR (ranking_score >= 0.0 AND ranking_score <= 1.0))
     AND (personalization_score IS NULL OR (personalization_score >= 0.0 AND personalization_score <= 1.0))
     AND (availability_score IS NULL OR (availability_score >= 0.0 AND availability_score <= 1.0)));

ALTER TABLE ${catalog}.${ac_schema}.discovery_result_event
  ADD CONSTRAINT chk_discovery_result_event_reason_code
  CHECK (reason_code IN ('lexical_match', 'semantic_match', 'purchase_affinity', 'substitute', 'complement', 'trending', 'available_nearby', 'business_rule'));

ALTER TABLE ${catalog}.${ac_schema}.discovery_engagement_event
  ADD CONSTRAINT chk_discovery_engagement_event_type
  CHECK (engagement_type IN ('view', 'select', 'add_to_cart', 'purchase', 'dismiss'));

ALTER TABLE ${catalog}.${ac_schema}.discovery_engagement_event
  ADD CONSTRAINT chk_discovery_engagement_event_nonnegative_values
  CHECK ((quantity IS NULL OR quantity >= 0)
     AND (net_amount IS NULL OR net_amount >= 0.0)
     AND (attribution_window_minutes IS NULL OR attribution_window_minutes >= 0));

-- ============================================================
-- Agent-to-Agent (A2A) transactions
-- ============================================================

-- a2a_session -> customer.profile (buying side)
ALTER TABLE ${catalog}.${ac_schema}.a2a_session
  ADD CONSTRAINT fk_a2a_session_profile
  FOREIGN KEY (buyer_profile_sk) REFERENCES ${catalog}.${customer_schema}.profile (profile_sk);

-- a2a_session -> store.store (selling side)
ALTER TABLE ${catalog}.${ac_schema}.a2a_session
  ADD CONSTRAINT fk_a2a_session_store
  FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);

-- a2a_session -> product.product (primary product under negotiation)
ALTER TABLE ${catalog}.${ac_schema}.a2a_session
  ADD CONSTRAINT fk_a2a_session_product
  FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);

-- a2a_session -> a2a_agent (role-qualified: initiating + responding agent)
ALTER TABLE ${catalog}.${ac_schema}.a2a_session
  ADD CONSTRAINT fk_a2a_session_initiating_agent
  FOREIGN KEY (initiating_agent_sk) REFERENCES ${catalog}.${ac_schema}.a2a_agent (a2a_agent_sk);

ALTER TABLE ${catalog}.${ac_schema}.a2a_session
  ADD CONSTRAINT fk_a2a_session_responding_agent
  FOREIGN KEY (responding_agent_sk) REFERENCES ${catalog}.${ac_schema}.a2a_agent (a2a_agent_sk);

-- a2a_negotiation_event -> a2a_session (parent negotiation)
ALTER TABLE ${catalog}.${ac_schema}.a2a_negotiation_event
  ADD CONSTRAINT fk_a2a_negotiation_event_session
  FOREIGN KEY (a2a_session_sk) REFERENCES ${catalog}.${ac_schema}.a2a_session (a2a_session_sk);

-- a2a_negotiation_event -> a2a_agent (emitting agent)
ALTER TABLE ${catalog}.${ac_schema}.a2a_negotiation_event
  ADD CONSTRAINT fk_a2a_negotiation_event_agent
  FOREIGN KEY (a2a_agent_sk) REFERENCES ${catalog}.${ac_schema}.a2a_agent (a2a_agent_sk);

-- a2a_negotiation_event -> product.product (product the step concerns)
ALTER TABLE ${catalog}.${ac_schema}.a2a_negotiation_event
  ADD CONSTRAINT fk_a2a_negotiation_event_product
  FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);

-- a2a_mandate -> customer.profile (the human granting authority)
ALTER TABLE ${catalog}.${ac_schema}.a2a_mandate
  ADD CONSTRAINT fk_a2a_mandate_profile
  FOREIGN KEY (buyer_profile_sk) REFERENCES ${catalog}.${customer_schema}.profile (profile_sk);

-- a2a_mandate -> a2a_agent (the buying agent it governs)
ALTER TABLE ${catalog}.${ac_schema}.a2a_mandate
  ADD CONSTRAINT fk_a2a_mandate_agent
  FOREIGN KEY (a2a_agent_sk) REFERENCES ${catalog}.${ac_schema}.a2a_agent (a2a_agent_sk);

-- ============================================================
-- Enum / state-domain CHECK constraints (always via ALTER TABLE;
-- Databricks does not support inline CHECK in CREATE TABLE).
-- Lists match the "Allowed values" in each column's COMMENT.
-- ============================================================
ALTER TABLE ${catalog}.${ac_schema}.a2a_session
  ADD CONSTRAINT chk_a2a_session_status
  CHECK (session_status IN ('initiated', 'negotiating', 'agreed', 'completed', 'abandoned', 'failed', 'expired'));

ALTER TABLE ${catalog}.${ac_schema}.a2a_session
  ADD CONSTRAINT chk_a2a_session_communication_channel
  CHECK (communication_channel IN ('api', 'marketplace', 'direct', 'voice'));

ALTER TABLE ${catalog}.${ac_schema}.a2a_session
  ADD CONSTRAINT chk_a2a_session_initiator_type
  CHECK (initiator_type IN ('buyer_agent', 'seller_agent'));

-- a2a_agent enums
ALTER TABLE ${catalog}.${ac_schema}.a2a_agent
  ADD CONSTRAINT chk_a2a_agent_role
  CHECK (agent_role IN ('buyer_agent', 'seller_agent'));

ALTER TABLE ${catalog}.${ac_schema}.a2a_agent
  ADD CONSTRAINT chk_a2a_agent_trust_status
  CHECK (trust_status IN ('unverified', 'verified', 'suspended', 'revoked'));

-- a2a_negotiation_event enums
ALTER TABLE ${catalog}.${ac_schema}.a2a_negotiation_event
  ADD CONSTRAINT chk_a2a_negotiation_event_type
  CHECK (event_type IN ('price_request', 'offer', 'counter_offer', 'acceptance', 'rejection', 'availability_check', 'escalation_to_human'));

-- a2a_mandate enums
ALTER TABLE ${catalog}.${ac_schema}.a2a_mandate
  ADD CONSTRAINT chk_a2a_mandate_status
  CHECK (mandate_status IN ('active', 'suspended', 'revoked', 'expired'));
