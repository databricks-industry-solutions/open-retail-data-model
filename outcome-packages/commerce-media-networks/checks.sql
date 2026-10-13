-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks · data-quality checks
-- Version: 0.5 · Generated: 2026-07-13 · LLM-generated: true · Reviewed: 2026-07-14
-- Each assertion SELECTs violating rows; 0 rows = PASS. `metric` checks report a
-- value and never fail. Run by runtime/data-quality/run_checks.py.
--
-- Grain integrity: the `*_grain_unique` checks assert the DURABLE business key
-- (`<table>_id`), which encodes each fact/aggregate's natural grain — NOT the
-- IDENTITY surrogate (`*_sk`), which is generated per-row and can never collide,
-- so a `_sk` uniqueness test is a tautology that would let a double-loaded event
-- or duplicate aggregate row pass silently and double-count downstream.
-- ============================================================

-- ========== media_event ==========
-- check: fme_grain_unique | severity: error
SELECT media_event_id, COUNT(*) AS n FROM ${catalog}.${cmn_schema}.media_event GROUP BY media_event_id HAVING COUNT(*) > 1;
-- check: fme_keys_not_null | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.media_event WHERE media_event_sk IS NULL OR media_event_id IS NULL OR event_type IS NULL OR event_ts IS NULL OR event_date IS NULL;
-- check: fme_campaign_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.media_event f LEFT JOIN ${catalog}.${cmn_schema}.campaign c ON f.campaign_sk = c.campaign_sk WHERE f.campaign_sk IS NOT NULL AND c.campaign_sk IS NULL;
-- check: fme_event_type_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.media_event WHERE event_type NOT IN ('impression','viewable_impression','click','ad_play','video_start','video_complete');
-- check: fme_single_currency | severity: error
SELECT * FROM (SELECT COUNT(DISTINCT currency_code) AS n FROM ${catalog}.${cmn_schema}.media_event WHERE currency_code IS NOT NULL) WHERE n > 1;

-- ========== conversion_event ==========
-- check: fce_grain_unique | severity: error
SELECT conversion_event_id, COUNT(*) AS n FROM ${catalog}.${cmn_schema}.conversion_event GROUP BY conversion_event_id HAVING COUNT(*) > 1;
-- check: fce_keys_not_null | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.conversion_event WHERE conversion_event_sk IS NULL OR conversion_event_id IS NULL OR conversion_type IS NULL OR outcome_ts IS NULL;
-- check: fce_product_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.conversion_event f LEFT JOIN ${catalog}.${product_schema}.product p ON f.product_sk = p.product_sk WHERE f.product_sk IS NOT NULL AND p.product_sk IS NULL;
-- check: fce_single_currency | severity: error
SELECT * FROM (SELECT COUNT(DISTINCT currency_code) AS n FROM ${catalog}.${cmn_schema}.conversion_event WHERE currency_code IS NOT NULL) WHERE n > 1;

-- ========== attributed_outcome ==========
-- check: fao_grain_unique | severity: error
SELECT attributed_outcome_id, COUNT(*) AS n FROM ${catalog}.${cmn_schema}.attributed_outcome GROUP BY attributed_outcome_id HAVING COUNT(*) > 1;
-- check: fao_campaign_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.attributed_outcome f LEFT JOIN ${catalog}.${cmn_schema}.campaign c ON f.campaign_sk = c.campaign_sk WHERE f.campaign_sk IS NOT NULL AND c.campaign_sk IS NULL;
-- check: fao_touch_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.attributed_outcome f LEFT JOIN ${catalog}.${cmn_schema}.media_event m ON f.touch_media_event_sk = m.media_event_sk WHERE f.touch_media_event_sk IS NOT NULL AND m.media_event_sk IS NULL;
-- check: fao_conversion_fk_orphan | severity: error
-- The attributed conversion must resolve to a real conversion event: CVR denominators
-- and multi-touch dedup (fao_fraction_sum, grouped on conversion_event_id) hinge on it.
SELECT f.* FROM ${catalog}.${cmn_schema}.attributed_outcome f LEFT JOIN ${catalog}.${cmn_schema}.conversion_event ce ON f.conversion_event_sk = ce.conversion_event_sk WHERE f.conversion_event_sk IS NOT NULL AND ce.conversion_event_sk IS NULL;
-- check: fao_fraction_range | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.attributed_outcome WHERE attributed_fraction IS NOT NULL AND attributed_fraction NOT BETWEEN 0 AND 1;
-- check: fao_fraction_sum | severity: error
-- Multi-touch credit for one conversion must not over-attribute: the fractions for
-- a given conversion under one attribution model sum to <= 1. Guarded on a linked
-- conversion (un-linked rows carry a NULL conversion and are out of scope).
SELECT conversion_event_id, attribution_model, SUM(attributed_fraction) AS total_fraction FROM ${catalog}.${cmn_schema}.attributed_outcome WHERE conversion_event_id IS NOT NULL AND attributed_fraction IS NOT NULL GROUP BY conversion_event_id, attribution_model HAVING SUM(attributed_fraction) > 1.001;
-- check: fao_single_currency | severity: error
SELECT * FROM (SELECT COUNT(DISTINCT currency_code) AS n FROM ${catalog}.${cmn_schema}.attributed_outcome WHERE currency_code IS NOT NULL) WHERE n > 1;

-- ========== experiment_assignment_bridge ==========
-- check: bea_grain_unique | severity: error
SELECT experiment_assignment_id, COUNT(*) AS n FROM ${catalog}.${cmn_schema}.experiment_assignment_bridge GROUP BY experiment_assignment_id HAVING COUNT(*) > 1;
-- check: bea_experiment_fk_orphan | severity: error
SELECT b.* FROM ${catalog}.${cmn_schema}.experiment_assignment_bridge b LEFT JOIN ${catalog}.${cmn_schema}.experiment e ON b.experiment_sk = e.experiment_sk WHERE b.experiment_sk IS NOT NULL AND e.experiment_sk IS NULL;
-- check: bea_experiment_cell_fk_orphan | severity: error
SELECT b.* FROM ${catalog}.${cmn_schema}.experiment_assignment_bridge b LEFT JOIN ${catalog}.${cmn_schema}.experiment_cell ec ON b.experiment_cell_sk = ec.experiment_cell_sk WHERE b.experiment_cell_sk IS NOT NULL AND ec.experiment_cell_sk IS NULL;
-- check: bea_profile_fk_orphan | severity: error
SELECT b.* FROM ${catalog}.${cmn_schema}.experiment_assignment_bridge b LEFT JOIN ${catalog}.${customer_schema}.profile p ON b.profile_sk = p.profile_sk WHERE b.profile_sk IS NOT NULL AND p.profile_sk IS NULL;

-- ========== campaign_day ==========
-- check: acd_grain_unique | severity: error
SELECT campaign_day_id, COUNT(*) AS n FROM ${catalog}.${cmn_schema}.campaign_day GROUP BY campaign_day_id HAVING COUNT(*) > 1;
-- check: acd_grain_single_level | severity: error
-- The aggregate uses 'ALL' sentinels for dims not applicable to a row. A rolled-up
-- ('ALL' on every finer dim) row and detail rows must never coexist for the same
-- campaign×day, or a downstream SUM double-counts the rollup with its detail. The
-- finer axes are ALL breakout dimensions of the grain: ad_group, creative, placement,
-- product, store, AND delivery_channel + audience (a delivery_channel/audience-broken-out row summed
-- next to the fully-rolled row inflates delivery/spend ~2× — review M1). So all seven
-- participate in the has_rollup/has_detail predicates. (attribution_model is a single
-- per-row disclosure, not a grain axis — see acd_single_attribution_model — so rollup
-- detection is model-independent.)
SELECT campaign_id, metric_date FROM (SELECT campaign_id, metric_date, MAX(CASE WHEN ad_group_id = 'ALL' AND creative_id = 'ALL' AND placement_id = 'ALL' AND product_id = 'ALL' AND store_id = 'ALL' AND delivery_channel_id = 'ALL' AND audience_id = 'ALL' THEN 1 ELSE 0 END) AS has_rollup, MAX(CASE WHEN ad_group_id <> 'ALL' OR creative_id <> 'ALL' OR placement_id <> 'ALL' OR product_id <> 'ALL' OR store_id <> 'ALL' OR delivery_channel_id <> 'ALL' OR audience_id <> 'ALL' THEN 1 ELSE 0 END) AS has_detail FROM ${catalog}.${cmn_schema}.campaign_day GROUP BY campaign_id, metric_date) WHERE has_rollup = 1 AND has_detail = 1;
-- check: acd_single_attribution_model | severity: error
-- The attributed measures are reported under ONE attribution model per campaign×day
-- (the campaign's configured model). attribution_model is a per-row disclosure, NOT
-- a grain axis: the gold views (gold_campaign_performance, gold_supplier_campaign_report)
-- SUM delivery + attributed measures without partitioning by model, so a second
-- model for the same campaign×day would inflate impressions/spend (delivery is
-- model-independent) and mix incompatible attributions — corrupting ROAS/iROAS.
-- Multi-model / per-touch comparison belongs in attributed_outcome.
SELECT campaign_id, metric_date, COUNT(DISTINCT attribution_model) AS n
FROM ${catalog}.${cmn_schema}.campaign_day
WHERE attribution_model IS NOT NULL
GROUP BY campaign_id, metric_date HAVING COUNT(DISTINCT attribution_model) > 1;
-- check: acd_uniform_breakout | severity: error
-- Additivity contract (the GENERAL partition guard). Every row for a campaign×day must
-- share ONE breakout signature — the same set of non-'ALL' breakout dims — so the rows
-- form a single, non-overlapping partition of the campaign×day total. Two DIFFERENT
-- partial breakouts (e.g. product-level rows with delivery_channel='ALL' next to
-- delivery_channel-level rows with product='ALL') each independently sum to the total, so
-- the gold views (which SUM grouped by campaign×day with no grain filter) would ~2x
-- double-count. This is the general guard; acd_grain_single_level (fully-rolled 'ALL'-
-- everywhere vs any detail) is the special case it subsumes. Together they make the gold
-- SUM provably additive (one canonical grain per campaign×day).
SELECT campaign_id, metric_date, COUNT(DISTINCT breakout_sig) AS n FROM (
  SELECT campaign_id, metric_date, CONCAT(
    CASE WHEN ad_group_id = 'ALL' THEN '0' ELSE '1' END,
    CASE WHEN creative_id = 'ALL' THEN '0' ELSE '1' END,
    CASE WHEN placement_id = 'ALL' THEN '0' ELSE '1' END,
    CASE WHEN product_id = 'ALL' THEN '0' ELSE '1' END,
    CASE WHEN store_id = 'ALL' THEN '0' ELSE '1' END,
    CASE WHEN delivery_channel_id = 'ALL' THEN '0' ELSE '1' END,
    CASE WHEN audience_id = 'ALL' THEN '0' ELSE '1' END) AS breakout_sig
  FROM ${catalog}.${cmn_schema}.campaign_day
) GROUP BY campaign_id, metric_date HAVING COUNT(DISTINCT breakout_sig) > 1;
-- check: acd_campaign_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${cmn_schema}.campaign_day a LEFT JOIN ${catalog}.${cmn_schema}.campaign c ON a.campaign_sk = c.campaign_sk WHERE a.campaign_sk IS NOT NULL AND c.campaign_sk IS NULL;
-- check: acd_single_currency | severity: error
SELECT * FROM (SELECT COUNT(DISTINCT currency_code) AS n FROM ${catalog}.${cmn_schema}.campaign_day WHERE currency_code IS NOT NULL) WHERE n > 1;
-- check: acd_spend_nonnegative | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.campaign_day WHERE (media_spend_gross IS NOT NULL AND media_spend_gross < 0) OR (media_spend_net IS NOT NULL AND media_spend_net < 0);

-- ========== incrementality_result ==========
-- check: fir_grain_unique | severity: error
SELECT incrementality_result_id, COUNT(*) AS n FROM ${catalog}.${cmn_schema}.incrementality_result GROUP BY incrementality_result_id HAVING COUNT(*) > 1;
-- check: fir_experiment_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.incrementality_result f LEFT JOIN ${catalog}.${cmn_schema}.experiment e ON f.experiment_sk = e.experiment_sk WHERE f.experiment_sk IS NOT NULL AND e.experiment_sk IS NULL;
-- check: fir_p_value_range | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.incrementality_result WHERE p_value IS NOT NULL AND p_value NOT BETWEEN 0 AND 1;
-- check: fir_confidence_range | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.incrementality_result WHERE confidence_level_pct IS NOT NULL AND confidence_level_pct NOT BETWEEN 0 AND 100;
-- check: fir_single_currency | severity: error
SELECT * FROM (SELECT COUNT(DISTINCT currency_code) AS n FROM ${catalog}.${cmn_schema}.incrementality_result WHERE currency_code IS NOT NULL) WHERE n > 1;

-- ========== experiment_daily ==========
-- check: aed_grain_unique | severity: error
SELECT experiment_daily_id, COUNT(*) AS n FROM ${catalog}.${cmn_schema}.experiment_daily GROUP BY experiment_daily_id HAVING COUNT(*) > 1;
-- check: aed_experiment_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${cmn_schema}.experiment_daily a LEFT JOIN ${catalog}.${cmn_schema}.experiment e ON a.experiment_sk = e.experiment_sk WHERE a.experiment_sk IS NOT NULL AND e.experiment_sk IS NULL;
-- check: aed_single_currency | severity: error
SELECT * FROM (SELECT COUNT(DISTINCT currency_code) AS n FROM ${catalog}.${cmn_schema}.experiment_daily WHERE currency_code IS NOT NULL) WHERE n > 1;

-- ========== budget_allocation ==========
-- check: fba_grain_unique | severity: error
SELECT budget_allocation_id, COUNT(*) AS n FROM ${catalog}.${cmn_schema}.budget_allocation GROUP BY budget_allocation_id HAVING COUNT(*) > 1;
-- check: fba_campaign_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.budget_allocation f LEFT JOIN ${catalog}.${cmn_schema}.campaign c ON f.campaign_sk = c.campaign_sk WHERE f.campaign_sk IS NOT NULL AND c.campaign_sk IS NULL;
-- check: fba_budget_nonnegative | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.budget_allocation WHERE allocated_budget_amount IS NOT NULL AND allocated_budget_amount < 0;
-- check: fba_single_currency | severity: error
SELECT * FROM (SELECT COUNT(DISTINCT currency_code) AS n FROM ${catalog}.${cmn_schema}.budget_allocation WHERE currency_code IS NOT NULL) WHERE n > 1;

-- ========== pacing_snapshot ==========
-- check: fps_grain_unique | severity: error
SELECT pacing_snapshot_id, COUNT(*) AS n FROM ${catalog}.${cmn_schema}.pacing_snapshot GROUP BY pacing_snapshot_id HAVING COUNT(*) > 1;
-- check: fps_campaign_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.pacing_snapshot f LEFT JOIN ${catalog}.${cmn_schema}.campaign c ON f.campaign_sk = c.campaign_sk WHERE f.campaign_sk IS NOT NULL AND c.campaign_sk IS NULL;
-- check: fps_pacing_ratio_nonnegative | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.pacing_snapshot WHERE pacing_ratio IS NOT NULL AND pacing_ratio < 0;
-- check: fps_single_currency | severity: error
SELECT * FROM (SELECT COUNT(DISTINCT currency_code) AS n FROM ${catalog}.${cmn_schema}.pacing_snapshot WHERE currency_code IS NOT NULL) WHERE n > 1;

-- ========== store_zone_interval (relocated) ==========
-- The footfall fact moved to connected_store_signals.sensor_report_interval (ADR 0033).
-- szi_grain_unique and szi_store_fk_orphan now live in that package's checks.sql as
-- sri_grain_unique and sri_store_fk_orphan. The compatibility view is covered by
-- szi_compat_view_readable below, which is what actually protects a 0.1-beta consumer.
-- check: szi_compat_view_readable | severity: error
SELECT * FROM (SELECT COUNT(*) AS n FROM ${catalog}.${cmn_schema}.store_zone_interval) WHERE n IS NULL;

-- ========== product_store_day ==========
-- check: psd_grain_unique | severity: error
SELECT product_store_day_id, COUNT(*) AS n FROM ${catalog}.${cmn_schema}.product_store_day GROUP BY product_store_day_id HAVING COUNT(*) > 1;
-- check: psd_product_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.product_store_day f LEFT JOIN ${catalog}.${product_schema}.product p ON f.product_sk = p.product_sk WHERE f.product_sk IS NOT NULL AND p.product_sk IS NULL;
-- check: psd_single_currency | severity: error
SELECT * FROM (SELECT COUNT(DISTINCT currency_code) AS n FROM ${catalog}.${cmn_schema}.product_store_day WHERE currency_code IS NOT NULL) WHERE n > 1;

-- ========== shared-marketing conformance FKs (ADR 0022 audience, ADR 0006 promotion) ==========
-- Guarded orphan checks: the conformed delivery_channel FK resolves within CMN gold, and the audience + promotion FKs
-- resolve to silver marketing, when populated (NULL = not applicable / sentinel).
-- check: fme_delivery_channel_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.media_event f LEFT JOIN ${catalog}.${cmn_schema}.delivery_channel d ON f.delivery_channel_sk = d.delivery_channel_sk WHERE f.delivery_channel_sk IS NOT NULL AND d.delivery_channel_sk IS NULL;
-- check: fme_audience_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.media_event f LEFT JOIN ${catalog}.${marketing_schema}.audience a ON f.audience_sk = a.audience_sk WHERE f.audience_sk IS NOT NULL AND a.audience_sk IS NULL;
-- check: acd_delivery_channel_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${cmn_schema}.campaign_day a LEFT JOIN ${catalog}.${cmn_schema}.delivery_channel d ON a.delivery_channel_sk = d.delivery_channel_sk WHERE a.delivery_channel_sk IS NOT NULL AND d.delivery_channel_sk IS NULL;
-- check: acd_audience_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${cmn_schema}.campaign_day a LEFT JOIN ${catalog}.${marketing_schema}.audience au ON a.audience_sk = au.audience_sk WHERE a.audience_sk IS NOT NULL AND au.audience_sk IS NULL;
-- check: fce_promotion_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.conversion_event f LEFT JOIN ${catalog}.${marketing_schema}.promotion p ON f.promo_sk = p.promo_sk WHERE f.promo_sk IS NOT NULL AND p.promo_sk IS NULL;
-- check: fao_promotion_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.attributed_outcome f LEFT JOIN ${catalog}.${marketing_schema}.promotion p ON f.promo_sk = p.promo_sk WHERE f.promo_sk IS NOT NULL AND p.promo_sk IS NULL;

-- ========== per-FK orphan coverage (review m1 + follow-up M1) ==========
-- The MUST tier is satisfied by a representative orphan check per fact; this block
-- completes coverage to EVERY declared FK on EVERY fact/aggregate in the package
-- (including the media_event parent self-FK), so no fact->dim link is unguarded.
-- Each guards its nullable _sk against the referenced dimension's PK (NULL =
-- not-applicable / sentinel, out of scope).

-- media_event (remaining FKs)
-- check: fme_ad_group_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.media_event f LEFT JOIN ${catalog}.${cmn_schema}.ad_group d ON f.ad_group_sk = d.ad_group_sk WHERE f.ad_group_sk IS NOT NULL AND d.ad_group_sk IS NULL;
-- check: fme_creative_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.media_event f LEFT JOIN ${catalog}.${cmn_schema}.creative d ON f.creative_sk = d.creative_sk WHERE f.creative_sk IS NOT NULL AND d.creative_sk IS NULL;
-- check: fme_placement_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.media_event f LEFT JOIN ${catalog}.${cmn_schema}.placement d ON f.placement_sk = d.placement_sk WHERE f.placement_sk IS NOT NULL AND d.placement_sk IS NULL;
-- check: fme_product_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.media_event f LEFT JOIN ${catalog}.${product_schema}.product d ON f.product_sk = d.product_sk WHERE f.product_sk IS NOT NULL AND d.product_sk IS NULL;
-- check: fme_store_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.media_event f LEFT JOIN ${catalog}.${store_schema}.store d ON f.store_sk = d.store_sk WHERE f.store_sk IS NOT NULL AND d.store_sk IS NULL;
-- check: fme_profile_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.media_event f LEFT JOIN ${catalog}.${customer_schema}.profile d ON f.profile_sk = d.profile_sk WHERE f.profile_sk IS NOT NULL AND d.profile_sk IS NULL;
-- check: fme_experiment_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.media_event f LEFT JOIN ${catalog}.${cmn_schema}.experiment d ON f.experiment_sk = d.experiment_sk WHERE f.experiment_sk IS NOT NULL AND d.experiment_sk IS NULL;
-- check: fme_experiment_cell_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.media_event f LEFT JOIN ${catalog}.${cmn_schema}.experiment_cell d ON f.experiment_cell_sk = d.experiment_cell_sk WHERE f.experiment_cell_sk IS NOT NULL AND d.experiment_cell_sk IS NULL;
-- check: fme_keyword_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.media_event f LEFT JOIN ${catalog}.${cmn_schema}.keyword d ON f.keyword_sk = d.keyword_sk WHERE f.keyword_sk IS NOT NULL AND d.keyword_sk IS NULL;

-- conversion_event (remaining FKs)
-- check: fce_profile_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.conversion_event f LEFT JOIN ${catalog}.${customer_schema}.profile d ON f.profile_sk = d.profile_sk WHERE f.profile_sk IS NOT NULL AND d.profile_sk IS NULL;
-- check: fce_store_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.conversion_event f LEFT JOIN ${catalog}.${store_schema}.store d ON f.store_sk = d.store_sk WHERE f.store_sk IS NOT NULL AND d.store_sk IS NULL;
-- check: fce_order_line_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.conversion_event f LEFT JOIN ${catalog}.${order_schema}.customer_order_line d ON f.order_line_sk = d.order_line_sk WHERE f.order_line_sk IS NOT NULL AND d.order_line_sk IS NULL;
-- check: fce_experiment_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.conversion_event f LEFT JOIN ${catalog}.${cmn_schema}.experiment d ON f.experiment_sk = d.experiment_sk WHERE f.experiment_sk IS NOT NULL AND d.experiment_sk IS NULL;
-- check: fce_experiment_cell_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.conversion_event f LEFT JOIN ${catalog}.${cmn_schema}.experiment_cell d ON f.experiment_cell_sk = d.experiment_cell_sk WHERE f.experiment_cell_sk IS NOT NULL AND d.experiment_cell_sk IS NULL;

-- attributed_outcome (remaining FKs)
-- check: fao_ad_group_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.attributed_outcome f LEFT JOIN ${catalog}.${cmn_schema}.ad_group d ON f.ad_group_sk = d.ad_group_sk WHERE f.ad_group_sk IS NOT NULL AND d.ad_group_sk IS NULL;
-- check: fao_creative_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.attributed_outcome f LEFT JOIN ${catalog}.${cmn_schema}.creative d ON f.creative_sk = d.creative_sk WHERE f.creative_sk IS NOT NULL AND d.creative_sk IS NULL;
-- check: fao_placement_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.attributed_outcome f LEFT JOIN ${catalog}.${cmn_schema}.placement d ON f.placement_sk = d.placement_sk WHERE f.placement_sk IS NOT NULL AND d.placement_sk IS NULL;
-- check: fao_advertiser_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.attributed_outcome f LEFT JOIN ${catalog}.${cmn_schema}.advertiser d ON f.advertiser_sk = d.advertiser_sk WHERE f.advertiser_sk IS NOT NULL AND d.advertiser_sk IS NULL;
-- check: fao_product_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.attributed_outcome f LEFT JOIN ${catalog}.${product_schema}.product d ON f.product_sk = d.product_sk WHERE f.product_sk IS NOT NULL AND d.product_sk IS NULL;
-- check: fao_store_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.attributed_outcome f LEFT JOIN ${catalog}.${store_schema}.store d ON f.store_sk = d.store_sk WHERE f.store_sk IS NOT NULL AND d.store_sk IS NULL;
-- check: fao_profile_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.attributed_outcome f LEFT JOIN ${catalog}.${customer_schema}.profile d ON f.profile_sk = d.profile_sk WHERE f.profile_sk IS NOT NULL AND d.profile_sk IS NULL;
-- check: fao_experiment_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.attributed_outcome f LEFT JOIN ${catalog}.${cmn_schema}.experiment d ON f.experiment_sk = d.experiment_sk WHERE f.experiment_sk IS NOT NULL AND d.experiment_sk IS NULL;
-- check: fao_keyword_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.attributed_outcome f LEFT JOIN ${catalog}.${cmn_schema}.keyword d ON f.keyword_sk = d.keyword_sk WHERE f.keyword_sk IS NOT NULL AND d.keyword_sk IS NULL;

-- campaign_day (remaining FKs)
-- check: acd_advertiser_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${cmn_schema}.campaign_day a LEFT JOIN ${catalog}.${cmn_schema}.advertiser d ON a.advertiser_sk = d.advertiser_sk WHERE a.advertiser_sk IS NOT NULL AND d.advertiser_sk IS NULL;
-- check: acd_ad_group_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${cmn_schema}.campaign_day a LEFT JOIN ${catalog}.${cmn_schema}.ad_group d ON a.ad_group_sk = d.ad_group_sk WHERE a.ad_group_sk IS NOT NULL AND d.ad_group_sk IS NULL;
-- check: acd_creative_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${cmn_schema}.campaign_day a LEFT JOIN ${catalog}.${cmn_schema}.creative d ON a.creative_sk = d.creative_sk WHERE a.creative_sk IS NOT NULL AND d.creative_sk IS NULL;
-- check: acd_placement_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${cmn_schema}.campaign_day a LEFT JOIN ${catalog}.${cmn_schema}.placement d ON a.placement_sk = d.placement_sk WHERE a.placement_sk IS NOT NULL AND d.placement_sk IS NULL;
-- check: acd_product_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${cmn_schema}.campaign_day a LEFT JOIN ${catalog}.${product_schema}.product d ON a.product_sk = d.product_sk WHERE a.product_sk IS NOT NULL AND d.product_sk IS NULL;
-- check: acd_store_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${cmn_schema}.campaign_day a LEFT JOIN ${catalog}.${store_schema}.store d ON a.store_sk = d.store_sk WHERE a.store_sk IS NOT NULL AND d.store_sk IS NULL;

-- media_event self-FK (click -> served impression; review m1)
-- check: fme_parent_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.media_event f LEFT JOIN ${catalog}.${cmn_schema}.media_event p ON f.parent_media_event_sk = p.media_event_sk WHERE f.parent_media_event_sk IS NOT NULL AND p.media_event_sk IS NULL;

-- incrementality_result (remaining FKs — feeds gold_incrementality_readout iROAS/lift; review M1)
-- check: fir_treatment_cell_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.incrementality_result f LEFT JOIN ${catalog}.${cmn_schema}.experiment_cell d ON f.treatment_cell_sk = d.experiment_cell_sk WHERE f.treatment_cell_sk IS NOT NULL AND d.experiment_cell_sk IS NULL;
-- check: fir_control_cell_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.incrementality_result f LEFT JOIN ${catalog}.${cmn_schema}.experiment_cell d ON f.control_cell_sk = d.experiment_cell_sk WHERE f.control_cell_sk IS NOT NULL AND d.experiment_cell_sk IS NULL;
-- check: fir_campaign_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.incrementality_result f LEFT JOIN ${catalog}.${cmn_schema}.campaign d ON f.campaign_sk = d.campaign_sk WHERE f.campaign_sk IS NOT NULL AND d.campaign_sk IS NULL;
-- check: fir_advertiser_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.incrementality_result f LEFT JOIN ${catalog}.${cmn_schema}.advertiser d ON f.advertiser_sk = d.advertiser_sk WHERE f.advertiser_sk IS NOT NULL AND d.advertiser_sk IS NULL;
-- check: fir_product_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.incrementality_result f LEFT JOIN ${catalog}.${product_schema}.product d ON f.product_sk = d.product_sk WHERE f.product_sk IS NOT NULL AND d.product_sk IS NULL;

-- experiment_daily (remaining FK)
-- check: aed_experiment_cell_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${cmn_schema}.experiment_daily a LEFT JOIN ${catalog}.${cmn_schema}.experiment_cell d ON a.experiment_cell_sk = d.experiment_cell_sk WHERE a.experiment_cell_sk IS NOT NULL AND d.experiment_cell_sk IS NULL;

-- budget_allocation (remaining FKs)
-- check: fba_ad_group_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.budget_allocation f LEFT JOIN ${catalog}.${cmn_schema}.ad_group d ON f.ad_group_sk = d.ad_group_sk WHERE f.ad_group_sk IS NOT NULL AND d.ad_group_sk IS NULL;
-- check: fba_placement_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.budget_allocation f LEFT JOIN ${catalog}.${cmn_schema}.placement d ON f.placement_sk = d.placement_sk WHERE f.placement_sk IS NOT NULL AND d.placement_sk IS NULL;
-- check: fba_advertiser_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.budget_allocation f LEFT JOIN ${catalog}.${cmn_schema}.advertiser d ON f.advertiser_sk = d.advertiser_sk WHERE f.advertiser_sk IS NOT NULL AND d.advertiser_sk IS NULL;

-- pacing_snapshot (remaining FKs)
-- check: fps_ad_group_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.pacing_snapshot f LEFT JOIN ${catalog}.${cmn_schema}.ad_group d ON f.ad_group_sk = d.ad_group_sk WHERE f.ad_group_sk IS NOT NULL AND d.ad_group_sk IS NULL;
-- check: fps_placement_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.pacing_snapshot f LEFT JOIN ${catalog}.${cmn_schema}.placement d ON f.placement_sk = d.placement_sk WHERE f.placement_sk IS NOT NULL AND d.placement_sk IS NULL;

-- product_store_day (remaining FK)
-- check: psd_store_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${cmn_schema}.product_store_day f LEFT JOIN ${catalog}.${store_schema}.store d ON f.store_sk = d.store_sk WHERE f.store_sk IS NOT NULL AND d.store_sk IS NULL;

-- ========== gold views — no-raw-PII guard ==========
-- check: cmn_gold_no_raw_pii | severity: error
-- Gold views must NOT expose the hashed person-level identifiers; those stay in
-- the person-level facts (masked). Gold is supplier-safe / aggregate.
SELECT table_name, column_name
FROM ${catalog}.information_schema.columns
WHERE table_schema = '${cmn_schema}'
  AND table_name IN ('gold_campaign_performance','gold_incrementality_readout','gold_pacing_current','gold_supplier_campaign_report')
  AND column_name IN ('customer_key_hash','household_key_hash','assignment_unit_key_hash');

-- check: cmn_media_event_count | severity: metric
SELECT COUNT(*) AS media_event_rows FROM ${catalog}.${cmn_schema}.media_event;

-- ========== relocated retail-media dimensions (gold) ==========
-- Ported from the former canonical-core/media domain: per-dim DQ checks for
-- the advertiser / campaign / ad_group / creative / placement / experiment /
-- experiment_cell dims now co-located in this package, plus the delivery_channel dim.
-- ---------- advertiser ----------

-- check: advertiser_keys_not_null | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.advertiser
WHERE advertiser_sk IS NULL OR advertiser_id IS NULL OR supplier_id IS NULL
   OR effective_from_date IS NULL OR is_current IS NULL;

-- check: advertiser_business_key_unique_current | severity: error
SELECT advertiser_id, COUNT(*) AS current_versions
FROM ${catalog}.${cmn_schema}.advertiser
WHERE is_current = true
GROUP BY advertiser_id
HAVING COUNT(*) > 1;

-- check: advertiser_supplier_fk_orphan | severity: error
-- Every advertiser must reference an existing supplier (by surrogate FK).
SELECT sb.* FROM ${catalog}.${cmn_schema}.advertiser sb
LEFT JOIN ${catalog}.${supplier_schema}.supplier s ON sb.supplier_sk = s.supplier_sk
WHERE sb.supplier_sk IS NOT NULL AND s.supplier_sk IS NULL;

-- check: advertiser_supplier_businesskey_orphan | severity: error
-- The durable supplier business key must also exist on supplier.
SELECT sb.* FROM ${catalog}.${cmn_schema}.advertiser sb
LEFT JOIN (SELECT DISTINCT supplier_id FROM ${catalog}.${supplier_schema}.supplier) s
  ON sb.supplier_id = s.supplier_id
WHERE s.supplier_id IS NULL;

-- check: advertiser_relationship_type_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.advertiser
WHERE relationship_type IS NOT NULL
  AND relationship_type NOT IN ('direct', 'agency', 'reseller');

-- check: advertiser_advertiser_status_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.advertiser
WHERE advertiser_status IS NOT NULL
  AND advertiser_status NOT IN ('active', 'inactive');

-- check: advertiser_scd2_current_open | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.advertiser
WHERE (is_current = true  AND effective_to_date IS NOT NULL)
   OR (is_current = false AND effective_to_date IS NULL);

-- check: advertiser_scd2_date_order | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.advertiser
WHERE effective_to_date IS NOT NULL
  AND effective_to_date <= effective_from_date;

-- ---------- campaign ----------

-- check: campaign_keys_not_null | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.campaign
WHERE campaign_sk IS NULL OR campaign_id IS NULL
   OR effective_from_date IS NULL OR is_current IS NULL;

-- check: campaign_business_key_unique_current | severity: error
SELECT campaign_id, COUNT(*) AS current_versions
FROM ${catalog}.${cmn_schema}.campaign
WHERE is_current = true
GROUP BY campaign_id
HAVING COUNT(*) > 1;

-- check: campaign_advertiser_fk_orphan | severity: error
-- Every campaign must reference an existing advertiser (by surrogate FK).
SELECT c.* FROM ${catalog}.${cmn_schema}.campaign c
LEFT JOIN ${catalog}.${cmn_schema}.advertiser sb ON c.advertiser_sk = sb.advertiser_sk
WHERE c.advertiser_sk IS NOT NULL AND sb.advertiser_sk IS NULL;

-- check: campaign_advertiser_businesskey_orphan | severity: error
SELECT c.* FROM ${catalog}.${cmn_schema}.campaign c
LEFT JOIN (SELECT DISTINCT advertiser_id FROM ${catalog}.${cmn_schema}.advertiser) sb
  ON c.advertiser_id = sb.advertiser_id
WHERE c.advertiser_id IS NOT NULL AND sb.advertiser_id IS NULL;

-- check: campaign_objective_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.campaign
WHERE objective IS NOT NULL
  AND objective NOT IN ('awareness', 'consideration', 'conversion', 'loyalty', 'other');

-- check: campaign_status_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.campaign
WHERE campaign_status IS NOT NULL
  AND campaign_status NOT IN ('draft', 'active', 'paused', 'completed', 'archived');

-- check: campaign_buy_model_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.campaign
WHERE buy_model IS NOT NULL
  AND buy_model NOT IN ('cpc', 'cpm', 'cpa', 'flat', 'other');

-- check: campaign_attribution_model_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.campaign
WHERE attribution_model IS NOT NULL
  AND attribution_model NOT IN ('last_touch', 'first_touch', 'linear', 'position_based', 'data_driven');

-- check: campaign_sales_metric_type_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.campaign
WHERE sales_metric_type IS NOT NULL
  AND sales_metric_type NOT IN ('gross', 'net');

-- check: campaign_dates_order | severity: error
-- When both set, the flight end date must be on or after the start date.
SELECT * FROM ${catalog}.${cmn_schema}.campaign
WHERE start_date IS NOT NULL AND end_date IS NOT NULL
  AND end_date < start_date;

-- check: campaign_budget_nonnegative | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.campaign
WHERE budget_amount IS NOT NULL AND budget_amount < 0;

-- check: campaign_attribution_windows_nonnegative | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.campaign
WHERE (default_post_click_days IS NOT NULL AND default_post_click_days < 0)
   OR (default_post_view_days  IS NOT NULL AND default_post_view_days  < 0);

-- check: campaign_scd2_current_open | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.campaign
WHERE (is_current = true  AND effective_to_date IS NOT NULL)
   OR (is_current = false AND effective_to_date IS NULL);

-- check: campaign_scd2_date_order | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.campaign
WHERE effective_to_date IS NOT NULL
  AND effective_to_date <= effective_from_date;

-- ---------- ad_group ----------

-- check: ad_group_keys_not_null | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.ad_group
WHERE ad_group_sk IS NULL OR ad_group_id IS NULL
   OR effective_from_date IS NULL OR is_current IS NULL;

-- check: ad_group_business_key_unique_current | severity: error
SELECT ad_group_id, COUNT(*) AS current_versions
FROM ${catalog}.${cmn_schema}.ad_group
WHERE is_current = true
GROUP BY ad_group_id
HAVING COUNT(*) > 1;

-- check: ad_group_campaign_fk_orphan | severity: error
SELECT ag.* FROM ${catalog}.${cmn_schema}.ad_group ag
LEFT JOIN ${catalog}.${cmn_schema}.campaign c ON ag.campaign_sk = c.campaign_sk
WHERE ag.campaign_sk IS NOT NULL AND c.campaign_sk IS NULL;

-- check: ad_group_audience_fk_orphan | severity: error
SELECT ag.* FROM ${catalog}.${cmn_schema}.ad_group ag
LEFT JOIN ${catalog}.${marketing_schema}.audience a ON ag.audience_sk = a.audience_sk
WHERE ag.audience_sk IS NOT NULL AND a.audience_sk IS NULL;

-- check: ad_group_campaign_businesskey_orphan | severity: error
SELECT ag.* FROM ${catalog}.${cmn_schema}.ad_group ag
LEFT JOIN (SELECT DISTINCT campaign_id FROM ${catalog}.${cmn_schema}.campaign) c
  ON ag.campaign_id = c.campaign_id
WHERE ag.campaign_id IS NOT NULL AND c.campaign_id IS NULL;

-- check: ad_group_status_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.ad_group
WHERE ad_group_status IS NOT NULL
  AND ad_group_status NOT IN ('draft', 'active', 'paused', 'completed', 'archived');

-- check: ad_group_targeting_mode_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.ad_group
WHERE targeting_mode IS NOT NULL
  AND targeting_mode NOT IN ('keyword', 'audience', 'automatic', 'contextual', 'manual');

-- check: ad_group_bid_strategy_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.ad_group
WHERE bid_strategy IS NOT NULL
  AND bid_strategy NOT IN ('manual_cpc', 'auto', 'target_cpa', 'target_roas', 'max_conversions');

-- check: ad_group_optimization_goal_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.ad_group
WHERE optimization_goal IS NOT NULL
  AND optimization_goal NOT IN ('clicks', 'conversions', 'roas', 'impressions', 'reach');

-- check: ad_group_default_bid_nonnegative | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.ad_group
WHERE default_bid_amount IS NOT NULL AND default_bid_amount < 0;

-- check: ad_group_dates_order | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.ad_group
WHERE start_date IS NOT NULL AND end_date IS NOT NULL AND end_date < start_date;

-- check: ad_group_scd2_current_open | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.ad_group
WHERE (is_current = true  AND effective_to_date IS NOT NULL)
   OR (is_current = false AND effective_to_date IS NULL);

-- check: ad_group_scd2_date_order | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.ad_group
WHERE effective_to_date IS NOT NULL AND effective_to_date <= effective_from_date;

-- ---------- creative ----------

-- check: creative_keys_not_null | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.creative
WHERE creative_sk IS NULL OR creative_id IS NULL
   OR effective_from_date IS NULL OR is_current IS NULL;

-- check: creative_business_key_unique_current | severity: error
SELECT creative_id, COUNT(*) AS current_versions
FROM ${catalog}.${cmn_schema}.creative
WHERE is_current = true
GROUP BY creative_id
HAVING COUNT(*) > 1;

-- check: creative_campaign_fk_orphan | severity: error
SELECT cr.* FROM ${catalog}.${cmn_schema}.creative cr
LEFT JOIN ${catalog}.${cmn_schema}.campaign c ON cr.campaign_sk = c.campaign_sk
WHERE cr.campaign_sk IS NOT NULL AND c.campaign_sk IS NULL;

-- check: creative_campaign_businesskey_orphan | severity: error
SELECT cr.* FROM ${catalog}.${cmn_schema}.creative cr
LEFT JOIN (SELECT DISTINCT campaign_id FROM ${catalog}.${cmn_schema}.campaign) c
  ON cr.campaign_id = c.campaign_id
WHERE cr.campaign_id IS NOT NULL AND c.campaign_id IS NULL;

-- check: creative_type_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.creative
WHERE creative_type IS NOT NULL
  AND creative_type NOT IN ('image', 'video', 'audio', 'html', 'native', 'text');

-- check: creative_approval_status_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.creative
WHERE approval_status IS NOT NULL
  AND approval_status NOT IN ('draft', 'submitted', 'approved', 'rejected', 'archived');

-- check: creative_brand_safety_class_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.creative
WHERE brand_safety_class IS NOT NULL
  AND brand_safety_class NOT IN ('safe', 'moderate', 'restricted');

-- check: creative_duration_nonnegative | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.creative
WHERE duration_seconds IS NOT NULL AND duration_seconds < 0;

-- check: creative_scd2_current_open | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.creative
WHERE (is_current = true  AND effective_to_date IS NOT NULL)
   OR (is_current = false AND effective_to_date IS NULL);

-- check: creative_scd2_date_order | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.creative
WHERE effective_to_date IS NOT NULL AND effective_to_date <= effective_from_date;

-- ---------- placement ----------

-- check: placement_keys_not_null | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.placement
WHERE placement_sk IS NULL OR placement_id IS NULL
   OR effective_from_date IS NULL OR is_current IS NULL;

-- check: placement_business_key_unique_current | severity: error
SELECT placement_id, COUNT(*) AS current_versions
FROM ${catalog}.${cmn_schema}.placement
WHERE is_current = true
GROUP BY placement_id
HAVING COUNT(*) > 1;

-- check: placement_ad_product_line_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.placement
WHERE ad_product_line IS NOT NULL
  AND ad_product_line NOT IN ('sponsored_products', 'onsite_display', 'offsite_display', 'email', 'loyalty');

-- check: placement_type_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.placement
WHERE placement_type IS NOT NULL
  AND placement_type NOT IN ('search', 'banner', 'product_listing', 'video', 'audio', 'endcap', 'shelf', 'other');

-- check: placement_ad_format_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.placement
WHERE ad_format IS NOT NULL
  AND ad_format NOT IN ('display', 'video', 'audio', 'native', 'sponsored_product', 'text');

-- check: placement_pricing_model_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.placement
WHERE pricing_model IS NOT NULL
  AND pricing_model NOT IN ('cpc', 'cpm', 'cpa', 'flat', 'other');

-- check: placement_device_type_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.placement
WHERE device_type IS NOT NULL
  AND device_type NOT IN ('desktop', 'mobile', 'tablet', 'ctv', 'other');

-- check: placement_store_scope_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.placement
WHERE store_scope IS NOT NULL
  AND store_scope NOT IN ('all_stores', 'banner', 'region', 'single_store', 'online');

-- check: placement_capacity_unit_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.placement
WHERE capacity_unit IS NOT NULL
  AND capacity_unit NOT IN ('impressions', 'slots', 'seconds', 'sov_pct');

-- check: placement_capacity_nonnegative | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.placement
WHERE sellable_capacity_qty IS NOT NULL AND sellable_capacity_qty < 0;

-- check: placement_scd2_current_open | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.placement
WHERE (is_current = true  AND effective_to_date IS NOT NULL)
   OR (is_current = false AND effective_to_date IS NULL);

-- check: placement_scd2_date_order | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.placement
WHERE effective_to_date IS NOT NULL AND effective_to_date <= effective_from_date;

-- ---------- experiment ----------

-- check: experiment_keys_not_null | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.experiment
WHERE experiment_sk IS NULL OR experiment_id IS NULL
   OR effective_from_date IS NULL OR is_current IS NULL;

-- check: experiment_business_key_unique_current | severity: error
SELECT experiment_id, COUNT(*) AS current_versions
FROM ${catalog}.${cmn_schema}.experiment
WHERE is_current = true
GROUP BY experiment_id
HAVING COUNT(*) > 1;

-- check: experiment_campaign_fk_orphan | severity: error
-- When set, the campaign under test must reference an existing campaign.
SELECT e.* FROM ${catalog}.${cmn_schema}.experiment e
LEFT JOIN ${catalog}.${cmn_schema}.campaign c ON e.campaign_sk = c.campaign_sk
WHERE e.campaign_sk IS NOT NULL AND c.campaign_sk IS NULL;

-- check: experiment_campaign_businesskey_orphan | severity: error
SELECT e.* FROM ${catalog}.${cmn_schema}.experiment e
LEFT JOIN (SELECT DISTINCT campaign_id FROM ${catalog}.${cmn_schema}.campaign) c
  ON e.campaign_id = c.campaign_id
WHERE e.campaign_id IS NOT NULL AND c.campaign_id IS NULL;

-- check: experiment_type_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.experiment
WHERE experiment_type IS NOT NULL
  AND experiment_type NOT IN ('geo_holdout', 'audience_holdout', 'ghost_ads', 'switchback', 'pre_post', 'other');

-- check: experiment_methodology_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.experiment
WHERE methodology IS NOT NULL
  AND methodology NOT IN ('randomized_control', 'matched_market', 'synthetic_control', 'difference_in_differences', 'other');

-- check: experiment_unit_of_assignment_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.experiment
WHERE unit_of_assignment IS NOT NULL
  AND unit_of_assignment NOT IN ('user', 'household', 'geo', 'store', 'device');

-- check: experiment_objective_metric_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.experiment
WHERE objective_metric IS NOT NULL
  AND objective_metric NOT IN ('incremental_sales', 'incremental_units', 'roas', 'conversion_rate', 'reach', 'other');

-- check: experiment_status_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.experiment
WHERE experiment_status IS NOT NULL
  AND experiment_status NOT IN ('draft', 'running', 'completed', 'analyzed', 'archived');

-- check: experiment_confidence_level_range | severity: error
-- Confidence level is a probability in [0,1].
SELECT * FROM ${catalog}.${cmn_schema}.experiment
WHERE confidence_level IS NOT NULL AND confidence_level NOT BETWEEN 0 AND 1;

-- check: experiment_dates_order | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.experiment
WHERE start_date IS NOT NULL AND end_date IS NOT NULL AND end_date < start_date;

-- check: experiment_scd2_current_open | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.experiment
WHERE (is_current = true  AND effective_to_date IS NOT NULL)
   OR (is_current = false AND effective_to_date IS NULL);

-- check: experiment_scd2_date_order | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.experiment
WHERE effective_to_date IS NOT NULL AND effective_to_date <= effective_from_date;

-- ---------- experiment_cell ----------

-- check: experiment_cell_keys_not_null | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.experiment_cell
WHERE experiment_cell_sk IS NULL OR experiment_cell_id IS NULL
   OR effective_from_date IS NULL OR is_current IS NULL;

-- check: experiment_cell_business_key_unique_current | severity: error
SELECT experiment_cell_id, COUNT(*) AS current_versions
FROM ${catalog}.${cmn_schema}.experiment_cell
WHERE is_current = true
GROUP BY experiment_cell_id
HAVING COUNT(*) > 1;

-- check: experiment_cell_experiment_fk_orphan | severity: error
SELECT ec.* FROM ${catalog}.${cmn_schema}.experiment_cell ec
LEFT JOIN ${catalog}.${cmn_schema}.experiment e ON ec.experiment_sk = e.experiment_sk
WHERE ec.experiment_sk IS NOT NULL AND e.experiment_sk IS NULL;

-- check: experiment_cell_experiment_businesskey_orphan | severity: error
SELECT ec.* FROM ${catalog}.${cmn_schema}.experiment_cell ec
LEFT JOIN (SELECT DISTINCT experiment_id FROM ${catalog}.${cmn_schema}.experiment) e
  ON ec.experiment_id = e.experiment_id
WHERE ec.experiment_id IS NOT NULL AND e.experiment_id IS NULL;

-- check: experiment_cell_role_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.experiment_cell
WHERE cell_role IS NOT NULL
  AND cell_role NOT IN ('treatment', 'control', 'holdout');

-- check: experiment_cell_allocation_range | severity: error
-- Traffic allocation is a percent in [0,100].
SELECT * FROM ${catalog}.${cmn_schema}.experiment_cell
WHERE traffic_allocation_pct IS NOT NULL AND traffic_allocation_pct NOT BETWEEN 0 AND 100;

-- check: experiment_cell_scd2_current_open | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.experiment_cell
WHERE (is_current = true  AND effective_to_date IS NOT NULL)
   OR (is_current = false AND effective_to_date IS NULL);

-- check: experiment_cell_scd2_date_order | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.experiment_cell
WHERE effective_to_date IS NOT NULL AND effective_to_date <= effective_from_date;

-- ---------- delivery_channel (coarse distribution channel) ----------

-- check: delivery_channel_keys_not_null | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.delivery_channel
WHERE delivery_channel_sk IS NULL OR delivery_channel_id IS NULL;

-- check: delivery_channel_id_unique | severity: error
SELECT delivery_channel_id, COUNT(*) AS n
FROM ${catalog}.${cmn_schema}.delivery_channel
GROUP BY delivery_channel_id HAVING COUNT(*) > 1;

-- check: delivery_channel_category_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.delivery_channel
WHERE delivery_channel_category IS NOT NULL
  AND delivery_channel_category NOT IN ('onsite_web', 'onsite_app', 'offsite', 'in_store_screen', 'in_store_audio', 'dooh', 'other');

-- ---------- keyword (search targeting) ----------

-- check: keyword_keys_not_null | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.keyword
WHERE keyword_sk IS NULL OR keyword_id IS NULL
   OR effective_from_date IS NULL OR is_current IS NULL;

-- check: keyword_business_key_unique_current | severity: error
SELECT keyword_id, COUNT(*) AS current_versions
FROM ${catalog}.${cmn_schema}.keyword
WHERE is_current = true
GROUP BY keyword_id
HAVING COUNT(*) > 1;

-- check: keyword_ad_group_fk_orphan | severity: error
SELECT k.* FROM ${catalog}.${cmn_schema}.keyword k
LEFT JOIN ${catalog}.${cmn_schema}.ad_group ag ON k.ad_group_sk = ag.ad_group_sk
WHERE k.ad_group_sk IS NOT NULL AND ag.ad_group_sk IS NULL;

-- check: keyword_ad_group_businesskey_orphan | severity: error
SELECT k.* FROM ${catalog}.${cmn_schema}.keyword k
LEFT JOIN (SELECT DISTINCT ad_group_id FROM ${catalog}.${cmn_schema}.ad_group) ag
  ON k.ad_group_id = ag.ad_group_id
WHERE k.ad_group_id IS NOT NULL AND ag.ad_group_id IS NULL;

-- check: keyword_match_type_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.keyword
WHERE match_type IS NOT NULL
  AND match_type NOT IN ('exact', 'phrase', 'broad', 'negative');

-- check: keyword_status_domain | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.keyword
WHERE keyword_status IS NOT NULL
  AND keyword_status NOT IN ('active', 'paused', 'archived');

-- check: keyword_bid_nonnegative | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.keyword
WHERE bid_amount IS NOT NULL AND bid_amount < 0;

-- check: keyword_scd2_current_open | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.keyword
WHERE (is_current = true  AND effective_to_date IS NOT NULL)
   OR (is_current = false AND effective_to_date IS NULL);

-- check: keyword_scd2_date_order | severity: error
SELECT * FROM ${catalog}.${cmn_schema}.keyword
WHERE effective_to_date IS NOT NULL AND effective_to_date <= effective_from_date;

-- ---------- audience ----------
-- audience DQ checks moved to canonical-core/marketing/checks.sql (ADR 0022 — audience
-- promoted to shared silver marketing; CMN now only references it via FK).
