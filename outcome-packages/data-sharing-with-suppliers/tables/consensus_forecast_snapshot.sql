-- ============================================================
-- ORDM · Outcome Package · Data Sharing with Suppliers
-- Table: consensus_forecast_snapshot
-- Layer: outcome package (extension table / transactional fact)
-- Version: 0.5
-- Generated: 2026-08-01
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-01
-- ============================================================
-- Append-only, IMMUTABLE published CONSENSUS demand plan — one row per publish
-- snapshot × supplier × product × fiscal week × plan version. Freezes the agreed
-- consensus numbers (and each side's number at agreement time) at a point in
-- time for accountability / dispute / reconciliation, so a later restatement of a
-- party's submission does not change what was already agreed. Carries the
-- retailer vs supplier variance so the exception queue and downstream ordering can
-- read a governed, frozen figure. Threshold-suppressed; supplier-safe (no
-- person-level data). Pairs with demand_plan_submission (the live per-party plans).
--
-- Grain: one publish snapshot × supplier × product × fiscal week × plan_version.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${dss_schema}.consensus_forecast_snapshot (
  consensus_forecast_snapshot_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  consensus_forecast_snapshot_id STRING NOT NULL
                          COMMENT 'Durable natural/business key (grain hash incl. plan_version).',

  plan_cycle_id         STRING NOT NULL COMMENT 'CPFR plan cycle this consensus was agreed in (NOT NULL, matching demand_plan_submission.plan_cycle_id).',
  supplier_sk           BIGINT COMMENT 'FK to supplier.supplier_sk.',
  supplier_id           STRING COMMENT 'Durable supplier business key.',
  product_sk            BIGINT COMMENT 'FK to product.product_sk.',
  product_id            STRING COMMENT 'Durable product business key.',

  fiscal_week_id        INT COMMENT 'Target demand week = fiscal_year * 100 + fiscal_week (join key to fiscal_calendar.fiscal_week_id).',

  snapshot_ts           TIMESTAMP NOT NULL COMMENT 'When this consensus was published/frozen (UTC, ISO 8601).',
  snapshot_date         DATE NOT NULL COMMENT 'Publish date (cluster key).',
  plan_version          INT COMMENT 'Monotonic publish version for this scope/week (immutable per version).',

  consensus_qty         BIGINT COMMENT 'Agreed consensus demand quantity (units) for the week.',
  consensus_value_net   DECIMAL(18,2) COMMENT 'Agreed consensus net value for the week, reporting/base currency.',
  retailer_qty          BIGINT COMMENT 'Retailer submitted quantity at agreement time.',
  supplier_qty          BIGINT COMMENT 'Supplier submitted quantity at agreement time.',
  variance_pct          DECIMAL(9,4) COMMENT 'Retailer-vs-supplier disagreement FROZEN at agreement time = (retailer_qty - supplier_qty) / NULLIF(supplier_qty, 0). The immutable counterpart of gold_joint_demand_plan.plan_variance_pct (which is recomputed LIVE from the latest submissions).',
  currency_code         STRING COMMENT 'Amount currency, ISO 4217 alpha-3 (single reporting currency).',
  threshold_suppressed_flag BOOLEAN COMMENT 'TRUE if any measure was threshold-suppressed before disclosure.',

  -- Audit / provenance (append-only fact block; all timestamps UTC)
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_consensus_forecast_snapshot PRIMARY KEY (consensus_forecast_snapshot_sk)
)
USING DELTA
CLUSTER BY (snapshot_date, supplier_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Data Sharing with Suppliers — immutable published consensus demand-plan snapshot (append-only).';

ALTER TABLE ${catalog}.${dss_schema}.consensus_forecast_snapshot SET TAGS ('dbx_data_type' = 'transactional');
