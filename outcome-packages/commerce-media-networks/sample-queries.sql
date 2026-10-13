-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks · sample queries
-- Version: 0.5 · Generated: 2026-07-13 · LLM-generated: true · Reviewed: 2026-07-13
-- Illustrative reads against the gold views. Substitute ${catalog}/${cmn_schema}
-- at deploy time. No raw PII is available in these surfaces.
-- ============================================================

-- 1. Top campaigns by ROAS in the last 30 days.
SELECT campaign_id, campaign_name, brand_name,
       SUM(media_spend_net)      AS spend,
       SUM(attributed_net_sales) AS attributed_sales,
       ROUND(SUM(attributed_net_sales) / NULLIF(SUM(media_spend_net), 0), 2) AS roas
FROM ${catalog}.${cmn_schema}.gold_campaign_performance
WHERE metric_date >= date_add(current_date(), -30)
GROUP BY campaign_id, campaign_name, brand_name
ORDER BY roas DESC
LIMIT 25;

-- 2. Viewability and invalid-traffic quality by campaign.
SELECT campaign_id,
       ROUND(AVG(viewable_rate), 4) AS avg_viewable_rate,
       ROUND(AVG(ivt_rate), 4)      AS avg_ivt_rate,
       ROUND(AVG(ctr), 4)           AS avg_ctr
FROM ${catalog}.${cmn_schema}.gold_campaign_performance
GROUP BY campaign_id
ORDER BY avg_ivt_rate DESC;

-- 3. Incrementality readout — significant lifts with iROAS.
SELECT experiment_name, campaign_id, metric_name, analysis_level,
       lift_pct, iroas_value, confidence_level_pct, p_value
FROM ${catalog}.${cmn_schema}.gold_incrementality_readout
WHERE statistical_significance_flag = TRUE
ORDER BY iroas_value DESC;

-- 4. Same-SKU vs halo vs new-to-brand mix per brand.
SELECT brand_name,
       SUM(same_sku_sales)     AS same_sku,
       SUM(halo_sales)         AS halo,
       SUM(new_to_brand_sales) AS new_to_brand,
       ROUND(SUM(new_to_brand_sales) / NULLIF(SUM(attributed_net_sales), 0), 4) AS ntb_rate
FROM ${catalog}.${cmn_schema}.gold_campaign_performance
GROUP BY brand_name
ORDER BY new_to_brand DESC;

-- 5. Campaigns over-pacing right now.
SELECT campaign_id, campaign_name, pacing_ratio, pacing_status, actual_spend_to_date, daily_budget
FROM ${catalog}.${cmn_schema}.gold_pacing_current
WHERE pacing_status IN ('over_pacing', 'exhausted')
ORDER BY pacing_ratio DESC;

-- 6. Supplier-safe campaign report for one advertiser.
SELECT campaign_name, impressions, clicks, media_spend_net, attributed_net_sales, roas_net, iroas
FROM ${catalog}.${cmn_schema}.gold_supplier_campaign_report
WHERE advertiser_id = 'ADV-SUP-00000001-1'
ORDER BY attributed_net_sales DESC;
