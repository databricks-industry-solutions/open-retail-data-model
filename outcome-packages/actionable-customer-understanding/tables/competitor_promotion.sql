-- ============================================================
-- ORDM · Outcome Package · Actionable Customer Understanding
-- Table: competitor_promotion
-- Layer: outcome package (append-only observation fact)
-- Version: 0.5
-- Generated: 2026-08-24
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-24 by @saurabhshukla-db
-- License: see repository LICENSE.md
-- ============================================================
-- Grain: one source observation of a competitor promotion. Source-event identity
-- is record_source|source_observation_id and never changes when product matching
-- changes. Product and match fields are the snapshot known at observation time.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${acu_schema}.competitor_promotion (
  competitor_promotion_sk BIGINT GENERATED ALWAYS AS IDENTITY
                            COMMENT 'Surrogate key for this append-only observation.',
  competitor_promotion_id STRING NOT NULL
                            COMMENT 'Durable observation key: record_source|source_observation_id; independent of mutable product matching.',
  source_observation_id   STRING NOT NULL
                            COMMENT 'Source-system identity of the delivered promotion observation. The synthetic recipe is PROMO|competitor_id|competitor_item_ref|competitor_location_ref|promo_vehicle|date.',

  competitor_sk           BIGINT NOT NULL COMMENT 'Competitor SCD2 version resolved at observation time; retained as lineage, not a cross-package FK.',
  competitor_id           STRING NOT NULL COMMENT 'Durable competitor business key and logical relationship to the BMV-owned competitor dimension.',
  competitor_item_ref     STRING COMMENT 'Source item reference when the promotion is item-level; NULL for category-only placements.',
  product_sk              BIGINT COMMENT 'FK to the own-product SCD2 version matched at observation time; NULL when unmatched or category-only.',
  product_id              STRING COMMENT 'Durable own-product key captured with the match snapshot; NULL when unmatched or category-only.',
  category_ref            STRING NOT NULL COMMENT 'Own merchandising category attribution captured with the observation.',
  match_type              STRING COMMENT 'Match snapshot: exact, equivalent, or similar; NULL when no item match applies.',
  match_method            STRING COMMENT 'Match snapshot method: gtin, mpn_brand, ai_text, ai_image, or manual.',
  match_confidence        DECIMAL(5,4) COMMENT 'Match confidence captured with the observation, from 0 through 1.',

  competitor_location_ref STRING NOT NULL COMMENT 'Competitor location reference. National v1 observations use the sentinel ALL.',
  channel_code            STRING NOT NULL COMMENT 'Observation channel: online, in_store, marketplace, or other.',
  promo_vehicle           STRING NOT NULL COMMENT 'Observed vehicle: circular_print, circular_digital, onsite, in_store, email_app, or other.',
  promo_type              STRING NOT NULL COMMENT 'Observed mechanic: TPR, FEATURE, DISPLAY, FEATURE_AND_DISPLAY, BOGO, COUPON, or BUNDLE.',
  promo_price             DECIMAL(18,4) COMMENT 'Observed promotional unit price in reporting currency.',
  regular_price           DECIMAL(18,4) COMMENT 'Observed regular unit price in reporting currency.',
  discount_depth_pct      DECIMAL(5,2) COMMENT 'Observed or ingest-derived discount depth percentage, from 0 through 100.',
  promo_start_date        DATE COMMENT 'Displayed promotion start date, inclusive; NULL when the source does not show a window.',
  promo_end_date          DATE COMMENT 'Displayed promotion end date, inclusive; NULL when the source does not show a window.',
  date_key                DATE NOT NULL COMMENT 'Logical observation date; logical FK to fiscal_calendar.date_key.',
  observed_at_ts          TIMESTAMP NOT NULL COMMENT 'Exact source observation timestamp in UTC.',
  placement_rank          INT COMMENT 'Placement order within the observed vehicle, when supplied.',
  is_front_page           BOOLEAN COMMENT 'TRUE when a circular placement was on the front page; NULL for other sources.',
  currency_code           STRING NOT NULL COMMENT 'ISO 4217 reporting/base currency for normalized monetary values.',
  transaction_currency_code STRING COMMENT 'ISO 4217 currency exactly as captured before normalization.',
  data_source             STRING NOT NULL COMMENT 'Vendor-neutral acquisition family such as crawl, circular_tracker, or syndicated.',
  raw_data_uri            STRING COMMENT 'Optional pointer to governed source evidence; access remains adopter-controlled.',

  record_source           STRING NOT NULL COMMENT 'Originating source-system identifier and observation-id namespace.',
  load_timestamp          TIMESTAMP NOT NULL COMMENT 'Timestamp this observation version was loaded into the lakehouse.',

  CONSTRAINT pk_competitor_promotion PRIMARY KEY (competitor_promotion_sk)
)
USING DELTA
CLUSTER BY (date_key, competitor_sk)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Append-only competitor promotion observations for human decision support; source events retain their point-in-time match snapshot.';

ALTER TABLE ${catalog}.${acu_schema}.competitor_promotion
  SET TAGS ('dbx_data_type' = 'transactional');
