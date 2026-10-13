-- ============================================================
-- ORDM · Outcome Package · Promote with Purpose
-- Table: promotion_scope
-- Layer: outcome package (gold / bridge fact)
-- Version: 0.5
-- Generated: 2026-06-09
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-09
-- ============================================================
-- The product x store coverage of each promotion: one row per
-- (promotion, product, store) that the promotion applied to. Current-state
-- bridge (no SCD2). Surrogate FKs (promo_sk, product_sk, store_sk) are the
-- version-specific references; durable business keys are retained.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${promo_schema}.promotion_scope (
  scope_sk              BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  scope_id              STRING NOT NULL
                          COMMENT 'Durable natural/business key for the scope row.',

  promo_sk              BIGINT COMMENT 'FK to promotion.promo_sk.',
  promo_id              STRING NOT NULL COMMENT 'Durable promotion business key.',
  product_sk            BIGINT COMMENT 'FK to product.product_sk.',
  product_id            STRING NOT NULL COMMENT 'Durable product business key.',
  store_sk              BIGINT COMMENT 'FK to store.store_sk.',
  store_id              STRING NOT NULL COMMENT 'Durable store business key.',

  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'Timestamp this row was loaded into the canonical core (UTC, ISO 8601).',

  CONSTRAINT pk_promotion_scope PRIMARY KEY (scope_sk)
)
USING DELTA
CLUSTER BY (promo_sk, product_sk, store_sk)
-- Deletion vectors speed row-level MERGE/UPDATE (SCD2 version closes, corrections).
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Promotion product x store coverage bridge for the Promote with Purpose outcome package.';

-- Table classification (machine-checkable layer/role): TAGS-DATA-TYPE
ALTER TABLE ${catalog}.${promo_schema}.promotion_scope SET TAGS ('dbx_data_type' = 'association');
