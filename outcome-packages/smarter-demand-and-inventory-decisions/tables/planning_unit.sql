-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- Table: planning_unit
-- Layer: outcome package (extension table / reference)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Atomic forecasting entity at a configurable planning grain (store-SKU or rolled-up IBP).
-- ============================================================


CREATE TABLE IF NOT EXISTS ${catalog}.${sdi_schema}.planning_unit (
  planning_unit_sk        BIGINT GENERATED ALWAYS AS IDENTITY
                            COMMENT 'Surrogate key.',
  planning_unit_id        STRING NOT NULL
                            COMMENT 'Durable business key for the planning unit.',

  grain_type              STRING NOT NULL
                            COMMENT 'Planning grain. Allowed values: store_sku, account_product_region, dc_product.',
  product_sk              BIGINT COMMENT 'FK to product.product_sk (version-specific). Nullable when grain is above SKU.',
  product_id              STRING COMMENT 'Durable product business key.',
  store_sk                BIGINT COMMENT 'FK to store.store_sk (version-specific). Nullable when grain is above store.',
  store_id                STRING COMMENT 'Durable store business key.',
  account_sk              BIGINT COMMENT 'FK to account.account_sk (version-specific). Optional B2B key account.',
  account_id              STRING COMMENT 'Durable account business key.',
  planning_hierarchy_level STRING COMMENT 'Forecast hierarchy level (e.g. H1, H2, H3, H4, store_sku).',
  is_active               BOOLEAN NOT NULL COMMENT 'Whether this planning unit is currently active.',

  -- Audit / provenance (reference table block; standard §8)
  created_timestamp        TIMESTAMP COMMENT 'When the record was created (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified (UTC, ISO 8601).',
  record_source           STRING    COMMENT 'Originating system of record.',
  load_timestamp          TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_planning_unit PRIMARY KEY (planning_unit_sk)
)
USING DELTA
CLUSTER BY (planning_unit_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Reference table defining atomic demand-planning entities.';

ALTER TABLE ${catalog}.${sdi_schema}.planning_unit SET TAGS ('dbx_data_type' = 'reference');
ALTER TABLE ${catalog}.${sdi_schema}.planning_unit ADD CONSTRAINT chk_pu_grain_type CHECK (grain_type IN ('store_sku', 'account_product_region', 'dc_product'));
-- At store_sku grain the product and store business keys are mandatory (they are
-- legitimately nullable only for grains that roll up above SKU / store).
ALTER TABLE ${catalog}.${sdi_schema}.planning_unit ADD CONSTRAINT chk_pu_store_sku_keys CHECK (grain_type <> 'store_sku' OR (product_id IS NOT NULL AND store_id IS NOT NULL));
