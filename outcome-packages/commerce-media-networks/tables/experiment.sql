-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- Table: experiment
-- Layer: outcome package (gold dimension)
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- The incrementality EXPERIMENT design dimension (SCD2). One version per
-- experiment: methodology, unit of assignment, objective metric, dates, and
-- confidence level. Conforms the incrementality-testing brief's dim_experiment
-- and the experiment referenced by media-measurement's incrementality results.
--
-- This is the DESIGN, not the results — assignment/exposure/conversion facts and
-- the incrementality-result fact (iROAS / lift, treatment vs control,
-- counterfactual, CIs, p-values) are outcome-package deliverables that reference
-- this dimension. An experiment MAY evaluate a campaign (campaign_sk, optional);
-- experiments can also be campaign-agnostic.
--
-- Grain: one current version per experiment.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${cmn_schema}.experiment (
  experiment_sk         BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version; the join/FK target.',
  experiment_id         STRING NOT NULL
                          COMMENT 'Durable natural/business key for the experiment.',

  -- Optional campaign under test (cmn.campaign)
  campaign_sk           BIGINT COMMENT 'FK to campaign.campaign_sk when the experiment evaluates a campaign (NULL for campaign-agnostic experiments).',
  campaign_id           STRING COMMENT 'Durable business key of the evaluated campaign, if any (join on current campaign version).',

  experiment_name       STRING COMMENT 'Human-readable experiment name.',
  experiment_type       STRING COMMENT 'Experiment design. Allowed values: geo_holdout, audience_holdout, ghost_ads, switchback, pre_post, other.',
  methodology           STRING COMMENT 'Causal method. Allowed values: randomized_control, matched_market, synthetic_control, difference_in_differences, other.',
  unit_of_assignment    STRING COMMENT 'Randomization unit. Allowed values: user, household, geo, store, device.',
  objective_metric      STRING COMMENT 'Primary outcome measured. Allowed values: incremental_sales, incremental_units, roas, conversion_rate, reach, other.',
  experiment_status     STRING COMMENT 'Lifecycle status. Allowed values: draft, running, completed, analyzed, archived.',
  start_date            DATE   COMMENT 'Experiment start date, inclusive (ISO 8601).',
  end_date              DATE   COMMENT 'Experiment end date, inclusive (ISO 8601); NULL if ongoing.',
  confidence_level      DECIMAL(5,4) COMMENT 'Target statistical confidence level in [0,1] (e.g. 0.9500 for 95%).',

  -- SCD2 versioning (principle #8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version of this experiment.',

  -- Audit / provenance (standard block; all timestamps UTC)
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_experiment PRIMARY KEY (experiment_sk)
)
USING DELTA
CLUSTER BY (experiment_id)
-- Deletion vectors speed row-level MERGE/UPDATE (SCD2 version closes, corrections).
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'ORDM Commerce Media Networks incrementality experiment design dimension (SCD2).';

-- Table classification (machine-checkable layer/role): TAGS-DATA-TYPE
ALTER TABLE ${catalog}.${cmn_schema}.experiment SET TAGS ('dbx_data_type' = 'master');
