-- ============================================================
-- ORDM · Outcome Package · AI-Assisted Store Associates
-- Table: associate_context_event
-- Layer: outcome package (extension table / transactional fact)
-- Version: 0.5
-- Generated: 2026-08-11
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-11
-- ============================================================
-- Append-only, streaming-ready event log for associate real-time
-- context. Adopters land inventory, price, promotion, order, and
-- operations change events here (CDC / Structured Streaming / micro-
-- batch). ORDM does not ship ingestion pipelines (CONTRIBUTING §2);
-- this table is the governed contract and synthetic fixture surface.
--
-- Idempotency: durable associate_context_event_id is unique per source
-- event. Late / out-of-order events are retained; current-state gold
-- views pick the latest valid event by event_timestamp then ingest.
--
-- CDF: delta.enableChangeDataFeed supports incremental MV refresh,
-- Lakebase sync, and late-event debug (see LAKEBASE_SERVING.md).
-- Cluster keys favour associate point lookup (store × product × time).
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${aasa_schema}.associate_context_event (
  associate_context_event_sk BIGINT GENERATED ALWAYS AS IDENTITY
                               COMMENT 'Surrogate key.',
  associate_context_event_id STRING NOT NULL
                               COMMENT 'Durable natural/business key for the source event (idempotency key).',

  event_domain          STRING NOT NULL
                          COMMENT 'Domain of the change. Allowed values: inventory, price, promotion, order, operations.',
  event_type            STRING NOT NULL
                          COMMENT 'Change type within the domain (e.g. stock_adjustment, price_update, promo_activate, fulfillment_update, equipment_alert).',

  store_sk              BIGINT COMMENT 'FK to store.store_sk when store-scoped.',
  store_id              STRING COMMENT 'Durable store business key when store-scoped.',
  product_sk            BIGINT COMMENT 'FK to product.product_sk when product-scoped.',
  product_id            STRING COMMENT 'Durable product business key when product-scoped.',
  order_id              STRING COMMENT 'Durable order business key when order-scoped. No customer identifiers.',
  promo_id              STRING COMMENT 'Durable promotion business key when promotion-scoped.',
  equipment_id          STRING COMMENT 'Durable equipment business key when operations/equipment-scoped.',

  quantity_on_hand      DECIMAL(12,3) COMMENT 'Observed on-hand quantity for inventory events (nullable).',
  quantity_available    DECIMAL(12,3) COMMENT 'Observed available-to-sell quantity for inventory events (nullable).',
  quantity_reserved     DECIMAL(12,3) COMMENT 'Observed reserved quantity for inventory events (nullable).',
  quantity_in_transit   DECIMAL(12,3) COMMENT 'Observed in-transit quantity for inventory events (nullable).',
  unit_price_amount     DECIMAL(18,4) COMMENT 'Observed unit price for price events (unit-grain DECIMAL scale 4).',
  currency_code         STRING COMMENT 'ISO 4217 reporting/base currency for monetary amounts; constant base_currency.',
  status_code           STRING COMMENT 'Domain status payload (stock status, order status, alert severity, etc.).',
  location_code         STRING COMMENT 'Sales-floor or backroom location code when provided by source.',
  event_payload_summary STRING COMMENT 'Short vendor-neutral summary suitable for associate display; never PII.',

  source_system         STRING NOT NULL COMMENT 'Vendor-neutral source-system label (e.g. inventory_ledger, price_engine, oms, iot_gateway).',
  event_timestamp       TIMESTAMP NOT NULL COMMENT 'Event time at source (UTC, ISO 8601).',
  ingest_timestamp      TIMESTAMP NOT NULL COMMENT 'When the event was ingested into the lakehouse (UTC, ISO 8601).',
  processed_timestamp   TIMESTAMP COMMENT 'When current-state processing considered this event (UTC, ISO 8601).',
  latency_seconds       INT COMMENT 'Ingest latency = ingest_timestamp - event_timestamp, in seconds.',

  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_associate_context_event PRIMARY KEY (associate_context_event_sk)
)
USING DELTA
CLUSTER BY (store_id, product_id, event_timestamp)
TBLPROPERTIES (
  delta.enableDeletionVectors = true,
  delta.enableChangeDataFeed = true
)
COMMENT 'Append-only associate context events for Real-Time Data Access. Streaming-ready contract; current-state gold views derive from the latest valid event per entity.';

ALTER TABLE ${catalog}.${aasa_schema}.associate_context_event SET TAGS ('dbx_data_type' = 'transactional');

ALTER TABLE ${catalog}.${aasa_schema}.associate_context_event ADD CONSTRAINT chk_ace_domain CHECK (event_domain IN ('inventory', 'price', 'promotion', 'order', 'operations'));
ALTER TABLE ${catalog}.${aasa_schema}.associate_context_event ADD CONSTRAINT chk_ace_qty_on_hand CHECK (quantity_on_hand IS NULL OR quantity_on_hand >= 0);
ALTER TABLE ${catalog}.${aasa_schema}.associate_context_event ADD CONSTRAINT chk_ace_qty_available CHECK (quantity_available IS NULL OR quantity_available >= 0);
ALTER TABLE ${catalog}.${aasa_schema}.associate_context_event ADD CONSTRAINT chk_ace_qty_reserved CHECK (quantity_reserved IS NULL OR quantity_reserved >= 0);
ALTER TABLE ${catalog}.${aasa_schema}.associate_context_event ADD CONSTRAINT chk_ace_qty_transit CHECK (quantity_in_transit IS NULL OR quantity_in_transit >= 0);
ALTER TABLE ${catalog}.${aasa_schema}.associate_context_event ADD CONSTRAINT chk_ace_price CHECK (unit_price_amount IS NULL OR unit_price_amount >= 0);
