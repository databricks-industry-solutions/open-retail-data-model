-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- Table: forecast_adjustment
-- Layer: outcome package (extension table / transactional fact)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Planner overrides and enrichment for demand forecasts (FVA analytical mirror).
-- ============================================================


CREATE TABLE IF NOT EXISTS ${catalog}.${sdi_schema}.forecast_adjustment (
  forecast_adjustment_sk  BIGINT GENERATED ALWAYS AS IDENTITY
                            COMMENT 'Surrogate key.',
  forecast_adjustment_id  STRING NOT NULL
                            COMMENT 'Durable business key.',

  planning_unit_sk        BIGINT NOT NULL COMMENT 'FK to planning_unit.planning_unit_sk.',
  planning_unit_id        STRING NOT NULL COMMENT 'Durable planning unit business key.',
  forecast_date_key       DATE NOT NULL COMMENT 'Forecast period being adjusted.',

  adjustment_quantity     DECIMAL(12,3) NOT NULL COMMENT 'Adjustment amount per adjustment_method.',
  adjustment_method       STRING NOT NULL
                            COMMENT 'How to apply adjustment. Allowed values: absolute, delta, pct.',
  adjustment_reason_code  STRING COMMENT 'Reason code (e.g. promo_not_in_model, new_listing).',
  adjusted_by             STRING COMMENT 'Planner identifier.',
  adjusted_at_timestamp   TIMESTAMP COMMENT 'When the adjustment was made (UTC).',
  approval_status         STRING NOT NULL
                            COMMENT 'Approval state. Allowed values: pending, approved, rejected.',

  record_source           STRING    COMMENT 'Originating system of record.',
  load_timestamp          TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_forecast_adjustment PRIMARY KEY (forecast_adjustment_sk)
)
USING DELTA
CLUSTER BY (forecast_date_key, planning_unit_sk)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Planner forecast adjustments for FVA and enriched forecast.';

ALTER TABLE ${catalog}.${sdi_schema}.forecast_adjustment SET TAGS ('dbx_data_type' = 'transactional');
ALTER TABLE ${catalog}.${sdi_schema}.forecast_adjustment ALTER COLUMN adjusted_by SET TAGS ('dbx_pii_identifier' = 'true');
ALTER TABLE ${catalog}.${sdi_schema}.forecast_adjustment ADD CONSTRAINT chk_fa_method CHECK (adjustment_method IN ('absolute', 'delta', 'pct'));
ALTER TABLE ${catalog}.${sdi_schema}.forecast_adjustment ADD CONSTRAINT chk_fa_status CHECK (approval_status IN ('pending', 'approved', 'rejected'));
