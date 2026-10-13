-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- Table: planogram
-- Layer: outcome package (master)
-- Version: 0.5
-- Generated: 2026-06-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================
-- Planogram and space allocation dimension.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${bmv_schema}.planogram (
  planogram_sk BIGINT GENERATED ALWAYS AS IDENTITY
               COMMENT 'Surrogate key for the planogram observation.',
  planogram_id STRING NOT NULL
               COMMENT 'Durable natural key (store_id|product_id).',

  store_sk BIGINT COMMENT 'FK to canonical store.store_sk.',
  store_id STRING NOT NULL COMMENT 'Store business key.',
  product_sk BIGINT COMMENT 'FK to canonical product.product_sk.',
  product_id STRING NOT NULL COMMENT 'Product business key.',

  space_planning_category STRING COMMENT 'Merchandising category for the planogram allocation.',
  allocated_facings INT COMMENT 'Number of facings allocated',
  allocated_sqft DECIMAL(10,2) COMMENT 'Square footage allocated',
  
  -- SCD2 versioning (principle #8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version.',

  -- Audit / provenance
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record.',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',
  
  CONSTRAINT pk_planogram PRIMARY KEY (planogram_sk)
)
USING DELTA
CLUSTER BY (store_sk, product_sk)
COMMENT 'Planogram and space allocation dimension.';

ALTER TABLE ${catalog}.${bmv_schema}.planogram SET TAGS ('dbx_data_type' = 'master');
