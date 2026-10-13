-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- Table: delivery_channel
-- Layer: outcome package (gold reference dimension)
-- Version: 0.5
-- Generated: 2026-07-14
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-14
-- ============================================================
-- Conformed DELIVERY CHANNEL reference dimension: the coarse distribution channel
-- / delivery environment an ad exposure occurs in (onsite web/app, offsite,
-- in-store screen/audio, DOOH). This is IAB AdCOM/OpenRTB's distribution-channel
-- axis (Site / App / DOOH) crossed with the onsite/offsite/in-store environment —
-- NOT the buying platform (media_platform), NOT the device (device_type), and NOT
-- the fine on-page slot (placement.placement_type). A small, static lookup
-- (Type 1; no SCD). Renamed from `channel` (four-axis untangle) because a bare
-- channel is overloaded; IAB/Criteo/AMC all qualify these axes.
--
-- Grain: one row per delivery-channel code.
--
-- Key: deliberately keyed on a minted `delivery_channel_sk` IDENTITY (not the natural
-- `delivery_channel_id` code), a conscious deviation from §D's reference/code-table
-- convention. Rationale: it keeps the fact-side FK shape uniform (`<dim>_sk` + `<dim>_id`
-- everywhere) — the package values that uniformity over saving a surrogate on a 7-row lookup.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${cmn_schema}.delivery_channel (
  delivery_channel_sk   BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  delivery_channel_id   STRING NOT NULL
                          COMMENT 'Durable business key / delivery-channel code (e.g., onsite_app, in_store_screen).',

  delivery_channel_name STRING COMMENT 'Human-readable delivery-channel / environment label.',
  delivery_channel_category STRING COMMENT 'Coarse distribution/delivery-channel class. Allowed values: onsite_web, onsite_app, offsite, in_store_screen, in_store_audio, dooh, other.',
  is_in_store_flag      BOOLEAN COMMENT 'TRUE for in-store channels (screens, audio); FALSE for online/offsite channels.',

  -- Audit / provenance (standard block; required on reference tables, standard §8)
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_delivery_channel PRIMARY KEY (delivery_channel_sk)
)
USING DELTA
CLUSTER BY (delivery_channel_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'ORDM Commerce Media Networks conformed delivery-channel reference dimension (Type 1). The coarse distribution channel / environment, distinct from media_platform, device_type, and the fine placement slot.';

-- Table classification (machine-checkable layer/role): TAGS-DATA-TYPE
ALTER TABLE ${catalog}.${cmn_schema}.delivery_channel SET TAGS ('dbx_data_type' = 'reference');
