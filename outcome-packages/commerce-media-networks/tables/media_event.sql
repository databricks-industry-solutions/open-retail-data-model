-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- Table: media_event
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- Append-only, one row per measurable ad-delivery or engagement event. The
-- conformed spine that absorbs impression / viewable impression / click /
-- ad_play / video events across sponsored-products, in-store-digital-ads,
-- media-measurement, and incrementality exposures (event_type discriminates;
-- click is NOT a separate table). A click links to its served impression via
-- parent_media_event_sk so CTR / IAB click-to-valid-impression survives.
--
-- Person-level and privacy-tiered: identifiers are HASHED (customer_key_hash /
-- household_key_hash, PII-tagged + masked); profile_sk/profile_id resolve to the
-- governed customer dimension for internal use. Consent is carried per row.
-- MRC/IAB measurement: viewable_flag (display 50%/1s, video 50%/2s), ivt_flag +
-- ivt_type (GIVT/SIVT). Nullable experiment_sk/experiment_cell_sk fold
-- incrementality exposures onto this spine.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${cmn_schema}.media_event (
  media_event_sk        BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  media_event_id        STRING NOT NULL
                          COMMENT 'Durable natural/business key for the media event.',

  -- Delivery dimensions (retail-media, commerce-media-networks gold) — nullable _sk + durable _id pairs
  campaign_sk           BIGINT COMMENT 'FK to cmn.campaign.campaign_sk.',
  campaign_id           STRING COMMENT 'Durable campaign business key.',
  ad_group_sk           BIGINT COMMENT 'FK to cmn.ad_group.ad_group_sk.',
  ad_group_id           STRING COMMENT 'Durable ad group business key.',
  creative_sk           BIGINT COMMENT 'FK to cmn.creative.creative_sk.',
  creative_id           STRING COMMENT 'Durable creative business key.',
  placement_sk          BIGINT COMMENT 'FK to cmn.placement.placement_sk.',
  placement_id          STRING COMMENT 'Durable placement business key.',

  -- Retail dimensions (canonical core)
  product_sk            BIGINT COMMENT 'FK to product.product_sk (the advertised/served product), if applicable.',
  product_id            STRING COMMENT 'Durable product business key.',
  store_sk              BIGINT COMMENT 'FK to store.store_sk (in-store playout location), if applicable.',
  store_id              STRING COMMENT 'Durable store business key.',
  profile_sk            BIGINT COMMENT 'FK to customer.profile.profile_sk (the resolved exposed customer), if known.',
  profile_id            STRING COMMENT 'Durable customer business key (pseudonymous).',

  -- Conformed delivery-channel dimension (CMN gold, ADR 0021) + audience dimension (shared marketing silver, ADR 0022)
  delivery_channel_sk    BIGINT COMMENT 'FK to cmn.delivery_channel.delivery_channel_sk (coarse channel the exposure occurred in).',
  delivery_channel_id    STRING COMMENT 'Durable delivery-channel business key.',
  audience_sk           BIGINT COMMENT 'FK to marketing.audience.audience_sk (targeted segment from shared marketing dimension), if audience-targeted.',
  audience_id           STRING COMMENT 'Durable audience business key.',

  -- Search targeting (nullable — set only for search / sponsored-products events)
  keyword_sk            BIGINT COMMENT 'FK to cmn.keyword.keyword_sk (the bid keyword this search event matched), if a search event.',
  keyword_id            STRING COMMENT 'Durable keyword business key.',
  search_term_text      STRING COMMENT 'Raw shopper search query for query-level reporting (degenerate attribute; vendor-neutral, no PII).',

  -- Incrementality (nullable — set only for experiment-assigned exposures)
  experiment_sk         BIGINT COMMENT 'FK to cmn.experiment.experiment_sk if this event is under an experiment.',
  experiment_id         STRING COMMENT 'Durable experiment business key.',
  experiment_cell_sk    BIGINT COMMENT 'FK to cmn.experiment_cell.experiment_cell_sk (treatment/control), if assigned.',
  experiment_cell_id    STRING COMMENT 'Durable experiment cell business key.',

  -- Self-reference: a click points to the impression it resolved from
  parent_media_event_sk BIGINT COMMENT 'FK to media_event.media_event_sk — the served impression a click resolved from.',
  parent_media_event_id STRING COMMENT 'Durable business key of the parent served impression.',

  event_type            STRING NOT NULL COMMENT 'Event type. Allowed values: impression, viewable_impression, click, ad_play, video_start, video_complete.',
  event_ts              TIMESTAMP NOT NULL COMMENT 'When the event occurred at source (UTC, ISO 8601).',
  event_date            DATE NOT NULL COMMENT 'Business date of the event (partition/cluster key).',
  cost_amount           DECIMAL(18,2) COMMENT 'Media cost of this event, in the reporting/base currency.',
  currency_code         STRING COMMENT 'Cost currency, ISO 4217 alpha-3 (single reporting currency).',
  duration_sec          INT COMMENT 'Play/view duration in seconds for time-based events (NULL otherwise).',

  -- MRC / IAB measurement
  viewable_flag         BOOLEAN COMMENT 'TRUE if the impression met the viewability standard (display 50%/1s, video 50%/2s).',
  ivt_flag              BOOLEAN COMMENT 'TRUE if classified as invalid traffic.',
  ivt_type              STRING COMMENT 'Invalid-traffic class. Allowed values: none, givt, sivt.',
  click_resolved_flag   BOOLEAN COMMENT 'For clicks: TRUE if resolved to a valid served impression.',

  -- Person-level identifiers (pseudonymized / PII) + consent
  customer_key_hash     STRING COMMENT 'Hashed/tokenized customer identifier for clean-room matching (PII, never raw).',
  household_key_hash     STRING COMMENT 'Hashed/tokenized household identifier (PII, never raw).',
  consent_status        STRING COMMENT 'Consent state for measurement at event time. Allowed values: granted, denied, unknown.',

  -- Audit / provenance (append-only fact block; all timestamps UTC)
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_media_event PRIMARY KEY (media_event_sk)
)
USING DELTA
CLUSTER BY (campaign_id, event_date)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Commerce Media Networks — conformed retail-media delivery/engagement event fact (append-only).';

ALTER TABLE ${catalog}.${cmn_schema}.media_event SET TAGS ('dbx_data_type' = 'transactional');

-- PII column classification (principle #11) — hashed identifiers.
ALTER TABLE ${catalog}.${cmn_schema}.media_event ALTER COLUMN customer_key_hash  SET TAGS ('dbx_pii_identifier' = 'true');
ALTER TABLE ${catalog}.${cmn_schema}.media_event ALTER COLUMN household_key_hash SET TAGS ('dbx_pii_identifier' = 'true');
