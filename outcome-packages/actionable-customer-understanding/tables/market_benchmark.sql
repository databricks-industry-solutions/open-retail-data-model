-- ============================================================
-- ORDM · Outcome Package · Actionable Customer Understanding
-- Table: market_benchmark
-- Layer: outcome package (append-only licensed aggregate)
-- Version: 0.5
-- Generated: 2026-08-24
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-24 by @saurabhshukla-db
-- License: see repository LICENSE.md
-- ============================================================
-- Grain: one delivered version of a provider-defined benchmark cell. The stable
-- benchmark_cell_id identifies the logical cell across restatements; each delivered
-- version has its own record_source|source_observation_id identity and is never updated.
-- Licensed rows are internal-use-only by default and excluded from sharing surfaces.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${acu_schema}.market_benchmark (
  market_benchmark_sk          BIGINT GENERATED ALWAYS AS IDENTITY
                                COMMENT 'Surrogate key for this delivered cell version.',
  market_benchmark_id          STRING NOT NULL
                                COMMENT 'Durable delivered-version key: record_source|source_observation_id.',
  source_observation_id        STRING NOT NULL COMMENT 'Source-system identity of this delivered cell version.',
  benchmark_cell_id            STRING NOT NULL COMMENT 'Stable logical-cell identity: record_source|market_definition|geography_level|geography_code|category_ref|subject_type|subject_id-or-TOTAL|period_type|period_end_date. An adopter category remap intentionally creates a new cell; see ADR 0042.',

  competitor_sk                BIGINT COMMENT 'Nullable competitor SCD2 version retained as lineage, not a cross-package FK.',
  competitor_id                STRING COMMENT 'Nullable durable competitor key and logical relationship to the BMV-owned dimension.',
  market_definition            STRING NOT NULL COMMENT 'Provider-defined measured market/store universe, preserved verbatim.',
  geography_level              STRING NOT NULL COMMENT 'Geography grain: total, region, market, key_account, or account_market.',
  geography_code               STRING NOT NULL COMMENT 'Provider or adopter geography identifier at geography_level.',
  category_ref                 STRING NOT NULL COMMENT 'Adopter-owned mapping to the own merchandising category hierarchy.',
  subject_type                 STRING NOT NULL COMMENT 'Cell subject: own_banner, competitor_banner, brand, private_label, or total_category.',
  subject_id                   STRING COMMENT 'Subject identifier in the provider namespace; NULL only for total_category.',
  period_type                  STRING NOT NULL COMMENT 'Provider period type: week, quad_week, 13_week, or 52_week.',
  period_end_date              DATE NOT NULL COMMENT 'Provider period end date; never relabeled as an own fiscal week.',

  sales_amount                 DECIMAL(18,2) COMMENT 'Measured sales amount in reporting currency.',
  unit_volume                  DECIMAL(18,2) COMMENT 'Measured unit volume for the benchmark cell.',
  market_share_pct             DECIMAL(7,4) COMMENT 'Provider-reported market share percentage, from 0 through 100.',
  market_growth_rate_pct       DECIMAL(7,4) COMMENT 'Provider-reported market growth percentage; never recomputed across restatements.',
  eq_volume                    DECIMAL(18,2) COMMENT 'Optional equivalized volume supplied by the provider.',
  acv_weighted_distribution_pct DECIMAL(7,4) COMMENT 'Optional importance-weighted distribution percentage.',
  numeric_distribution_pct     DECIMAL(7,4) COMMENT 'Optional outlet-count-weighted distribution percentage.',
  tdp                          DECIMAL(18,4) COMMENT 'Optional total distribution points.',
  promo_sales_amount           DECIMAL(18,2) COMMENT 'Optional sales amount attributed to promotional conditions.',
  base_sales_amount            DECIMAL(18,2) COMMENT 'Optional sales amount attributed to base conditions.',
  currency_code                STRING NOT NULL COMMENT 'ISO 4217 reporting/base currency for monetary measures.',

  is_restatement               BOOLEAN NOT NULL COMMENT 'TRUE when this delivered version revises an earlier logical cell.',
  restates_market_benchmark_id STRING COMMENT 'Delivered-version key superseded by this restatement, when supplied.',
  observed_at_ts               TIMESTAMP NOT NULL COMMENT 'Timestamp the provider observed or published this delivered cell version.',
  provider_updated_at_ts       TIMESTAMP COMMENT 'Provider update timestamp used before observed/load time in latest-wins ordering.',
  raw_data_uri                 STRING COMMENT 'Optional governed pointer to the licensed delivery evidence.',
  record_source                STRING NOT NULL COMMENT 'Licensed provider/source-system identifier and version namespace.',
  load_timestamp               TIMESTAMP NOT NULL COMMENT 'Timestamp this delivered version was loaded into the lakehouse.',

  CONSTRAINT pk_market_benchmark PRIMARY KEY (market_benchmark_sk)
)
USING DELTA
CLUSTER BY (period_end_date, category_ref, benchmark_cell_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Append-only market benchmark cell versions. License terms are adopter-owned; redistribution is disabled by default.';

ALTER TABLE ${catalog}.${acu_schema}.market_benchmark
  SET TAGS ('dbx_data_type' = 'transactional');
