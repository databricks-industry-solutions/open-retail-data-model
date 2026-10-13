-- ============================================================
-- ORDM · Outcome Package · Early Risk Detection
-- Table: disruption_event
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-06-30
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-30 by @sreekanthmunigati
-- ============================================================
-- Append-only disruption event log — the unifying exception table for
-- the control tower. Each row records one detected disruption: a late
-- shipment, a stockout risk, a supplier quality issue, a feed outage,
-- or any other exception the rule engine fires. Event-grained and
-- append-only: rows are never updated; resolution is tracked by a
-- subsequent event or by the disruption_alert lifecycle.
--
-- Designed for streaming: carries event_timestamp, ingest_timestamp,
-- and latency_seconds for freshness monitoring.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${risk_schema}.disruption_event (
  disruption_event_sk   BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  disruption_event_id   STRING NOT NULL
                          COMMENT 'Durable natural/business key for the disruption event.',

  disruption_rule_sk    BIGINT COMMENT 'FK to disruption_rule.disruption_rule_sk — the rule that fired.',
  disruption_rule_id    STRING COMMENT 'Durable business key of the rule that detected this event.',

  disruption_type       STRING NOT NULL COMMENT 'Category of disruption. Allowed values: shipment_delay, stockout_risk, quality_issue, feed_outage, supplier_risk, demand_spike, customs_hold, capacity_constraint.',
  severity              STRING NOT NULL COMMENT 'Severity level. Allowed values: info, warning, critical.',

  -- Affected entities (nullable; which dimension is populated depends on the disruption type)
  shipment_sk           BIGINT COMMENT 'FK to shipment.shipment_sk if shipment-related.',
  shipment_id           STRING COMMENT 'Durable shipment business key.',
  supplier_sk           BIGINT COMMENT 'FK to supplier.supplier_sk if supplier-related.',
  supplier_id           STRING COMMENT 'Durable supplier business key.',
  product_sk            BIGINT COMMENT 'FK to product.product_sk if product-related.',
  product_id            STRING COMMENT 'Durable product business key.',
  store_sk              BIGINT COMMENT 'FK to store.store_sk if location-related.',
  store_id              STRING COMMENT 'Durable store business key.',
  lane_sk               BIGINT COMMENT 'FK to lane.lane_sk if lane-related.',
  lane_id               STRING COMMENT 'Durable lane business key.',

  event_description     STRING COMMENT 'Human-readable description of the disruption.',
  metric_name           STRING COMMENT 'Name of the metric that triggered the event (e.g. eta_slip_days, days_of_supply).',
  metric_value          DOUBLE COMMENT 'Observed value of the triggering metric.',
  threshold_value       DOUBLE COMMENT 'Threshold that was breached.',

  -- Real-time / streaming support
  event_timestamp       TIMESTAMP NOT NULL COMMENT 'When the disruption was detected at source (UTC, ISO 8601).',
  ingest_timestamp      TIMESTAMP NOT NULL COMMENT 'When this event was ingested into the lakehouse (UTC, ISO 8601).',
  latency_seconds       INT COMMENT 'Ingest latency = ingest_timestamp - event_timestamp, in seconds.',

  -- Audit / provenance (append-only fact block)
  record_source         STRING    COMMENT 'Originating system or rule engine that produced this event.',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_disruption_event PRIMARY KEY (disruption_event_sk)
)
USING DELTA
CLUSTER BY (event_timestamp, disruption_type)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Append-only disruption event log for the Early Risk Detection control tower. The unifying exception table across shipment, inventory, and supplier disruptions.';

ALTER TABLE ${catalog}.${risk_schema}.disruption_event SET TAGS ('dbx_data_type' = 'transactional');

-- CHECK constraints moved from the CREATE (Databricks does not support
-- inline CHECK; ADD CONSTRAINT is the supported, idempotent form).
ALTER TABLE ${catalog}.${risk_schema}.disruption_event ADD CONSTRAINT chk_de_disruption_type CHECK (disruption_type IN ('shipment_delay', 'stockout_risk', 'quality_issue', 'feed_outage', 'supplier_risk', 'demand_spike', 'customs_hold', 'capacity_constraint'));
ALTER TABLE ${catalog}.${risk_schema}.disruption_event ADD CONSTRAINT chk_de_severity CHECK (severity IN ('info', 'warning', 'critical'));
