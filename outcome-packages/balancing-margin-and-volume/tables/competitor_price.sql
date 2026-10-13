-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- Table: competitor_price
-- Layer: outcome package (gold / dimensional fact)
-- Version: 0.5
-- Generated: 2026-06-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${bmv_schema}.competitor_price (
  competitor_price_sk   BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key for the price observation.',
  competitor_price_id   STRING NOT NULL
                          COMMENT 'Durable natural key (competitor_id|product_id|date_key).',

  competitor_sk         BIGINT COMMENT 'FK to competitor.competitor_sk.',
  competitor_id         STRING NOT NULL COMMENT 'Durable competitor business key.',
  product_sk            BIGINT COMMENT 'FK to canonical product.product_sk (mapped).',
  product_id            STRING NOT NULL COMMENT 'Durable product business key (mapped to our catalog).',

  date_key              DATE NOT NULL
                          COMMENT 'Date of the price observation. FK to fiscal_calendar.date_key.',

  competitor_price      DECIMAL(18,4) COMMENT 'Observed unit price, in base currency.',
  competitor_mrp        DECIMAL(18,4) COMMENT 'Observed Maximum Retail Price (MRP).',
  currency_code         STRING NOT NULL COMMENT 'Reporting/base currency, ISO 4217 alpha-3.',
  is_on_comp_promo      BOOLEAN       COMMENT 'True if the competitor was running a promotion.',
  is_out_of_stock       BOOLEAN       COMMENT 'True if the competitor was out of stock.',
  data_source           STRING        COMMENT 'Source of the observation data.',

  -- Audit / provenance
  record_source         STRING    COMMENT 'Originating system (e.g. scraping vendor).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC).',

  CONSTRAINT pk_competitor_price PRIMARY KEY (competitor_price_sk)
)
USING DELTA
CLUSTER BY (product_sk, competitor_sk, date_key)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Competitor price observations fact table for elasticity modeling.';

ALTER TABLE ${catalog}.${bmv_schema}.competitor_price SET TAGS ('dbx_data_type' = 'transactional');
