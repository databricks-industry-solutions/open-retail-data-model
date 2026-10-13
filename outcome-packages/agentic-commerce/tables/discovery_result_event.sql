-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce
-- Table: discovery_result_event
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-07-27
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-27
-- ============================================================
-- Append-only fact at one product result returned for a discovery intent. The
-- grain is intent event x product x rank, with ranking/reason/availability
-- context retained for explainable discovery performance analysis.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${ac_schema}.discovery_result_event (
  discovery_result_event_sk BIGINT GENERATED ALWAYS AS IDENTITY
                            COMMENT 'Surrogate key for the returned discovery result.',
  discovery_result_event_id STRING NOT NULL
                            COMMENT 'Durable natural/business key for the returned result.',

  discovery_intent_event_sk BIGINT COMMENT 'FK to discovery_intent_event.discovery_intent_event_sk.',
  discovery_intent_event_id STRING NOT NULL COMMENT 'Durable business key for the parent discovery intent event.',

  product_sk                BIGINT COMMENT 'FK to product.product_sk for the returned product.',
  product_id                STRING NOT NULL COMMENT 'Durable product business key for the returned product.',
  store_sk                  BIGINT COMMENT 'FK to store.store_sk when result availability is store-scoped.',
  store_id                  STRING COMMENT 'Durable store business key when result availability is store-scoped.',

  result_rank               INT NOT NULL COMMENT 'One-based product rank within the returned result set.',
  retrieval_score           DOUBLE COMMENT 'Candidate retrieval score, from 0.0 to 1.0 when normalized.',
  ranking_score             DOUBLE COMMENT 'Final ranking score, from 0.0 to 1.0 when normalized.',
  personalization_score     DOUBLE COMMENT 'Personalization component of the ranking score, from 0.0 to 1.0 when normalized.',
  availability_score        DOUBLE COMMENT 'Availability component of the ranking score, from 0.0 to 1.0 when normalized.',
  reason_code               STRING COMMENT 'Primary explainability reason. Allowed values: lexical_match, semantic_match, purchase_affinity, substitute, complement, trending, available_nearby, business_rule.',

  is_available_flag         BOOLEAN COMMENT 'TRUE when the result was considered buyable/available at ranking time.',
  units_available           DECIMAL(12,3) COMMENT 'Units available at ranking time when known.',
  list_price_amount         DECIMAL(18,4) COMMENT 'List/shelf price shown or used at ranking time, in the reporting/base currency.',
  currency_code             STRING COMMENT 'Reporting/base currency for price fields, ISO 4217 alpha-3.',

  event_ts                  TIMESTAMP NOT NULL COMMENT 'When the result was produced at source (UTC, ISO 8601).',
  event_date                DATE NOT NULL COMMENT 'Business date of the result event.',

  record_source             STRING COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp            TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_discovery_result_event PRIMARY KEY (discovery_result_event_sk)
)
USING DELTA
CLUSTER BY (discovery_intent_event_id, event_date)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Agentic Commerce returned product result fact for organic intent product discovery.';

ALTER TABLE ${catalog}.${ac_schema}.discovery_result_event SET TAGS ('dbx_data_type' = 'transactional');
