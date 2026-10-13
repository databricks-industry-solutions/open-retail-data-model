-- ============================================================
-- ORDM · Outcome Package · Actionable Customer Understanding
-- Sample Queries
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- ============================================================

-- 1. Top customers by lifetime value (RFM + value tier)
SELECT
    profile_id,
    value_tier,
    rfm_score,
    historical_clv,
    predicted_clv
FROM ${catalog}.${acu_schema}.gold_customer_ltv
ORDER BY historical_clv DESC
LIMIT 100;

-- 2. Behavioral trait surface for a customer (the wide "parent model" an audience
--    builder composes from). One row per customer.
SELECT
    profile_id,
    lifecycle_stage,
    recency_periods,
    frequency,
    top_category,
    top_brand,
    promo_purchase_share_ratio,
    value_tier,
    churn_risk_proxy,
    opt_in_status,
    account_id
FROM ${catalog}.${acu_schema}.gold_customer_behavioral_attributes
WHERE profile_id = 'C1';

-- 3. Segment sizing: current member count per behavioral segment (latest snapshot).
SELECT
    m.audience_id,
    a.audience_name,
    a.segmentation_basis,
    COUNT(DISTINCT m.profile_id) AS member_count
-- latest-as-of, minus exited: same membership-currency rule as the governed
-- gold_activatable_audience_current / mv_segment_performance CTEs. If that rule
-- changes, update those views AND these sample queries (no shared-SQL include).
FROM ${catalog}.${acu_schema}.segment_membership m
JOIN (
    SELECT audience_id, MAX(as_of_date) AS max_as_of
    FROM ${catalog}.${acu_schema}.segment_membership
    GROUP BY audience_id
) mx ON m.audience_id = mx.audience_id AND m.as_of_date = mx.max_as_of
JOIN ${catalog}.${marketing_schema}.audience a
  ON a.audience_id = m.audience_id AND a.is_current = TRUE
WHERE (m.membership_status IS NULL OR m.membership_status <> 'exited')
GROUP BY m.audience_id, a.audience_name, a.segmentation_basis
ORDER BY member_count DESC;

-- 4. Build a custom audience from traits (ad-hoc composition, the "custom attributes"
--    path): high-value repeat customers who skew to full price.
SELECT profile_id, value_tier, frequency, promo_purchase_share_ratio
FROM ${catalog}.${acu_schema}.gold_customer_behavioral_attributes
WHERE value_tier IN ('PLATINUM', 'GOLD')
  AND frequency >= 3
  AND promo_purchase_share_ratio < 0.2
ORDER BY historical_clv DESC
LIMIT 500;

-- 5. Activatable audience: members of a segment who actually clear the consent +
--    preference + reachability gate, per OWNED channel (the reverse-ETL-ready surface).
--    channel_code IS NOT NULL restricts to owned email/sms/phone/postal reachability (H1):
--    the channel-agnostic purposes (personalization/analytics/retail_media) carry a NULL
--    channel and are not owned-channel reachable, so they are excluded here rather than
--    forming an unlabeled NULL bucket. Matches mv_segment_performance / sample #6.
SELECT
    audience_id,
    audience_name,
    channel_code,
    COUNT(DISTINCT profile_id) AS reachable_members
FROM ${catalog}.${ucv_schema}.gold_activatable_audience_current
WHERE channel_code IS NOT NULL
GROUP BY audience_id, audience_name, channel_code
ORDER BY audience_id, channel_code;

-- 6. Activatable penetration per segment: reachable share of total membership
--    (ratio-of-sums). Surfaces how much of a segment is actually contactable.
WITH members AS (
    -- latest-as-of, minus exited: same rule as the governed
    -- gold_activatable_audience_current / mv_segment_performance CTEs (keep in sync).
    SELECT m.audience_id, COUNT(DISTINCT m.profile_id) AS total_members
    FROM ${catalog}.${acu_schema}.segment_membership m
    JOIN (
        SELECT audience_id, MAX(as_of_date) AS max_as_of
        FROM ${catalog}.${acu_schema}.segment_membership GROUP BY audience_id
    ) mx ON m.audience_id = mx.audience_id AND m.as_of_date = mx.max_as_of
    WHERE (m.membership_status IS NULL OR m.membership_status <> 'exited')
    GROUP BY m.audience_id
),
reachable AS (
    -- Owned-channel reachability ONLY (H1): the multi-purpose gate (ADR 0028) emits
    -- channel-agnostic NULL-channel rows (personalization/analytics/retail_media) where
    -- has_identifier_flag is vacuously TRUE, so an unfiltered read counts analytics-only
    -- consenters as reachable and inflates penetration. Match mv_segment_performance's
    -- reachable CTE: restrict to owned channels (channel_code IS NOT NULL).
    SELECT audience_id, COUNT(DISTINCT profile_id) AS reachable_members
    FROM ${catalog}.${ucv_schema}.gold_activatable_audience_current
    WHERE channel_code IS NOT NULL
    GROUP BY audience_id
)
SELECT
    mem.audience_id,
    mem.total_members,
    COALESCE(r.reachable_members, 0) AS reachable_members,
    ROUND(COALESCE(r.reachable_members, 0) / NULLIF(mem.total_members, 0), 4) AS activatable_penetration
FROM members mem
LEFT JOIN reachable r ON r.audience_id = mem.audience_id
ORDER BY activatable_penetration DESC;

-- 7. Market Analysis: observation-native competitive KPIs by row scope.
--    Keep channel/scope visible: national price and source-channel observation
--    rows do not necessarily co-occur, and cross-competitor overlap is not a union.
SELECT
    category,
    competitor_id,
    competitor_name,
    channel_code,
    measure_scope,
    MEASURE(price_index_vs_competitor) AS price_index_vs_competitor,
    MEASURE(sales_weighted_price_index_vs_competitor) AS sales_weighted_price_index,
    MEASURE(price_observation_coverage_pct) AS usable_price_coverage_pct,
    MEASURE(promo_sov_pct) AS promo_sov_pct,
    MEASURE(listed_share_pct) AS listed_share_pct,
    MEASURE(availability_rate_pct) AS observed_availability_pct,
    MEASURE(listed_channel_count) AS listed_channel_count,
    MEASURE(assortment_overlap_pct) AS assortment_overlap_pct,
    MEASURE(assortment_uniqueness_pct) AS assortment_uniqueness_pct,
    MEASURE(match_coverage_pct) AS match_coverage_pct,
    MEASURE(avg_promotion_detection_lag_days) AS promotion_detection_lag_days,
    MEASURE(avg_assortment_detection_lag_days) AS assortment_detection_lag_days
FROM ${catalog}.${acu_schema}.mv_competitive_position
WHERE fiscal_year = 2026
GROUP BY category, competitor_id, competitor_name, channel_code, measure_scope
ORDER BY category, competitor_id, channel_code;

-- 8. Inspect the latest competitive-position basis and raw observation populations.
--    ORDER BY + LIMIT avoids tuple-vs-scalar subquery comparisons in Spark SQL.
SELECT
    category,
    competitor_id,
    competitor_name,
    fiscal_year,
    fiscal_period,
    channel_code,
    measure_scope,
    valid_price_product_count,
    observed_price_product_count,
    comparable_promo_day_count,
    competitor_promotion_observation_count,
    assortment_observation_count,
    listed_observation_count,
    out_of_stock_observation_count,
    stock_flagged_observation_count,
    listed_channel_count,
    unmatched_listed_item_count,
    unmatched_listed_item_present_flag,
    observed_own_product_count,
    own_catalog_product_count,
    own_catalog_observation_coverage_pct,
    matched_listed_inactive_product_count,
    detection_lag_observation_count,
    price_index_basis,
    promo_sov_basis,
    assortment_basis,
    detection_basis
FROM ${catalog}.${acu_schema}.gold_competitive_position
ORDER BY fiscal_year DESC, fiscal_period DESC, category, competitor_id
LIMIT 100;

-- 9. Licensed market share at its own provider market/geography grain.
SELECT
    market_definition,
    geography_level,
    geography_code,
    category_ref,
    subject_type,
    subject_id,
    period_type,
    period_end_date,
    MEASURE(market_share_pct) AS market_share_pct,
    MEASURE(market_share_sales_amount) AS subject_sales,
    MEASURE(market_size_sales_amount) AS measured_market_sales
FROM ${catalog}.${acu_schema}.mv_market_share
WHERE period_end_date >= DATE '2026-01-01'
GROUP BY
    market_definition, geography_level, geography_code, category_ref,
    subject_type, subject_id, period_type, period_end_date
ORDER BY period_end_date DESC, category_ref, subject_type, subject_id;

-- NOTE (buyability): the affinity surfaces are all-history and deliberately carry no
-- product.product_status — a score/rule is defined over past behaviour, not current
-- sellability. A recommendation FEED must therefore gate on buyable status itself (join
-- product on the durable product_id, is_current = TRUE AND product_status = 'active'), so a
-- discontinued SKU a customer once bought heavily never tops the feed. Queries 11 and 12 show
-- the gate; the "raw mechanics" queries (10/14/15) leave it off to keep the affinity logic clear.

-- NOTE (windowing): gold_product_affinity_pairwise emits one row per directed pair PER trailing
-- window (30D / 90D / ALL_TIME), so every pairwise query MUST pick a time_window (or add it to the
-- projection) — otherwise each pair returns up to three times. The examples below use ALL_TIME for
-- the long-run view; query 14 uses 30D for the recent view.

-- 10. Product Affinity: "frequently bought together" with a given product (directional
--     confidence — P(buys B | bought A)), strongest associations first, over all history.
SELECT
    product_id_b,
    product_name_b,
    category_b,
    cooccurrence_baskets,
    support,
    confidence,
    lift
FROM ${catalog}.${acu_schema}.gold_product_affinity_pairwise
WHERE product_id_a = 'P1'
  AND time_window = 'ALL_TIME'
ORDER BY lift DESC, confidence DESC
LIMIT 20;

-- 11. Cross-sell discovery: the top cross-CATEGORY product pairs by lift (undirected —
--     is_mirrored_pair = FALSE returns each pair once), for merchandising/bundling. Gated so
--     BOTH legs are currently buyable (product_status = 'active'), so a bundle never surfaces a
--     discontinued SKU.
SELECT
    x.category_a,
    x.product_name_a,
    x.category_b,
    x.product_name_b,
    x.cooccurrence_baskets,
    x.lift
FROM ${catalog}.${acu_schema}.gold_product_affinity_pairwise x
JOIN ${catalog}.${product_schema}.product pa
  ON pa.product_id = x.product_id_a AND pa.is_current = TRUE AND pa.product_status = 'active'
JOIN ${catalog}.${product_schema}.product pb
  ON pb.product_id = x.product_id_b AND pb.is_current = TRUE AND pb.product_status = 'active'
WHERE x.time_window = 'ALL_TIME'
  AND x.is_mirrored_pair = FALSE
  AND x.category_a <> x.category_b
ORDER BY x.lift DESC
LIMIT 50;

-- 12. Personalized re-purchase: a customer's strongest product affinities (recency-weighted
--     purchase history), for a "recommended for you" feed. Gated to currently buyable products
--     (product_status = 'active') so a discontinued SKU never tops the feed.
SELECT
    a.product_id,
    a.product_name,
    a.category,
    a.purchase_count,
    a.last_purchase_date,
    a.recency_weight,
    a.affinity_score,
    a.affinity_band
FROM ${catalog}.${acu_schema}.gold_customer_product_affinity a
JOIN ${catalog}.${product_schema}.product p
  ON p.product_id = a.product_id AND p.is_current = TRUE AND p.product_status = 'active'
WHERE a.profile_id = 'C1'
ORDER BY a.affinity_score DESC
LIMIT 20;

-- 13. Governed semantic surface: customer→product affinity reach and average strength by
--     category (Genie / AI-BI). Means are ratio-of-sums, so they re-aggregate at any grain.
SELECT
    category,
    affinity_band,
    MEASURE(distinct_customers)     AS customers_with_affinity,
    MEASURE(distinct_products)      AS products_with_affinity,
    MEASURE(avg_affinity_score)     AS avg_affinity_score,
    MEASURE(total_affinity_spend)   AS spend_behind_affinity
FROM ${catalog}.${acu_schema}.mv_product_affinity
GROUP BY category, affinity_band
ORDER BY category, affinity_band;

-- 14. Trailing-window affinity: "frequently bought together" with a product over the last
--     30 days (recent behavior), strongest first.
SELECT
    product_id_b,
    product_name_b,
    cooccurrence_baskets,
    confidence,
    lift
FROM ${catalog}.${acu_schema}.gold_product_affinity_pairwise
WHERE product_id_a = 'P1'
  AND time_window = '30D'
ORDER BY lift DESC, confidence DESC
LIMIT 20;

-- 15. Emerging cross-sell: pairs whose RECENT (30D) lift materially exceeds their long-run
--     (ALL_TIME) lift — associations trending up, worth surfacing before the all-time view
--     catches them. (Undirected: is_mirrored_pair = FALSE returns each pair once.)
WITH w30 AS (
    SELECT product_id_a, product_id_b, lift AS lift_30d, cooccurrence_baskets
    FROM ${catalog}.${acu_schema}.gold_product_affinity_pairwise
    WHERE time_window = '30D' AND is_mirrored_pair = FALSE
),
w_all AS (
    SELECT product_id_a, product_id_b, lift AS lift_all_time
    FROM ${catalog}.${acu_schema}.gold_product_affinity_pairwise
    WHERE time_window = 'ALL_TIME' AND is_mirrored_pair = FALSE
)
SELECT
    w30.product_id_a,
    w30.product_id_b,
    w30.cooccurrence_baskets,
    w_all.lift_all_time,
    w30.lift_30d,
    w30.lift_30d - COALESCE(w_all.lift_all_time, 0) AS lift_uplift
FROM w30
LEFT JOIN w_all
  ON w_all.product_id_a = w30.product_id_a AND w_all.product_id_b = w30.product_id_b
WHERE w30.lift_30d > COALESCE(w_all.lift_all_time, 0)
ORDER BY lift_uplift DESC
LIMIT 50;
