-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce
-- Table: a2a_mandate
-- Layer: outcome package (extension table / dimensional master)
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-02 by @shubhamp051991
-- ============================================================
-- SCOPE: agent-to-agent (A2A) commerce. See a2a_session.sql for the
-- scope boundary vs human-to-assistant conversational shopping.
--
-- The delegated authority a human customer grants to a BUYING agent — the
-- guardrails an agent must transact within: a spend ceiling, the product
-- categories it may buy, and the value above which a human must approve.
-- SCD2: a customer revises the mandate over time (raises the ceiling,
-- narrows categories), and each version is retained.
--
-- Relationships (declared in relationships.sql):
--   buyer_profile_sk  -> customer.profile      (the human granting authority)
--   a2a_agent_sk      -> a2a_agent             (the buying agent it governs)
-- The consent that authorizes automated purchasing is referenced by the
-- durable consent_id business key (logical link — consent is SCD2 in the
-- customer core; the mandate names the decision, not a version).
--
-- Catalog/schema are injected at deploy time (${catalog}.${ac_schema});
-- never hardcode.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${ac_schema}.a2a_mandate (
  a2a_mandate_sk        BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version.',
  a2a_mandate_id        STRING NOT NULL
                          COMMENT 'Durable natural/business key for the mandate. Stable across SCD2 versions.',

  -- The human granting authority and the agent governed by it
  buyer_profile_sk      BIGINT COMMENT 'FK to customer.profile.profile_sk — the customer granting the mandate.',
  buyer_profile_id      STRING COMMENT 'Durable business key of the granting customer.',
  a2a_agent_sk          BIGINT COMMENT 'FK to a2a_agent.a2a_agent_sk — the buying agent this mandate governs.',
  a2a_agent_id          STRING COMMENT 'Durable business key of the governed agent.',

  -- Authorizing consent (logical link to the SCD2 consent decision in the core)
  consent_id            STRING COMMENT 'Durable customer.consent business key authorizing automated purchasing. Logical reference (not a UC FK) — consent is SCD2 in the core (ADR 0030).',

  -- Guardrails
  spend_ceiling_amount  DECIMAL(18,2) COMMENT 'Maximum cumulative spend the agent may commit under this mandate, in the reporting currency.',
  per_transaction_limit_amount DECIMAL(18,2) COMMENT 'Maximum value of a single transaction the agent may commit without human approval, in the reporting currency.',
  currency_code         STRING COMMENT 'ISO 4217 reporting-currency code for the amount columns. Single reporting currency across the package.',
  approval_threshold_amount DECIMAL(18,2) COMMENT 'Transaction value at or above which a human must approve. NULL = no human-approval step.',
  allowed_categories    STRING COMMENT 'Comma-separated product categories the agent may transact in. NULL = unrestricted.',
  mandate_status        STRING NOT NULL COMMENT 'Lifecycle status. Allowed values: active, suspended, revoked, expired.',

  -- SCD2 versioning
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date this version stopped being effective; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version of this mandate.',

  -- Audit / provenance (master block)
  created_timestamp        TIMESTAMP COMMENT 'When the mandate was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the mandate was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded into the lakehouse (UTC, ISO 8601).',

  CONSTRAINT pk_a2a_mandate PRIMARY KEY (a2a_mandate_sk)
)
USING DELTA
CLUSTER BY (a2a_mandate_id, effective_from_date)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Delegated purchasing authority a customer grants to a buying agent — spend ceiling, per-transaction limit, approval threshold, and allowed categories. SCD2 dimensional master.';

ALTER TABLE ${catalog}.${ac_schema}.a2a_mandate SET TAGS ('dbx_data_type' = 'master');
