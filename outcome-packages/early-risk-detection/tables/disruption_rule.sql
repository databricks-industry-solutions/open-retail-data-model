-- ============================================================
-- ORDM · Outcome Package · Early Risk Detection
-- Table: disruption_rule
-- Layer: outcome package (extension table / reference)
-- Version: 0.5
-- Generated: 2026-06-30
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-30 by @sreekanthmunigati
-- ============================================================
-- Small reference table defining the detection rules that fire
-- disruption events. Each rule specifies a metric, a threshold,
-- a severity, and whether it is currently enabled. Rules are the
-- configuration layer for the disruption detection engine.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${risk_schema}.disruption_rule (
  disruption_rule_sk    BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  disruption_rule_id    STRING NOT NULL
                          COMMENT 'Durable natural/business key for the rule (e.g. RULE-ETA-SLIP-3D).',

  rule_name             STRING NOT NULL COMMENT 'Human-readable name of the rule.',
  rule_description      STRING COMMENT 'Detailed description of what the rule detects and why.',
  disruption_type       STRING NOT NULL COMMENT 'Category of disruption this rule detects. Allowed values: shipment_delay, stockout_risk, quality_issue, feed_outage, supplier_risk, demand_spike, customs_hold, capacity_constraint.',
  default_severity      STRING NOT NULL COMMENT 'Default severity when this rule fires. Allowed values: info, warning, critical.',

  metric_name           STRING NOT NULL COMMENT 'Name of the metric the rule evaluates (e.g. eta_slip_days, days_of_supply, feed_age_minutes).',
  threshold_operator    STRING NOT NULL COMMENT 'Comparison operator. Allowed values: gt, gte, lt, lte, eq, neq.',
  threshold_value       DOUBLE NOT NULL COMMENT 'Threshold value for the metric comparison.',

  is_enabled            BOOLEAN NOT NULL COMMENT 'Whether the rule is currently active.',
  evaluation_interval   STRING COMMENT 'How often the rule runs (e.g. 5m, 1h, 1d). Informational.',

  -- Audit / provenance (reference table block)
  created_timestamp        TIMESTAMP COMMENT 'When the rule was created (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the rule was last modified (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system or configuration source.',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_disruption_rule PRIMARY KEY (disruption_rule_sk)
)
USING DELTA
CLUSTER BY (disruption_rule_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Reference table of disruption detection rules for the Early Risk Detection outcome package.';

ALTER TABLE ${catalog}.${risk_schema}.disruption_rule SET TAGS ('dbx_data_type' = 'reference');

-- CHECK constraints moved from the CREATE (Databricks does not support
-- inline CHECK; ADD CONSTRAINT is the supported, idempotent form).
ALTER TABLE ${catalog}.${risk_schema}.disruption_rule ADD CONSTRAINT chk_dr_disruption_type CHECK (disruption_type IN ('shipment_delay', 'stockout_risk', 'quality_issue', 'feed_outage', 'supplier_risk', 'demand_spike', 'customs_hold', 'capacity_constraint'));
ALTER TABLE ${catalog}.${risk_schema}.disruption_rule ADD CONSTRAINT chk_dr_severity CHECK (default_severity IN ('info', 'warning', 'critical'));
ALTER TABLE ${catalog}.${risk_schema}.disruption_rule ADD CONSTRAINT chk_dr_operator CHECK (threshold_operator IN ('gt', 'gte', 'lt', 'lte', 'eq', 'neq'));
