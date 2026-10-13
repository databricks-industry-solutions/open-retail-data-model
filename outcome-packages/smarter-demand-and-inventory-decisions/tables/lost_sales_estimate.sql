-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- Table: lost_sales_estimate
-- Layer: outcome package (extension table / transactional fact)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Lost sales estimate for demand not captured due to OOS.
-- ============================================================


CREATE TABLE IF NOT EXISTS ${catalog}.${sdi_schema}.lost_sales_estimate (
  lost_sales_estimate_sk  BIGINT GENERATED ALWAYS AS IDENTITY
                            COMMENT 'Surrogate key.',
  lost_sales_estimate_id  STRING NOT NULL
                            COMMENT 'Durable business key.',

  oos_event_sk            BIGINT NOT NULL COMMENT 'FK to oos_event.oos_event_sk.',
  oos_event_id            STRING NOT NULL COMMENT 'Durable OOS event business key.',
  estimate_date_key       DATE NOT NULL COMMENT 'Day within the OOS episode.',

  actual_units_sold       INT COMMENT 'Actual units sold from sales.',
  expected_units_demand   DECIMAL(12,3) COMMENT 'Expected unconstrained demand.',
  lost_units              DECIMAL(12,3) COMMENT 'Estimated lost units.',
  estimation_method       STRING NOT NULL
                            COMMENT 'Method. Allowed values: forecast_residual, trailing_average, peer_store, ml_model.',
  censoring_adjusted      BOOLEAN COMMENT 'TRUE when forecast excludes stockout days.',
  lost_revenue            DECIMAL(18,2) COMMENT 'Estimated lost revenue, in the reporting/base currency.',
  lost_margin             DECIMAL(18,2) COMMENT 'Estimated lost GROSS MARGIN (lost_units x (list_price - unit_cost)), in the reporting/base currency. Margin, not revenue, is the correct basis for prioritizing recovery.',
  currency_code           STRING COMMENT 'Reporting/base currency of ALL monetary columns, ISO 4217 alpha-3. Equals the deploy base_currency; single-currency by construction.',
  confidence_score        DOUBLE COMMENT 'Confidence score 0-1.',

  record_source           STRING    COMMENT 'Originating system of record.',
  load_timestamp          TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_lost_sales_estimate PRIMARY KEY (lost_sales_estimate_sk)
)
USING DELTA
CLUSTER BY (estimate_date_key, oos_event_sk)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Daily lost sales estimate within an OOS episode.';

ALTER TABLE ${catalog}.${sdi_schema}.lost_sales_estimate SET TAGS ('dbx_data_type' = 'transactional');
ALTER TABLE ${catalog}.${sdi_schema}.lost_sales_estimate ADD CONSTRAINT chk_lse_method CHECK (estimation_method IN ('forecast_residual', 'trailing_average', 'peer_store', 'ml_model'));
