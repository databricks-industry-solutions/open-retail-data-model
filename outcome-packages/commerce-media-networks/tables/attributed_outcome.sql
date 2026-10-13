-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- Table: attributed_outcome
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- Append-only, one row per attributed conversion/order-line × attribution model
-- × window × credited touchpoint. The conformed attribution fact deduping four
-- brief designs (SP g_rm_attributed_sale, MM attributed_outcome, INCR
-- fact_attributed_sale, CPRM fact_measurement_attribution_restricted). Links the
-- crediting touchpoint (touch_media_event_sk) to the conversion
-- (conversion_event_sk). attributed_fraction supports multi-touch splits.
--
-- Attribution auditability is first-class: same_sku vs halo, new-to-brand,
-- click-or-view basis, and the declared post_click/post_view windows travel with
-- every row. gross AND net are separate (never one opaque metric). Person-level,
-- privacy-tiered (hashed key + consent). Nullable experiment link.
--
-- Additivity contract: attribution_model is part of the grain, so amounts are only
-- additive WITHIN a single attribution_model filter — SUM(...) across the whole
-- table multi-counts one conversion across models. gross/net/margin amounts are the
-- credited value already apportioned by attributed_fraction, so per-conversion
-- fractions sum to <= 1 under one model (enforced by DQ check fao_fraction_sum).
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${cmn_schema}.attributed_outcome (
  attributed_outcome_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  attributed_outcome_id STRING NOT NULL
                          COMMENT 'Durable natural/business key for the attributed outcome.',

  -- Credited delivery + advertiser (retail-media, commerce-media-networks gold)
  campaign_sk           BIGINT COMMENT 'FK to cmn.campaign.campaign_sk (credited campaign).',
  campaign_id           STRING COMMENT 'Durable campaign business key.',
  ad_group_sk           BIGINT COMMENT 'FK to cmn.ad_group.ad_group_sk.',
  ad_group_id           STRING COMMENT 'Durable ad group business key.',
  creative_sk           BIGINT COMMENT 'FK to cmn.creative.creative_sk.',
  creative_id           STRING COMMENT 'Durable creative business key.',
  placement_sk          BIGINT COMMENT 'FK to cmn.placement.placement_sk.',
  placement_id          STRING COMMENT 'Durable placement business key.',
  advertiser_sk     BIGINT COMMENT 'FK to cmn.advertiser.advertiser_sk (the advertiser).',
  advertiser_id     STRING COMMENT 'Durable advertiser business key.',
  keyword_sk            BIGINT COMMENT 'FK to cmn.keyword.keyword_sk (the credited bid keyword), if search-attributed.',
  keyword_id            STRING COMMENT 'Durable keyword business key.',

  -- Retail dimensions (canonical core)
  product_sk            BIGINT COMMENT 'FK to product.product_sk (the sold product).',
  product_id            STRING COMMENT 'Durable product business key.',
  store_sk              BIGINT COMMENT 'FK to store.store_sk, if applicable.',
  store_id              STRING COMMENT 'Durable store business key.',
  profile_sk            BIGINT COMMENT 'FK to customer.profile.profile_sk (the converting customer), if known.',
  profile_id            STRING COMMENT 'Durable customer business key (pseudonymous).',
  -- Concurrent trade promotion (conformed; ADR 0006) — same-window price/promo control.
  promo_sk              BIGINT COMMENT 'FK to marketing.promotion.promo_sk (promotion active for the attributed conversion), if any.',
  promo_id              STRING COMMENT 'Durable promotion business key (NO_PROMO when none).',

  -- Linked event + conversion (intra-package)
  touch_media_event_sk  BIGINT COMMENT 'FK to media_event.media_event_sk — the crediting touchpoint.',
  touch_media_event_id  STRING COMMENT 'Durable business key of the crediting media event.',
  conversion_event_sk   BIGINT COMMENT 'FK to conversion_event.conversion_event_sk — the credited conversion.',
  conversion_event_id   STRING COMMENT 'Durable business key of the conversion.',

  -- Incrementality (nullable)
  experiment_sk         BIGINT COMMENT 'FK to cmn.experiment.experiment_sk if under an experiment.',
  experiment_id         STRING COMMENT 'Durable experiment business key.',

  outcome_date          DATE NOT NULL COMMENT 'Business date of the attributed conversion (cluster key).',
  attribution_model     STRING COMMENT 'Model that credited this outcome. Allowed values: last_touch, first_touch, linear, position_based, data_driven.',
  click_or_view_basis   STRING COMMENT 'Whether credit was earned via a click or a view. Allowed values: click, view.',
  post_click_days       INT COMMENT 'Declared post-click attribution window applied (days).',
  post_view_days        INT COMMENT 'Declared post-view attribution window applied (days).',
  attributed_fraction   DECIMAL(9,6) COMMENT 'Fractional credit assigned to this touchpoint in [0,1] (multi-touch splits).',
  gross_sales_amount    DECIMAL(18,2) COMMENT 'Attributed gross sales, in the reporting/base currency.',
  net_sales_amount      DECIMAL(18,2) COMMENT 'Attributed net sales, in the reporting/base currency.',
  margin_amount         DECIMAL(18,2) COMMENT 'Attributed gross margin, in the reporting/base currency.',
  currency_code         STRING COMMENT 'Amount currency, ISO 4217 alpha-3 (single reporting currency).',
  units                 INT COMMENT 'Attributed units.',
  same_sku_flag         BOOLEAN COMMENT 'TRUE if the sold product is the same SKU/parent family as the advertised product.',
  halo_flag             BOOLEAN COMMENT 'TRUE if a halo (same-brand/same-category) outcome per IAB, not same-SKU.',
  new_to_brand_flag     BOOLEAN COMMENT 'TRUE if the customer is new to the brand within the lookback.',
  new_to_category_flag  BOOLEAN COMMENT 'TRUE if the customer is new to the category within the lookback.',
  extrapolated_flag     BOOLEAN COMMENT 'TRUE if the outcome is modeled/extrapolated rather than deterministically observed.',

  -- Person-level identifier (pseudonymized / PII) + consent
  customer_key_hash     STRING COMMENT 'Hashed/tokenized customer identifier (PII, never raw).',
  consent_status        STRING COMMENT 'Consent state for measurement. Allowed values: granted, denied, unknown.',

  -- Audit / provenance (append-only fact block; all timestamps UTC)
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_attributed_outcome PRIMARY KEY (attributed_outcome_sk)
)
USING DELTA
CLUSTER BY (campaign_id, outcome_date)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Commerce Media Networks — conformed attributed-outcome fact (append-only); same-SKU/halo/window auditable.';

ALTER TABLE ${catalog}.${cmn_schema}.attributed_outcome SET TAGS ('dbx_data_type' = 'transactional');

ALTER TABLE ${catalog}.${cmn_schema}.attributed_outcome ALTER COLUMN customer_key_hash SET TAGS ('dbx_pii_identifier' = 'true');
