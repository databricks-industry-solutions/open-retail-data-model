-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- Table: oos_event
-- Layer: outcome package (extension table / transactional fact)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Out-of-stock episode at product x store grain.
-- ============================================================


CREATE TABLE IF NOT EXISTS ${catalog}.${sdi_schema}.oos_event (
  oos_event_sk            BIGINT GENERATED ALWAYS AS IDENTITY
                            COMMENT 'Surrogate key.',
  oos_event_id            STRING NOT NULL
                            COMMENT 'Durable business key.',

  product_sk              BIGINT COMMENT 'FK to product.product_sk (version-specific).',
  product_id              STRING NOT NULL COMMENT 'Durable product business key.',
  store_sk                BIGINT COMMENT 'FK to store.store_sk (version-specific).',
  store_id                STRING NOT NULL COMMENT 'Durable store business key.',

  oos_start_date_key      DATE NOT NULL COMMENT 'First day of the OOS episode.',
  oos_end_date_key        DATE COMMENT 'Last day of the episode; NULL if ongoing.',
  oos_duration_days       INT COMMENT 'Duration of the episode in days.',
  detection_method        STRING NOT NULL
                            COMMENT 'How detected. Allowed values: inventory_snapshot, velocity_collapse, pos_absence, smart_shelf, planner_reported.',
  oos_cause               STRING NOT NULL
                            COMMENT 'Root cause. Allowed values: replenishment_miss, supplier_delay, demand_spike, allocation_shortage, planogram_issue, phantom_stock, record_inaccuracy, shrinkage, misplaced, unknown. The phantom_stock/record_inaccuracy/shrinkage/misplaced values capture on-shelf-availability gaps where system on-hand > 0 but the shelf is empty (the dominant real-world OOS driver); populated only where a shelf/OSA signal exists, else system-availability causes apply.',
  oos_severity            STRING NOT NULL
                            COMMENT 'Severity. Allowed values: critical, high, medium, low.',
  is_promo_period         BOOLEAN COMMENT 'Whether a promotion overlapped the episode.',
  stockout_pct_total      DECIMAL(5,4) COMMENT 'Average stockout_pct_day over the episode.',
  competitor_spillover_flag BOOLEAN COMMENT 'Competitor stockout spillover detected.',
  data_quality_flag       BOOLEAN COMMENT 'Suspected data quality issue.',
  is_preventable           BOOLEAN COMMENT 'Whether the OOS was preventable.',
  linked_disruption_event_id STRING COMMENT 'Degenerate reference to early-risk-detection disruption_event.',

  record_source           STRING    COMMENT 'Originating system of record.',
  load_timestamp          TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_oos_event PRIMARY KEY (oos_event_sk)
)
USING DELTA
CLUSTER BY (oos_start_date_key, product_sk, store_sk)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Out-of-stock episode fact at product x store grain.';

ALTER TABLE ${catalog}.${sdi_schema}.oos_event SET TAGS ('dbx_data_type' = 'transactional');
ALTER TABLE ${catalog}.${sdi_schema}.oos_event ADD CONSTRAINT chk_oe_detection CHECK (detection_method IN ('inventory_snapshot', 'velocity_collapse', 'pos_absence', 'smart_shelf', 'planner_reported'));
ALTER TABLE ${catalog}.${sdi_schema}.oos_event ADD CONSTRAINT chk_oe_cause CHECK (oos_cause IN ('replenishment_miss', 'supplier_delay', 'demand_spike', 'allocation_shortage', 'planogram_issue', 'phantom_stock', 'record_inaccuracy', 'shrinkage', 'misplaced', 'unknown'));
ALTER TABLE ${catalog}.${sdi_schema}.oos_event ADD CONSTRAINT chk_oe_severity CHECK (oos_severity IN ('critical', 'high', 'medium', 'low'));
