-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- Table: order_forecast
-- Layer: outcome package (extension table / transactional fact)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Order forecast translating demand into replenishment, purchase, or transfer orders.
-- ============================================================


CREATE TABLE IF NOT EXISTS ${catalog}.${sdi_schema}.order_forecast (
  order_forecast_sk       BIGINT GENERATED ALWAYS AS IDENTITY
                            COMMENT 'Surrogate key.',
  order_forecast_id       STRING NOT NULL
                            COMMENT 'Durable business key.',

  planning_unit_sk        BIGINT NOT NULL COMMENT 'FK to planning_unit.planning_unit_sk.',
  planning_unit_id        STRING NOT NULL COMMENT 'Durable planning unit business key.',
  order_date_key          DATE NOT NULL COMMENT 'Planned order placement date.',
  need_by_date_key        DATE COMMENT 'Required on-shelf or in-DC date.',
  order_forecast_quantity DECIMAL(12,3) NOT NULL COMMENT 'Forecasted order quantity.',
  order_type              STRING NOT NULL
                            COMMENT 'Order type. Allowed values: replenishment, purchase, transfer, allocation.',
  source_location_id      STRING COMMENT 'Origin DC or supplier site (degenerate polymorphic reference).',

  destination_store_sk    BIGINT COMMENT 'FK to store.store_sk (version-specific).',
  destination_store_id    STRING COMMENT 'Durable store business key.',
  demand_forecast_sk      BIGINT COMMENT 'FK to demand_forecast.demand_forecast_sk.',
  demand_forecast_id      STRING COMMENT 'Durable demand forecast business key.',
  inventory_policy_sk     BIGINT COMMENT 'FK to inventory_policy.inventory_policy_sk.',
  inventory_policy_id     STRING COMMENT 'Durable inventory policy business key.',

  record_source           STRING    COMMENT 'Originating system of record.',
  load_timestamp          TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_order_forecast PRIMARY KEY (order_forecast_sk)
)
USING DELTA
CLUSTER BY (order_date_key, planning_unit_sk)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Order forecast at planning-unit x order-date grain.';

ALTER TABLE ${catalog}.${sdi_schema}.order_forecast SET TAGS ('dbx_data_type' = 'transactional');
ALTER TABLE ${catalog}.${sdi_schema}.order_forecast ADD CONSTRAINT chk_of_type CHECK (order_type IN ('replenishment', 'purchase', 'transfer', 'allocation'));
