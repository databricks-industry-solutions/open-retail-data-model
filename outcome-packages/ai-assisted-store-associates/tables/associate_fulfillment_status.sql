-- ============================================================
-- ORDM · Outcome Package · AI-Assisted Store Associates
-- Table: associate_fulfillment_status
-- Layer: outcome package (extension table / transactional fact)
-- Version: 0.5
-- Generated: 2026-08-11
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-11
-- ============================================================
-- Associate-safe customer-order fulfillment / pickup status.
--
-- DOMAIN EXTENSION: the canonical-core `order` domain
-- (`customer_order_line`) is a purchase-line fact for CLV and does not
-- model BOPIS / curbside / ship-to-store fulfillment lifecycle. This
-- table fills that gap for associate lookup only. It intentionally
-- omits customer PII (no profile_id, name, contact, loyalty). Order
-- lookup requires an exact order_id; broad search is denied in the
-- policy layer.
--
-- CDF: delta.enableChangeDataFeed supports incremental Lakebase sync
-- and MV refresh of gold_associate_order_status_current.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${aasa_schema}.associate_fulfillment_status (
  associate_fulfillment_status_sk BIGINT GENERATED ALWAYS AS IDENTITY
                                    COMMENT 'Surrogate key.',
  associate_fulfillment_status_id STRING NOT NULL
                                    COMMENT 'Durable natural/business key (typically equals order_id for current-state grain).',

  order_id              STRING NOT NULL COMMENT 'Durable customer-order business key. Required for associate lookup.',
  store_sk              BIGINT COMMENT 'FK to store.store_sk of the fulfillment / pickup store.',
  store_id              STRING NOT NULL COMMENT 'Durable store business key where the order is fulfilled or picked up.',

  fulfillment_type      STRING NOT NULL
                          COMMENT 'Fulfillment mode. Allowed values: bopis, curbside, ship_to_store, ship_to_home, in_store_reserve.',
  order_status          STRING NOT NULL
                          COMMENT 'Associate-safe order status. Allowed values: received, picking, packing, ready_for_pickup, picked_up, shipped, cancelled, exception.',
  pickup_readiness      STRING NOT NULL
                          COMMENT 'Pickup readiness. Allowed values: not_ready, ready, overdue, completed, not_applicable.',
  pickup_location_code  STRING COMMENT 'Pickup desk / locker / curbside bay code. No customer address.',
  exception_state       STRING
                          COMMENT 'Exception state when order_status = exception. Allowed values: missing_item, payment_hold, customer_no_show, damaged, other, none.',

  last_event_timestamp  TIMESTAMP NOT NULL COMMENT 'Latest known fulfillment event time (UTC, ISO 8601).',
  source_system         STRING NOT NULL COMMENT 'Vendor-neutral OMS / fulfillment source label.',
  requires_customer_verification BOOLEAN NOT NULL
                          COMMENT 'TRUE when associate must present authorized customer-verification context before detail is returned.',
  data_freshness_timestamp TIMESTAMP NOT NULL COMMENT 'When this current-state row was last refreshed (UTC, ISO 8601).',

  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_associate_fulfillment_status PRIMARY KEY (associate_fulfillment_status_sk)
)
USING DELTA
CLUSTER BY (store_id, order_id)
TBLPROPERTIES (
  delta.enableDeletionVectors = true,
  delta.enableChangeDataFeed = true
)
COMMENT 'Associate-safe order fulfillment / pickup status. No customer PII. Exact order_id required for lookup.';

ALTER TABLE ${catalog}.${aasa_schema}.associate_fulfillment_status SET TAGS ('dbx_data_type' = 'transactional');

ALTER TABLE ${catalog}.${aasa_schema}.associate_fulfillment_status ADD CONSTRAINT chk_afs_fulfillment_type CHECK (fulfillment_type IN ('bopis', 'curbside', 'ship_to_store', 'ship_to_home', 'in_store_reserve'));
ALTER TABLE ${catalog}.${aasa_schema}.associate_fulfillment_status ADD CONSTRAINT chk_afs_order_status CHECK (order_status IN ('received', 'picking', 'packing', 'ready_for_pickup', 'picked_up', 'shipped', 'cancelled', 'exception'));
ALTER TABLE ${catalog}.${aasa_schema}.associate_fulfillment_status ADD CONSTRAINT chk_afs_pickup_readiness CHECK (pickup_readiness IN ('not_ready', 'ready', 'overdue', 'completed', 'not_applicable'));
ALTER TABLE ${catalog}.${aasa_schema}.associate_fulfillment_status ADD CONSTRAINT chk_afs_exception CHECK (exception_state IS NULL OR exception_state IN ('missing_item', 'payment_hold', 'customer_no_show', 'damaged', 'other', 'none'));
