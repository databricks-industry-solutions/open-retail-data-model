-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce
-- Table: discovery_intent_event
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-07-27
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-27
-- ============================================================
-- Append-only fact at one shopper intent/query turn grain. Captures the
-- privacy-safe intent signal an agent or search experience used to discover
-- products, without storing raw prompt/conversation text or application state.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${ac_schema}.discovery_intent_event (
  discovery_intent_event_sk BIGINT GENERATED ALWAYS AS IDENTITY
                            COMMENT 'Surrogate key for the discovery intent event.',
  discovery_intent_event_id STRING NOT NULL
                            COMMENT 'Durable natural/business key for the intent event.',

  conversation_session_sk   BIGINT COMMENT 'FK to conversation_session.conversation_session_sk when the intent is part of a guided shopping conversation.',
  conversation_session_id   STRING COMMENT 'Durable conversational shopping session business key when the intent is part of a guided conversation.',
  profile_sk                BIGINT COMMENT 'FK to customer.profile.profile_sk when the shopper is resolved.',
  profile_id                STRING COMMENT 'Durable customer business key (pseudonymous). NULL for anonymous intent.',
  store_sk                  BIGINT COMMENT 'FK to store.store_sk when discovery is scoped to a store/location.',
  store_id                  STRING COMMENT 'Durable store business key when store context is known.',

  session_id                STRING COMMENT 'Pseudonymous session identifier from the discovery surface; degenerate, not application state.',
  conversation_id           STRING COMMENT 'Pseudonymous conversation identifier when the intent came from an agent/chat turn; degenerate, not transcript state.',
  discovery_channel         STRING COMMENT 'Surface where intent was captured. Allowed values: web, mobile_app, kiosk, store_associate, voice, api.',
  locale_code               STRING COMMENT 'Locale/language context for the intent, e.g. en-US.',
  jurisdiction_code         STRING COMMENT 'Jurisdiction used for consent/personalization evaluation, ISO 3166-1 alpha-2 when available.',

  intent_text_hash          STRING COMMENT 'Deterministic hash of the redacted normalized intent text. Raw shopper text is not stored in ORDM.',
  intent_category           STRING COMMENT 'Normalized intent category. Allowed values: product_search, need_based, occasion, problem_solution, compatibility, style_fit, replenishment, comparison, unknown.',
  intent_confidence_score   DOUBLE COMMENT 'Model confidence that the normalized category reflects the shopper intent, from 0.0 to 1.0.',

  personalization_eligible_flag BOOLEAN COMMENT 'TRUE when the shopper was eligible for personalized ranking at event time.',
  consent_status            STRING COMMENT 'Consent state used for personalization at event time. Allowed values: granted, denied, unknown.',

  event_ts                  TIMESTAMP NOT NULL COMMENT 'When the intent event occurred at source (UTC, ISO 8601).',
  event_date                DATE NOT NULL COMMENT 'Business date of the intent event.',

  record_source             STRING COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp            TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_discovery_intent_event PRIMARY KEY (discovery_intent_event_sk)
)
USING DELTA
CLUSTER BY (conversation_session_id, event_date)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Agentic Commerce intent event fact for organic product discovery.';

ALTER TABLE ${catalog}.${ac_schema}.discovery_intent_event SET TAGS ('dbx_data_type' = 'transactional');
ALTER TABLE ${catalog}.${ac_schema}.discovery_intent_event ALTER COLUMN profile_id SET TAGS ('dbx_pii_identifier' = 'true');
ALTER TABLE ${catalog}.${ac_schema}.discovery_intent_event ALTER COLUMN intent_text_hash SET TAGS ('dbx_pii_identifier' = 'true');
ALTER TABLE ${catalog}.${ac_schema}.discovery_intent_event ALTER COLUMN session_id SET TAGS ('dbx_pii_identifier' = 'true');
ALTER TABLE ${catalog}.${ac_schema}.discovery_intent_event ALTER COLUMN conversation_id SET TAGS ('dbx_pii_identifier' = 'true');
