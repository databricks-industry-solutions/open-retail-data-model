-- ============================================================
-- ORDM · Outcome Package · Data Sharing with Suppliers
-- Table: data_product_subscription
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-08-03
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-03
-- ============================================================
-- The LICENCE: which governance principal (a UC group / account / service principal —
-- NOT a customer) has licensed which data product, on what commercial terms, for which
-- supplier scope. This is both the entitlement anchor and the contract record for DATA
-- MONETIZATION, playing the same role demand_collaboration plays for Joint Demand
-- Planning: a deploy-time row filter uses principal_id to serve each partner only their
-- own revenue and usage rows.
--
-- Scope: supplier_sk NULL means the licence spans EVERY supplier the product covers;
-- a non-NULL supplier_sk narrows it to one. gold_data_product_revenue resolves a
-- principal holding BOTH by ranking the supplier-scoped grant ahead of the
-- all-supplier one, so the row is emitted once at the more specific terms.
--
-- contracted_price_amount is the NEGOTIATED rate, which may differ from the product's
-- published data_product.list_price_amount; the gap is the discount. contracted_units
-- is the committed allowance the metered usage in data_share_consumption is compared
-- against, so an unused or over-run licence is detectable.
--
-- SCD2 so the commercial history is auditable — a renewal or re-price opens a new
-- version rather than rewriting what was already invoiced. Supplier-safe (no
-- person-level data).
--
-- Grain: one version per (principal, data product, supplier scope) (SCD2).
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${dss_schema}.data_product_subscription (
  data_product_subscription_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version.',
  data_product_subscription_id STRING NOT NULL
                          COMMENT 'Durable natural/business key for the subscription grant.',

  principal_id          STRING NOT NULL COMMENT 'Governance principal holding the licence (UC group / account / service principal; not a customer identity).',
  principal_type        STRING COMMENT 'Kind of principal. Allowed values: group, account, service_principal.',

  data_product_sk       BIGINT COMMENT 'FK to data_product.data_product_sk (the licensed product version).',
  data_product_id       STRING COMMENT 'Durable data-product business key.',

  supplier_sk           BIGINT COMMENT 'FK to supplier.supplier_sk when the licence is scoped to one supplier (NULL = every supplier the product covers).',
  supplier_id           STRING COMMENT 'Durable supplier business key; NULL for an all-supplier licence.',
  advertiser_sk         BIGINT COMMENT 'FK to commerce-media-networks advertiser.advertiser_sk when the licence is tied to one advertiser (brand) role of the supplier; NULL otherwise. Lets the revenue view align data revenue with that advertiser retail-media spend.',
  advertiser_id         STRING COMMENT 'Durable advertiser business key; NULL when the licence is not advertiser-scoped.',

  -- Commercial terms (negotiated; compare against data_product.list_price_amount)
  contracted_price_amount DECIMAL(18,2) COMMENT 'Negotiated price per billing period (or per consumption_unit, per the product pricing_model), reporting/base currency. May differ from data_product.list_price_amount; the gap is the discount.',
  contracted_units      BIGINT COMMENT 'Committed consumption allowance per billing period, in the product consumption_unit. Metered usage is compared against this to detect an unused or over-run licence. NULL = uncapped.',
  billing_frequency     STRING COMMENT 'How often the subscription bills. Allowed values: monthly, quarterly, annual.',
  currency_code         STRING COMMENT 'Amount currency, ISO 4217 alpha-3 (single reporting currency).',

  term_start_date       DATE COMMENT 'Contractual term start (business date, distinct from the SCD2 version window).',
  term_end_date         DATE COMMENT 'Contractual term end; NULL for an evergreen/auto-renewing term.',
  min_disclosure_threshold INT COMMENT 'Minimum aggregation volume a row must reach before it is disclosable to this principal — a low-volume/materiality floor, NOT a k-anonymity control (the shared rows are already aggregate and carry no underlying entity count). Overrides the product default. NULL means NO floor (every entitled row is disclosed regardless of volume).',
  subscription_status   STRING COMMENT 'Licence lifecycle. Allowed values: pending, active, suspended, cancelled, expired.',
  subscribed_ts         TIMESTAMP NOT NULL COMMENT 'When this version of the licence was agreed (UTC, ISO 8601). NOT NULL: it is the primary latest-wins ordering key in gold_data_product_revenue, so a NULL would sort a genuine latest version last and silently serve stale commercial terms.',

  -- SCD2 versioning (principle #8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version.',

  -- Audit / provenance (all timestamps UTC)
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_data_product_subscription PRIMARY KEY (data_product_subscription_sk)
)
USING DELTA
CLUSTER BY (data_product_id, principal_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Data Sharing with Suppliers — data-product subscription licence (row-level access + commercial terms, SCD2).';

ALTER TABLE ${catalog}.${dss_schema}.data_product_subscription SET TAGS ('dbx_data_type' = 'association');
