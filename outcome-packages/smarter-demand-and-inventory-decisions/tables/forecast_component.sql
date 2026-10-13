-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- Table: forecast_component
-- Layer: outcome package (extension table / transactional fact)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Demand driver decomposition for each demand forecast line.
-- ============================================================


CREATE TABLE IF NOT EXISTS ${catalog}.${sdi_schema}.forecast_component (
  forecast_component_sk   BIGINT GENERATED ALWAYS AS IDENTITY
                            COMMENT 'Surrogate key.',
  forecast_component_id   STRING NOT NULL
                            COMMENT 'Durable business key.',

  demand_forecast_sk      BIGINT NOT NULL COMMENT 'FK to demand_forecast.demand_forecast_sk.',
  demand_forecast_id      STRING NOT NULL COMMENT 'Durable demand forecast business key.',
  component_type          STRING NOT NULL
                            COMMENT 'Driver type. Allowed values: base, promo, price, weather, holiday, trend, residual.',
  component_quantity      DECIMAL(12,3) NOT NULL COMMENT 'Signed contribution in UOM.',

  record_source           STRING    COMMENT 'Originating system of record.',
  load_timestamp          TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_forecast_component PRIMARY KEY (forecast_component_sk)
)
USING DELTA
CLUSTER BY (demand_forecast_sk)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Demand driver decomposition child of demand_forecast.';

ALTER TABLE ${catalog}.${sdi_schema}.forecast_component SET TAGS ('dbx_data_type' = 'transactional');
ALTER TABLE ${catalog}.${sdi_schema}.forecast_component ADD CONSTRAINT chk_fc_type CHECK (component_type IN ('base', 'promo', 'price', 'weather', 'holiday', 'trend', 'residual'));
