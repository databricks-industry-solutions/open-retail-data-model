-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- Table: product_relationship
-- Layer: outcome package (gold / dimensional)
-- Version: 0.5
-- Generated: 2026-06-23
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-23 by @ojasvi-goyal-03
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${bmv_schema}.product_relationship (
  product_relationship_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per relationship record.',
  product_relationship_id STRING NOT NULL
                          COMMENT 'Durable natural key (product_id|related_product_id|relationship_type).',

  product_sk            BIGINT COMMENT 'FK to canonical product.product_sk.',
  product_id            STRING NOT NULL COMMENT 'Durable business key of the primary product.',
  related_product_sk    BIGINT COMMENT 'FK to canonical product.product_sk.',
  related_product_id    STRING NOT NULL COMMENT 'Durable business key of the related product.',

  relationship_type     STRING COMMENT 'Type of relationship. Allowed values: substitute, complement.',
  affinity_coefficient  DECIMAL(5,4) COMMENT 'Strength of relationship (0.0 to 1.0). NULL if not calculated.',

  -- Audit / provenance
  record_source         STRING    COMMENT 'Originating system.',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC).',

  CONSTRAINT pk_product_relationship PRIMARY KEY (product_relationship_sk)
)
USING DELTA
CLUSTER BY (product_id, related_product_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Product substitution and complement relationships mapping table for cross-elasticity optimization.';

ALTER TABLE ${catalog}.${bmv_schema}.product_relationship SET TAGS ('dbx_data_type' = 'association');

-- CHECK constraints moved from the CREATE (Databricks does not support
-- inline CHECK; ADD CONSTRAINT is the supported, idempotent form).
ALTER TABLE ${catalog}.${bmv_schema}.product_relationship ADD CONSTRAINT chk_product_relationship_type CHECK (relationship_type IN ('substitute', 'complement'));
ALTER TABLE ${catalog}.${bmv_schema}.product_relationship ADD CONSTRAINT chk_product_relationship_affinity CHECK (affinity_coefficient >= 0.0 AND affinity_coefficient <= 1.0);
