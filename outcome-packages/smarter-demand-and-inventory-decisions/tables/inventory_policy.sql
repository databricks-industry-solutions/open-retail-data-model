-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- Table: inventory_policy
-- Layer: outcome package (extension table / reference)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Versioned replenishment policy per planning unit.
-- ============================================================


CREATE TABLE IF NOT EXISTS ${catalog}.${sdi_schema}.inventory_policy (
  inventory_policy_sk     BIGINT GENERATED ALWAYS AS IDENTITY
                            COMMENT 'Surrogate key.',
  inventory_policy_id     STRING NOT NULL
                            COMMENT 'Durable business key.',

  planning_unit_sk        BIGINT NOT NULL COMMENT 'FK to planning_unit.planning_unit_sk.',
  planning_unit_id        STRING NOT NULL COMMENT 'Durable planning unit business key.',
  policy_type             STRING NOT NULL
                            COMMENT 'Policy type. Allowed values: min_max, reorder_point, periodic_review, days_of_supply.',

  safety_stock_quantity   DECIMAL(12,3) COMMENT 'Safety stock in units.',
  reorder_point_quantity  DECIMAL(12,3) COMMENT 'Reorder point in units.',
  min_quantity            DECIMAL(12,3) COMMENT 'Minimum shelf or order quantity.',
  max_quantity            DECIMAL(12,3) COMMENT 'Maximum shelf or order quantity.',
  order_up_to_quantity    DECIMAL(12,3) COMMENT 'Order-up-to level for (s,S) policies.',
  review_period_days      INT COMMENT 'Review period for periodic review policies.',
  lead_time_days          INT COMMENT 'Default lead time in days.',

  service_level_target_sk BIGINT COMMENT 'FK to service_level_target.service_level_target_sk.',
  service_level_target_id STRING COMMENT 'Durable service level target business key.',
  policy_source           STRING NOT NULL
                            COMMENT 'Origin. Allowed values: system_calculated, planner_override, abc_xyz_template.',

  effective_from_date     DATE NOT NULL COMMENT 'Inclusive start date for this version.',
  effective_to_date       DATE COMMENT 'Exclusive end date; NULL for current.',
  is_current              BOOLEAN NOT NULL COMMENT 'Whether this is the current version.',

  created_timestamp        TIMESTAMP COMMENT 'When created (UTC).',
  source_updated_timestamp TIMESTAMP COMMENT 'When last modified (UTC).',
  record_source           STRING    COMMENT 'Originating system of record.',
  load_timestamp          TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_inventory_policy PRIMARY KEY (inventory_policy_sk)
)
USING DELTA
CLUSTER BY (planning_unit_sk)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Versioned inventory replenishment policy per planning unit.';

ALTER TABLE ${catalog}.${sdi_schema}.inventory_policy SET TAGS ('dbx_data_type' = 'reference');
ALTER TABLE ${catalog}.${sdi_schema}.inventory_policy ADD CONSTRAINT chk_ip_type CHECK (policy_type IN ('min_max', 'reorder_point', 'periodic_review', 'days_of_supply'));
ALTER TABLE ${catalog}.${sdi_schema}.inventory_policy ADD CONSTRAINT chk_ip_source CHECK (policy_source IN ('system_calculated', 'planner_override', 'abc_xyz_template'));
