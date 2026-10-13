-- ============================================================
-- ORDM · Outcome Package · Data Sharing with Suppliers
-- Table: demand_plan_submission
-- Layer: outcome package (extension table / transactional fact)
-- Version: 0.5
-- Generated: 2026-08-01
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-01
-- ============================================================
-- Each collaborating party's versioned demand-forecast submission for a CPFR plan
-- cycle. One row per (plan cycle × party × supplier × product × fiscal week ×
-- submission version). Both sides of the collaboration submit here: the retailer's
-- plan and the supplier's plan land as separate rows (party_role), and each
-- resubmission bumps submission_version so the reconciliation view can pick the
-- latest per party. Quantities are the shared unit of demand; the monetary
-- forecast is a single reporting currency. Sourced from each party's planning
-- system; supplier-safe (no person-level data).
--
-- Grain: one row per (plan_cycle_id, party_role, supplier, product, fiscal week,
-- submission_version).
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${dss_schema}.demand_plan_submission (
  demand_plan_submission_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  demand_plan_submission_id STRING NOT NULL
                          COMMENT 'Durable natural/business key (grain hash incl. submission_version).',

  plan_cycle_id         STRING NOT NULL COMMENT 'CPFR plan cycle this submission belongs to (e.g. a monthly consensus round).',
  party_role            STRING COMMENT 'Which side submitted the plan. Allowed values: retailer, supplier.',

  supplier_sk           BIGINT COMMENT 'FK to supplier.supplier_sk.',
  supplier_id           STRING COMMENT 'Durable supplier business key.',
  product_sk            BIGINT COMMENT 'FK to product.product_sk.',
  product_id            STRING COMMENT 'Durable product business key.',

  fiscal_week_id        INT COMMENT 'Target demand week = fiscal_year * 100 + fiscal_week (join key to fiscal_calendar.fiscal_week_id).',

  forecast_qty          BIGINT COMMENT 'Submitted forecast demand quantity (units) for the week.',
  forecast_value_net    DECIMAL(18,2) COMMENT 'Submitted forecast net value for the week, reporting/base currency.',
  currency_code         STRING COMMENT 'Amount currency, ISO 4217 alpha-3 (single reporting currency).',

  submission_version    INT COMMENT 'Monotonic version for this (cycle, party, grain); latest wins in reconciliation.',
  submission_status     STRING COMMENT 'Lifecycle. Allowed values: draft, submitted, superseded, withdrawn.',
  submitted_ts          TIMESTAMP NOT NULL COMMENT 'When this version was submitted (UTC, ISO 8601). NOT NULL: it is the primary latest-wins ordering key in gold_joint_demand_plan (event time is cycle-agnostic), so a NULL would sort a genuine latest row last and silently serve a stale plan.',

  -- Audit / provenance (append-only fact block; all timestamps UTC)
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_demand_plan_submission PRIMARY KEY (demand_plan_submission_sk)
)
USING DELTA
CLUSTER BY (supplier_id, fiscal_week_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Data Sharing with Suppliers — per-party versioned demand-plan submission (CPFR).';

ALTER TABLE ${catalog}.${dss_schema}.demand_plan_submission SET TAGS ('dbx_data_type' = 'transactional');
