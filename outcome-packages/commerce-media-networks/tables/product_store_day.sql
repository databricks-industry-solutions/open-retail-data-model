-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- Table: product_store_day
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- Append-only, one row per product × store × day: availability + POS context.
-- Conforms ISDA product_store_day. The in-stock signal feeds the
-- in-stock-weighted impression adjustment in campaign_day (grocery: don't
-- credit impressions for out-of-stock SKUs). Aggregate; not person-level.
--
-- This is now the ONLY in-store input fact CMN owns. Its former sibling — the footfall
-- aggregate store_zone_interval — moved to connected_store_signals as
-- sensor_report_interval (ADR 0033), because footfall is store-operations subject matter
-- and CMN was only ever one of its consumers. CMN still reads it, cross-package, through
-- gold/store_zone_interval.sql, whose new-row opportunity-to-see value remains NULL
-- derivation now lives. Availability and POS context stay here: they are product-scoped,
-- not sensor-scoped.
--
-- Each row is a base-grain snapshot (dbx_data_type = transactional, per §D — the
-- classification lives in the tag, not the table name).
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${cmn_schema}.product_store_day (
  product_store_day_sk  BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  product_store_day_id  STRING NOT NULL
                          COMMENT 'Durable natural/business key (grain hash).',

  product_sk            BIGINT COMMENT 'FK to product.product_sk.',
  product_id            STRING COMMENT 'Durable product business key.',
  store_sk              BIGINT COMMENT 'FK to store.store_sk.',
  store_id              STRING COMMENT 'Durable store business key.',

  business_date         DATE NOT NULL COMMENT 'Business date (cluster key).',
  in_stock_flag         BOOLEAN COMMENT 'TRUE if the product was in stock at the store that day.',
  on_hand_units         INT COMMENT 'End-of-day on-hand units.',
  pos_units             INT COMMENT 'POS units sold that day.',
  pos_net_sales_amount  DECIMAL(18,2) COMMENT 'POS net sales that day, in the reporting/base currency.',
  currency_code         STRING COMMENT 'Amount currency, ISO 4217 alpha-3 (single reporting currency).',

  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_product_store_day PRIMARY KEY (product_store_day_sk)
)
USING DELTA
CLUSTER BY (business_date, store_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Commerce Media Networks — product×store×day availability + POS aggregate.';

ALTER TABLE ${catalog}.${cmn_schema}.product_store_day SET TAGS ('dbx_data_type' = 'transactional');
