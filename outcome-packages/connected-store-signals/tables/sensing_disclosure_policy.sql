-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Table: sensing_disclosure_policy
-- Layer: outcome package (gold / dimensional policy)
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-28
-- ============================================================
-- Effective-dated disclosure configuration for explicitly shared sensing views.
-- Operational interval facts and gold views remain complete; this policy does not
-- authorize write-time suppression.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${css_schema}.sensing_disclosure_policy (
  sensing_disclosure_policy_sk BIGINT GENERATED ALWAYS AS IDENTITY
      COMMENT 'Surrogate key for this effective-dated policy version.',
  sensing_disclosure_policy_id STRING NOT NULL
      COMMENT 'Durable policy business key.',
  audience_code STRING NOT NULL
      COMMENT 'Intended disclosure audience, such as external or partner.',
  k_threshold INT NOT NULL
      COMMENT 'Minimum count published to this audience. Zero disables below-k suppression so suppress_zero_flag can govern measured zeros independently.',
  suppress_zero_flag BOOLEAN NOT NULL
      COMMENT 'TRUE when measured zero cells are suppressed for this audience.',
  minimum_interval_minutes INT NOT NULL
      COMMENT 'Minimum publishable time window. Finer canonical rows must be aggregated before threshold evaluation.',
  effective_from_date DATE NOT NULL
      COMMENT 'Inclusive policy-effective date.',
  effective_to_date DATE
      COMMENT 'Exclusive policy-effective date; NULL for current.',
  is_current BOOLEAN NOT NULL
      COMMENT 'TRUE for the current policy version.',
  policy_basis STRING
      COMMENT 'Governance or policy basis for the configured disclosure controls.',
  record_source STRING
      COMMENT 'Originating system of record.',
  load_timestamp TIMESTAMP
      COMMENT 'When this policy version was loaded (UTC).',

  CONSTRAINT pk_sensing_disclosure_policy
    PRIMARY KEY (sensing_disclosure_policy_sk)
)
USING DELTA
CLUSTER BY (sensing_disclosure_policy_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Connected Store Signals -- effective-dated disclosure policy for explicit shared projections.';

ALTER TABLE ${catalog}.${css_schema}.sensing_disclosure_policy
  SET TAGS ('dbx_data_type' = 'master');
