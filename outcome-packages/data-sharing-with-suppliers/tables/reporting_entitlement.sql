-- ============================================================
-- ORDM · Outcome Package · Data Sharing with Suppliers
-- Table: reporting_entitlement
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- Row-level entitlement anchor for supplier-facing media/measurement sharing:
-- which principal (a UC group / account / service principal — NOT a customer)
-- may see which advertiser (advertiser), optionally scoped to one campaign,
-- and the minimum aggregation threshold that must be met before disclosure.
-- SCD2 so entitlement history is auditable. A deploy-time row filter uses this
-- to serve each supplier only their entitled rows of the shared report.
--
-- Grain: one current version per (principal, advertiser, campaign-scope).
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${dss_schema}.reporting_entitlement (
  reporting_entitlement_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version.',
  reporting_entitlement_id STRING NOT NULL
                          COMMENT 'Durable natural/business key for the entitlement.',

  principal_id          STRING NOT NULL COMMENT 'Governance principal granted access (UC group / account / service principal; not a customer identity).',
  principal_type        STRING COMMENT 'Kind of principal. Allowed values: group, account, service_principal.',

  advertiser_sk     BIGINT COMMENT 'FK to cmn.advertiser.advertiser_sk (the advertiser the principal may see).',
  advertiser_id     STRING COMMENT 'Durable advertiser business key.',
  campaign_sk           BIGINT COMMENT 'FK to cmn.campaign.campaign_sk when scoped to one campaign (NULL = all campaigns of the brand).',
  campaign_id           STRING COMMENT 'Durable campaign business key; NULL for brand-wide entitlement.',

  min_disclosure_threshold INT COMMENT 'Minimum aggregation count required before a row is disclosable to this principal.',
  entitlement_status    STRING COMMENT 'Lifecycle. Allowed values: active, suspended, revoked.',

  -- SCD2 versioning (principle #8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version.',

  -- Audit / provenance (all timestamps UTC)
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_reporting_entitlement PRIMARY KEY (reporting_entitlement_sk)
)
USING DELTA
CLUSTER BY (advertiser_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Data Sharing with Suppliers — supplier reporting entitlement (row-level access anchor, SCD2).';

ALTER TABLE ${catalog}.${dss_schema}.reporting_entitlement SET TAGS ('dbx_data_type' = 'association');
