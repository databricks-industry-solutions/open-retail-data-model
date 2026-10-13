-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- Table: inventory_policy_calculation
-- Layer: outcome package (extension table / transactional fact)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Audit log of how an inventory policy was derived.
-- ============================================================


CREATE TABLE IF NOT EXISTS ${catalog}.${sdi_schema}.inventory_policy_calculation (
  policy_calculation_sk   BIGINT GENERATED ALWAYS AS IDENTITY
                            COMMENT 'Surrogate key.',
  policy_calculation_id   STRING NOT NULL
                            COMMENT 'Durable business key.',

  inventory_policy_sk     BIGINT NOT NULL COMMENT 'FK to inventory_policy.inventory_policy_sk.',
  inventory_policy_id     STRING NOT NULL COMMENT 'Durable inventory policy business key.',
  calculated_at_timestamp TIMESTAMP NOT NULL COMMENT 'When the policy was calculated (UTC).',

  avg_daily_demand        DECIMAL(12,3) COMMENT 'Average daily demand used.',
  demand_std_dev          DECIMAL(12,3) COMMENT 'Demand standard deviation.',
  forecast_bias_pct       DOUBLE COMMENT 'Forecast bias percentage input.',
  lead_time_days          INT COMMENT 'Lead time in days.',
  lead_time_std_dev       DOUBLE COMMENT 'Lead time standard deviation.',
  safety_stock_formula    STRING COMMENT 'Formula identifier used.',
  z_score                 DOUBLE COMMENT 'Z-score from service level.',
  supplier_reliability_multiplier DOUBLE COMMENT 'Supplier reliability adjustment.',

  record_source           STRING    COMMENT 'Originating system of record.',
  load_timestamp          TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_inventory_policy_calculation PRIMARY KEY (policy_calculation_sk)
)
USING DELTA
CLUSTER BY (inventory_policy_sk)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Audit trail for inventory policy derivation.';

ALTER TABLE ${catalog}.${sdi_schema}.inventory_policy_calculation SET TAGS ('dbx_data_type' = 'transactional');
