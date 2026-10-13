-- ============================================================
-- ORDM · Outcome Package · Early Risk Detection
-- Table: disruption_alert
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-06-30
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-30 by @sreekanthmunigati
-- ============================================================
-- Actionable alerts derived from disruption events. Each alert is the
-- detection output for one or more related disruption events.
--
-- ADOPTER-EXTENSIBLE LIFECYCLE: The lifecycle/workflow columns
-- (alert_status, assigned_to, acknowledged_timestamp, resolved_timestamp,
-- resolution_notes) are published as a column contract but their lifecycle
-- management (open -> acknowledged -> resolved / escalated) is the
-- adopter's responsibility. ORDM defines the schema; the adopter's
-- operational tooling owns the state transitions. See ADR-0016.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${risk_schema}.disruption_alert (
  disruption_alert_sk   BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  disruption_alert_id   STRING NOT NULL
                          COMMENT 'Durable natural/business key for the alert.',

  disruption_event_sk   BIGINT COMMENT 'FK to the primary disruption_event that triggered this alert.',
  disruption_event_id   STRING COMMENT 'Durable business key of the triggering event.',
  disruption_rule_sk    BIGINT COMMENT 'FK to disruption_rule.disruption_rule_sk.',
  disruption_rule_id    STRING COMMENT 'Durable business key of the rule.',

  alert_type            STRING NOT NULL COMMENT 'Category matching disruption_type. Allowed values: shipment_delay, stockout_risk, quality_issue, feed_outage, supplier_risk, demand_spike, customs_hold, capacity_constraint.',
  severity              STRING NOT NULL COMMENT 'Alert severity. Allowed values: info, warning, critical.',
  alert_status          STRING NOT NULL COMMENT 'Lifecycle status (adopter-managed, should default to open). Allowed values: open, acknowledged, resolved, escalated, suppressed.',

  alert_title           STRING COMMENT 'Short summary of the alert for display.',
  alert_description     STRING COMMENT 'Detailed description including affected entities and recommended action.',
  assigned_to           STRING COMMENT 'User or team assigned to handle the alert (adopter-managed).',

  -- Affected entities (denormalized for the control tower serving layer)
  shipment_id           STRING COMMENT 'Affected shipment business key.',
  supplier_id           STRING COMMENT 'Affected supplier business key.',
  product_id            STRING COMMENT 'Affected product business key.',
  store_id              STRING COMMENT 'Affected store business key.',

  created_timestamp     TIMESTAMP NOT NULL COMMENT 'When the alert was created (UTC, ISO 8601).',
  acknowledged_timestamp TIMESTAMP COMMENT 'When the alert was acknowledged (UTC, ISO 8601). Adopter-managed.',
  resolved_timestamp    TIMESTAMP COMMENT 'When the alert was resolved (UTC, ISO 8601). Adopter-managed.',
  resolution_notes      STRING COMMENT 'Notes on how the alert was resolved. Adopter-managed.',

  -- Audit / provenance
  record_source         STRING    COMMENT 'Originating system or rule engine.',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_disruption_alert PRIMARY KEY (disruption_alert_sk)
)
USING DELTA
CLUSTER BY (alert_status, severity, created_timestamp)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Actionable disruption alerts with lifecycle tracking for the Early Risk Detection control tower.';

ALTER TABLE ${catalog}.${risk_schema}.disruption_alert SET TAGS ('dbx_data_type' = 'transactional');
ALTER TABLE ${catalog}.${risk_schema}.disruption_alert ALTER COLUMN assigned_to SET TAGS ('dbx_pii_name' = 'true');

-- CHECK constraints moved from the CREATE (Databricks does not support
-- inline CHECK; ADD CONSTRAINT is the supported, idempotent form).
ALTER TABLE ${catalog}.${risk_schema}.disruption_alert ADD CONSTRAINT chk_da_alert_type CHECK (alert_type IN ('shipment_delay', 'stockout_risk', 'quality_issue', 'feed_outage', 'supplier_risk', 'demand_spike', 'customs_hold', 'capacity_constraint'));
ALTER TABLE ${catalog}.${risk_schema}.disruption_alert ADD CONSTRAINT chk_da_severity CHECK (severity IN ('info', 'warning', 'critical'));
ALTER TABLE ${catalog}.${risk_schema}.disruption_alert ADD CONSTRAINT chk_da_alert_status CHECK (alert_status IN ('open', 'acknowledged', 'resolved', 'escalated', 'suppressed'));
