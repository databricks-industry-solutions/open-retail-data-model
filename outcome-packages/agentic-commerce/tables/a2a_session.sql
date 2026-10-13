-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce
-- Table: a2a_session
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-07-10
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-02 by @shubhamp051991
-- ============================================================
-- SCOPE: this package models AUTONOMOUS AGENT-TO-AGENT (A2A) commerce —
-- a buyer's AI agent negotiating a transaction with a seller's AI agent.
-- Human-to-assistant conversational shopping (Intent Product Discovery,
-- Conversational Shopping) is a SEPARATE scope and is modeled by
-- the conversation_session / discovery_* tables, not here. The `a2a_` prefix
-- marks the agent-to-agent tables so the two scopes never conflate.
--
-- One row per A2A negotiation session. A session tracks the full lifecycle
-- of a negotiation between a buying agent (acting on behalf of a customer)
-- and a selling agent (acting on behalf of a retailer/store). The session is
-- the spine that child tables (a2a_negotiation_event) reference.
--
-- Mutable: session_status is updated as the lifecycle progresses
-- (initiated -> negotiating -> agreed -> completed / abandoned /
-- failed / expired). Not append-only; not SCD2.
--
-- Catalog/schema are injected at deploy time (${catalog}.${ac_schema});
-- never hardcode.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${ac_schema}.a2a_session (
  a2a_session_sk        BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per session.',
  a2a_session_id        STRING NOT NULL
                          COMMENT 'Durable natural/business key for the session (e.g. a UUID issued by the orchestrator).',

  -- Buying side (the customer the buying agent acts for)
  buyer_profile_sk      BIGINT COMMENT 'FK to customer.profile.profile_sk — the individual the buying agent represents.',
  buyer_profile_id      STRING COMMENT 'Durable business key of the buyer profile. Stable across SCD2 versions.',

  -- Selling side (the retailer channel the selling agent represents)
  store_sk              BIGINT COMMENT 'FK to store.store.store_sk — the store or channel the selling agent represents.',
  store_id              STRING COMMENT 'Durable business key of the store.',

  -- Primary product under negotiation (nullable; a session may cover multiple products via child events)
  product_sk            BIGINT COMMENT 'FK to product.product.product_sk — the primary product being negotiated, if applicable.',
  product_id            STRING COMMENT 'Durable business key of the product.',

  -- The two agents in the session (role-qualified refs to a2a_agent).
  initiating_agent_sk   BIGINT COMMENT 'FK to a2a_agent.a2a_agent_sk — the agent that opened the session.',
  initiating_agent_id   STRING COMMENT 'Durable business key of the initiating agent.',
  responding_agent_sk   BIGINT COMMENT 'FK to a2a_agent.a2a_agent_sk — the agent that responded.',
  responding_agent_id   STRING COMMENT 'Durable business key of the responding agent.',

  -- Session metadata
  session_status        STRING NOT NULL COMMENT 'Lifecycle status. Allowed values: initiated, negotiating, agreed, completed, abandoned, failed, expired.',
  communication_channel STRING NOT NULL COMMENT 'Communication channel between agents. Allowed values: api, marketplace, direct, voice.',
  initiator_type        STRING NOT NULL COMMENT 'Which side initiated the session. Allowed values: buyer_agent, seller_agent.',

  session_summary       STRING COMMENT 'Free-text summary of the session outcome or current state. May contain PII if agents reference customer details.',

  -- Lifecycle timestamps (domain-specific; not SCD2)
  initiated_timestamp   TIMESTAMP NOT NULL COMMENT 'When the session was created (UTC, ISO 8601).',
  last_activity_timestamp TIMESTAMP COMMENT 'When the most recent interaction occurred (UTC, ISO 8601). Updated on each negotiation event.',
  completed_timestamp   TIMESTAMP COMMENT 'When the session concluded (UTC, ISO 8601). NULL if still active.',

  -- Audit / provenance. This table is transactional but MUTABLE: session_status
  -- and last_activity_timestamp are updated in place, so it carries
  -- source_updated_timestamp -- when the row last changed in the source -- on top
  -- of the append-only record_source + load_timestamp. created_timestamp is
  -- intentionally omitted because initiated_timestamp is the creation instant.
  record_source            STRING    COMMENT 'Originating system or orchestration platform that produced this session.',
  source_updated_timestamp TIMESTAMP COMMENT 'When this session row was last modified in the source system (UTC, ISO 8601). Advances on each in-place status/activity update.',
  load_timestamp           TIMESTAMP COMMENT 'When this row was loaded into the lakehouse (UTC, ISO 8601).',

  CONSTRAINT pk_a2a_session PRIMARY KEY (a2a_session_sk)
)
USING DELTA
CLUSTER BY (a2a_session_id, initiated_timestamp)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Agent-to-agent commerce session tracking for the Agentic Commerce outcome package. One row per A2A negotiation lifecycle between a buying agent (customer) and a selling agent (retailer).';

-- Table classification: TAGS-DATA-TYPE
ALTER TABLE ${catalog}.${ac_schema}.a2a_session SET TAGS ('dbx_data_type' = 'transactional');

-- PII column classification. session_summary is free text that may relay customer
-- details of ANY PII type (name, address, contact) written by the agents. Because
-- no single typed dbx_pii_* (name/email/phone/dob/address/financial/identifier)
-- describes an untyped free-text column, it takes the untyped `dbx_pii` tag so the
-- column is still governed (masking/ABAC) without asserting a wrong type.
ALTER TABLE ${catalog}.${ac_schema}.a2a_session ALTER COLUMN session_summary SET TAGS ('dbx_pii' = 'true');
