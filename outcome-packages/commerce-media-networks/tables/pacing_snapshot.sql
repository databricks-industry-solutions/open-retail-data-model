-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- Table: pacing_snapshot
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- Append-only, one row per pacing snapshot at snapshot_ts × campaign × ad_group
-- × placement. The operational STATE that paces against budget_allocation.
-- Conforms CPRM pacing_snapshot + SP g_rm_budget_pacing_snapshot (taking the
-- finer CPRM grain with nullable ad_group/placement). Not person-level; an ideal
-- Lakebase serving projection in a real deployment.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${cmn_schema}.pacing_snapshot (
  pacing_snapshot_sk    BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  pacing_snapshot_id    STRING NOT NULL
                          COMMENT 'Durable natural/business key for the snapshot.',

  campaign_sk           BIGINT COMMENT 'FK to cmn.campaign.campaign_sk.',
  campaign_id           STRING COMMENT 'Durable campaign business key.',
  ad_group_sk           BIGINT COMMENT 'FK to cmn.ad_group.ad_group_sk (or NULL at campaign level).',
  ad_group_id           STRING COMMENT 'Durable ad group business key.',
  placement_sk          BIGINT COMMENT 'FK to cmn.placement.placement_sk (or NULL).',
  placement_id          STRING COMMENT 'Durable placement business key.',

  snapshot_ts           TIMESTAMP NOT NULL COMMENT 'When the pacing state was captured (UTC, ISO 8601).',
  snapshot_date         DATE NOT NULL COMMENT 'Business date of the snapshot (cluster key).',
  daily_budget          DECIMAL(18,2) COMMENT 'Daily budget target, in the reporting/base currency.',
  planned_spend_to_date DECIMAL(18,2) COMMENT 'Planned cumulative spend to date, in the reporting/base currency.',
  actual_spend_to_date  DECIMAL(18,2) COMMENT 'Actual cumulative spend to date, in the reporting/base currency.',
  expected_spend_to_date DECIMAL(18,2) COMMENT 'Expected cumulative spend to date under the pacing curve.',
  projected_end_spend   DECIMAL(18,2) COMMENT 'Projected total spend at window end, in the reporting/base currency.',
  currency_code         STRING COMMENT 'Amount currency, ISO 4217 alpha-3 (single reporting currency).',
  pacing_ratio          DECIMAL(9,4) COMMENT 'actual_spend_to_date / planned_spend_to_date.',
  pacing_status         STRING COMMENT 'Pacing state. Allowed values: on_track, under_pacing, over_pacing, exhausted.',

  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_pacing_snapshot PRIMARY KEY (pacing_snapshot_sk)
)
USING DELTA
CLUSTER BY (snapshot_date, campaign_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Commerce Media Networks — budget pacing snapshot fact (append-only operational state).';

ALTER TABLE ${catalog}.${cmn_schema}.pacing_snapshot SET TAGS ('dbx_data_type' = 'transactional');
