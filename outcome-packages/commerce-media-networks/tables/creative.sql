-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- Table: creative
-- Layer: outcome package (gold dimension)
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- The retail-media CREATIVE dimension (SCD2): the ad asset. Conforms the ISDA
-- (physical-asset focus: mime/duration/aspect) and CPRM (approval workflow +
-- product lineage) designs into one dim with both blocks. SP has no creative
-- (the sponsored SKU is the ad).
--
-- Grain: one current version per creative. FKs into cmn.campaign. A creative
-- can run in multiple ad groups / promote multiple products, so those links are
-- many-to-many bridges in the outcome packages, not FKs on the dimension.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${cmn_schema}.creative (
  creative_sk           BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version; the join/FK target.',
  creative_id           STRING NOT NULL
                          COMMENT 'Durable natural/business key for the creative.',

  -- Parent campaign (cmn.campaign)
  campaign_sk           BIGINT COMMENT 'FK to campaign.campaign_sk (the campaign this creative belongs to).',
  campaign_id           STRING COMMENT 'Durable business key of the parent campaign (join on current campaign version).',

  creative_name         STRING COMMENT 'Human-readable creative name.',
  creative_type         STRING COMMENT 'Asset type. Allowed values: image, video, audio, html, native, text.',
  mime_type             STRING COMMENT 'MIME type of the asset (e.g. image/jpeg, video/mp4).',
  duration_seconds      INT    COMMENT 'Play duration in seconds for time-based assets (NULL for static).',
  aspect_ratio          STRING COMMENT 'Aspect ratio of the asset (e.g. 16:9, 1:1, 9:16).',
  language_code         STRING COMMENT 'Creative language, ISO 639-1 alpha-2.',
  approval_status       STRING COMMENT 'Review workflow state. Allowed values: draft, submitted, approved, rejected, archived.',
  brand_safety_class    STRING COMMENT 'Brand-safety classification. Allowed values: safe, moderate, restricted.',
  asset_uri             STRING COMMENT 'Reference/URI to the stored asset (not the asset itself).',

  -- SCD2 versioning (principle #8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version of this creative.',

  -- Audit / provenance (standard block; all timestamps UTC)
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_creative PRIMARY KEY (creative_sk)
)
USING DELTA
CLUSTER BY (creative_id)
-- Deletion vectors speed row-level MERGE/UPDATE (SCD2 version closes, corrections).
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'ORDM Commerce Media Networks retail-media creative dimension (SCD2).';

-- Table classification (machine-checkable layer/role): TAGS-DATA-TYPE
ALTER TABLE ${catalog}.${cmn_schema}.creative SET TAGS ('dbx_data_type' = 'master');
