-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- Table: competitor
-- Layer: outcome package (gold / dimensional)
-- Version: 0.5
-- Generated: 2026-06-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${bmv_schema}.competitor (
  competitor_sk         BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version.',
  competitor_id         STRING NOT NULL
                          COMMENT 'Durable natural/business key for the competitor.',

  competitor_name       STRING COMMENT 'Display name of the competitor.',
  competitor_type       STRING COMMENT 'Type of competitor. Allowed values: online, brick_and_mortar, discount, premium.',
  website_url           STRING COMMENT 'Competitor primary URL.',

  -- SCD2 versioning (principle #8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version.',

  -- Audit / provenance
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record.',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_competitor PRIMARY KEY (competitor_sk)
)
USING DELTA
CLUSTER BY (competitor_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Competitor dimension (SCD2) for the Balancing Margin and Volume outcome package.';

ALTER TABLE ${catalog}.${bmv_schema}.competitor SET TAGS ('dbx_data_type' = 'master');


-- CHECK constraints moved from the CREATE (Databricks does not support
-- inline CHECK; ADD CONSTRAINT is the supported, idempotent form).
ALTER TABLE ${catalog}.${bmv_schema}.competitor ADD CONSTRAINT chk_competitor_type CHECK (competitor_type IN ('online', 'brick_and_mortar', 'discount', 'premium'));
