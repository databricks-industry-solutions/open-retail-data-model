-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce
-- Table: a2a_agent
-- Layer: outcome package (extension table / dimensional master)
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-02 by @shubhamp051991
-- ============================================================
-- SCOPE: agent-to-agent (A2A) commerce. See a2a_session.sql for the
-- scope boundary vs human-to-assistant conversational shopping.
--
-- The autonomous agents that participate in A2A sessions, as first-class
-- actors. An agent acts on behalf of either a buyer (a customer) or a
-- seller (a retailer/store). SCD2: an agent's trust status, capabilities,
-- and protocol version change over time and are versioned here.
--
-- A buying agent links to the customer it represents via
-- represented_profile_id; a selling agent links to the store it
-- represents via represented_store_id. Exactly one is populated per row
-- (enforced in checks.sql), matching the agent_role.
--
-- Catalog/schema are injected at deploy time (${catalog}.${ac_schema});
-- never hardcode.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${ac_schema}.a2a_agent (
  a2a_agent_sk          BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version.',
  a2a_agent_id          STRING NOT NULL
                          COMMENT 'Durable natural/business key for the agent. Stable across SCD2 versions.',

  agent_name            STRING COMMENT 'Display name of the agent.',
  agent_role            STRING NOT NULL COMMENT 'Which side the agent acts for. Allowed values: buyer_agent, seller_agent.',
  operator_name         STRING COMMENT 'Organization or platform that operates the agent (vendor-neutral label).',

  -- Whom the agent represents (exactly one populated per agent_role; see checks.sql).
  -- INTENTIONAL logical (non-FK) reference (ADR 0030): these are durable business keys ONLY,
  -- with no represented_*_sk surrogate and no declared FK, by design. An agent is
  -- often registered before its principal is resolved in-model, and the target
  -- (profile/store) is SCD2 so a surrogate would bind to one version — whereas the
  -- represented party is version-independent. The hard, version-specific FKs live
  -- on a2a_session (buyer_profile_sk, store_sk); this column is the soft registry
  -- link, validated by the business-key orphan checks in checks.sql, not a UC FK.
  represented_profile_id STRING COMMENT 'Durable customer profile business key the agent represents, when agent_role = buyer_agent. NULL for seller agents. Logical reference (not a UC FK) — see header.',
  represented_store_id   STRING COMMENT 'Durable store business key the agent represents, when agent_role = seller_agent. NULL for buyer agents. Logical reference (not a UC FK) — see header.',

  protocol_version      STRING COMMENT 'A2A protocol version the agent speaks (free STRING; e.g. 1.0, 2.1).',
  trust_status          STRING NOT NULL COMMENT 'Verification/trust state. Allowed values: unverified, verified, suspended, revoked.',
  is_autonomous         BOOLEAN COMMENT 'TRUE if the agent can complete a transaction without human approval within its mandate.',

  -- SCD2 versioning
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date this version stopped being effective; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version of this agent.',

  -- Audit / provenance (master block)
  created_timestamp        TIMESTAMP COMMENT 'When the agent record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the agent record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded into the lakehouse (UTC, ISO 8601).',

  CONSTRAINT pk_a2a_agent PRIMARY KEY (a2a_agent_sk)
)
USING DELTA
CLUSTER BY (a2a_agent_id, effective_from_date)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Autonomous agents (buyer-side and seller-side) participating in agent-to-agent commerce sessions. SCD2 dimensional master.';

ALTER TABLE ${catalog}.${ac_schema}.a2a_agent SET TAGS ('dbx_data_type' = 'master');
