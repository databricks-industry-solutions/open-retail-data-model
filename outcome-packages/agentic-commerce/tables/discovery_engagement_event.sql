-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce
-- Table: discovery_engagement_event
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-07-27
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-27
-- ============================================================
-- Append-only fact for shopper engagement with a returned discovery result.
-- Keeps clicks, selections, add-to-cart, and purchase attribution as events
-- rather than mutable state on the ranked-result fact.
-- quantity/net_amount/currency_code are a point-of-engagement attribution
-- SNAPSHOT recorded at engagement time; they are NOT reconciled against
-- customer_order_line even when order_line_sk resolves (the order line remains
-- the authoritative financial record). Report on customer_order_line when you
-- need the reconciled purchase value; use these for engagement attribution.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${ac_schema}.discovery_engagement_event (
  discovery_engagement_event_sk BIGINT GENERATED ALWAYS AS IDENTITY
                                COMMENT 'Surrogate key for the discovery engagement event.',
  discovery_engagement_event_id STRING NOT NULL
                                COMMENT 'Durable natural/business key for the engagement event.',

  discovery_result_event_sk     BIGINT COMMENT 'FK to discovery_result_event.discovery_result_event_sk.',
  discovery_result_event_id     STRING NOT NULL COMMENT 'Durable business key for the engaged result.',
  discovery_intent_event_sk     BIGINT COMMENT 'FK to discovery_intent_event.discovery_intent_event_sk.',
  discovery_intent_event_id     STRING NOT NULL COMMENT 'Durable business key for the parent discovery intent event.',

  profile_sk                    BIGINT COMMENT 'FK to customer.profile.profile_sk when the shopper is resolved.',
  profile_id                    STRING COMMENT 'Durable customer business key (pseudonymous). NULL for anonymous engagement.',
  product_sk                    BIGINT COMMENT 'FK to product.product_sk for the engaged product.',
  product_id                    STRING NOT NULL COMMENT 'Durable product business key for the engaged product.',
  store_sk                      BIGINT COMMENT 'FK to store.store_sk when engagement is store-scoped.',
  store_id                      STRING COMMENT 'Durable store business key when engagement is store-scoped.',
  order_line_sk                 BIGINT COMMENT 'FK to customer_order_line.order_line_sk when engagement converted to a purchase.',
  order_line_id                 STRING COMMENT 'Durable order-line business key when purchase attribution is known.',
  order_id                      STRING COMMENT 'Operational order identifier retained as a degenerate attribute.',

  engagement_type               STRING NOT NULL COMMENT 'Type of engagement. Allowed values: view, select, add_to_cart, purchase, dismiss.',
  engagement_ts                 TIMESTAMP NOT NULL COMMENT 'When the engagement occurred at source (UTC, ISO 8601).',
  engagement_date               DATE NOT NULL COMMENT 'Business date of the engagement.',
  quantity                      INT COMMENT 'Units associated with the engagement, populated for add-to-cart or purchase events when known.',
  net_amount                    DECIMAL(18,2) COMMENT 'Net purchase amount in the reporting/base currency, populated only for purchase events. Point-of-engagement attribution snapshot; not reconciled against customer_order_line.net_amount even when order_line_sk resolves.',
  currency_code                 STRING COMMENT 'Reporting/base currency for net_amount, ISO 4217 alpha-3.',
  attribution_window_minutes    INT COMMENT 'Minutes between result production and engagement when known.',

  record_source                 STRING COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp                TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_discovery_engagement_event PRIMARY KEY (discovery_engagement_event_sk)
)
USING DELTA
CLUSTER BY (discovery_intent_event_id, engagement_date)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Agentic Commerce engagement fact for organic intent product discovery results.';

ALTER TABLE ${catalog}.${ac_schema}.discovery_engagement_event SET TAGS ('dbx_data_type' = 'transactional');
ALTER TABLE ${catalog}.${ac_schema}.discovery_engagement_event ALTER COLUMN profile_id SET TAGS ('dbx_pii_identifier' = 'true');
