-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce
-- Table: a2a_negotiation_event
-- Layer: outcome package (extension table / append-only fact)
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-02 by @shubhamp051991
-- ============================================================
-- SCOPE: agent-to-agent (A2A) commerce. See a2a_session.sql for the
-- scope boundary vs human-to-assistant conversational shopping.
--
-- Append-only log of every negotiation step within an A2A session: a
-- price request, an offer, a counter-offer, an acceptance, a rejection,
-- an availability check, or an escalation to a human. Event-grained and
-- append-only: rows are never updated. The parent a2a_session carries the
-- current lifecycle state; this table is the immutable history behind it.
--
-- Designed for streaming: carries event_timestamp, ingest_timestamp, and
-- latency_seconds for freshness monitoring (same pattern as the Early Risk
-- Detection disruption_event log).
--
-- Monetary: proposed_price is DECIMAL(18,4) (unit-grain price) normalized to
-- the reporting currency; currency_code preserves the ISO 4217 code so a
-- single-reporting-currency DQ check can assert consistency.
--
-- Catalog/schema are injected at deploy time (${catalog}.${ac_schema});
-- never hardcode.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${ac_schema}.a2a_negotiation_event (
  a2a_negotiation_event_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  a2a_negotiation_event_id STRING NOT NULL
                          COMMENT 'Durable natural/business key for the negotiation event.',

  -- Parent session (the negotiation this event belongs to). Mandatory: unlike
  -- the optional product link, an event has no meaning without its session — a
  -- NULL here would silently vanish from every gold view (all LEFT JOIN from
  -- a2a_session), so it is NOT NULL rather than a nullable informational FK.
  a2a_session_sk        BIGINT NOT NULL COMMENT 'FK to a2a_session.a2a_session_sk — the session this event occurred in.',
  a2a_session_id        STRING NOT NULL COMMENT 'Durable business key of the parent session.',

  -- Which agent emitted this event
  a2a_agent_sk          BIGINT COMMENT 'FK to a2a_agent.a2a_agent_sk — the agent that emitted this event.',
  a2a_agent_id          STRING COMMENT 'Durable business key of the emitting agent.',

  -- Product the step concerns (a session may span several; each event names one)
  product_sk            BIGINT COMMENT 'FK to product.product.product_sk — the product this step concerns, if applicable.',
  product_id            STRING COMMENT 'Durable product business key.',

  event_type            STRING NOT NULL COMMENT 'The negotiation step. Allowed values: price_request, offer, counter_offer, acceptance, rejection, availability_check, escalation_to_human.',
  event_sequence        INT NOT NULL COMMENT 'Monotonic step number within the session (1 = first event). NOT NULL: it is load-bearing for ordering — gold_a2a_session_summary anchors first_offer_price via MIN_BY(price, event_sequence) and de-dups the acceptance via ROW_NUMBER() OVER (ORDER BY event_sequence). A NULL would silently misorder replay and the concession anchor.',

  -- Proposed terms (nullable; which are set depends on event_type)
  proposed_price        DECIMAL(18,4) COMMENT 'Proposed unit price for this step, normalized to the reporting currency. NULL for non-price events.',
  currency_code         STRING COMMENT 'ISO 4217 reporting-currency code for proposed_price. Single reporting currency across the package.',
  proposed_quantity     INT COMMENT 'Proposed quantity for this step. NULL when not applicable.',

  -- Real-time / streaming support
  event_timestamp       TIMESTAMP NOT NULL COMMENT 'When the event occurred at source (UTC, ISO 8601).',
  ingest_timestamp      TIMESTAMP NOT NULL COMMENT 'When this event was ingested into the lakehouse (UTC, ISO 8601).',
  latency_seconds       INT COMMENT 'Ingest latency = ingest_timestamp - event_timestamp, in seconds.',

  -- Audit / provenance (append-only fact block)
  record_source         STRING    COMMENT 'Originating system or orchestration platform that produced this event.',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_a2a_negotiation_event PRIMARY KEY (a2a_negotiation_event_sk)
)
USING DELTA
CLUSTER BY (a2a_session_id, event_timestamp)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Append-only negotiation event log for agent-to-agent commerce sessions. One row per offer / counter-offer / acceptance / escalation step.';

ALTER TABLE ${catalog}.${ac_schema}.a2a_negotiation_event SET TAGS ('dbx_data_type' = 'transactional');
