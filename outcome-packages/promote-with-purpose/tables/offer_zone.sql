-- ============================================================
-- ORDM · Outcome Package · Promote with Purpose
-- Table: offer_zone
-- Layer: outcome package (silver / dimension, SCD2)
-- Version: 0.5
-- Generated: 2026-07-27
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-27
-- ============================================================
-- A defined location zone an offer can be attached to. Location is modeled ONLY
-- as membership in a named zone — never raw coordinates, device identifiers, or
-- customer location trails. The zone centroid is stored as a coarse 7-char
-- geohash (~150 m) that is the privacy floor by design. Current-state SCD2
-- dimension (effective_from_date / effective_to_date / is_current).
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${promo_schema}.offer_zone (
  zone_sk               BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  zone_id               STRING NOT NULL
                          COMMENT 'Durable natural/business key for the zone.',

  store_id              STRING COMMENT 'Durable store business key this zone is anchored to (logical reference to store.store_id).',

  zone_type             STRING COMMENT 'Zone geometry kind. Common values: store_radius, polygon, beacon, mall_common_area (enum enforced in relationships.sql).',
  radius_m              INT COMMENT 'Radius in metres for a store_radius zone; NULL for non-radial zones. When present, must be > 0.',
  centroid_geohash7     STRING COMMENT '7-character geohash of the zone centroid (~150 m cell). Coarse BY DESIGN — the privacy floor; never a precise coordinate.',

  -- SCD2 versioning (principle #8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version.',

  -- Audit / provenance (standard block; all timestamps UTC)
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded into the canonical core (UTC, ISO 8601).',

  CONSTRAINT pk_offer_zone PRIMARY KEY (zone_sk)
)
USING DELTA
CLUSTER BY (store_id, zone_type)
-- Deletion vectors speed row-level MERGE/UPDATE (SCD2 version closes, corrections).
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Defined location zones (membership only; coarse geohash centroid) for the Location-Based Offers use case.';

-- Table classification (machine-checkable layer/role): TAGS-DATA-TYPE
ALTER TABLE ${catalog}.${promo_schema}.offer_zone SET TAGS ('dbx_data_type' = 'master');
