-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks · column comments
-- Version: 0.5 · Generated: 2026-07-13 · LLM-generated: true · Reviewed: 2026-07-13
-- Column-level documentation for the gold views (Genie / AI-BI / UC metadata, and
-- the source of column descriptions in the generated ODCS contract). COMMENT ON
-- COLUMN is standard SQL — consistent with the engine-neutral choice. Run AFTER
-- the views exist.
-- ============================================================

-- ========== gold_campaign_performance ==========
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.metric_date IS 'Business date of the performance row.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.campaign_id IS 'Durable campaign business key.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.campaign_name IS 'Campaign display name.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.advertiser_id IS 'Durable advertiser business key.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.brand_name IS 'Advertised brand name.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.attribution_model IS 'The single attribution model the attributed measures/ROAS are reported under for this campaign×day (one model per grain).';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.impressions IS 'Total impressions.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.viewable_impressions IS 'Viewable impressions (MRC/IAB).';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.clicks IS 'Total clicks.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.conversions IS 'Attributed conversions.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.orders IS 'Attributed orders.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.units IS 'Attributed units.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.media_spend_net IS 'Net media spend, reporting/base currency.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.attributed_net_sales IS 'Attributed net sales, reporting/base currency.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.same_sku_sales IS 'Same-SKU attributed sales.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.halo_sales IS 'Halo (brand/category) attributed sales.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.new_to_brand_sales IS 'New-to-brand attributed sales.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.incremental_sales IS 'Incremental sales (from experiment), reporting/base currency.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.ctr IS 'Click-through rate = clicks / impressions.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.viewable_rate IS 'Viewable impressions / impressions.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.ivt_rate IS 'Invalid-traffic impressions / gross impressions.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.cvr IS 'Conversion rate = conversions / clicks.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.roas_net IS 'Return on ad spend = attributed_net_sales / media_spend_net.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.iroas IS 'Incremental ROAS = incremental_sales / media_spend_net.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.new_to_brand_rate IS 'New-to-brand sales / attributed net sales.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_campaign_performance.fresh_as_of_ts IS 'View evaluation timestamp (UTC).';

-- ========== gold_incrementality_readout ==========
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_incrementality_readout.experiment_id IS 'Durable experiment business key.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_incrementality_readout.experiment_name IS 'Experiment display name.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_incrementality_readout.methodology IS 'Causal method used.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_incrementality_readout.campaign_id IS 'Durable campaign business key.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_incrementality_readout.snapshot_date IS 'Measurement snapshot date.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_incrementality_readout.metric_name IS 'Metric evaluated.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_incrementality_readout.analysis_level IS 'Slice level of the result.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_incrementality_readout.incremental_sales_amount IS 'Incremental sales, reporting/base currency.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_incrementality_readout.media_spend_amount IS 'Media spend attributed to treatment.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_incrementality_readout.lift_pct IS 'Relative lift of treatment over control, percent.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_incrementality_readout.iroas_value IS 'Incremental ROAS.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_incrementality_readout.confidence_level_pct IS 'Confidence level, percent.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_incrementality_readout.ci_lower_value IS 'Confidence interval lower bound.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_incrementality_readout.ci_upper_value IS 'Confidence interval upper bound.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_incrementality_readout.p_value IS 'Test p-value.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_incrementality_readout.statistical_significance_flag IS 'TRUE if significant at the confidence level.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_incrementality_readout.fresh_as_of_ts IS 'View evaluation timestamp (UTC).';

-- ========== gold_pacing_current ==========
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_pacing_current.campaign_id IS 'Durable campaign business key.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_pacing_current.snapshot_ts IS 'Latest pacing snapshot timestamp (UTC).';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_pacing_current.daily_budget IS 'Daily budget target, reporting/base currency.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_pacing_current.actual_spend_to_date IS 'Actual cumulative spend to date.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_pacing_current.pacing_ratio IS 'actual_spend_to_date / planned_spend_to_date.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_pacing_current.pacing_status IS 'on_track / under_pacing / over_pacing / exhausted.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_pacing_current.fresh_as_of_ts IS 'View evaluation timestamp (UTC).';

-- ========== gold_supplier_campaign_report ==========
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_supplier_campaign_report.advertiser_id IS 'Durable advertiser business key.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_supplier_campaign_report.brand_name IS 'Advertised brand name.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_supplier_campaign_report.campaign_id IS 'Durable campaign business key.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_supplier_campaign_report.campaign_name IS 'Campaign display name.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_supplier_campaign_report.attribution_model IS 'The single attribution model the campaign''s attributed measures/ROAS are reported under (one model per grain).';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_supplier_campaign_report.impressions IS 'Total impressions over the campaign.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_supplier_campaign_report.media_spend_net IS 'Net media spend, reporting/base currency.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_supplier_campaign_report.attributed_net_sales IS 'Attributed net sales, reporting/base currency.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_supplier_campaign_report.roas_net IS 'Return on ad spend.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_supplier_campaign_report.iroas IS 'Incremental ROAS.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.gold_supplier_campaign_report.fresh_as_of_ts IS 'View evaluation timestamp (UTC).';

-- ========== store_zone_interval (DEPRECATED EXACT-NAME SHIM, ADR 0033) ==========
-- The tag, not just the header comment. ADR 0010 makes system.certification_status the Genie
-- Ontology authority signal (certified | deprecated), so without it this shim keeps ranking
-- alongside connected_store_signals.gold_zone_traffic_current, which is the view consumers are
-- being asked to move to. It lives here rather than in the view file because a gold/*.sql file
-- is parsed as exactly one CREATE VIEW. Removal date is in the view header: 2026-10-31.
ALTER VIEW ${catalog}.${cmn_schema}.store_zone_interval SET TAGS ('system.certification_status' = 'deprecated');
COMMENT ON COLUMN ${catalog}.${cmn_schema}.store_zone_interval.store_zone_interval_id IS 'DEPRECATED EXACT-NAME SHIM. New rows use a stable store-zone-day id; migrate to connected_store_signals.gold_zone_traffic_shared.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.store_zone_interval.store_zone_code IS 'DEPRECATED EXACT-NAME SHIM. Zone code sourced from the CSS zone-day shared projection.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.store_zone_interval.interval_date IS 'DEPRECATED EXACT-NAME SHIM. CSS trading date for the disclosure-controlled daily row.';
COMMENT ON COLUMN ${catalog}.${cmn_schema}.store_zone_interval.opportunity_to_see IS 'DEPRECATED EXACT-NAME SHIM. NULL for new rows until CMN approves a versioned placement-level OTS derivation; historical values remain in the CMN legacy mapping during migration.';
