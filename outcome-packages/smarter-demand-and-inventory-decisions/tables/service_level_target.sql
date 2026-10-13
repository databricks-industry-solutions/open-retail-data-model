-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- Table: service_level_target
-- Layer: outcome package (extension table / reference)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Enterprise and segment-level service level goals for inventory optimization.
-- ============================================================


CREATE TABLE IF NOT EXISTS ${catalog}.${sdi_schema}.service_level_target (
  service_level_target_sk BIGINT GENERATED ALWAYS AS IDENTITY
                            COMMENT 'Surrogate key.',
  service_level_target_id STRING NOT NULL
                            COMMENT 'Durable business key.',

  abc_class               STRING COMMENT 'ABC class filter; NULL = default for all.',
  xyz_class               STRING COMMENT 'XYZ class filter; NULL = default for all.',
  service_measure_type    STRING COMMENT 'Which service definition target_service_level_pct expresses. Allowed values: cycle_service_level (Type I / alpha - probability of no stockout per cycle, maps directly to the safety-stock z-score), fill_rate (Type II / beta - fraction of demand met from stock, requires the unit-normal loss function), in_stock_rate (share of time in stock). These are NOT interchangeable; conflating them mis-sizes safety stock.',
  target_service_level_pct DECIMAL(5,4) COMMENT 'Target service level (0-1) interpreted per service_measure_type.',
  target_fill_rate_pct    DECIMAL(5,4) COMMENT 'Target in-stock fill rate (0-1). Retained for backward compatibility; prefer service_measure_type = fill_rate with target_service_level_pct.',
  target_days_of_supply   DECIMAL(8,2) COMMENT 'Target days of supply alternative.',

  effective_from_date     DATE NOT NULL COMMENT 'Inclusive start date for this version.',
  effective_to_date       DATE COMMENT 'Exclusive end date; NULL for current.',
  is_current              BOOLEAN NOT NULL COMMENT 'Whether this is the current version.',

  created_timestamp        TIMESTAMP COMMENT 'When created (UTC).',
  source_updated_timestamp TIMESTAMP COMMENT 'When last modified (UTC).',
  record_source           STRING    COMMENT 'Originating system of record.',
  load_timestamp          TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_service_level_target PRIMARY KEY (service_level_target_sk)
)
USING DELTA
CLUSTER BY (service_level_target_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Service level targets by ABC/XYZ segment.';

ALTER TABLE ${catalog}.${sdi_schema}.service_level_target SET TAGS ('dbx_data_type' = 'reference');
ALTER TABLE ${catalog}.${sdi_schema}.service_level_target ADD CONSTRAINT chk_slt_abc CHECK (abc_class IS NULL OR abc_class IN ('A', 'B', 'C'));
ALTER TABLE ${catalog}.${sdi_schema}.service_level_target ADD CONSTRAINT chk_slt_xyz CHECK (xyz_class IS NULL OR xyz_class IN ('X', 'Y', 'Z'));
ALTER TABLE ${catalog}.${sdi_schema}.service_level_target ADD CONSTRAINT chk_slt_measure_type CHECK (service_measure_type IS NULL OR service_measure_type IN ('cycle_service_level', 'fill_rate', 'in_stock_rate'));
ALTER TABLE ${catalog}.${sdi_schema}.service_level_target ADD CONSTRAINT chk_slt_service_level_range CHECK (target_service_level_pct IS NULL OR target_service_level_pct BETWEEN 0 AND 1);
