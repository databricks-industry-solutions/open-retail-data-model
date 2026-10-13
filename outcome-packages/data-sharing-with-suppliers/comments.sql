-- ============================================================
-- ORDM · Outcome Package · Data Sharing with Suppliers · column comments
-- Version: 0.5 · Generated: 2026-06-10 · LLM-generated: true · Reviewed: 2026-08-03 (Data Monetization gold-view comments added)
-- Column-level documentation for this package's gold views (Genie / AI-BI / UC),
-- sectioned by use case: Category Growth, Media Measurement, Joint Demand Planning,
-- Data Monetization. Run AFTER the views exist.
-- ============================================================

COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.category IS 'Merchandising category.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.fiscal_year IS 'NRF fiscal year.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.fiscal_period IS 'NRF 4-5-4 fiscal period (1-12).';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.category_revenue IS 'Category net revenue in the period.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.category_units IS 'Category units sold in the period.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.category_margin IS 'Category gross margin (revenue - units x unit_cost).';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.prior_period_revenue IS 'Revenue in the prior fiscal period (period_index - 1).';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.delta_revenue IS 'category_revenue - prior_period_revenue (the four effects reconcile to this).';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.pop_growth_pct IS 'Period-over-period revenue growth %; NULL when no prior period.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.prior_year_revenue IS 'Revenue in the same fiscal period last year (period_index - 12).';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.yoy_growth_pct IS 'Year-over-year revenue growth %; NULL when no prior-year period.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.distribution_effect IS 'Delta-revenue from changing the number of product x store selling points.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.volume_effect IS 'Delta-revenue from changing units per selling point (depth).';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.price_effect IS 'Delta-revenue from like-for-like sub-category price change.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.mix_effect IS 'Delta-revenue from shifting the sub-category mix.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.category_share IS 'category_revenue / total period revenue (sums to ~1 across categories).';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.promo_contribution IS 'Incremental margin from promotions in the category that period (NULL if the promo view is absent).';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.value_share_platinum IS 'Share of customer-attributed category revenue from PLATINUM CLV customers.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.value_share_gold IS 'Share of customer-attributed category revenue from GOLD CLV customers.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.value_share_silver IS 'Share of customer-attributed category revenue from SILVER CLV customers.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.value_share_bronze IS 'Share of customer-attributed category revenue from BRONZE CLV customers.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.top_supplier_id IS 'Supplier with the largest share of category procurement spend.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.supplier_top_share IS 'That supplier share of category procurement spend.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_category_growth.supplier_top_score IS 'That supplier average scorecard composite (NULL if the scorecard is absent).';

-- ========== gold_supplier_media_report (media measurement) ==========
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_supplier_media_report.principal_id IS 'Governance principal entitled to see this row (row-filter key).';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_supplier_media_report.advertiser_id IS 'Durable advertiser business key.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_supplier_media_report.brand_name IS 'Advertised brand name.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_supplier_media_report.campaign_id IS 'Durable campaign business key.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_supplier_media_report.campaign_name IS 'Campaign display name.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_supplier_media_report.impressions IS 'Impressions disclosed to the supplier.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_supplier_media_report.media_spend_net IS 'Net media spend, reporting/base currency.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_supplier_media_report.attributed_net_sales IS 'Attributed net sales, reporting/base currency.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_supplier_media_report.roas_net IS 'Return on ad spend.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_supplier_media_report.iroas IS 'Incremental ROAS.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_supplier_media_report.fresh_as_of_ts IS 'View evaluation timestamp (UTC).';

-- ========== gold_joint_demand_plan (joint demand planning) ==========
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_joint_demand_plan.principal_id IS 'Governance principal entitled to see this row (row-filter key).';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_joint_demand_plan.supplier_id IS 'Durable supplier business key.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_joint_demand_plan.supplier_name IS 'Supplier registered/legal name.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_joint_demand_plan.product_id IS 'Durable product business key.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_joint_demand_plan.product_name IS 'Product display name.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_joint_demand_plan.fiscal_week_id IS 'Fiscal week identifier = fiscal_year * 100 + fiscal_week.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_joint_demand_plan.plan_cycle_id IS 'CPFR plan cycle the consensus was agreed in.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_joint_demand_plan.retailer_qty IS 'Latest retailer-submitted demand quantity for the week.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_joint_demand_plan.supplier_qty IS 'Latest supplier-submitted demand quantity for the week.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_joint_demand_plan.consensus_qty IS 'Agreed consensus demand quantity for the week.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_joint_demand_plan.retailer_value_net IS 'Latest retailer-submitted net value for the week, reporting/base currency.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_joint_demand_plan.supplier_value_net IS 'Latest supplier-submitted net value for the week, reporting/base currency.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_joint_demand_plan.consensus_value_net IS 'Agreed consensus net value, reporting/base currency.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_joint_demand_plan.currency_code IS 'Amount currency, ISO 4217 alpha-3.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_joint_demand_plan.statistical_forecast_qty IS 'Statistical demand baseline from the Smarter Demand package, allocated to this supplier by its demand share of the product x week (so a product shared by multiple suppliers does not fan the whole-product baseline onto every row). NULL if that package is absent.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_joint_demand_plan.plan_variance_pct IS 'Retailer-vs-supplier disagreement recomputed LIVE from the latest submissions = (retailer_qty - supplier_qty) / supplier_qty. Live counterpart of the frozen consensus_forecast_snapshot.variance_pct.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_joint_demand_plan.consensus_vs_baseline_pct IS 'Consensus lift over the statistical baseline = (consensus_qty - statistical_forecast_qty) / statistical_forecast_qty.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_joint_demand_plan.fresh_as_of_ts IS 'View evaluation timestamp (UTC).';

-- ========== gold_demand_plan_exceptions (joint demand planning) ==========
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_demand_plan_exceptions.principal_id IS 'Governance principal entitled to see this row (row-filter key).';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_demand_plan_exceptions.supplier_id IS 'Durable supplier business key.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_demand_plan_exceptions.supplier_name IS 'Supplier registered/legal name.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_demand_plan_exceptions.product_id IS 'Durable product business key.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_demand_plan_exceptions.product_name IS 'Product display name.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_demand_plan_exceptions.fiscal_week_id IS 'Fiscal week identifier = fiscal_year * 100 + fiscal_week.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_demand_plan_exceptions.plan_cycle_id IS 'CPFR plan cycle the exception was raised in.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_demand_plan_exceptions.exception_reason IS 'Why the row needs attention. One of: missing_retailer_plan, missing_supplier_plan, party_disagreement, consensus_baseline_divergence.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_demand_plan_exceptions.retailer_qty IS 'Latest retailer-submitted demand quantity for the week.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_demand_plan_exceptions.supplier_qty IS 'Latest supplier-submitted demand quantity for the week.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_demand_plan_exceptions.consensus_qty IS 'Agreed consensus demand quantity for the week.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_demand_plan_exceptions.statistical_forecast_qty IS 'Statistical demand baseline from the Smarter Demand package (NULL if absent).';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_demand_plan_exceptions.plan_variance_pct IS 'Retailer-vs-supplier disagreement on the latest submissions.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_demand_plan_exceptions.consensus_vs_baseline_pct IS 'Consensus lift over the statistical baseline.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_demand_plan_exceptions.demand_value_at_risk IS 'Consensus net value used to rank the exception queue.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_demand_plan_exceptions.currency_code IS 'Amount currency, ISO 4217 alpha-3.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_demand_plan_exceptions.priority_rank IS 'Rank within a principal by demand_value_at_risk (1 = highest).';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_demand_plan_exceptions.fresh_as_of_ts IS 'View evaluation timestamp (UTC).';

-- ========== gold_data_product_revenue (data monetization) ==========
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.principal_id IS 'Governance principal entitled to see this row (row-filter key).';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.data_product_id IS 'Durable data-product business key.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.data_product_name IS 'Display name of the licensed data product.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.data_product_category IS 'Kind of data product. One of: media_measurement, demand_collaboration, category_benchmark, audience_insight.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.pricing_model IS 'How the product is charged. One of: subscription_flat, per_consumption_unit, tiered, revenue_share.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.consumption_unit IS 'Unit the consumption_units measure is denominated in. One of: query, row_scanned, report_delivery, api_call.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.supplier_scope_id IS 'Durable supplier business key the LICENCE is scoped to; NULL for a licence spanning every supplier the product covers (not the supplier of an individual usage row).';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.supplier_name IS 'Supplier registered/legal name; NULL for an all-supplier licence.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.advertiser_id IS 'Durable advertiser business key the licence is tied to (the brand role of the supplier); NULL when not advertiser-scoped. This is the grain the media allocation is computed over.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.fiscal_year IS 'NRF fiscal year.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.fiscal_period IS 'NRF 4-5-4 fiscal period (1-12).';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.subscription_status IS 'Licence lifecycle at its latest version. One of: active, suspended, expired (pending and cancelled licences are excluded).';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.billing_frequency IS 'How often the subscription bills. One of: monthly, quarterly, annual.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.term_start_date IS 'Contractual term start.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.term_end_date IS 'Contractual term end; NULL for an evergreen/auto-renewing term.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.contracted_price_amount IS 'Negotiated price per billing period, reporting/base currency.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.list_price_amount IS 'Published rate-card price from the data-product catalog, reporting/base currency.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.contracted_units IS 'Committed consumption allowance per BILLING period (not per fiscal period; contract_utilisation_pct pro-rates it).';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.consumption_units IS 'Metered consumption in the period, in the product consumption_unit. NULL when the licence billed no usage that period.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.billed_query_count IS 'Number of billable requests behind consumption_units (transparency; not the billing basis).';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.data_revenue_amount IS 'Revenue billed from metered consumption in the period, reporting/base currency.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.currency_code IS 'Amount currency, ISO 4217 alpha-3.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.last_usage_date IS 'Most recent usage date in the period; NULL when the licence was unused or its usage was suppressed.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.usage_suppressed_flag IS 'TRUE when this period had usage but below the entitled disclosure floor (the grant threshold, else the data product default), so the usage measures (and every metric derived from them) are withheld as NULL while the licence row itself remains visible. Distinguishes "withheld" from "genuinely unused": a row with this flag set must NOT be read as paid-but-unused. Distinct from data_share_consumption.threshold_suppressed_flag, which is set upstream on a SOURCE usage row and excludes it before aggregation; this flag marks an aggregate that was computed and then withheld.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.contract_discount_pct IS 'Discount granted off the rate card = (list_price_amount - contracted_price_amount) / list_price_amount.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.contract_utilisation_pct IS 'Share of the period allowance consumed = consumption_units / (contracted_units pro-rated from the billing frequency to one fiscal period). Greater than 1 means the licence ran over its commitment; near 0 means it was paid for and not used. NULL for an uncapped licence or an unrecognised billing frequency.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.revenue_per_consumption_unit IS 'Realised price the partner effectively paid per metered unit = data_revenue_amount / consumption_units.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.media_spend_net IS 'The advertiser retail-media net spend for the period from the Commerce Media Networks package, ALLOCATED to this licence row by its revenue share of the advertiser (so per-row values sum back to the advertiser actual spend, rather than fanning the whole total onto every row). NULL if that package is absent or unpopulated.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.total_monetised_value IS 'Total monetised value of the supplier relationship for the period = data_revenue_amount + media_spend_net. NULL-propagating: NULL if either component is absent, rather than presenting a partial sum as a total.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.data_revenue_share_pct IS 'Data revenue as a share of total monetised value. Because the media allocation is revenue-proportional, this is invariant across the licence rows of one advertiser x period — it is the advertiser-level data share, carried per row so it survives the row filter.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_product_revenue.fresh_as_of_ts IS 'View evaluation timestamp (UTC).';

-- ========== gold_data_monetization_exceptions (data monetization) ==========
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_monetization_exceptions.principal_id IS 'Governance principal entitled to see this row (row-filter key).';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_monetization_exceptions.data_product_id IS 'Durable data-product business key.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_monetization_exceptions.data_product_name IS 'Display name of the licensed data product.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_monetization_exceptions.data_product_category IS 'Kind of data product.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_monetization_exceptions.supplier_scope_id IS 'Durable supplier business key the licence is scoped to; NULL for an all-supplier licence.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_monetization_exceptions.supplier_name IS 'Supplier registered/legal name; NULL for an all-supplier licence.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_monetization_exceptions.fiscal_year IS 'NRF fiscal year.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_monetization_exceptions.fiscal_period IS 'NRF 4-5-4 fiscal period (1-12) the exception was raised in.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_monetization_exceptions.exception_reason IS 'Why the row needs attention. One of: paid_unused_subscription, under_consumed_subscription, over_contracted_consumption, lapsing_term, rate_card_divergence.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_monetization_exceptions.subscription_status IS 'Licence lifecycle at its latest version.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_monetization_exceptions.term_end_date IS 'Contractual term end; NULL for an evergreen term.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_monetization_exceptions.contracted_units IS 'Committed consumption allowance per billing period.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_monetization_exceptions.consumption_units IS 'Metered consumption in the period.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_monetization_exceptions.contract_utilisation_pct IS 'Share of the period allowance consumed (pro-rated to one fiscal period).';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_monetization_exceptions.contracted_price_amount IS 'Negotiated price per billing period, reporting/base currency.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_monetization_exceptions.data_revenue_amount IS 'Revenue billed from metered consumption in the period, reporting/base currency.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_monetization_exceptions.revenue_per_consumption_unit IS 'Realised price per metered unit.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_monetization_exceptions.contract_discount_pct IS 'Discount granted off the rate card.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_monetization_exceptions.last_usage_date IS 'Most recent usage date in the period; NULL when unused.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_monetization_exceptions.revenue_at_risk IS 'Money exposed by the exception, used to rank the queue: the contracted price for an unused licence (what a non-renewal would cost), else the realised revenue.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_monetization_exceptions.currency_code IS 'Amount currency, ISO 4217 alpha-3.';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_monetization_exceptions.priority_rank IS 'Rank within a principal by revenue_at_risk (1 = highest).';
COMMENT ON COLUMN ${catalog}.${dss_schema}.gold_data_monetization_exceptions.fresh_as_of_ts IS 'View evaluation timestamp (UTC).';
