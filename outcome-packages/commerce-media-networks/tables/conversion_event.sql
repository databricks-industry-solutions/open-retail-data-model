-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- Table: conversion_event
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- Append-only, one row per qualifying commerce/conversion event (purchase
-- order-line, add-to-cart, PDP view, store visit, signup). This is the PAID-ATTRIBUTION
-- MEASUREMENT PROJECTION of the conversion-relevant subset — the clean-room-keyed
-- (customer_key_hash), experiment-cell-scoped, money/order-line-enriched view CMN needs as
-- the CVR denominator and attributed_outcome's FK target. It is NOT the source of truth for
-- the raw OCCURRENCE of a behavioral touch: that is the conformed canonical-core
-- interaction.touchpoint fact (ADR 0029). The overlapping mid-funnel rows (pdp_view/
-- add_to_cart) and the offline store_visit are the paid-context projection of a touchpoint
-- occurrence; a nullable touchpoint_id lineage reference + a reconciliation DQ check are a
-- deferred CMN follow-on (today the generator emits only purchase conversions, so there is
-- no browse-row duplication yet). Kept distinct from attributed_outcome because attribution
-- is many-to-one (one conversion credited across methods/windows/experiments) and CVR /
-- new-to-brand baselines need the un-attributed denominator. Person-level and privacy-tiered
-- (hashed keys + consent). Nullable experiment_sk/experiment_cell_sk fold incrementality on.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${cmn_schema}.conversion_event (
  conversion_event_sk   BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  conversion_event_id   STRING NOT NULL
                          COMMENT 'Durable natural/business key for the conversion event.',

  -- Retail dimensions (canonical core) + order linkage
  profile_sk            BIGINT COMMENT 'FK to customer.profile.profile_sk (the converting customer), if known.',
  profile_id            STRING COMMENT 'Durable customer business key (pseudonymous).',
  product_sk            BIGINT COMMENT 'FK to product.product_sk.',
  product_id            STRING COMMENT 'Durable product business key.',
  store_sk              BIGINT COMMENT 'FK to store.store_sk (fulfilling/visited store), if applicable.',
  store_id              STRING COMMENT 'Durable store business key.',
  order_line_sk         BIGINT COMMENT 'FK to order.customer_order_line.order_line_sk for purchase conversions.',
  order_line_id         STRING COMMENT 'Durable order-line business key.',
  order_id              STRING COMMENT 'Durable order business key.',
  -- Concurrent trade promotion (conformed; ADR 0006) — lets measurement control
  -- for a price/promotion active on the same product/store/date as the conversion.
  promo_sk              BIGINT COMMENT 'FK to marketing.promotion.promo_sk (promotion active for this conversion), if any.',
  promo_id              STRING COMMENT 'Durable promotion business key (NO_PROMO when none).',

  -- Incrementality (nullable)
  experiment_sk         BIGINT COMMENT 'FK to cmn.experiment.experiment_sk if under an experiment.',
  experiment_id         STRING COMMENT 'Durable experiment business key.',
  experiment_cell_sk    BIGINT COMMENT 'FK to cmn.experiment_cell.experiment_cell_sk (treatment/control), if assigned.',
  experiment_cell_id    STRING COMMENT 'Durable experiment cell business key.',

  conversion_type       STRING NOT NULL COMMENT 'Kind of conversion. Allowed values: purchase, add_to_cart, pdp_view, store_visit, signup.',
  outcome_ts            TIMESTAMP NOT NULL COMMENT 'When the conversion occurred (UTC, ISO 8601).',
  outcome_date          DATE NOT NULL COMMENT 'Business date of the conversion (cluster key).',
  gross_sales_amount    DECIMAL(18,2) COMMENT 'Gross sales value, in the reporting/base currency (purchase conversions).',
  net_sales_amount      DECIMAL(18,2) COMMENT 'Net sales value, in the reporting/base currency.',
  margin_amount         DECIMAL(18,2) COMMENT 'Gross margin, in the reporting/base currency.',
  currency_code         STRING COMMENT 'Amount currency, ISO 4217 alpha-3 (single reporting currency).',
  units                 INT COMMENT 'Units for purchase conversions.',

  -- Person-level identifiers (pseudonymized / PII) + consent
  customer_key_hash     STRING COMMENT 'Hashed/tokenized customer identifier (PII, never raw).',
  consent_status        STRING COMMENT 'Consent state for measurement. Allowed values: granted, denied, unknown.',

  -- Audit / provenance (append-only fact block; all timestamps UTC)
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_conversion_event PRIMARY KEY (conversion_event_sk)
)
USING DELTA
CLUSTER BY (product_id, outcome_date)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Commerce Media Networks — paid-attribution measurement projection of the conversion-relevant subset (append-only); the CVR denominator + attributed_outcome FK target. Raw touch occurrence lives in canonical-core interaction.touchpoint (ADR 0029).';

ALTER TABLE ${catalog}.${cmn_schema}.conversion_event SET TAGS ('dbx_data_type' = 'transactional');

ALTER TABLE ${catalog}.${cmn_schema}.conversion_event ALTER COLUMN customer_key_hash SET TAGS ('dbx_pii_identifier' = 'true');
