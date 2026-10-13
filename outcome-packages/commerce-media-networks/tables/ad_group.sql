-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- Table: ad_group
-- Layer: outcome package (gold dimension)
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- The retail-media AD GROUP dimension (SCD2). A targeting/bidding unit within
-- a campaign. Conforms the SP (g_rm_ad_group) and CPRM (dim_ad_group) designs;
-- MM folds it into dim_delivery_context as attributes, ISDA has none.
--
-- Grain: one current version per ad group. FKs into cmn.campaign.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${cmn_schema}.ad_group (
  ad_group_sk           BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version; the join/FK target.',
  ad_group_id           STRING NOT NULL
                          COMMENT 'Durable natural/business key for the ad group.',

  -- Parent campaign (cmn.campaign)
  campaign_sk           BIGINT COMMENT 'FK to campaign.campaign_sk (the campaign this ad group belongs to).',
  campaign_id           STRING COMMENT 'Durable business key of the parent campaign (join on current campaign version).',

  -- Targeting audience (shared marketing dim, ADR 0022)
  audience_sk           BIGINT COMMENT 'FK to marketing.audience.audience_sk (the segment this ad group targets), if audience-targeted.',
  audience_id           STRING COMMENT 'Durable audience business key (join on current audience version).',

  ad_group_name         STRING COMMENT 'Human-readable ad group name.',
  ad_group_status       STRING COMMENT 'Lifecycle status. Allowed values: draft, active, paused, completed, archived.',
  targeting_mode        STRING COMMENT 'How the ad group targets. Allowed values: keyword, audience, automatic, contextual, manual.',
  bid_strategy          STRING COMMENT 'Bidding strategy. Allowed values: manual_cpc, auto, target_cpa, target_roas, max_conversions.',
  default_bid_amount    DECIMAL(18,2) COMMENT 'Default bid, in the reporting/base currency.',
  currency_code         STRING COMMENT 'Bid currency, ISO 4217 alpha-3.',
  optimization_goal     STRING COMMENT 'What the ad group optimizes for. Allowed values: clicks, conversions, roas, impressions, reach.',
  start_date            DATE   COMMENT 'Ad group start date, inclusive (ISO 8601).',
  end_date              DATE   COMMENT 'Ad group end date, inclusive (ISO 8601); NULL if open-ended.',

  -- SCD2 versioning (principle #8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version of this ad group.',

  -- Audit / provenance (standard block; all timestamps UTC)
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_ad_group PRIMARY KEY (ad_group_sk)
)
USING DELTA
CLUSTER BY (ad_group_id)
-- Deletion vectors speed row-level MERGE/UPDATE (SCD2 version closes, corrections).
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'ORDM Commerce Media Networks retail-media ad group dimension (SCD2).';

-- Table classification (machine-checkable layer/role): TAGS-DATA-TYPE
ALTER TABLE ${catalog}.${cmn_schema}.ad_group SET TAGS ('dbx_data_type' = 'master');
