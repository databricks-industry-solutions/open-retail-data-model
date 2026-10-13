-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- Table: placement
-- Layer: outcome package (gold dimension)
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- The retail-media PLACEMENT dimension (SCD2): a sellable ad surface /
-- inventory package. Adopts CPRM's dim_inventory_placement superset (which
-- spans onsite/offsite/in-store/sponsored/loyalty) and folds in SP's thin slot
-- definition and MM's inline placement attributes.
--
-- Grain: one current version per placement (sellable surface). Standalone
-- inventory catalog — a campaign BUYS placements (that link is a fact in the
-- outcome packages), so placement does not FK to campaign.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${cmn_schema}.placement (
  placement_sk          BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version; the join/FK target.',
  placement_id          STRING NOT NULL
                          COMMENT 'Durable natural/business key for the placement.',

  placement_name        STRING COMMENT 'Human-readable placement / inventory-package name.',
  media_platform        STRING COMMENT 'Buying platform or ad network — the RMN tech platform such as Criteo or CitrusAd, or an offsite DSP such as DV360 or The Trade Desk. Coined qualified name; no IAB standard.',
  ad_product_line       STRING COMMENT 'Retailer go-to-market ad-product packaging / inventory line, cf. common retail-media ad-product taxonomies. Distinct from delivery_channel (where it rendered), media_platform (where bought), and device_type. Allowed values: sponsored_products, onsite_display, offsite_display, email, loyalty.',
  placement_type        STRING COMMENT 'Fine on-page ad surface / slot (IAB Ad Placement). Allowed values: search, banner, product_listing, video, audio, endcap, shelf, other.',
  ad_format             STRING COMMENT 'Accepted ad format. Allowed values: display, video, audio, native, sponsored_product, text.',
  pricing_model         STRING COMMENT 'How the surface is priced. Allowed values: cpc, cpm, cpa, flat, other.',
  device_type           STRING COMMENT 'Device platform (OS/hardware) the surface targets. Allowed values: desktop, mobile, tablet, ctv, other. DOOH and in-store surfaces live on delivery_channel, not here.',
  store_scope           STRING COMMENT 'Store reach of the surface. Allowed values: all_stores, banner, region, single_store, online.',
  sellable_capacity_qty INT    COMMENT 'Sellable capacity for the surface, expressed in capacity_unit.',
  capacity_unit         STRING COMMENT 'Unit of sellable_capacity_qty. Allowed values: impressions, slots, seconds, sov_pct.',
  page_or_zone_code     STRING COMMENT 'Page location or in-store zone code the surface maps to (external natural code).',

  -- SCD2 versioning (principle #8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version of this placement.',

  -- Audit / provenance (standard block; all timestamps UTC)
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_placement PRIMARY KEY (placement_sk)
)
USING DELTA
CLUSTER BY (placement_id)
-- Deletion vectors speed row-level MERGE/UPDATE (SCD2 version closes, corrections).
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'ORDM Commerce Media Networks retail-media placement / inventory-surface dimension (SCD2).';

-- Table classification (machine-checkable layer/role): TAGS-DATA-TYPE
ALTER TABLE ${catalog}.${cmn_schema}.placement SET TAGS ('dbx_data_type' = 'master');
