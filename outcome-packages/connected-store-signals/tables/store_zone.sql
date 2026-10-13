-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Table: store_zone
-- Layer: outcome package (gold / dimensional, master-tagged)
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-28
-- ============================================================
-- The conformed in-store sub-location dimension: a recursive
-- store -> zone -> aisle -> bay -> shelf_position hierarchy. Before this table,
-- in-store zone was a bare string (commerce-media-networks.store_zone_interval
-- .store_zone_code) with no identity, no area, and no capacity.
--
-- zone_type spans the FULL depth deliberately, even though the Foot Traffic build
-- only populates site/entrance/area rows: RFID Tracking and Smart Shelf need
-- bay/shelf_position, and widening a published enum later is a breaking change for
-- a table this central. Cost of the unused values today is zero.
--
-- master-tagged inside a gold package -- precedent
-- balancing-margin-and-volume/tables/competitor.sql. Legal because PK-CONTRACT and
-- FK-COMPLETENESS are canonical-core-only gates (standards/rules.yaml), and ADR 0021
-- established that single-outcome constructs belong in gold rather than silver.
-- Promotion to canonical-core silver is deferred until a genuine second outcome
-- consumes it (see ADR 0033 and the design note).
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${css_schema}.store_zone (
  store_zone_sk         BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version.',
  store_zone_id         STRING NOT NULL
                          COMMENT 'Durable natural/business key for the zone. Stable across SCD2 versions.',

  store_sk              BIGINT COMMENT 'FK to store.store_sk (SCD2 version current at load).',
  store_id              STRING COMMENT 'Durable store business key. Use this for SCD2-safe joins (ADR 0025).',

  zone_code             STRING COMMENT 'Zone code as emitted by the source system. Replaces the bare store_zone_code string the CMN fact carried.',
  zone_name             STRING COMMENT 'Human-readable zone name for display and Genie.',
  zone_type             STRING COMMENT 'Depth in the spatial hierarchy. Allowed values: site, entrance, area, department, aisle, bay, shelf_position, queue, fitting_room, perimeter, back_of_house.',

  -- Recursive self-reference. Resolved on the DURABLE id, not the _sk, so a parent
  -- re-version does not orphan children (see sz_parent_resolves_current in checks.sql).
  parent_zone_sk        BIGINT COMMENT 'FK to store_zone.store_zone_sk -- the containing zone. NULL for the site row.',
  parent_zone_id        STRING COMMENT 'Durable id of the containing zone. The SCD2-safe join key; prefer this over parent_zone_sk.',
  hierarchy_depth       INT    COMMENT 'Materialised depth (0 = site). Avoids a recursive CTE in every consumer.',
  hierarchy_path        STRING COMMENT 'Materialised ancestry path, e.g. /site/area-grocery/aisle-07. Denormalised for filtering.',

  area_sqm              DECIMAL(12,2) COMMENT 'Zone floor area in square metres. Denominator for traffic and occupancy density.',
  capacity_persons      INT    COMMENT 'Safe/design occupancy in persons, where known. Used to warn on implausible occupancy, never to clamp it.',
  is_sales_floor        BOOLEAN COMMENT 'TRUE if the zone is customer-accessible selling space. FALSE for back-of-house.',
  is_countable          BOOLEAN COMMENT 'TRUE if this zone is instrumented for people counting. FALSE zones exist for spatial structure only.',

  -- SCD2 versioning (principle #8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version.',

  -- Audit / provenance
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_store_zone PRIMARY KEY (store_zone_sk)
)
USING DELTA
CLUSTER BY (store_zone_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Connected Store Signals -- conformed in-store zone dimension (SCD2), recursive store->zone->aisle->bay->shelf_position.';

ALTER TABLE ${catalog}.${css_schema}.store_zone SET TAGS ('dbx_data_type' = 'master');
