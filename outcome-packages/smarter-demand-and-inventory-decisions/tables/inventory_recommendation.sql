-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- Table: inventory_recommendation
-- Layer: outcome package (extension table / transactional fact)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- System-generated replenishment recommendation before PO creation.
-- ============================================================


CREATE TABLE IF NOT EXISTS ${catalog}.${sdi_schema}.inventory_recommendation (
  inventory_recommendation_sk BIGINT GENERATED ALWAYS AS IDENTITY
                            COMMENT 'Surrogate key.',
  inventory_recommendation_id STRING NOT NULL
                            COMMENT 'Durable business key.',

  planning_unit_sk        BIGINT NOT NULL COMMENT 'FK to planning_unit.planning_unit_sk.',
  planning_unit_id        STRING NOT NULL COMMENT 'Durable planning unit business key.',
  recommendation_date_key DATE NOT NULL COMMENT 'Date recommendation was generated.',
  recommended_order_quantity DECIMAL(12,3) NOT NULL COMMENT 'Recommended order quantity.',
  recommended_order_date_key DATE COMMENT 'Recommended order placement date.',
  projected_days_of_supply DECIMAL(8,2) COMMENT 'Projected DoS before recommendation.',
  projected_days_of_supply_after DECIMAL(8,2) COMMENT 'Projected DoS after receipt.',
  recommendation_reason   STRING NOT NULL
                            COMMENT 'Reason. Allowed values: below_rop, below_min, forecast_spike, promo_build.',
  recommendation_status   STRING NOT NULL
                            COMMENT 'Status. Allowed values: open, accepted, rejected, expired.',

  inventory_policy_sk     BIGINT COMMENT 'FK to inventory_policy.inventory_policy_sk.',
  inventory_policy_id     STRING COMMENT 'Durable inventory policy business key.',

  record_source           STRING    COMMENT 'Originating system of record.',
  load_timestamp          TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_inventory_recommendation PRIMARY KEY (inventory_recommendation_sk)
)
USING DELTA
CLUSTER BY (recommendation_date_key, planning_unit_sk)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Replenishment recommendations generated from inventory policy.';

ALTER TABLE ${catalog}.${sdi_schema}.inventory_recommendation SET TAGS ('dbx_data_type' = 'transactional');
ALTER TABLE ${catalog}.${sdi_schema}.inventory_recommendation ADD CONSTRAINT chk_ir_reason CHECK (recommendation_reason IN ('below_rop', 'below_min', 'forecast_spike', 'promo_build'));
ALTER TABLE ${catalog}.${sdi_schema}.inventory_recommendation ADD CONSTRAINT chk_ir_status CHECK (recommendation_status IN ('open', 'accepted', 'rejected', 'expired'));
