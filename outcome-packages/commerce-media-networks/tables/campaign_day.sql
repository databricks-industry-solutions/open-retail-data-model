-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- Table: campaign_day
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- The conformed daily rollup every brief re-invented (SP campaign×day×channel,
-- ISDA campaign×store×day and ×product×store×day, CPRM delivery_performance_daily,
-- MM advertiser×campaign×day×product×delivery_context). One grain with
-- sentinel 'ALL' members so channels lacking a dimension stay additive.
--
-- Aggregate and supplier-safe: NO person-level data. Carries delivery,
-- reconciliation (platform vs ad-server vs reconciled), attribution (gross/net,
-- same-SKU/halo/new-to-brand), and privacy-suppression flags for threshold
-- suppression before supplier disclosure.
--
-- Grain: metric_date × advertiser × campaign × ad_group × creative ×
-- placement × product × store × delivery_channel × audience (sentinel 'ALL' where a
-- dimension does not apply or is rolled up). delivery_channel and audience are breakout
-- axes on the same footing as the finer product/placement dims.
--
-- ADDITIVITY CONTRACT: for a given campaign×day the loaded rows must form exactly ONE
-- non-overlapping partition of the total — every row shares a single breakout signature
-- (the same set of non-'ALL' dims). The campaign×day gold views SUM these rows grouped by
-- campaign×day with NO grain filter, so a mixed set would double-count: either a
-- fully-rolled row coexisting with detail, OR two different partial breakouts (product-level
-- rows next to delivery_channel-level rows) — each independently sums to the total. Both are
-- forbidden — acd_grain_single_level (no rollup+detail) and acd_uniform_breakout (no two
-- partial breakouts). Finer breakouts for drill-down live in a query/agg that filters to one
-- signature, never mixed into this table for the same campaign×day.
--
-- attribution_model is a per-row DISCLOSURE, not a grain axis: the attributed
-- measures on a given campaign×day are reported under exactly ONE model (the
-- campaign's configured model), and the delivery measures (impressions/clicks/
-- spend) are model-independent. Loading two models for the same campaign×day would
-- double-count when the gold views SUM, so acd_single_attribution_model (checks.sql)
-- forbids it. Multi-model / per-touch attribution comparison belongs in
-- attributed_outcome, which carries attribution_model per touch.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${cmn_schema}.campaign_day (
  campaign_day_sk   BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  campaign_day_id   STRING NOT NULL
                          COMMENT 'Durable natural/business key for the aggregate row (grain hash).',

  metric_date           DATE NOT NULL COMMENT 'Business date of the aggregate (cluster key).',
  advertiser_sk     BIGINT COMMENT 'FK to cmn.advertiser.advertiser_sk.',
  advertiser_id     STRING COMMENT 'Durable advertiser business key.',
  campaign_sk           BIGINT COMMENT 'FK to cmn.campaign.campaign_sk.',
  campaign_id           STRING COMMENT 'Durable campaign business key.',
  ad_group_sk           BIGINT COMMENT 'FK to cmn.ad_group.ad_group_sk (or sentinel ALL member).',
  ad_group_id           STRING COMMENT 'Durable ad group business key; ALL when not applicable.',
  creative_sk           BIGINT COMMENT 'FK to cmn.creative.creative_sk (or sentinel ALL member).',
  creative_id           STRING COMMENT 'Durable creative business key; ALL when not applicable.',
  placement_sk          BIGINT COMMENT 'FK to cmn.placement.placement_sk (or sentinel ALL member).',
  placement_id          STRING COMMENT 'Durable placement business key; ALL when not applicable.',
  product_sk            BIGINT COMMENT 'FK to product.product_sk (or sentinel ALL member).',
  product_id            STRING COMMENT 'Durable product business key; ALL when not applicable.',
  store_sk              BIGINT COMMENT 'FK to store.store_sk (or sentinel ALL member).',
  store_id              STRING COMMENT 'Durable store business key; ALL when not applicable.',
  -- Conformed delivery-channel + audience dimensions. ALL when rolled up.
  delivery_channel_sk    BIGINT COMMENT 'FK to cmn.delivery_channel.delivery_channel_sk (or sentinel ALL member).',
  delivery_channel_id    STRING COMMENT 'Durable delivery-channel business key; ALL when not applicable.',
  audience_sk           BIGINT COMMENT 'FK to marketing.audience.audience_sk (or sentinel ALL member).',
  audience_id           STRING COMMENT 'Durable audience business key; ALL when not applicable.',

  -- Delivery measures
  impressions           BIGINT COMMENT 'Total impressions.',
  viewable_impressions  BIGINT COMMENT 'Viewable impressions (MRC/IAB standard).',
  gross_impressions     BIGINT COMMENT 'Gross impressions (pre-filtering / in-store OTS basis).',
  ots_impressions       BIGINT COMMENT 'Opportunity-to-see impressions (in-store).',
  invalid_traffic_impressions BIGINT COMMENT 'Impressions filtered as invalid traffic (GIVT+SIVT).',
  clicks                BIGINT COMMENT 'Total clicks.',
  scheduled_plays       BIGINT COMMENT 'Scheduled in-store ad plays.',
  actual_plays          BIGINT COMMENT 'Verified in-store ad plays (proof-of-play).',
  conversions           BIGINT COMMENT 'Attributed conversions.',
  orders                BIGINT COMMENT 'Attributed orders.',
  units                 BIGINT COMMENT 'Attributed units.',

  -- Reconciliation (platform vs ad-server)
  platform_impressions  BIGINT COMMENT 'Impressions as reported by the platform.',
  ad_server_impressions BIGINT COMMENT 'Impressions as reported by the ad server.',
  reconciled_impressions BIGINT COMMENT 'Reconciled impression count.',
  discrepancy_pct       DECIMAL(9,4) COMMENT 'Platform-vs-ad-server discrepancy, percent.',

  -- Money / outcome (single reporting currency)
  media_spend_gross     DECIMAL(18,2) COMMENT 'Gross media spend, in the reporting/base currency.',
  media_spend_net       DECIMAL(18,2) COMMENT 'Net media spend, in the reporting/base currency.',
  attributed_gross_sales DECIMAL(18,2) COMMENT 'Attributed gross sales, in the reporting/base currency.',
  attributed_net_sales  DECIMAL(18,2) COMMENT 'Attributed net sales, in the reporting/base currency.',
  same_sku_sales        DECIMAL(18,2) COMMENT 'Same-SKU attributed sales, in the reporting/base currency.',
  halo_sales            DECIMAL(18,2) COMMENT 'Halo attributed sales, in the reporting/base currency.',
  new_to_brand_sales    DECIMAL(18,2) COMMENT 'New-to-brand attributed sales, in the reporting/base currency.',
  incremental_sales     DECIMAL(18,2) COMMENT 'Incremental sales (joined from experiment when present), reporting/base currency.',
  currency_code         STRING COMMENT 'Amount currency, ISO 4217 alpha-3 (single reporting currency).',

  -- Disclosure / flags
  attribution_model     STRING COMMENT 'The SINGLE attribution model the attributed measures are reported under for this campaign×day (per-row disclosure, not a grain axis; one model per grain — see acd_single_attribution_model). Allowed values: last_touch, first_touch, linear, position_based, data_driven.',
  post_click_days       INT COMMENT 'Post-click window applied (days).',
  post_view_days        INT COMMENT 'Post-view window applied (days).',
  extrapolated_metric_flag BOOLEAN COMMENT 'TRUE if any measure is modeled/extrapolated.',
  privacy_suppressed_flag  BOOLEAN COMMENT 'TRUE if the row is threshold-suppressed for supplier disclosure.',
  suppression_reason    STRING COMMENT 'Why suppressed. Allowed values: below_threshold, consent, policy, none.',

  -- Audit / provenance (append-only aggregate block; all timestamps UTC)
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_campaign_day PRIMARY KEY (campaign_day_sk)
)
USING DELTA
CLUSTER BY (campaign_id, metric_date)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Commerce Media Networks — conformed campaign×day delivery/attribution aggregate (supplier-safe).';

ALTER TABLE ${catalog}.${cmn_schema}.campaign_day SET TAGS ('dbx_data_type' = 'transactional');
