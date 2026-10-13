-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce
-- Table: conversation_session
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-07-27
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-27
-- ============================================================
-- Append-only, privacy-safe session summary for a guided shopping conversation.
-- The application emits exactly one immutable ORDM row per
-- conversation_session_id when the session is reportable, usually after close.
-- CDC producers must aggregate mutable backend state before emission; they must
-- not stream each lifecycle transition into this table. Active/null-ended rows
-- are point-in-time analytical snapshots, not rows that ORDM refreshes in place:
-- an emitted row is terminal for ORDM and is never superseded by a later
-- active->completed correction (that would violate cs_business_key_unique). A
-- producer that needs the closed outcome defers emission until close. See
-- governance/decisions/0034-conversation-session-emit-once-grain.md.
-- No raw transcript, prompt, response, assistant memory, or application workflow
-- state is stored in ORDM.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${ac_schema}.conversation_session (
  conversation_session_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key for the conversational shopping session.',
  conversation_session_id STRING NOT NULL
                          COMMENT 'Durable natural/business key for the conversational shopping session.',

  profile_sk              BIGINT COMMENT 'FK to customer.profile.profile_sk when the shopper is resolved.',
  profile_id              STRING COMMENT 'Durable customer business key (pseudonymous). NULL for anonymous sessions.',
  store_sk                BIGINT COMMENT 'FK to store.store_sk when the conversation is scoped to a store/location.',
  store_id                STRING COMMENT 'Durable store business key when store context is known.',

  session_id              STRING COMMENT 'Pseudonymous session identifier from the shopping surface; degenerate, not application state.',
  conversation_id         STRING COMMENT 'Pseudonymous conversation identifier; degenerate, not transcript state.',
  entry_channel           STRING COMMENT 'Surface where the conversation started. Allowed values: web, mobile_app, kiosk, store_associate, voice, api.',
  locale_code             STRING COMMENT 'Locale/language context for the conversation, e.g. en-US.',
  jurisdiction_code       STRING COMMENT 'Jurisdiction used for consent/personalization evaluation, ISO 3166-1 alpha-2 when available.',

  started_ts              TIMESTAMP NOT NULL COMMENT 'When the conversation started at source (UTC, ISO 8601).',
  ended_ts                TIMESTAMP COMMENT 'When the conversation ended at source (UTC, ISO 8601). NULL only when still active at the reporting cutoff or unknown.',
  started_date            DATE NOT NULL COMMENT 'Business date the conversation started.',
  session_status          STRING COMMENT 'Lifecycle status at the immutable reporting point. Allowed values: active, completed, abandoned, escalated.',
  resolution_type         STRING COMMENT 'How the session resolved. Allowed values: product_selected, add_to_cart, purchase, handoff, no_resolution, abandoned.',

  personalization_eligible_flag BOOLEAN COMMENT 'TRUE when the shopper was eligible for personalized assistance at session start.',
  consent_status          STRING COMMENT 'Consent state used for personalization at session start. Allowed values: granted, denied, unknown.',

  record_source           STRING COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp          TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_conversation_session PRIMARY KEY (conversation_session_sk)
)
USING DELTA
CLUSTER BY (conversation_session_id, started_date)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Agentic Commerce append-only privacy-safe conversational shopping session fact.';

ALTER TABLE ${catalog}.${ac_schema}.conversation_session SET TAGS ('dbx_data_type' = 'transactional');
ALTER TABLE ${catalog}.${ac_schema}.conversation_session ALTER COLUMN profile_id SET TAGS ('dbx_pii_identifier' = 'true');
ALTER TABLE ${catalog}.${ac_schema}.conversation_session ALTER COLUMN session_id SET TAGS ('dbx_pii_identifier' = 'true');
ALTER TABLE ${catalog}.${ac_schema}.conversation_session ALTER COLUMN conversation_id SET TAGS ('dbx_pii_identifier' = 'true');
