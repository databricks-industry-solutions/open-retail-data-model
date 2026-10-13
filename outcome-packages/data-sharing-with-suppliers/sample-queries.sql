-- ============================================================
-- ORDM · Outcome Package · Data Sharing with Suppliers · sample queries
-- Version: 0.5 · Generated: 2026-07-13 · LLM-generated: true · Reviewed: 2026-07-13
-- Illustrative reads. Substitute ${catalog}/${dss_schema} at deploy time.
-- ============================================================

-- 1. Category growth decomposition, largest revenue change first (all periods).
SELECT category, fiscal_year, fiscal_period, category_revenue, delta_revenue,
       volume_effect, price_effect, mix_effect, distribution_effect
FROM ${catalog}.${dss_schema}.gold_category_growth
ORDER BY delta_revenue DESC
LIMIT 25;

-- 2. What a given supplier principal is entitled to see.
SELECT principal_id, advertiser_id, campaign_id, min_disclosure_threshold, entitlement_status
FROM ${catalog}.${dss_schema}.reporting_entitlement
WHERE is_current = TRUE AND principal_id = 'grp_supplier_00000001';

-- 3. Entitled supplier media report (a downstream row filter narrows principal_id
--    to the querying group; here we show one principal's rows).
SELECT brand_name, campaign_name, impressions, clicks, media_spend_net,
       attributed_net_sales, roas_net, iroas
FROM ${catalog}.${dss_schema}.gold_supplier_media_report
WHERE principal_id = 'grp_supplier_00000001'
ORDER BY attributed_net_sales DESC;

-- 4. Published report history for one advertiser (immutable snapshots, versioned).
SELECT snapshot_date, report_version, report_level, campaign_id,
       media_spend_net, attributed_net_sales, roas_net
FROM ${catalog}.${dss_schema}.supplier_media_report_snapshot
WHERE advertiser_id = 'ADV-SUP-00000001-1'
ORDER BY snapshot_date DESC, report_version DESC;

-- 5. Reconcile the live report vs the latest published snapshot (dispute check).
SELECT l.advertiser_id, l.campaign_id,
       l.attributed_net_sales AS live_sales,
       s.attributed_net_sales AS published_sales,
       l.attributed_net_sales - s.attributed_net_sales AS delta
FROM (SELECT advertiser_id, campaign_id, SUM(attributed_net_sales) AS attributed_net_sales
      FROM ${catalog}.${dss_schema}.gold_supplier_media_report GROUP BY advertiser_id, campaign_id) l
JOIN ${catalog}.${dss_schema}.supplier_media_report_snapshot s
  ON s.advertiser_id = l.advertiser_id AND s.campaign_id = l.campaign_id
ORDER BY ABS(l.attributed_net_sales - s.attributed_net_sales) DESC;

-- ========== Joint Demand Planning (CPFR) ==========

-- 6. What a given partner principal is entitled to collaborate on.
SELECT principal_id, supplier_id, product_id, plan_horizon_weeks, min_disclosure_threshold, collaboration_status
FROM ${catalog}.${dss_schema}.demand_collaboration
WHERE is_current = TRUE AND principal_id = 'grp_supplier_00000001';

-- 7. Entitled joint demand plan for one partner (a downstream row filter narrows
--    principal_id to the querying group; here we show one principal's rows).
SELECT supplier_name, product_name, fiscal_week_id,
       retailer_qty, supplier_qty, consensus_qty, statistical_forecast_qty,
       plan_variance_pct, consensus_vs_baseline_pct
FROM ${catalog}.${dss_schema}.gold_joint_demand_plan
WHERE principal_id = 'grp_supplier_00000001'
ORDER BY fiscal_week_id, product_name;

-- 8. The CPFR exception queue for a partner, highest demand value at risk first.
SELECT supplier_name, product_name, fiscal_week_id, exception_reason,
       retailer_qty, supplier_qty, consensus_qty, demand_value_at_risk, priority_rank
FROM ${catalog}.${dss_schema}.gold_demand_plan_exceptions
WHERE principal_id = 'grp_supplier_00000001'
ORDER BY priority_rank;

-- 9. Published consensus history for one supplier × product (immutable, versioned).
SELECT snapshot_date, plan_version, fiscal_week_id,
       consensus_qty, consensus_value_net, retailer_qty, supplier_qty, variance_pct
FROM ${catalog}.${dss_schema}.consensus_forecast_snapshot
WHERE supplier_id = 'SUP-00000001' AND product_id = 'PRD-00000001'
ORDER BY snapshot_date DESC, plan_version DESC;

-- ========== Data Monetization ==========

-- 10. What data products a given partner principal has licensed, and on what terms.
SELECT s.data_product_id, p.data_product_name, p.pricing_model, p.consumption_unit,
       s.supplier_id, s.contracted_price_amount, s.contracted_units, s.billing_frequency,
       s.term_start_date, s.term_end_date, s.subscription_status
FROM ${catalog}.${dss_schema}.data_product_subscription s
LEFT JOIN ${catalog}.${dss_schema}.data_product p
  ON p.data_product_id = s.data_product_id AND p.is_current = TRUE
WHERE s.is_current = TRUE AND s.principal_id = 'grp_supplier_00000001';

-- 11. Entitled data-monetization revenue for one partner (a downstream row filter
--     narrows principal_id to the querying group; here we show one principal's rows).
SELECT data_product_name, supplier_name, fiscal_year, fiscal_period,
       consumption_units, data_revenue_amount, contract_utilisation_pct,
       revenue_per_consumption_unit, media_spend_net, total_monetised_value,
       data_revenue_share_pct, currency_code
FROM ${catalog}.${dss_schema}.gold_data_product_revenue
WHERE principal_id = 'grp_supplier_00000001'
ORDER BY fiscal_year, fiscal_period, data_product_name;

-- 12. The data-monetization attention queue for a partner, highest revenue at risk first.
SELECT data_product_name, supplier_name, fiscal_year, fiscal_period, exception_reason,
       contracted_units, consumption_units, contract_utilisation_pct,
       revenue_at_risk, priority_rank
FROM ${catalog}.${dss_schema}.gold_data_monetization_exceptions
WHERE principal_id = 'grp_supplier_00000001'
ORDER BY priority_rank;

-- 13. Which data products earn the most, and how efficiently (revenue per unit), across
--     the fiscal year. Aggregated WITHIN a single principal: the view emits one row per
--     entitled principal, so summing across principals would double-count shared revenue.
--     revenue_per_unit is a ratio of SUMs (a true weighted average), not an average of
--     the per-row ratios.
SELECT data_product_name, pricing_model,
       SUM(consumption_units)   AS consumption_units,
       SUM(data_revenue_amount) AS data_revenue_amount,
       SUM(data_revenue_amount) / NULLIF(SUM(consumption_units), 0) AS revenue_per_unit
FROM ${catalog}.${dss_schema}.gold_data_product_revenue
WHERE principal_id = 'grp_supplier_00000001'
  AND fiscal_year = 2026
GROUP BY data_product_name, pricing_model
ORDER BY data_revenue_amount DESC NULLS LAST;
