-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Table: tagged_item
-- Layer: outcome package (gold / serialized-item registry)
-- Version: 0.5
-- Generated: 2026-08-18
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-19
-- ============================================================
-- One row per serialized item identified by an EPC Pure Identity URI.
--
-- KEY AND HISTORY DEVIATION (ADR 0035): this streaming-written registry
-- uses xxhash64(tagged_item_id), not IDENTITY, and is Type 1 rather than SCD2.
-- The durable id is authoritative and ti_sk_collision is an error-severity guard.
-- At deployments approaching one billion distinct items, use ADR 0028 — Hash surrogate
-- keys for high-volume gold event facts — and its SHA-256
-- escape hatch rather than accepting 64-bit birthday-collision risk.
--
-- Identity is the EPC value. current_tid_hex identifies the current physical tag
-- carrier and may change when the same SGTIN is re-encoded onto another chip.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${css_schema}.tagged_item (
  tagged_item_sk       BIGINT NOT NULL
                         COMMENT 'Surrogate join key: xxhash64(tagged_item_id). The durable id remains authoritative; guarded by ti_sk_collision.',
  tagged_item_id       STRING NOT NULL
                         COMMENT 'Durable serialized-item key, valued as a GS1 EPC Pure Identity URI such as urn:epc:id:sgtin:0614141.107346.2017.',

  epc_scheme           STRING NOT NULL COMMENT 'EPC identity scheme. Allowed values: sgtin, grai.',
  gtin                 STRING COMMENT 'GTIN decomposed from an SGTIN EPC. NULL for schemes without a GTIN component.',
  serial_number        STRING COMMENT 'Serialized-unit component of an SGTIN EPC. Required for epc_scheme = sgtin.',
  current_tid_hex      STRING COMMENT 'Current physical RFID tag-chip identifier in hexadecimal. Carrier evidence, not serialized-item identity.',

  product_sk           BIGINT COMMENT 'FK to the product version resolved when the item was commissioned. NULL when the EPC cannot be resolved to a product.',
  product_id           STRING COMMENT 'Durable product business key. Retained with product_sk for portable joins.',
  lot_number           STRING COMMENT 'Optional source lot identifier for fresh or regulated categories; not a conformed lot entity.',
  expiry_date          DATE COMMENT 'Optional item expiry date for fresh or regulated categories.',

  tag_privacy_state    STRING NOT NULL COMMENT 'Current tag privacy state. Allowed values: active, protected, killed, detached.',
  commissioned_at_ts   TIMESTAMP NOT NULL COMMENT 'UTC instant when this EPC was commissioned for the serialized item.',
  decommissioned_at_ts TIMESTAMP COMMENT 'UTC instant when this EPC left active service. NULL while active.',

  created_timestamp        TIMESTAMP COMMENT 'When the registry record was created in the source system (UTC).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the Type 1 registry row was last changed in the source system (UTC).',
  record_source            STRING COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp           TIMESTAMP COMMENT 'When this row was loaded (UTC).',

  CONSTRAINT pk_tagged_item PRIMARY KEY (tagged_item_sk)
)
USING DELTA
CLUSTER BY (tagged_item_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Connected Store Signals serialized-item registry: EPC identity, product resolution, current carrier and tag privacy state.';

ALTER TABLE ${catalog}.${css_schema}.tagged_item SET TAGS ('dbx_data_type' = 'master');
