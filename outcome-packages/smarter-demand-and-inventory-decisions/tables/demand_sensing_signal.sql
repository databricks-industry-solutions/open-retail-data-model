-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- Table: demand_sensing_signal
-- Layer: outcome package (extension table / transactional fact)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Short-horizon demand sensing anomaly feed. Append-only.
-- ============================================================


CREATE TABLE IF NOT EXISTS ${catalog}.${sdi_schema}.demand_sensing_signal (
  demand_sensing_signal_sk BIGINT GENERATED ALWAYS AS IDENTITY
                            COMMENT 'Surrogate key.',
  demand_sensing_signal_id STRING NOT NULL
                            COMMENT 'Durable business key.',

  planning_unit_sk        BIGINT COMMENT 'FK to planning_unit.planning_unit_sk.',
  planning_unit_id        STRING COMMENT 'Durable planning unit business key.',
  product_sk              BIGINT COMMENT 'FK to product.product_sk (version-specific).',
  product_id              STRING COMMENT 'Durable product business key.',
  store_sk                BIGINT COMMENT 'FK to store.store_sk (version-specific).',
  store_id                STRING COMMENT 'Durable store business key.',

  signal_timestamp        TIMESTAMP NOT NULL COMMENT 'When the signal was detected (UTC).',
  signal_category         STRING NOT NULL
                            COMMENT 'Category. Allowed values: supply, promo, weather, transport, social, data_quality, competitor.',
  signal_type             STRING COMMENT 'Specific signal type (e.g. retail_stockout, transport_delay).',
  signal_description      STRING COMMENT 'Human-readable description.',
  severity                STRING NOT NULL
                            COMMENT 'Severity. Allowed values: critical, high, medium, low.',
  resolved_flag           BOOLEAN COMMENT 'Whether the signal has been resolved.',
  resolved_at_timestamp   TIMESTAMP COMMENT 'When resolved (UTC).',
  linked_oos_event_sk     BIGINT COMMENT 'FK to oos_event.oos_event_sk when promoted.',

  record_source           STRING    COMMENT 'Originating system of record.',
  load_timestamp          TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_demand_sensing_signal PRIMARY KEY (demand_sensing_signal_sk)
)
USING DELTA
CLUSTER BY (signal_timestamp)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Append-only short-horizon demand sensing signals.';

ALTER TABLE ${catalog}.${sdi_schema}.demand_sensing_signal SET TAGS ('dbx_data_type' = 'transactional');
ALTER TABLE ${catalog}.${sdi_schema}.demand_sensing_signal ADD CONSTRAINT chk_dss_category CHECK (signal_category IN ('supply', 'promo', 'weather', 'transport', 'social', 'data_quality', 'competitor'));
ALTER TABLE ${catalog}.${sdi_schema}.demand_sensing_signal ADD CONSTRAINT chk_dss_severity CHECK (severity IN ('critical', 'high', 'medium', 'low'));
