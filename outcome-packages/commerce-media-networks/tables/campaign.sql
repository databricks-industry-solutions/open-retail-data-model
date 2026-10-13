-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- Table: campaign
-- Layer: outcome package (gold dimension)
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- The retail-media CAMPAIGN dimension (SCD2). One version per advertising
-- campaign — NOT a trade promotion (that is marketing.promotion). Conforms
-- the four briefs' campaign designs (SP g_rm_campaign, ISDA/CPRM/MM
-- dim_campaign): mandates a surrogate campaign_sk (SP's natural key is the
-- outlier), DATE flight grain, and one attribution scheme
-- (post-click/post-view windows + an attribution model).
--
-- Grain: one current version per campaign. FKs into cmn.advertiser
-- (the advertiser). The retail-media outcome packages add the FACTS
-- (impression, click, conversion, attributed-sale) that reference it; those
-- always carry a real campaign, so there is no NO_* reserved member here.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${cmn_schema}.campaign (
  campaign_sk           BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version; the join/FK target.',
  campaign_id           STRING NOT NULL
                          COMMENT 'Durable natural/business key for the campaign.',

  -- Advertiser (cmn.advertiser)
  advertiser_sk     BIGINT COMMENT 'FK to advertiser.advertiser_sk (the advertiser running the campaign).',
  advertiser_id     STRING COMMENT 'Durable business key of the advertiser (join on current advertiser version).',

  campaign_name         STRING COMMENT 'Human-readable campaign name.',
  objective             STRING COMMENT 'Primary campaign objective. Allowed values: awareness, consideration, conversion, loyalty, other.',
  campaign_status       STRING COMMENT 'Lifecycle status. Allowed values: draft, active, paused, completed, archived.',
  start_date            DATE   COMMENT 'Campaign flight start date, inclusive (ISO 8601).',
  end_date              DATE   COMMENT 'Campaign flight end date, inclusive (ISO 8601); NULL if open-ended.',
  budget_amount         DECIMAL(18,2) COMMENT 'Total campaign budget, in the reporting/base currency.',
  currency_code         STRING COMMENT 'Budget currency, ISO 4217 alpha-3.',
  buy_model             STRING COMMENT 'Pricing/buy model. Allowed values: cpc, cpm, cpa, flat, other.',
  attribution_model     STRING COMMENT 'Attribution model applied to conversions. Allowed values: last_touch, first_touch, linear, position_based, data_driven.',
  default_post_click_days INT  COMMENT 'Default post-click attribution window in days (click lookback).',
  default_post_view_days  INT  COMMENT 'Default post-view attribution window in days (view lookback).',
  sales_metric_type     STRING COMMENT 'Whether attributed sales are measured gross or net. Allowed values: gross, net.',
  supplier_visible_flag BOOLEAN COMMENT 'TRUE if this campaign is visible to the supplier/advertiser in shared reporting.',

  -- SCD2 versioning (principle #8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version of this campaign.',

  -- Audit / provenance (standard block; all timestamps UTC)
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_campaign PRIMARY KEY (campaign_sk)
)
USING DELTA
CLUSTER BY (campaign_id)
-- Deletion vectors speed row-level MERGE/UPDATE (SCD2 version closes, corrections).
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'ORDM Commerce Media Networks retail-media campaign dimension (SCD2). Conformed across the four retail-media briefs.';

-- Table classification (machine-checkable layer/role): TAGS-DATA-TYPE
ALTER TABLE ${catalog}.${cmn_schema}.campaign SET TAGS ('dbx_data_type' = 'master');
