-- ============================================================
-- ORDM · Outcome Package · AI-Assisted Store Associates
-- Table: associate_lookup_audit
-- Layer: outcome package (extension table / transactional fact)
-- Version: 0.5
-- Generated: 2026-08-11
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-11
-- ============================================================
-- Structured audit log for associate real-time lookups. Records
-- allow/deny decisions, capability, store scope, latency, and
-- response status. Privacy: stores hashed entity keys only — never
-- raw search terms, customer identifiers, or response payloads.
-- Adopter applications / SQL UDFs append rows; ORDM ships the schema
-- and synthetic fixtures (applications themselves are out of scope).
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${aasa_schema}.associate_lookup_audit (
  associate_lookup_audit_sk BIGINT GENERATED ALWAYS AS IDENTITY
                              COMMENT 'Surrogate key.',
  associate_lookup_audit_id STRING NOT NULL
                              COMMENT 'Durable natural/business key for the audit event.',

  request_id            STRING NOT NULL COMMENT 'Caller-supplied request identifier.',
  correlation_id        STRING NOT NULL COMMENT 'Cross-system correlation identifier.',
  request_timestamp     TIMESTAMP NOT NULL COMMENT 'When the lookup was requested (UTC, ISO 8601).',
  generated_at          TIMESTAMP NOT NULL COMMENT 'When the audit row was written (UTC, ISO 8601).',

  associate_id          STRING COMMENT 'Pseudonymous associate / session identifier. Not a legal name.',
  associate_role        STRING COMMENT 'Requester role code (e.g. sales_associate, fulfillment, supervisor, store_manager).',
  channel               STRING COMMENT 'Request channel. Allowed values: mobile, kiosk, pos, dashboard, api, test.',
  store_id              STRING COMMENT 'Store scope asserted on the request.',

  capability            STRING NOT NULL
                          COMMENT 'Requested capability. Allowed values: get_product_availability, get_product_location, get_price_and_promotions, get_order_fulfillment_status, get_store_operations_context, get_associate_context_summary.',
  access_decision       STRING NOT NULL COMMENT 'Authorization outcome. Allowed values: allow, deny.',
  access_reason_code    STRING NOT NULL COMMENT 'Machine-readable reason for the access decision.',
  response_status       STRING NOT NULL
                          COMMENT 'Envelope status returned to the caller. Allowed values: SUCCESS, NOT_FOUND, NOT_AVAILABLE, STALE_DATA, ACCESS_DENIED, INVALID_REQUEST, PARTIAL_RESULT, UPSTREAM_DATA_DELAY.',

  latency_ms            INT COMMENT 'End-to-end lookup latency in milliseconds.',
  domains_accessed      STRING COMMENT 'Comma-separated domain tags actually read (inventory,price,promotion,order,operations).',
  data_classification   STRING COMMENT 'Highest classification of returned fields. Allowed values: public_ops, associate_ops, restricted.',
  product_id_hash       STRING COMMENT 'SHA-256 hex of product_id when product-scoped; NULL otherwise. Never store raw search text.',
  order_id_hash         STRING COMMENT 'SHA-256 hex of order_id when order-scoped; NULL otherwise.',

  record_source         STRING    COMMENT 'Originating lookup service label.',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_associate_lookup_audit PRIMARY KEY (associate_lookup_audit_sk)
)
USING DELTA
CLUSTER BY (store_id, request_timestamp)
TBLPROPERTIES (
  delta.enableDeletionVectors = true,
  delta.enableChangeDataFeed = true
)
COMMENT 'Associate lookup audit trail. Allow/deny, capability, latency, hashed keys only — no customer PII or raw search terms.';

ALTER TABLE ${catalog}.${aasa_schema}.associate_lookup_audit SET TAGS ('dbx_data_type' = 'transactional');

ALTER TABLE ${catalog}.${aasa_schema}.associate_lookup_audit ADD CONSTRAINT chk_ala_channel CHECK (channel IS NULL OR channel IN ('mobile', 'kiosk', 'pos', 'dashboard', 'api', 'test'));
ALTER TABLE ${catalog}.${aasa_schema}.associate_lookup_audit ADD CONSTRAINT chk_ala_capability CHECK (capability IN ('get_product_availability', 'get_product_location', 'get_price_and_promotions', 'get_order_fulfillment_status', 'get_store_operations_context', 'get_associate_context_summary'));
ALTER TABLE ${catalog}.${aasa_schema}.associate_lookup_audit ADD CONSTRAINT chk_ala_decision CHECK (access_decision IN ('allow', 'deny'));
ALTER TABLE ${catalog}.${aasa_schema}.associate_lookup_audit ADD CONSTRAINT chk_ala_status CHECK (response_status IN ('SUCCESS', 'NOT_FOUND', 'NOT_AVAILABLE', 'STALE_DATA', 'ACCESS_DENIED', 'INVALID_REQUEST', 'PARTIAL_RESULT', 'UPSTREAM_DATA_DELAY'));
ALTER TABLE ${catalog}.${aasa_schema}.associate_lookup_audit ADD CONSTRAINT chk_ala_class CHECK (data_classification IS NULL OR data_classification IN ('public_ops', 'associate_ops', 'restricted'));
ALTER TABLE ${catalog}.${aasa_schema}.associate_lookup_audit ADD CONSTRAINT chk_ala_latency CHECK (latency_ms IS NULL OR latency_ms >= 0);
