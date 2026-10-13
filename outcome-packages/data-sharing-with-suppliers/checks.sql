-- ============================================================
-- ORDM · Outcome Package · Data Sharing with Suppliers · data-quality checks
-- Version: 0.5 · Generated: 2026-06-09 · LLM-generated: true · Reviewed: 2026-08-01 (JDP checks added)
-- Each assertion SELECTs violating rows; 0 rows = PASS. `metric` checks report
-- a value and never fail the run.
-- ============================================================

-- check: growth_decomposition_reconciles | severity: error
-- The four effects must sum to delta_revenue within tolerance (when a prior period exists).
SELECT * FROM ${catalog}.${dss_schema}.gold_category_growth
WHERE delta_revenue IS NOT NULL
  AND ABS((distribution_effect + volume_effect + price_effect + mix_effect) - delta_revenue) > 0.01;

-- check: category_share_sums_to_one | severity: error
-- category_share must sum to ~1.0 across categories within each fiscal period.
SELECT fiscal_year, fiscal_period, SUM(category_share) AS share_sum
FROM ${catalog}.${dss_schema}.gold_category_growth
GROUP BY fiscal_year, fiscal_period
HAVING ABS(SUM(category_share) - 1.0) > 0.001;

-- check: growth_pct_null_only_when_prior_absent | severity: error
-- pop_growth_pct may be NULL only when the prior period is absent or zero.
SELECT * FROM ${catalog}.${dss_schema}.gold_category_growth
WHERE pop_growth_pct IS NULL AND prior_period_revenue IS NOT NULL AND prior_period_revenue <> 0;

-- check: category_growth_rowcount | severity: metric
SELECT COUNT(*) AS rows FROM ${catalog}.${dss_schema}.gold_category_growth;

-- check: promo_contribution_null_rate | severity: metric
-- Reported only: NULL-rate of the promo signal (degraded if gold_promo_roi is absent).
SELECT ROUND(AVG(CASE WHEN promo_contribution IS NULL THEN 1.0 ELSE 0.0 END), 4) AS promo_null_rate
FROM ${catalog}.${dss_schema}.gold_category_growth;

-- check: value_mix_null_rate | severity: metric
-- Reported only: NULL-rate of the value-tier-mix signal (degraded if gold_customer_ltv is absent).
SELECT ROUND(AVG(CASE WHEN value_share_platinum IS NULL THEN 1.0 ELSE 0.0 END), 4) AS value_mix_null_rate
FROM ${catalog}.${dss_schema}.gold_category_growth;

-- check: supplier_contribution_null_rate | severity: metric
-- Reported only: NULL-rate of the supplier signal (degraded if procurement/scorecard is absent).
SELECT ROUND(AVG(CASE WHEN top_supplier_id IS NULL THEN 1.0 ELSE 0.0 END), 4) AS supplier_null_rate
FROM ${catalog}.${dss_schema}.gold_category_growth;

-- ========== reporting_entitlement (media measurement) ==========

-- check: re_keys_not_null | severity: error
SELECT * FROM ${catalog}.${dss_schema}.reporting_entitlement
WHERE reporting_entitlement_sk IS NULL OR reporting_entitlement_id IS NULL OR principal_id IS NULL
   OR effective_from_date IS NULL OR is_current IS NULL;

-- check: re_business_key_unique_current | severity: error
SELECT reporting_entitlement_id, COUNT(*) AS n
FROM ${catalog}.${dss_schema}.reporting_entitlement
WHERE is_current = true GROUP BY reporting_entitlement_id HAVING COUNT(*) > 1;

-- check: re_advertiser_fk_orphan | severity: error
SELECT e.* FROM ${catalog}.${dss_schema}.reporting_entitlement e
LEFT JOIN ${catalog}.${cmn_schema}.advertiser sb ON e.advertiser_sk = sb.advertiser_sk
WHERE e.advertiser_sk IS NOT NULL AND sb.advertiser_sk IS NULL;

-- check: re_campaign_fk_orphan | severity: error
-- The optional campaign scope must resolve to an existing campaign (guarded; NULL = brand-wide).
SELECT e.* FROM ${catalog}.${dss_schema}.reporting_entitlement e
LEFT JOIN ${catalog}.${cmn_schema}.campaign c ON e.campaign_sk = c.campaign_sk
WHERE e.campaign_sk IS NOT NULL AND c.campaign_sk IS NULL;

-- check: re_status_domain | severity: error
SELECT * FROM ${catalog}.${dss_schema}.reporting_entitlement
WHERE entitlement_status IS NOT NULL AND entitlement_status NOT IN ('active', 'suspended', 'revoked');

-- check: re_scd2_current_open | severity: error
SELECT * FROM ${catalog}.${dss_schema}.reporting_entitlement
WHERE (is_current = true AND effective_to_date IS NOT NULL) OR (is_current = false AND effective_to_date IS NULL);

-- ========== supplier_media_report_snapshot ==========

-- check: smrs_grain_unique | severity: error
-- Grain integrity: assert the DURABLE business key, not the IDENTITY surrogate
-- (*_sk is generated per row and can never collide — a tautology).
SELECT supplier_media_report_snapshot_id, COUNT(*) AS n
FROM ${catalog}.${dss_schema}.supplier_media_report_snapshot
GROUP BY supplier_media_report_snapshot_id HAVING COUNT(*) > 1;

-- check: smrs_advertiser_fk_orphan | severity: error
SELECT s.* FROM ${catalog}.${dss_schema}.supplier_media_report_snapshot s
LEFT JOIN ${catalog}.${cmn_schema}.advertiser sb ON s.advertiser_sk = sb.advertiser_sk
WHERE s.advertiser_sk IS NOT NULL AND sb.advertiser_sk IS NULL;

-- check: smrs_campaign_fk_orphan | severity: error
-- The optional campaign scope must resolve to an existing campaign (guarded; NULL = brand-wide).
SELECT s.* FROM ${catalog}.${dss_schema}.supplier_media_report_snapshot s
LEFT JOIN ${catalog}.${cmn_schema}.campaign c ON s.campaign_sk = c.campaign_sk
WHERE s.campaign_sk IS NOT NULL AND c.campaign_sk IS NULL;

-- check: smrs_report_level_domain | severity: error
SELECT * FROM ${catalog}.${dss_schema}.supplier_media_report_snapshot
WHERE report_level IS NOT NULL AND report_level NOT IN ('brand', 'campaign', 'product');

-- check: smrs_single_currency | severity: error
SELECT * FROM (SELECT COUNT(DISTINCT currency_code) AS n FROM ${catalog}.${dss_schema}.supplier_media_report_snapshot WHERE currency_code IS NOT NULL) WHERE n > 1;

-- ========== gold_supplier_media_report — no person-level identifiers ==========

-- check: smr_gold_no_raw_pii | severity: error
-- The supplier report is aggregate; it must not expose any person-level hashed id.
SELECT table_name, column_name
FROM ${catalog}.information_schema.columns
WHERE table_schema = '${dss_schema}'
  AND table_name = 'gold_supplier_media_report'
  AND column_name IN ('customer_key_hash', 'household_key_hash', 'assignment_unit_key_hash');

-- ========== demand_collaboration (joint demand planning) ==========

-- check: dc_keys_not_null | severity: error
SELECT * FROM ${catalog}.${dss_schema}.demand_collaboration
WHERE demand_collaboration_sk IS NULL OR demand_collaboration_id IS NULL OR principal_id IS NULL
   OR effective_from_date IS NULL OR is_current IS NULL;

-- check: dc_business_key_unique_current | severity: error
SELECT demand_collaboration_id, COUNT(*) AS n
FROM ${catalog}.${dss_schema}.demand_collaboration
WHERE is_current = true GROUP BY demand_collaboration_id HAVING COUNT(*) > 1;

-- check: dc_scope_unique_current | severity: error
-- Enforce the stated grain: at most one active current grant per (principal, supplier,
-- product-scope). Two active grants for the same scope would both match the entitlement
-- join and leave the disclosure floor applied nondeterministically. COALESCE the nullable
-- product scope to a sentinel so supplier-wide grants (product_sk NULL) compare equal.
SELECT principal_id, supplier_sk, COALESCE(product_sk, -1) AS product_scope, COUNT(*) AS n
FROM ${catalog}.${dss_schema}.demand_collaboration
WHERE is_current = true AND collaboration_status = 'active'
GROUP BY principal_id, supplier_sk, COALESCE(product_sk, -1) HAVING COUNT(*) > 1;

-- check: dc_supplier_fk_orphan | severity: error
SELECT c.* FROM ${catalog}.${dss_schema}.demand_collaboration c
LEFT JOIN ${catalog}.${supplier_schema}.supplier sb ON c.supplier_sk = sb.supplier_sk
WHERE c.supplier_sk IS NOT NULL AND sb.supplier_sk IS NULL;

-- check: dc_product_fk_orphan | severity: error
-- The optional product scope must resolve to an existing product (guarded; NULL = supplier-wide).
SELECT c.* FROM ${catalog}.${dss_schema}.demand_collaboration c
LEFT JOIN ${catalog}.${product_schema}.product p ON c.product_sk = p.product_sk
WHERE c.product_sk IS NOT NULL AND p.product_sk IS NULL;

-- check: dc_status_domain | severity: error
SELECT * FROM ${catalog}.${dss_schema}.demand_collaboration
WHERE collaboration_status IS NOT NULL AND collaboration_status NOT IN ('active', 'suspended', 'ended');

-- check: dc_scd2_current_open | severity: error
SELECT * FROM ${catalog}.${dss_schema}.demand_collaboration
WHERE (is_current = true AND effective_to_date IS NOT NULL) OR (is_current = false AND effective_to_date IS NULL);

-- ========== demand_plan_submission ==========

-- check: dps_grain_unique | severity: error
-- Grain integrity: assert the DURABLE business key, not the IDENTITY surrogate.
SELECT demand_plan_submission_id, COUNT(*) AS n
FROM ${catalog}.${dss_schema}.demand_plan_submission
GROUP BY demand_plan_submission_id HAVING COUNT(*) > 1;

-- check: dps_submitted_ts_not_null | severity: error
-- submitted_ts is the primary latest-wins ordering key in gold_joint_demand_plan; a NULL
-- would sort a genuine latest submission last and silently serve a stale plan.
SELECT * FROM ${catalog}.${dss_schema}.demand_plan_submission
WHERE submitted_ts IS NULL;

-- check: dps_supplier_fk_orphan | severity: error
SELECT s.* FROM ${catalog}.${dss_schema}.demand_plan_submission s
LEFT JOIN ${catalog}.${supplier_schema}.supplier sb ON s.supplier_sk = sb.supplier_sk
WHERE s.supplier_sk IS NOT NULL AND sb.supplier_sk IS NULL;

-- check: dps_product_fk_orphan | severity: error
SELECT s.* FROM ${catalog}.${dss_schema}.demand_plan_submission s
LEFT JOIN ${catalog}.${product_schema}.product p ON s.product_sk = p.product_sk
WHERE s.product_sk IS NOT NULL AND p.product_sk IS NULL;

-- check: dps_party_role_domain | severity: error
SELECT * FROM ${catalog}.${dss_schema}.demand_plan_submission
WHERE party_role IS NOT NULL AND party_role NOT IN ('retailer', 'supplier');

-- check: dps_status_domain | severity: error
SELECT * FROM ${catalog}.${dss_schema}.demand_plan_submission
WHERE submission_status IS NOT NULL AND submission_status NOT IN ('draft', 'submitted', 'superseded', 'withdrawn');

-- check: dps_single_currency | severity: error
SELECT * FROM (SELECT COUNT(DISTINCT currency_code) AS n FROM ${catalog}.${dss_schema}.demand_plan_submission WHERE currency_code IS NOT NULL) WHERE n > 1;

-- ========== consensus_forecast_snapshot ==========

-- check: cfs_grain_unique | severity: error
SELECT consensus_forecast_snapshot_id, COUNT(*) AS n
FROM ${catalog}.${dss_schema}.consensus_forecast_snapshot
GROUP BY consensus_forecast_snapshot_id HAVING COUNT(*) > 1;

-- check: cfs_supplier_fk_orphan | severity: error
SELECT s.* FROM ${catalog}.${dss_schema}.consensus_forecast_snapshot s
LEFT JOIN ${catalog}.${supplier_schema}.supplier sb ON s.supplier_sk = sb.supplier_sk
WHERE s.supplier_sk IS NOT NULL AND sb.supplier_sk IS NULL;

-- check: cfs_product_fk_orphan | severity: error
SELECT s.* FROM ${catalog}.${dss_schema}.consensus_forecast_snapshot s
LEFT JOIN ${catalog}.${product_schema}.product p ON s.product_sk = p.product_sk
WHERE s.product_sk IS NOT NULL AND p.product_sk IS NULL;

-- check: cfs_single_currency | severity: error
SELECT * FROM (SELECT COUNT(DISTINCT currency_code) AS n FROM ${catalog}.${dss_schema}.consensus_forecast_snapshot WHERE currency_code IS NOT NULL) WHERE n > 1;

-- ========== joint-demand fused-currency consistency ==========

-- check: jdp_cross_table_single_currency | severity: error
-- gold_joint_demand_plan and gold_demand_plan_exceptions FUSE the submission and
-- consensus monetary columns under one COALESCE'd currency_code (and rank via GREATEST
-- across them). The per-table dps_/cfs_single_currency checks each pass on a load that is
-- internally consistent but uses a DIFFERENT currency between the two tables, which would
-- silently mislabel/mis-rank the fused row. Enforce the single-reporting-currency
-- convention ACROSS the two fused tables, matching what the gold views assume.
SELECT * FROM (
  SELECT COUNT(DISTINCT currency_code) AS n FROM (
    SELECT currency_code FROM ${catalog}.${dss_schema}.demand_plan_submission WHERE currency_code IS NOT NULL
    UNION
    SELECT currency_code FROM ${catalog}.${dss_schema}.consensus_forecast_snapshot WHERE currency_code IS NOT NULL
  )
) WHERE n > 1;

-- ========== gold_joint_demand_plan — no person-level identifiers ==========

-- check: jdp_gold_no_raw_pii | severity: error
-- The joint plan is aggregate; it must not expose any person-level hashed id.
SELECT table_name, column_name
FROM ${catalog}.information_schema.columns
WHERE table_schema = '${dss_schema}'
  AND table_name = 'gold_joint_demand_plan'
  AND column_name IN ('customer_key_hash', 'household_key_hash', 'assignment_unit_key_hash');

-- check: jdp_variance_present | severity: metric
-- Reported only: NULL-rate of the party-disagreement signal (both parties must submit).
SELECT ROUND(AVG(CASE WHEN plan_variance_pct IS NULL THEN 1.0 ELSE 0.0 END), 4) AS plan_variance_null_rate
FROM ${catalog}.${dss_schema}.gold_joint_demand_plan;

-- check: jdp_baseline_null_rate | severity: metric
-- Reported only: NULL-rate of the statistical-baseline signal (degraded if the
-- Smarter Demand package is absent — expected NULL-safe behavior, never a failure).
SELECT ROUND(AVG(CASE WHEN statistical_forecast_qty IS NULL THEN 1.0 ELSE 0.0 END), 4) AS baseline_null_rate
FROM ${catalog}.${dss_schema}.gold_joint_demand_plan;

-- ========== data_product (data monetization) ==========

-- check: dp_keys_not_null | severity: error
SELECT * FROM ${catalog}.${dss_schema}.data_product
WHERE data_product_sk IS NULL OR data_product_id IS NULL
   OR effective_from_date IS NULL OR is_current IS NULL;

-- check: dp_business_key_unique_current | severity: error
SELECT data_product_id, COUNT(*) AS n
FROM ${catalog}.${dss_schema}.data_product
WHERE is_current = true GROUP BY data_product_id HAVING COUNT(*) > 1;

-- check: dp_scd2_current_open | severity: error
SELECT * FROM ${catalog}.${dss_schema}.data_product
WHERE (is_current = true AND effective_to_date IS NOT NULL) OR (is_current = false AND effective_to_date IS NULL);

-- check: dp_category_domain | severity: error
SELECT * FROM ${catalog}.${dss_schema}.data_product
WHERE data_product_category IS NOT NULL
  AND data_product_category NOT IN ('media_measurement', 'demand_collaboration', 'category_benchmark', 'audience_insight');

-- check: dp_pricing_model_domain | severity: error
SELECT * FROM ${catalog}.${dss_schema}.data_product
WHERE pricing_model IS NOT NULL
  AND pricing_model NOT IN ('subscription_flat', 'per_consumption_unit', 'tiered', 'revenue_share');

-- check: dp_consumption_unit_domain | severity: error
SELECT * FROM ${catalog}.${dss_schema}.data_product
WHERE consumption_unit IS NOT NULL
  AND consumption_unit NOT IN ('query', 'row_scanned', 'report_delivery', 'api_call');

-- check: dp_delivery_mode_domain | severity: error
SELECT * FROM ${catalog}.${dss_schema}.data_product
WHERE delivery_mode IS NOT NULL AND delivery_mode NOT IN ('share', 'api', 'file_export', 'dashboard');

-- check: dp_status_domain | severity: error
SELECT * FROM ${catalog}.${dss_schema}.data_product
WHERE data_product_status IS NOT NULL
  AND data_product_status NOT IN ('draft', 'published', 'deprecated', 'retired');

-- check: dp_usage_priced_products_have_unit | severity: error
-- A per_consumption_unit product must declare WHICH unit it meters, or the rate is
-- uninterpretable and gold_data_product_revenue's rate-card divergence is meaningless.
SELECT * FROM ${catalog}.${dss_schema}.data_product
WHERE pricing_model = 'per_consumption_unit' AND consumption_unit IS NULL;

-- check: dp_single_currency | severity: error
SELECT * FROM (SELECT COUNT(DISTINCT currency_code) AS n FROM ${catalog}.${dss_schema}.data_product WHERE currency_code IS NOT NULL) WHERE n > 1;

-- ========== data_product_subscription ==========

-- check: dpsub_keys_not_null | severity: error
SELECT * FROM ${catalog}.${dss_schema}.data_product_subscription
WHERE data_product_subscription_sk IS NULL OR data_product_subscription_id IS NULL
   OR principal_id IS NULL OR effective_from_date IS NULL OR is_current IS NULL;

-- check: dpsub_business_key_unique_current | severity: error
SELECT data_product_subscription_id, COUNT(*) AS n
FROM ${catalog}.${dss_schema}.data_product_subscription
WHERE is_current = true GROUP BY data_product_subscription_id HAVING COUNT(*) > 1;

-- check: dpsub_scope_unique_current | severity: error
-- Enforce the stated grain: at most one current licence per (principal, data product,
-- supplier-scope). Two current grants for the same scope would both rank rn = 1 in
-- gold_data_product_revenue and bill the same consumption twice. COALESCE the nullable
-- supplier scope to a sentinel so all-supplier licences compare equal.
SELECT principal_id, data_product_id, COALESCE(supplier_id, '__all_suppliers__') AS supplier_scope, COUNT(*) AS n
FROM ${catalog}.${dss_schema}.data_product_subscription
WHERE is_current = true
GROUP BY principal_id, data_product_id, COALESCE(supplier_id, '__all_suppliers__') HAVING COUNT(*) > 1;

-- check: dpsub_subscribed_ts_not_null | severity: error
-- subscribed_ts is the primary latest-wins ordering key in gold_data_product_revenue; a
-- NULL would sort a genuine latest licence version last and silently serve stale
-- commercial terms (or resurrect a cancelled contract).
SELECT * FROM ${catalog}.${dss_schema}.data_product_subscription
WHERE subscribed_ts IS NULL;

-- check: dpsub_scd2_current_open | severity: error
SELECT * FROM ${catalog}.${dss_schema}.data_product_subscription
WHERE (is_current = true AND effective_to_date IS NOT NULL) OR (is_current = false AND effective_to_date IS NULL);

-- check: dpsub_data_product_fk_orphan | severity: error
SELECT s.* FROM ${catalog}.${dss_schema}.data_product_subscription s
LEFT JOIN ${catalog}.${dss_schema}.data_product p ON s.data_product_sk = p.data_product_sk
WHERE s.data_product_sk IS NOT NULL AND p.data_product_sk IS NULL;

-- check: dpsub_supplier_fk_orphan | severity: error
-- The optional supplier scope must resolve to an existing supplier (guarded; NULL = all).
SELECT s.* FROM ${catalog}.${dss_schema}.data_product_subscription s
LEFT JOIN ${catalog}.${supplier_schema}.supplier sb ON s.supplier_sk = sb.supplier_sk
WHERE s.supplier_sk IS NOT NULL AND sb.supplier_sk IS NULL;

-- check: dpsub_advertiser_fk_orphan | severity: error
-- The optional advertiser scope must resolve to an existing advertiser (guarded; NULL = none).
SELECT s.* FROM ${catalog}.${dss_schema}.data_product_subscription s
LEFT JOIN ${catalog}.${cmn_schema}.advertiser a ON s.advertiser_sk = a.advertiser_sk
WHERE s.advertiser_sk IS NOT NULL AND a.advertiser_sk IS NULL;

-- check: dpsub_billing_frequency_domain | severity: error
SELECT * FROM ${catalog}.${dss_schema}.data_product_subscription
WHERE billing_frequency IS NOT NULL AND billing_frequency NOT IN ('monthly', 'quarterly', 'annual');

-- check: dpsub_status_domain | severity: error
SELECT * FROM ${catalog}.${dss_schema}.data_product_subscription
WHERE subscription_status IS NOT NULL
  AND subscription_status NOT IN ('pending', 'active', 'suspended', 'cancelled', 'expired');

-- check: dpsub_billing_frequency_recognised | severity: error
-- gold_data_product_revenue pro-rates contracted_units to a fiscal period via a CASE on
-- billing_frequency, yielding NULL for an unrecognised value. A licence that commits
-- units MUST therefore declare a recognised frequency, or contract_utilisation_pct (and
-- the under/over-consumption exceptions that read it) silently vanishes for that row.
SELECT * FROM ${catalog}.${dss_schema}.data_product_subscription
WHERE contracted_units IS NOT NULL
  AND (billing_frequency IS NULL OR billing_frequency NOT IN ('monthly', 'quarterly', 'annual'));

-- check: dpsub_term_dates_ordered | severity: error
-- A term that ends before it starts would expand to zero fiscal periods, silently
-- dropping the licence from the revenue view rather than failing loud.
SELECT * FROM ${catalog}.${dss_schema}.data_product_subscription
WHERE term_end_date IS NOT NULL AND term_start_date IS NOT NULL AND term_end_date < term_start_date;

-- check: dpsub_term_start_not_null | severity: error
-- term_start_date anchors the licence-period expansion in gold_data_product_revenue; a
-- NULL start drops the licence from its in-term periods entirely (only usage-bearing
-- periods would survive), hiding paid-but-unused licences.
SELECT * FROM ${catalog}.${dss_schema}.data_product_subscription
WHERE term_start_date IS NULL;

-- check: dpsub_single_currency | severity: error
SELECT * FROM (SELECT COUNT(DISTINCT currency_code) AS n FROM ${catalog}.${dss_schema}.data_product_subscription WHERE currency_code IS NOT NULL) WHERE n > 1;

-- ========== data_share_consumption ==========

-- check: dsc_grain_unique | severity: error
-- Grain integrity: assert the DURABLE business key, not the IDENTITY surrogate
-- (*_sk is generated per row and can never collide — a tautology).
SELECT data_share_consumption_id, COUNT(*) AS n
FROM ${catalog}.${dss_schema}.data_share_consumption
GROUP BY data_share_consumption_id HAVING COUNT(*) > 1;

-- check: dsc_keys_not_null | severity: error
SELECT * FROM ${catalog}.${dss_schema}.data_share_consumption
WHERE data_share_consumption_sk IS NULL OR data_share_consumption_id IS NULL
   OR principal_id IS NULL OR usage_date IS NULL;

-- check: dsc_subscription_fk_orphan | severity: error
SELECT c.* FROM ${catalog}.${dss_schema}.data_share_consumption c
LEFT JOIN ${catalog}.${dss_schema}.data_product_subscription s ON c.data_product_subscription_sk = s.data_product_subscription_sk
WHERE c.data_product_subscription_sk IS NOT NULL AND s.data_product_subscription_sk IS NULL;

-- check: dsc_data_product_fk_orphan | severity: error
SELECT c.* FROM ${catalog}.${dss_schema}.data_share_consumption c
LEFT JOIN ${catalog}.${dss_schema}.data_product p ON c.data_product_sk = p.data_product_sk
WHERE c.data_product_sk IS NOT NULL AND p.data_product_sk IS NULL;

-- check: dsc_supplier_fk_orphan | severity: error
SELECT c.* FROM ${catalog}.${dss_schema}.data_share_consumption c
LEFT JOIN ${catalog}.${supplier_schema}.supplier sb ON c.supplier_sk = sb.supplier_sk
WHERE c.supplier_sk IS NOT NULL AND sb.supplier_sk IS NULL;

-- check: dsc_access_channel_domain | severity: error
SELECT * FROM ${catalog}.${dss_schema}.data_share_consumption
WHERE access_channel IS NOT NULL AND access_channel NOT IN ('share', 'api', 'file_export', 'dashboard');

-- check: dsc_fiscal_period_range | severity: error
-- fiscal_period is a degenerate NRF retail month (1-12), not a week or a day-of-year;
-- an out-of-range value would silently mis-bucket revenue against the calendar spine.
SELECT * FROM ${catalog}.${dss_schema}.data_share_consumption
WHERE fiscal_period IS NOT NULL AND (fiscal_period < 1 OR fiscal_period > 12);

-- check: dsc_measures_non_negative | severity: error
-- Usage and billed revenue are non-negative by construction; a negative would flip the
-- sign of a period's revenue and corrupt the allocation weights in the revenue view.
SELECT * FROM ${catalog}.${dss_schema}.data_share_consumption
WHERE consumption_units < 0 OR billed_query_count < 0 OR billable_amount < 0;

-- check: dsc_usage_date_in_calendar | severity: error
-- usage_date must resolve to a fiscal_calendar row, because gold_data_product_revenue
-- buckets revenue onto a fiscal-period spine DERIVED from that calendar: a usage row
-- outside the calendar window is silently dropped from the P&L (its billable_amount just
-- disappears, with no error). This is a LEFT JOIN on purpose — the sibling
-- dsc_fiscal_period_matches_usage_date check INNER JOINs, so it can only compare rows that
-- already resolved and can never catch an out-of-window date. The two are complementary:
-- this one asserts the row EXISTS in the calendar, that one asserts its degenerate keys
-- AGREE with it.
SELECT c.data_share_consumption_id, c.usage_date, c.fiscal_year, c.fiscal_period
FROM ${catalog}.${dss_schema}.data_share_consumption c
LEFT JOIN ${catalog}.${calendar_schema}.fiscal_calendar f ON f.date_key = c.usage_date
WHERE c.usage_date IS NOT NULL AND f.date_key IS NULL;

-- check: dsc_fiscal_period_matches_usage_date | severity: error
-- fiscal_year/fiscal_period are DEGENERATE keys carried on the fact rather than resolved
-- through a calendar FK, so nothing structural stops them drifting from usage_date. The
-- revenue view buckets by the degenerate pair while the exception queue judges a lapsing
-- term against the CALENDAR period end, so a drifted row would be reported in the wrong
-- period and compared against the wrong term window. Reconcile against fiscal_calendar.
SELECT c.data_share_consumption_id, c.usage_date, c.fiscal_year, c.fiscal_period,
       f.fiscal_year AS calendar_fiscal_year, f.fiscal_period AS calendar_fiscal_period
FROM ${catalog}.${dss_schema}.data_share_consumption c
JOIN ${catalog}.${calendar_schema}.fiscal_calendar f ON f.date_key = c.usage_date
WHERE c.fiscal_year IS NOT NULL AND c.fiscal_period IS NOT NULL
  AND (c.fiscal_year <> f.fiscal_year OR c.fiscal_period <> f.fiscal_period);

-- check: dsc_single_currency | severity: error
SELECT * FROM (SELECT COUNT(DISTINCT currency_code) AS n FROM ${catalog}.${dss_schema}.data_share_consumption WHERE currency_code IS NOT NULL) WHERE n > 1;

-- ========== data-monetization fused-currency consistency ==========

-- check: dm_cross_table_single_currency | severity: error
-- gold_data_product_revenue FUSES monetary columns from all three data-monetization
-- tables under one COALESCE'd currency_code (the licence's contracted_price_amount, the
-- product's list_price_amount, and the metered billable_amount), and derives
-- contract_discount_pct and total_monetised_value ACROSS them. The per-table
-- *_single_currency checks each pass on a load that is internally consistent but uses a
-- DIFFERENT currency between tables, which would silently mislabel the fused row and make
-- the discount a currency artefact. Enforce the single-reporting-currency convention
-- ACROSS the three fused tables, matching what the gold views assume.
SELECT * FROM (
  SELECT COUNT(DISTINCT currency_code) AS n FROM (
    SELECT currency_code FROM ${catalog}.${dss_schema}.data_product WHERE currency_code IS NOT NULL
    UNION
    SELECT currency_code FROM ${catalog}.${dss_schema}.data_product_subscription WHERE currency_code IS NOT NULL
    UNION
    SELECT currency_code FROM ${catalog}.${dss_schema}.data_share_consumption WHERE currency_code IS NOT NULL
  )
) WHERE n > 1;

-- ========== gold_data_product_revenue — no person-level identifiers ==========

-- check: dpr_gold_no_raw_pii | severity: error
-- The revenue view is aggregate; it must not expose any person-level hashed id.
SELECT table_name, column_name
FROM ${catalog}.information_schema.columns
WHERE table_schema = '${dss_schema}'
  AND table_name = 'gold_data_product_revenue'
  AND column_name IN ('customer_key_hash', 'household_key_hash', 'assignment_unit_key_hash');

-- check: dme_gold_no_raw_pii | severity: error
SELECT table_name, column_name
FROM ${catalog}.information_schema.columns
WHERE table_schema = '${dss_schema}'
  AND table_name = 'gold_data_monetization_exceptions'
  AND column_name IN ('customer_key_hash', 'household_key_hash', 'assignment_unit_key_hash');

-- check: dpr_media_allocation_reconciles | severity: error
-- gold_data_product_revenue ALLOCATES each advertiser's period media spend across the
-- licence rows sharing that advertiser (by revenue weight), so the per-row allocations
-- must sum back to the advertiser's actual spend — the property that makes
-- SUM(media_spend_net) and total_monetised_value additive in the metric view. A
-- regression here (e.g. reverting to a fanned-out join) silently double-counts spend.
WITH allocated AS (
  SELECT advertiser_id, fiscal_year, fiscal_period, SUM(media_spend_net) AS allocated_spend
  FROM ${catalog}.${dss_schema}.gold_data_product_revenue
  WHERE media_spend_net IS NOT NULL
  GROUP BY advertiser_id, fiscal_year, fiscal_period
),
actual AS (
  SELECT cp.advertiser_id, c.fiscal_year, c.fiscal_period, SUM(cp.media_spend_net) AS actual_spend
  FROM ${catalog}.${cmn_schema}.gold_campaign_performance cp
  JOIN ${catalog}.${calendar_schema}.fiscal_calendar c ON c.date_key = cp.metric_date
  GROUP BY cp.advertiser_id, c.fiscal_year, c.fiscal_period
)
SELECT a.advertiser_id, a.fiscal_year, a.fiscal_period, a.allocated_spend, x.actual_spend
FROM allocated a
JOIN actual x
  ON x.advertiser_id = a.advertiser_id AND x.fiscal_year = a.fiscal_year AND x.fiscal_period = a.fiscal_period
WHERE ABS(a.allocated_spend - x.actual_spend) > 0.01;

-- check: dpr_suppressed_measures_are_withheld | severity: error
-- The suppression contract: when usage_suppressed_flag is TRUE every usage measure AND
-- every metric derived from it must be NULL, or the withheld volume leaks back out
-- through a derived figure.
SELECT * FROM ${catalog}.${dss_schema}.gold_data_product_revenue
WHERE usage_suppressed_flag = TRUE
  AND (consumption_units IS NOT NULL OR billed_query_count IS NOT NULL
       OR data_revenue_amount IS NOT NULL OR contract_utilisation_pct IS NOT NULL
       OR revenue_per_consumption_unit IS NOT NULL OR total_monetised_value IS NOT NULL
       OR data_revenue_share_pct IS NOT NULL);

-- check: dpr_rowcount | severity: metric
SELECT COUNT(*) AS rows FROM ${catalog}.${dss_schema}.gold_data_product_revenue;

-- check: dpr_suppression_rate | severity: metric
-- Reported only: share of licence periods whose usage was withheld by the disclosure floor.
SELECT ROUND(AVG(CASE WHEN usage_suppressed_flag THEN 1.0 ELSE 0.0 END), 4) AS suppression_rate
FROM ${catalog}.${dss_schema}.gold_data_product_revenue;

-- check: dpr_media_signal_null_rate | severity: metric
-- Reported only: NULL-rate of the retail-media signal (degraded if the Commerce Media
-- Networks package is absent or unpopulated — expected NULL-safe behavior, never a failure).
SELECT ROUND(AVG(CASE WHEN media_spend_net IS NULL THEN 1.0 ELSE 0.0 END), 4) AS media_signal_null_rate
FROM ${catalog}.${dss_schema}.gold_data_product_revenue;

-- check: dpr_utilisation_null_rate | severity: metric
-- Reported only: NULL-rate of contract utilisation (NULL where a licence commits no
-- units, i.e. an uncapped contract — expected, not a failure).
SELECT ROUND(AVG(CASE WHEN contract_utilisation_pct IS NULL THEN 1.0 ELSE 0.0 END), 4) AS utilisation_null_rate
FROM ${catalog}.${dss_schema}.gold_data_product_revenue;

-- check: dme_exception_mix | severity: metric
-- Reported only: the shape of the attention queue by reason, so a deployment can see
-- whether one reason dominates (usually a mis-set tolerance rather than a real signal).
SELECT exception_reason, COUNT(*) AS rows
FROM ${catalog}.${dss_schema}.gold_data_monetization_exceptions
GROUP BY exception_reason
ORDER BY rows DESC, exception_reason;
