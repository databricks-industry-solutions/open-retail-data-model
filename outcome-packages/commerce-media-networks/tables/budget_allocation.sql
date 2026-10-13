-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- Table: budget_allocation
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- Append-only, one row per budget allocation version per (campaign / ad_group /
-- placement) × budget window × allocation level. The PLAN / denominator that
-- pacing_snapshot paces against. Conforms CPRM budget_allocation.
-- Not person-level.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${cmn_schema}.budget_allocation (
  budget_allocation_sk  BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  budget_allocation_id  STRING NOT NULL
                          COMMENT 'Durable natural/business key for the allocation.',

  campaign_sk           BIGINT COMMENT 'FK to cmn.campaign.campaign_sk.',
  campaign_id           STRING COMMENT 'Durable campaign business key.',
  ad_group_sk           BIGINT COMMENT 'FK to cmn.ad_group.ad_group_sk (or NULL at campaign level).',
  ad_group_id           STRING COMMENT 'Durable ad group business key.',
  placement_sk          BIGINT COMMENT 'FK to cmn.placement.placement_sk (or NULL).',
  placement_id          STRING COMMENT 'Durable placement business key.',
  advertiser_sk     BIGINT COMMENT 'FK to cmn.advertiser.advertiser_sk.',
  advertiser_id     STRING COMMENT 'Durable advertiser business key.',

  allocation_level      STRING COMMENT 'Level of the allocation. Allowed values: campaign, ad_group, placement.',
  budget_window_start   DATE COMMENT 'Budget window start date, inclusive (ISO 8601).',
  budget_window_end     DATE COMMENT 'Budget window end date, inclusive (ISO 8601).',
  allocated_budget_amount DECIMAL(18,2) COMMENT 'Allocated budget, in the reporting/base currency.',
  booked_budget_amount  DECIMAL(18,2) COMMENT 'Booked/committed budget, in the reporting/base currency.',
  currency_code         STRING COMMENT 'Amount currency, ISO 4217 alpha-3 (single reporting currency).',
  funding_source        STRING COMMENT 'Who funds the budget. Allowed values: supplier, retailer, shared, agency.',
  planned_impressions   BIGINT COMMENT 'Planned impressions for the window.',
  planned_clicks        BIGINT COMMENT 'Planned clicks for the window.',
  planned_sales_amount  DECIMAL(18,2) COMMENT 'Planned attributed sales, in the reporting/base currency.',
  pacing_method         STRING COMMENT 'Intended pacing method. Allowed values: even, asap, front_loaded, custom.',

  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_budget_allocation PRIMARY KEY (budget_allocation_sk)
)
USING DELTA
CLUSTER BY (campaign_id, budget_window_start)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Commerce Media Networks — budget allocation plan fact (append-only, versioned).';

ALTER TABLE ${catalog}.${cmn_schema}.budget_allocation SET TAGS ('dbx_data_type' = 'transactional');
