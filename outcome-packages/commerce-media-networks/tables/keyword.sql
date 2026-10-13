-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- Table: keyword
-- Layer: outcome package (gold dimension)
-- Version: 0.5
-- Generated: 2026-07-14
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-14
-- ============================================================
-- The retail-media KEYWORD (search-targeting) dimension (SCD2): a bid keyword
-- an ad group targets on search/sponsored-products surfaces, so query-level
-- reporting (keyword -> impressions/clicks/spend/attributed sales) is possible.
-- Conforms SP dim_keyword; the RAW shopper query is a degenerate attribute on
-- media_event (search_term_text), not a second high-cardinality dimension.
-- Un-defers the keyword_target dim that ADR 0017 logged as a follow-up.
--
-- Grain: one current version per keyword. FKs into cmn.ad_group (its owner).
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${cmn_schema}.keyword (
  keyword_sk            BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version; the join/FK target.',
  keyword_id            STRING NOT NULL
                          COMMENT 'Durable natural/business key for the keyword.',

  -- Parent ad group (cmn.ad_group)
  ad_group_sk           BIGINT COMMENT 'FK to ad_group.ad_group_sk (the ad group this keyword belongs to).',
  ad_group_id           STRING COMMENT 'Durable business key of the parent ad group (join on current ad_group version).',

  keyword_text          STRING COMMENT 'The bid keyword / targeting term (vendor-neutral; not a shopper PII value).',
  match_type            STRING COMMENT 'How the keyword matches queries. Allowed values: exact, phrase, broad, negative.',
  keyword_status        STRING COMMENT 'Lifecycle status. Allowed values: active, paused, archived.',
  is_negative_flag      BOOLEAN COMMENT 'TRUE for a negative keyword (excludes matching queries rather than bidding on them).',
  bid_amount            DECIMAL(18,2) COMMENT 'Keyword-level bid, in the reporting/base currency.',
  currency_code         STRING COMMENT 'Bid currency, ISO 4217 alpha-3.',

  -- SCD2 versioning (principle #8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version of this keyword.',

  -- Audit / provenance (standard block; all timestamps UTC)
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_keyword PRIMARY KEY (keyword_sk)
)
USING DELTA
CLUSTER BY (keyword_id)
-- Deletion vectors speed row-level MERGE/UPDATE (SCD2 version closes, corrections).
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'ORDM Commerce Media Networks retail-media keyword (search-targeting) dimension (SCD2).';

-- Table classification (machine-checkable layer/role): TAGS-DATA-TYPE
ALTER TABLE ${catalog}.${cmn_schema}.keyword SET TAGS ('dbx_data_type' = 'master');
