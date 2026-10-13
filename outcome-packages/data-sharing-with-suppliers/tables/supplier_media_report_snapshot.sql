-- ============================================================
-- ORDM · Outcome Package · Data Sharing with Suppliers
-- Table: supplier_media_report_snapshot
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- Append-only, IMMUTABLE published supplier media report — one row per
-- publish snapshot × advertiser × campaign × report level. Freezes the
-- numbers disclosed to a supplier at a point in time (for audit / dispute /
-- reconciliation), so a later restatement of the live aggregates does not
-- change what was already shared. Sourced from the Commerce Media Networks
-- campaign_day; supplier-safe (no person-level data), threshold-suppressed.
-- Conforms media-measurement's mart_supplier_report_snapshot.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${dss_schema}.supplier_media_report_snapshot (
  supplier_media_report_snapshot_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  supplier_media_report_snapshot_id STRING NOT NULL
                          COMMENT 'Durable natural/business key (grain hash incl. report_version).',

  advertiser_sk     BIGINT COMMENT 'FK to cmn.advertiser.advertiser_sk.',
  advertiser_id     STRING COMMENT 'Durable advertiser business key.',
  campaign_sk           BIGINT COMMENT 'FK to cmn.campaign.campaign_sk (or NULL for brand-level).',
  campaign_id           STRING COMMENT 'Durable campaign business key; NULL for brand-level.',

  report_level          STRING COMMENT 'Aggregation level of the report row. Allowed values: brand, campaign, product.',
  report_period_start   DATE COMMENT 'Reporting period start, inclusive (ISO 8601).',
  report_period_end     DATE COMMENT 'Reporting period end, inclusive (ISO 8601).',
  snapshot_ts           TIMESTAMP NOT NULL COMMENT 'When this report was published/frozen (UTC, ISO 8601).',
  snapshot_date         DATE NOT NULL COMMENT 'Publish date (cluster key).',
  report_version        INT COMMENT 'Monotonic publish version for this scope/period (immutable per version).',

  impressions           BIGINT COMMENT 'Impressions disclosed.',
  viewable_impressions  BIGINT COMMENT 'Viewable impressions disclosed.',
  clicks                BIGINT COMMENT 'Clicks disclosed.',
  conversions           BIGINT COMMENT 'Attributed conversions disclosed.',
  units                 BIGINT COMMENT 'Attributed units disclosed.',
  media_spend_net       DECIMAL(18,2) COMMENT 'Net media spend disclosed, reporting/base currency.',
  attributed_net_sales  DECIMAL(18,2) COMMENT 'Attributed net sales disclosed, reporting/base currency.',
  new_to_brand_sales    DECIMAL(18,2) COMMENT 'New-to-brand sales disclosed, reporting/base currency.',
  incremental_sales     DECIMAL(18,2) COMMENT 'Incremental sales disclosed, reporting/base currency.',
  roas_net              DECIMAL(12,4) COMMENT 'Return on ad spend at publish time.',
  iroas_value           DECIMAL(12,4) COMMENT 'Incremental ROAS at publish time.',
  currency_code         STRING COMMENT 'Amount currency, ISO 4217 alpha-3 (single reporting currency).',
  threshold_suppressed_flag BOOLEAN COMMENT 'TRUE if any measure was threshold-suppressed before disclosure.',

  -- Audit / provenance (append-only fact block; all timestamps UTC)
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_supplier_media_report_snapshot PRIMARY KEY (supplier_media_report_snapshot_sk)
)
USING DELTA
CLUSTER BY (snapshot_date, advertiser_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Data Sharing with Suppliers — immutable published supplier media report snapshot (append-only).';

ALTER TABLE ${catalog}.${dss_schema}.supplier_media_report_snapshot SET TAGS ('dbx_data_type' = 'transactional');
