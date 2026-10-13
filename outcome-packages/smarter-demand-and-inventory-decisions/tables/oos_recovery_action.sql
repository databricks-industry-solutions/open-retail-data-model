-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- Table: oos_recovery_action
-- Layer: outcome package (extension table / transactional fact)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Recommended or executed action to resolve an OOS event.
-- ============================================================


CREATE TABLE IF NOT EXISTS ${catalog}.${sdi_schema}.oos_recovery_action (
  oos_recovery_action_sk  BIGINT GENERATED ALWAYS AS IDENTITY
                            COMMENT 'Surrogate key.',
  oos_recovery_action_id  STRING NOT NULL
                            COMMENT 'Durable business key.',

  oos_event_sk            BIGINT NOT NULL COMMENT 'FK to oos_event.oos_event_sk.',
  oos_event_id            STRING NOT NULL COMMENT 'Durable OOS event business key.',
  action_type             STRING NOT NULL
                            COMMENT 'Action type. Allowed values: emergency_order, transfer, allocation_shift, substitute_product, expedite_shipment.',
  recommended_quantity    DECIMAL(12,3) COMMENT 'Recommended recovery quantity.',
  recommended_action_date_key DATE COMMENT 'Recommended action date.',
  estimated_recovery_date_key DATE COMMENT 'Estimated recovery date.',
  estimated_revenue_recovery DECIMAL(18,2) COMMENT 'Estimated revenue recovery, in the reporting/base currency.',
  estimated_margin_recovery DECIMAL(18,2) COMMENT 'Estimated GROSS-MARGIN recovery, in the reporting/base currency. Prioritizing by margin (not revenue) avoids over-ranking low-margin high-revenue SKUs.',
  recoverability_probability DOUBLE COMMENT 'Probability the recovery action succeeds within the horizon (0-1). Used with estimated_margin_recovery for expected-value ranking.',
  actual_revenue_recovered DECIMAL(18,2) COMMENT 'Realized revenue recovery after execution (NULL until measured); closes the estimate-vs-actual learn loop.',
  time_to_recover_days    INT COMMENT 'Days from recommended_action_date_key to observed recovery; NULL until recovered.',
  currency_code           STRING COMMENT 'Reporting/base currency of ALL monetary columns, ISO 4217 alpha-3. Equals the deploy base_currency; single-currency by construction.',
  action_status           STRING NOT NULL
                            COMMENT 'Status. Allowed values: recommended, approved, executed, rejected.',

  inventory_recommendation_sk BIGINT COMMENT 'FK to inventory_recommendation.inventory_recommendation_sk.',
  inventory_recommendation_id STRING COMMENT 'Durable inventory recommendation business key.',
  linked_po_line_sk       BIGINT COMMENT 'FK to purchase_order_line.po_line_sk when PO created.',

  record_source           STRING    COMMENT 'Originating system of record.',
  load_timestamp          TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_oos_recovery_action PRIMARY KEY (oos_recovery_action_sk)
)
USING DELTA
CLUSTER BY (oos_event_sk)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Recovery actions recommended or executed for OOS events.';

ALTER TABLE ${catalog}.${sdi_schema}.oos_recovery_action SET TAGS ('dbx_data_type' = 'transactional');
ALTER TABLE ${catalog}.${sdi_schema}.oos_recovery_action ADD CONSTRAINT chk_ora_type CHECK (action_type IN ('emergency_order', 'transfer', 'allocation_shift', 'substitute_product', 'expedite_shipment'));
ALTER TABLE ${catalog}.${sdi_schema}.oos_recovery_action ADD CONSTRAINT chk_ora_status CHECK (action_status IN ('recommended', 'approved', 'executed', 'rejected'));
