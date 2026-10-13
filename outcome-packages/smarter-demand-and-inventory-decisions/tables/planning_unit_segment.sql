-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- Table: planning_unit_segment
-- Layer: outcome package (extension table / reference)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- ABC/XYZ segmentation and cluster assignment per planning unit per fiscal period.
-- ============================================================


CREATE TABLE IF NOT EXISTS ${catalog}.${sdi_schema}.planning_unit_segment (
  segment_sk              BIGINT GENERATED ALWAYS AS IDENTITY
                            COMMENT 'Surrogate key.',
  segment_id              STRING NOT NULL
                            COMMENT 'Durable business key (planning_unit|fiscal_period).',

  planning_unit_sk        BIGINT NOT NULL COMMENT 'FK to planning_unit.planning_unit_sk.',
  planning_unit_id        STRING NOT NULL COMMENT 'Durable planning unit business key.',
  fiscal_period_key       INT NOT NULL COMMENT 'Fiscal period key = fiscal_calendar.fiscal_week_id (e.g. 202628 for fiscal year 2026 week 28).',

  abc_class               STRING NOT NULL COMMENT 'Volume tier. Allowed values: A, B, C.',
  xyz_class               STRING NOT NULL COMMENT 'Demand variability. Allowed values: X, Y, Z.',
  volume_tier             STRING COMMENT 'Volume tier label (e.g. very_high, intermittent, obsolete).',
  cluster_id              STRING COMMENT 'Model recipe selector cluster identifier.',
  cumulative_volume_pct   DOUBLE COMMENT 'Cumulative volume percentage for ABC audit.',
  coefficient_of_variation DOUBLE COMMENT 'Coefficient of variation for XYZ audit.',

  -- Audit / provenance (reference table block; standard §8)
  created_timestamp        TIMESTAMP COMMENT 'When the record was created (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified (UTC, ISO 8601).',
  record_source           STRING    COMMENT 'Originating system of record.',
  load_timestamp          TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_planning_unit_segment PRIMARY KEY (segment_sk)
)
USING DELTA
CLUSTER BY (fiscal_period_key, planning_unit_sk)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'ABC/XYZ segmentation per planning unit per fiscal period.';

ALTER TABLE ${catalog}.${sdi_schema}.planning_unit_segment SET TAGS ('dbx_data_type' = 'reference');
ALTER TABLE ${catalog}.${sdi_schema}.planning_unit_segment ADD CONSTRAINT chk_pus_abc CHECK (abc_class IN ('A', 'B', 'C'));
ALTER TABLE ${catalog}.${sdi_schema}.planning_unit_segment ADD CONSTRAINT chk_pus_xyz CHECK (xyz_class IN ('X', 'Y', 'Z'));
