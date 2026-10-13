-- ============================================================
-- ORDM · Outcome Package · Actionable Customer Understanding
-- Table: competitor_product_match
-- Layer: outcome package (Type-1 association)
-- Version: 0.5
-- Generated: 2026-08-24
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-24 by @saurabhshukla-db
-- License: see repository LICENSE.md
-- ============================================================
-- Grain: competitor × competitor_item_ref. The durable association identity excludes
-- product_id so a corrected own-product match updates this Type-1 row without re-keying.
-- Observation facts preserve the earlier match snapshot independently.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${acu_schema}.competitor_product_match (
  competitor_product_match_sk BIGINT GENERATED ALWAYS AS IDENTITY
                                COMMENT 'Surrogate key for the current Type-1 association.',
  competitor_product_match_id STRING NOT NULL
                                COMMENT 'Durable association key: competitor_id|competitor_item_ref; excludes the mutable own-product match.',

  competitor_sk                BIGINT NOT NULL COMMENT 'Current competitor SCD2 version retained as lineage, not a cross-package FK.',
  competitor_id                STRING NOT NULL COMMENT 'Durable competitor business key and logical relationship to the BMV-owned competitor dimension.',
  competitor_item_ref          STRING NOT NULL COMMENT 'Stable item reference in the competitor/source namespace.',
  product_sk                   BIGINT NOT NULL COMMENT 'FK to the currently matched own-product SCD2 version.',
  product_id                   STRING NOT NULL COMMENT 'Current durable own-product match; mutable under the Type-1 contract.',
  match_type                   STRING NOT NULL COMMENT 'Relationship semantics: exact, equivalent, or similar.',
  match_method                 STRING NOT NULL COMMENT 'Resolution method: gtin, mpn_brand, ai_text, ai_image, or manual.',
  match_confidence             DECIMAL(5,4) NOT NULL COMMENT 'Current match confidence from 0 through 1; serving KPIs default to a 0.80 floor.',
  first_matched_date           DATE NOT NULL COMMENT 'Date this competitor-item association was first established.',
  last_verified_date           DATE NOT NULL COMMENT 'Date the current Type-1 association was last verified.',
  is_active                    BOOLEAN NOT NULL COMMENT 'TRUE when the current association is approved for use.',

  created_timestamp            TIMESTAMP COMMENT 'Timestamp the association was first created in the source system.',
  source_updated_timestamp     TIMESTAMP COMMENT 'Timestamp the current Type-1 association was last updated in the source system.',
  record_source                STRING NOT NULL COMMENT 'Originating product-matching system.',
  load_timestamp               TIMESTAMP NOT NULL COMMENT 'Timestamp the current association was loaded into the lakehouse.',

  CONSTRAINT pk_competitor_product_match PRIMARY KEY (competitor_product_match_sk)
)
USING DELTA
CLUSTER BY (competitor_sk, competitor_item_ref)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Current Type-1 competitor-item to own-product association with auditable method and confidence.';

ALTER TABLE ${catalog}.${acu_schema}.competitor_product_match
  SET TAGS ('dbx_data_type' = 'association');
