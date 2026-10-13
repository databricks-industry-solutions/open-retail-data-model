-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- Table: experiment_cell
-- Layer: outcome package (gold dimension)
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- A CELL (arm) of an incrementality experiment (SCD2): treatment / control /
-- holdout, with its traffic allocation. Conforms the incrementality-testing
-- brief's dim_experiment_cell. Assignment of units to cells, and the measured
-- outcomes, are outcome-package facts that reference this dimension.
--
-- Grain: one current version per experiment cell. FKs into cmn.experiment.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${cmn_schema}.experiment_cell (
  experiment_cell_sk    BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version; the join/FK target.',
  experiment_cell_id    STRING NOT NULL
                          COMMENT 'Durable natural/business key for the experiment cell.',

  -- Parent experiment (cmn.experiment)
  experiment_sk         BIGINT COMMENT 'FK to experiment.experiment_sk (the experiment this cell belongs to).',
  experiment_id         STRING COMMENT 'Durable business key of the parent experiment (join on current experiment version).',

  cell_name             STRING COMMENT 'Human-readable cell name.',
  cell_role             STRING COMMENT 'Role of the cell in the design. Allowed values: treatment, control, holdout.',
  traffic_allocation_pct DECIMAL(5,2) COMMENT 'Share of assignment units allocated to this cell (0-100).',
  is_control            BOOLEAN COMMENT 'TRUE if this is the control/counterfactual cell.',

  -- SCD2 versioning (principle #8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version of this cell.',

  -- Audit / provenance (standard block; all timestamps UTC)
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_experiment_cell PRIMARY KEY (experiment_cell_sk)
)
USING DELTA
CLUSTER BY (experiment_cell_id)
-- Deletion vectors speed row-level MERGE/UPDATE (SCD2 version closes, corrections).
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'ORDM Commerce Media Networks incrementality experiment cell dimension (SCD2).';

-- Table classification (machine-checkable layer/role): TAGS-DATA-TYPE
ALTER TABLE ${catalog}.${cmn_schema}.experiment_cell SET TAGS ('dbx_data_type' = 'master');
