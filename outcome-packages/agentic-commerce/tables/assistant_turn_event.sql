-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce
-- Table: assistant_turn_event
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-07-27
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-27
-- ============================================================
-- Append-only fact at one actor turn/action within a conversational shopping
-- session. Stores structured action metadata only, never raw utterance or
-- generated response text.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${ac_schema}.assistant_turn_event (
  assistant_turn_event_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key for the assistant turn event.',
  assistant_turn_event_id STRING NOT NULL
                          COMMENT 'Durable natural/business key for the assistant turn event.',

  conversation_session_sk BIGINT COMMENT 'FK to conversation_session.conversation_session_sk.',
  conversation_session_id STRING NOT NULL COMMENT 'Durable business key for the parent conversational shopping session.',
  discovery_intent_event_sk BIGINT COMMENT 'FK to discovery_intent_event.discovery_intent_event_sk when this turn captured or used a discovery intent.',
  discovery_intent_event_id STRING COMMENT 'Durable business key for the linked discovery intent event.',

  turn_sequence_number    INT NOT NULL COMMENT 'One-based turn order within the conversation session.',
  actor_type              STRING NOT NULL COMMENT 'Actor responsible for the turn. Allowed values: shopper, assistant, associate, system.',
  turn_type               STRING NOT NULL COMMENT 'Structured turn type. Allowed values: intent_capture, recommendation, product_comparison, availability_check, cart_action, handoff, fallback, clarification, other.',
  assistant_action_type   STRING COMMENT 'Structured assistant action. Allowed values: none, search_products, recommend_products, compare_products, check_availability, add_to_cart, handoff_to_associate, answer_question, clarify_intent.',

  intent_category         STRING COMMENT 'Turn-local normalized shopper intent category when this turn captured or refined intent; not authoritative over the linked discovery_intent_event (use that row for the session intent of record). Allowed values: product_search, need_based, occasion, problem_solution, compatibility, style_fit, replenishment, comparison, unknown.',
  intent_confidence_score DOUBLE COMMENT 'Turn-local model confidence that the normalized category reflects the shopper intent, from 0.0 to 1.0; scoped to this turn, not authoritative over the linked discovery_intent_event.',
  is_fallback_flag        BOOLEAN COMMENT 'TRUE when the assistant could not confidently answer or proceed without fallback behavior.',
  is_handoff_flag         BOOLEAN COMMENT 'TRUE when the turn handed the shopper to an associate or other support channel.',

  event_ts                TIMESTAMP NOT NULL COMMENT 'When the turn occurred at source (UTC, ISO 8601).',
  event_date              DATE NOT NULL COMMENT 'Business date of the turn event.',

  record_source           STRING COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp          TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_assistant_turn_event PRIMARY KEY (assistant_turn_event_sk)
)
USING DELTA
CLUSTER BY (conversation_session_id, event_date)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Agentic Commerce structured assistant turn/action fact for conversational shopping.';

ALTER TABLE ${catalog}.${ac_schema}.assistant_turn_event SET TAGS ('dbx_data_type' = 'transactional');
