-- ============================================================
-- ORDM · Outcome Package · Actionable Customer Understanding
-- Table: competitor_assortment
-- Layer: outcome package (append-only observation fact)
-- Version: 0.5
-- Generated: 2026-08-24
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-24 by @saurabhshukla-db
-- License: see repository LICENSE.md
-- ============================================================
-- Grain: one source observation of a competitor item listing/availability state.
-- Unmatched competitor items remain first-class observations; source-event identity
-- is independent of any later Type-1 product-match update.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${acu_schema}.competitor_assortment (
  competitor_assortment_sk BIGINT GENERATED ALWAYS AS IDENTITY
                             COMMENT 'Surrogate key for this append-only observation.',
  competitor_assortment_id STRING NOT NULL
                             COMMENT 'Durable observation key: record_source|source_observation_id; independent of mutable product matching.',
  source_observation_id    STRING NOT NULL COMMENT 'Source-system identity of the delivered listing observation. The synthetic recipe is ASSORT|competitor_id|competitor_item_ref|competitor_location_ref|channel_code|date.',

  competitor_sk            BIGINT NOT NULL COMMENT 'Competitor SCD2 version resolved at observation time; retained as lineage, not a cross-package FK.',
  competitor_id            STRING NOT NULL COMMENT 'Durable competitor business key and logical relationship to the BMV-owned competitor dimension.',
  competitor_item_ref      STRING NOT NULL COMMENT 'Source item identity; retained even when the item is unmatched.',
  product_sk               BIGINT COMMENT 'FK to the own-product SCD2 version matched at observation time; NULL when unmatched.',
  product_id               STRING COMMENT 'Durable own-product key captured with the match snapshot; NULL when unmatched.',
  category_ref             STRING NOT NULL COMMENT 'Own merchandising category attribution captured with the observation.',
  match_type               STRING COMMENT 'Match snapshot: exact, equivalent, or similar; NULL when unmatched.',
  match_method             STRING COMMENT 'Match snapshot method: gtin, mpn_brand, ai_text, ai_image, or manual.',
  match_confidence         DECIMAL(5,4) COMMENT 'Match confidence captured with the observation, from 0 through 1.',

  competitor_location_ref STRING NOT NULL COMMENT 'Competitor location reference. National v1 observations use the sentinel ALL.',
  channel_code             STRING NOT NULL COMMENT 'Observation channel: online, in_store, marketplace, or other.',
  date_key                 DATE NOT NULL COMMENT 'Logical observation date; logical FK to fiscal_calendar.date_key.',
  observed_at_ts           TIMESTAMP NOT NULL COMMENT 'Exact source observation timestamp in UTC.',
  is_listed                BOOLEAN NOT NULL COMMENT 'TRUE when the item was listed at the observed point.',
  is_available             BOOLEAN COMMENT 'Availability state when observable; NULL distinguishes unknown from unavailable.',
  search_rank              INT COMMENT 'Observed search-result rank when supplied; NULL outside digital-shelf sources.',
  marketplace_seller      STRING COMMENT 'Seller reference for marketplace observations; NULL for first-party channels.',
  data_source              STRING NOT NULL COMMENT 'Vendor-neutral acquisition family such as crawl, digital_shelf, or syndicated.',
  raw_data_uri             STRING COMMENT 'Optional pointer to governed source evidence; access remains adopter-controlled.',

  record_source            STRING NOT NULL COMMENT 'Originating source-system identifier and observation-id namespace.',
  load_timestamp           TIMESTAMP NOT NULL COMMENT 'Timestamp this observation was loaded into the lakehouse.',

  CONSTRAINT pk_competitor_assortment PRIMARY KEY (competitor_assortment_sk)
)
USING DELTA
CLUSTER BY (date_key, competitor_sk)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Append-only competitor listing and availability observations, including sparse and unmatched source items.';

ALTER TABLE ${catalog}.${acu_schema}.competitor_assortment
  SET TAGS ('dbx_data_type' = 'transactional');
