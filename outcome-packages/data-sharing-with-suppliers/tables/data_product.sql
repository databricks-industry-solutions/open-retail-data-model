-- ============================================================
-- ORDM · Outcome Package · Data Sharing with Suppliers
-- Table: data_product
-- Layer: outcome package (extension table / reference)
-- Version: 0.5
-- Generated: 2026-08-03
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-03
-- ============================================================
-- The CATALOG of monetizable data products a retailer offers its suppliers — the
-- named, priced things a partner can license (a measured media report, a joint
-- demand-plan feed, a category benchmark, an audience insight). This is the supply
-- side of DATA MONETIZATION: it says what exists and what it lists for, while
-- data_product_subscription says who licensed it and data_share_consumption meters
-- what they actually used.
--
-- list_price_amount is the PUBLISHED rate card, deliberately separate from the
-- CONTRACTED price negotiated per subscription (data_product_subscription
-- .contracted_price_amount) — the gap between them is the discount, and keeping both
-- lets revenue be reported at either. SCD2 so a re-pricing never rewrites the rate a
-- historical subscription was sold at.
--
-- Vendor-neutral and supplier-safe: a data product is described by what it measures,
-- never by a person (no person-level data anywhere in this use case).
--
-- Grain: one version per data product (SCD2; one current row per data_product_id).
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${dss_schema}.data_product (
  data_product_sk       BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version.',
  data_product_id       STRING NOT NULL
                          COMMENT 'Durable natural/business key for the data product.',

  data_product_name     STRING COMMENT 'Display name of the licensable data product.',
  data_product_category STRING COMMENT 'What kind of data product this is. Allowed values: media_measurement, demand_collaboration, category_benchmark, audience_insight.',
  delivery_mode         STRING COMMENT 'How the licensed data reaches the partner. Allowed values: share, api, file_export, dashboard.',

  -- Rate card (published list price). The negotiated per-subscription rate lives on
  -- data_product_subscription.contracted_price_amount; the difference is the discount.
  pricing_model         STRING COMMENT 'How the product is charged. Allowed values: subscription_flat, per_consumption_unit, tiered, revenue_share. SCOPE NOTE: revenue_share is declarable in the catalog but has no modeled revenue path in this use case — its earnings depend on downstream sales made BY the licensed partner, which this model does not observe, so no data_share_consumption row can compute a billable_amount for it. Such a product would report consumption with NULL revenue until a share-settlement input is modeled (deferred, with invoicing).',
  consumption_unit      STRING COMMENT 'Unit metered for usage-based pricing. Allowed values: query, row_scanned, report_delivery, api_call.',
  list_price_amount     DECIMAL(18,2) COMMENT 'Published list price per billing period (subscription_flat/tiered) or per consumption_unit (per_consumption_unit), reporting/base currency. NULL for revenue_share, which carries no fixed rate.',
  currency_code         STRING COMMENT 'Amount currency, ISO 4217 alpha-3 (single reporting currency).',

  min_disclosure_threshold INT COMMENT 'Default minimum aggregation volume a row of this product must reach before it is disclosable — a low-volume/materiality floor, NOT a k-anonymity control. Overridden per grant by data_product_subscription.min_disclosure_threshold; NULL means NO default floor.',
  data_product_status   STRING COMMENT 'Catalog lifecycle. Allowed values: draft, published, deprecated, retired.',

  -- SCD2 versioning (principle #8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version.',

  -- Audit / provenance (all timestamps UTC)
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_data_product PRIMARY KEY (data_product_sk)
)
USING DELTA
CLUSTER BY (data_product_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Data Sharing with Suppliers — catalog of monetizable data products offered to suppliers (rate card, SCD2).';

ALTER TABLE ${catalog}.${dss_schema}.data_product SET TAGS ('dbx_data_type' = 'reference');
