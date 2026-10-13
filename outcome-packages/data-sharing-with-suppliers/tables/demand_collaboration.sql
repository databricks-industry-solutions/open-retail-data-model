-- ============================================================
-- ORDM · Outcome Package · Data Sharing with Suppliers
-- Table: demand_collaboration
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-08-01
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-01
-- ============================================================
-- Row-level entitlement + scope anchor for CPFR-style JOINT DEMAND PLANNING:
-- which governance principal (a UC group / account / service principal — NOT a
-- customer) collaborates on which supplier's demand plan, optionally scoped to one
-- product (NULL = the supplier's whole assortment), the agreed planning horizon,
-- and the minimum aggregation threshold that must be met before a plan row is
-- disclosable. SCD2 so the collaboration history is auditable. A deploy-time row
-- filter uses this to serve each partner only their entitled rows of the shared
-- joint demand plan.
--
-- Grain: one current version per (principal, supplier, product-scope).
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${dss_schema}.demand_collaboration (
  demand_collaboration_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version.',
  demand_collaboration_id STRING NOT NULL
                          COMMENT 'Durable natural/business key for the collaboration grant.',

  principal_id          STRING NOT NULL COMMENT 'Governance principal in the collaboration (UC group / account / service principal; not a customer identity).',
  principal_type        STRING COMMENT 'Kind of principal. Allowed values: group, account, service_principal.',

  supplier_sk           BIGINT COMMENT 'FK to supplier.supplier_sk (the supplier whose demand plan is shared).',
  supplier_id           STRING COMMENT 'Durable supplier business key.',
  product_sk            BIGINT COMMENT 'FK to product.product_sk when scoped to one product (NULL = all products of the supplier).',
  product_id            STRING COMMENT 'Durable product business key; NULL for supplier-wide collaboration.',

  plan_horizon_weeks    INT COMMENT 'Agreed collaborative planning horizon, in fiscal weeks.',
  min_disclosure_threshold INT COMMENT 'Minimum demand volume (units) a plan row must reach before it is disclosable to this principal — a low-volume/materiality floor, NOT a k-anonymity control (the shared rows are already aggregate at supplier x product x week and carry no underlying entity count). NULL means NO floor (every entitled row is disclosed regardless of volume).',
  collaboration_status  STRING COMMENT 'Lifecycle. Allowed values: active, suspended, ended.',

  -- SCD2 versioning (principle #8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version.',

  -- Audit / provenance (all timestamps UTC)
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_demand_collaboration PRIMARY KEY (demand_collaboration_sk)
)
USING DELTA
CLUSTER BY (supplier_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Data Sharing with Suppliers — joint demand planning collaboration entitlement (row-level access + scope anchor, SCD2).';

ALTER TABLE ${catalog}.${dss_schema}.demand_collaboration SET TAGS ('dbx_data_type' = 'association');
