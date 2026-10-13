-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- Table: advertiser
-- Layer: outcome package (gold dimension)
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-14
-- ============================================================
-- The retail-media ADVERTISER dimension: a THIN gold dimension that reuses the
-- silver `supplier` in an advertiser role. This is NOT a new party master — it
-- FKs into the canonical-core supplier; the "advertiser" seen in the retail-media
-- briefs (ISDA advertiser_id, SP brand_id, CPRM/MM dim_advertiser) is the
-- buying-side view of that same supplier, conformed with the brand, agency, and
-- finance/billing attributes retail-media reporting needs. One SCD2 version per
-- advertiser relationship.
--
-- Grain: one current version per advertiser relationship. FKs into the silver
-- `${supplier_schema}.supplier`. Referenced by cmn.campaign and the CMN facts as
-- the billing/entitlement anchor; the data-sharing-with-suppliers package (the
-- publish side of this one outcome) consumes it too.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${cmn_schema}.advertiser (
  advertiser_sk         BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version; the join/FK target.',
  advertiser_id         STRING NOT NULL
                          COMMENT 'Durable natural/business key for the advertiser relationship.',

  -- Owning supplier (silver canonical-core supplier domain — the advertiser IS a supplier in an ad role)
  supplier_sk           BIGINT COMMENT 'FK to supplier.supplier_sk (the supplier version this advertiser is).',
  supplier_id           STRING NOT NULL
                          COMMENT 'Durable business key of the owning supplier (join on current supplier version).',

  brand_name            STRING COMMENT 'Brand marketed by the supplier (the advertised brand). One brand per advertiser row (thin-dimension intent, ADR 0021); a supplier advertising multiple brands has multiple advertiser rows.',
  agency_name           STRING COMMENT 'Media agency acting for the advertiser, if any.',
  finance_account_code  STRING COMMENT 'Billing/finance-system account code for this advertiser (external natural code; the billing anchor). Not a modeled entity.',
  billing_currency_code STRING COMMENT 'Currency the advertiser is billed in, ISO 4217 alpha-3.',
  relationship_type     STRING COMMENT 'How the advertiser transacts with the retail-media network. Allowed values: direct, agency, reseller.',
  advertiser_status     STRING COMMENT 'Lifecycle status of the advertiser relationship. Allowed values: active, inactive.',

  -- SCD2 versioning (principle #8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version of this advertiser.',

  -- Audit / provenance (standard block; all timestamps UTC)
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_advertiser PRIMARY KEY (advertiser_sk)
)
USING DELTA
CLUSTER BY (advertiser_id)
-- Deletion vectors speed row-level MERGE/UPDATE (SCD2 version closes, corrections).
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'ORDM Commerce Media Networks retail-media advertiser dimension (thin gold; SCD2). Reuses silver supplier in an advertiser role.';

-- Table classification (machine-checkable layer/role): TAGS-DATA-TYPE
ALTER TABLE ${catalog}.${cmn_schema}.advertiser SET TAGS ('dbx_data_type' = 'master');
