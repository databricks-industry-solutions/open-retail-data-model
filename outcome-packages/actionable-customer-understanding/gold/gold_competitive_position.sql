-- ============================================================
-- ORDM · Outcome Package · Actionable Customer Understanding
-- View: gold_competitive_position
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-08-24
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-24 by @saurabhshukla-db
-- ============================================================
-- Observation-native synthesis over competitor price, promotion and assortment.
-- Each observation family is aggregated independently before the grains are
-- joined, so sparse feeds do not multiply rows or silently erase dimensions.
--
-- Grain: category × durable competitor_id × channel_code × fiscal period.
-- SCD2 contract: facts join the version-specific product_sk; aggregation and
-- windows use durable competitor_id/product_id; display names resolve at period
-- end. Price remains regular-vs-regular: own list price / competitor MRP.
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${acu_schema}.gold_competitive_position AS
WITH fiscal_periods AS (
  SELECT
    fiscal_year,
    fiscal_period,
    MIN(date_key) AS period_start_date,
    MAX(date_key) AS period_end_date
  FROM ${catalog}.${calendar_schema}.fiscal_calendar
  GROUP BY fiscal_year, fiscal_period
),
own_item_day AS (
  -- Collapse store rows before any competitor join; promotion presence comes
  -- from the promotion dimension and its product scope below.
  SELECT
    s.product_id,
    s.date_key,
    SUM(CASE WHEN s.units > 0 THEN s.units ELSE 0 END) AS own_units
  FROM ${catalog}.${transaction_schema}.sales s
  GROUP BY s.product_id, s.date_key
),
own_promotion_product_days AS (
  -- Own-side promoted presence is the promotion calendar expanded through the
  -- product scope. Store scope is deliberately collapsed to product-day before
  -- comparison with competitor observations.
  SELECT DISTINCT
    scope.product_id,
    calendar.date_key
  FROM ${catalog}.${marketing_schema}.promotion promotion
  JOIN ${catalog}.${promo_schema}.promotion_scope scope
    ON promotion.promo_sk = scope.promo_sk
  JOIN ${catalog}.${calendar_schema}.fiscal_calendar calendar
    ON calendar.date_key BETWEEN promotion.start_date AND promotion.end_date
  WHERE promotion.promo_id <> 'NO_PROMO'
    AND promotion.start_date IS NOT NULL
    AND promotion.end_date IS NOT NULL
),
price_observations AS (
  SELECT
    COALESCE(p.category, 'unclassified') AS category,
    cp.competitor_id,
    cp.product_id,
    cp.date_key,
    fc.fiscal_year,
    fc.fiscal_period,
    fp.period_start_date,
    fp.period_end_date,
    p.list_price AS own_regular_price,
    p.currency_code AS own_currency_code,
    cp.competitor_mrp AS competitor_regular_price,
    cp.currency_code AS competitor_currency_code,
    oid.own_units,
    CASE
      WHEN p.list_price > 0
       AND cp.competitor_mrp > 0
       AND p.currency_code IS NOT NULL
       AND cp.currency_code = p.currency_code
      THEN 1 ELSE 0
    END AS is_usable_price_pair
  FROM ${catalog}.${bmv_schema}.competitor_price cp
  JOIN ${catalog}.${product_schema}.product p
    ON cp.product_sk = p.product_sk
  JOIN ${catalog}.${calendar_schema}.fiscal_calendar fc
    ON cp.date_key = fc.date_key
  JOIN fiscal_periods fp
    ON fc.fiscal_year = fp.fiscal_year
   AND fc.fiscal_period = fp.fiscal_period
  LEFT JOIN own_item_day oid
    ON cp.product_id = oid.product_id
   AND cp.date_key = oid.date_key
),
price_period_aggregates AS (
  SELECT
    category,
    competitor_id,
    'all' AS channel_code,
    fiscal_year,
    fiscal_period,
    period_start_date,
    period_end_date,
    SUM(CASE WHEN is_usable_price_pair = 1
             THEN own_regular_price / competitor_regular_price ELSE 0 END) AS price_ratio_sum,
    SUM(CASE WHEN is_usable_price_pair = 1 THEN 1 ELSE 0 END) AS valid_price_observation_count,
    COUNT(DISTINCT CASE WHEN is_usable_price_pair = 1 THEN product_id END) AS valid_price_product_count,
    COUNT(DISTINCT product_id) AS observed_price_product_count,
    SUM(CASE WHEN is_usable_price_pair = 1 AND own_units > 0
             THEN (own_regular_price / competitor_regular_price) * own_units ELSE 0 END)
      AS sales_weighted_price_ratio_sum,
    SUM(CASE WHEN is_usable_price_pair = 1 AND own_units > 0
             THEN own_units ELSE 0 END) AS matched_units,
    COUNT(*) AS competitor_observation_count,
    CASE
      WHEN COUNT(DISTINCT CASE WHEN is_usable_price_pair = 1
                               THEN competitor_currency_code END) = 1
      THEN MIN(CASE WHEN is_usable_price_pair = 1
                    THEN competitor_currency_code END)
      ELSE NULL
    END AS price_currency_code
  FROM price_observations
  GROUP BY
    category, competitor_id, fiscal_year, fiscal_period,
    period_start_date, period_end_date
),
promotion_observations AS (
  SELECT
    promo.category_ref AS category,
    promo.competitor_id,
    promo.product_id,
    promo.channel_code,
    promo.promo_vehicle,
    promo.discount_depth_pct,
    promo.promo_start_date,
    promo.date_key,
    promo.observed_at_ts,
    promo.currency_code,
    fc.fiscal_year,
    fc.fiscal_period,
    fp.period_start_date,
    fp.period_end_date,
    CASE
      WHEN promo.promo_start_date IS NOT NULL
       AND promo.observed_at_ts >= CAST(promo.promo_start_date AS TIMESTAMP)
      THEN (UNIX_TIMESTAMP(promo.observed_at_ts)
            - UNIX_TIMESTAMP(CAST(promo.promo_start_date AS TIMESTAMP))) / 86400.0
      ELSE NULL
    END AS promotion_detection_lag_days
  FROM ${catalog}.${acu_schema}.competitor_promotion promo
  JOIN ${catalog}.${calendar_schema}.fiscal_calendar fc
    ON promo.date_key = fc.date_key
  JOIN fiscal_periods fp
    ON fc.fiscal_year = fp.fiscal_year
   AND fc.fiscal_period = fp.fiscal_period
),
own_catalog_product_set AS (
  SELECT
    COALESCE(product.category, 'unclassified') AS category,
    periods.fiscal_year,
    periods.fiscal_period,
    product.product_id
  FROM fiscal_periods periods
  JOIN ${catalog}.${product_schema}.product product
    ON product.effective_from_date <= periods.period_end_date
   AND (product.effective_to_date IS NULL
        OR product.effective_to_date > periods.period_end_date)
  WHERE product.product_status = 'active'
),
own_catalog_periods AS (
  SELECT
    category,
    fiscal_year,
    fiscal_period,
    COUNT(DISTINCT product_id) AS own_catalog_product_count
  FROM own_catalog_product_set
  GROUP BY category, fiscal_year, fiscal_period
),
assortment_ordered AS (
  SELECT
    assortment.category_ref AS category,
    assortment.competitor_id,
    assortment.competitor_item_ref,
    assortment.product_id,
    assortment.match_type,
    assortment.match_confidence,
    assortment.competitor_location_ref,
    assortment.channel_code,
    assortment.date_key,
    assortment.observed_at_ts,
    assortment.is_listed,
    assortment.is_available,
    assortment.search_rank,
    fc.fiscal_year,
    fc.fiscal_period,
    fp.period_start_date,
    fp.period_end_date,
    LAG(assortment.observed_at_ts) OVER (
      PARTITION BY assortment.competitor_id, assortment.competitor_item_ref,
                   assortment.competitor_location_ref, assortment.channel_code
      ORDER BY assortment.observed_at_ts, assortment.competitor_assortment_id
    ) AS previous_observed_at_ts,
    LAG(CAST(assortment.is_listed AS INT)) OVER (
      PARTITION BY assortment.competitor_id, assortment.competitor_item_ref,
                   assortment.competitor_location_ref, assortment.channel_code
      ORDER BY assortment.observed_at_ts, assortment.competitor_assortment_id
    ) AS previous_is_listed,
    LAG(CAST(assortment.is_available AS INT)) OVER (
      PARTITION BY assortment.competitor_id, assortment.competitor_item_ref,
                   assortment.competitor_location_ref, assortment.channel_code
      ORDER BY assortment.observed_at_ts, assortment.competitor_assortment_id
    ) AS previous_is_available
  FROM ${catalog}.${acu_schema}.competitor_assortment assortment
  JOIN ${catalog}.${calendar_schema}.fiscal_calendar fc
    ON assortment.date_key = fc.date_key
  JOIN fiscal_periods fp
    ON fc.fiscal_year = fp.fiscal_year
   AND fc.fiscal_period = fp.fiscal_period
),
assortment_observations AS (
  SELECT
    ordered.*,
    CASE WHEN catalog.product_id IS NOT NULL THEN 1 ELSE 0 END
      AS is_active_own_product,
    CASE
      WHEN previous_observed_at_ts IS NOT NULL
       AND (
         CAST(is_listed AS INT) <> previous_is_listed
         OR COALESCE(CAST(is_available AS INT), -1) <> COALESCE(previous_is_available, -1)
       )
      THEN 1 ELSE 0
    END AS is_state_change,
    CASE
      WHEN previous_observed_at_ts IS NOT NULL
      THEN (UNIX_TIMESTAMP(observed_at_ts) - UNIX_TIMESTAMP(previous_observed_at_ts)) / 86400.0
      ELSE NULL
    END AS observation_interval_days
  FROM assortment_ordered ordered
  LEFT JOIN own_catalog_product_set catalog
    ON ordered.category = catalog.category
   AND ordered.fiscal_year = catalog.fiscal_year
   AND ordered.fiscal_period = catalog.fiscal_period
   AND ordered.product_id = catalog.product_id
),
assortment_channel_counts AS (
  SELECT
    category,
    competitor_id,
    fiscal_year,
    fiscal_period,
    COUNT(DISTINCT CASE WHEN is_listed THEN channel_code END) AS listed_channel_count
  FROM assortment_observations
  GROUP BY category, competitor_id, fiscal_year, fiscal_period
),
assortment_period_aggregates AS (
  SELECT
    category,
    competitor_id,
    channel_code,
    fiscal_year,
    fiscal_period,
    period_start_date,
    period_end_date,
    COUNT(*) AS assortment_observation_count,
    SUM(CASE WHEN is_listed THEN 1 ELSE 0 END) AS listed_observation_count,
    SUM(CASE WHEN is_listed AND is_available = TRUE THEN 1 ELSE 0 END)
      AS available_observation_count,
    SUM(CASE WHEN is_listed AND is_available = FALSE THEN 1 ELSE 0 END)
      AS out_of_stock_observation_count,
    SUM(CASE WHEN is_listed AND is_available IS NOT NULL THEN 1 ELSE 0 END)
      AS stock_flagged_observation_count,
    COUNT(DISTINCT CASE WHEN is_listed THEN competitor_location_ref END)
      AS points_of_availability_count,
    COUNT(DISTINCT CASE WHEN is_listed THEN competitor_item_ref END)
      AS competitor_listed_item_count,
    COUNT(DISTINCT CASE
      WHEN is_listed
       AND product_id IS NOT NULL
       AND match_type IN ('exact', 'equivalent')
       AND match_confidence >= 0.80
       AND is_active_own_product = 1
      THEN product_id END) AS matched_listed_product_count,
    COUNT(DISTINCT CASE
      WHEN is_listed
       AND product_id IS NOT NULL
       AND match_type IN ('exact', 'equivalent')
       AND match_confidence >= 0.80
       AND is_active_own_product = 0
      THEN product_id END) AS matched_listed_inactive_product_count,
    COUNT(DISTINCT CASE
      WHEN product_id IS NOT NULL AND is_active_own_product = 1
      THEN product_id END) AS observed_own_product_count,
    COUNT(DISTINCT CASE
      WHEN is_listed
       AND product_id IS NOT NULL
       AND match_type IN ('exact', 'equivalent')
       AND match_confidence >= 0.80
      THEN competitor_item_ref END) AS matched_listed_competitor_item_count,
    COUNT(DISTINCT CASE
      WHEN is_listed
       AND NOT (
         product_id IS NOT NULL
         AND match_type IN ('exact', 'equivalent')
         AND match_confidence >= 0.80
       )
      THEN competitor_item_ref END) AS unmatched_listed_item_count,
    SUM(CASE WHEN search_rank IS NOT NULL THEN search_rank ELSE 0 END) AS search_rank_sum,
    SUM(CASE WHEN search_rank IS NOT NULL THEN 1 ELSE 0 END)
      AS search_rank_observation_count,
    SUM(is_state_change) AS assortment_state_change_count,
    SUM(CASE WHEN is_state_change = 1 THEN observation_interval_days ELSE 0 END)
      AS assortment_detection_lag_days_sum,
    SUM(CASE WHEN is_state_change = 1 THEN 1 ELSE 0 END)
      AS assortment_detection_observation_count,
    SUM(CASE WHEN observation_interval_days IS NOT NULL THEN observation_interval_days ELSE 0 END)
      AS observation_interval_days_sum,
    SUM(CASE WHEN observation_interval_days IS NOT NULL THEN 1 ELSE 0 END)
      AS observation_interval_count
  FROM assortment_observations
  GROUP BY
    category, competitor_id, channel_code, fiscal_year, fiscal_period,
    period_start_date, period_end_date
),
source_observation_channels AS (
  SELECT DISTINCT
    category, competitor_id, channel_code, fiscal_year, fiscal_period,
    period_start_date, period_end_date
  FROM promotion_observations
  UNION
  SELECT DISTINCT
    category, competitor_id, channel_code, fiscal_year, fiscal_period,
    period_start_date, period_end_date
  FROM assortment_observations
),
promotion_coverage_product_days AS (
  -- Any competitor observation establishes coverage. National price observations
  -- are attributed only to source-observed channels for the SOV population; their
  -- price measures remain on the explicit channel_code='all' row.
  SELECT
    price.category,
    price.competitor_id,
    price.product_id,
    channels.channel_code,
    price.date_key,
    price.fiscal_year,
    price.fiscal_period,
    price.period_start_date,
    price.period_end_date
  FROM price_observations price
  JOIN source_observation_channels channels
    ON price.category = channels.category
   AND price.competitor_id = channels.competitor_id
   AND price.fiscal_year = channels.fiscal_year
   AND price.fiscal_period = channels.fiscal_period
  WHERE price.product_id IS NOT NULL
  UNION
  SELECT
    category, competitor_id, product_id, channel_code, date_key,
    fiscal_year, fiscal_period, period_start_date, period_end_date
  FROM promotion_observations
  WHERE product_id IS NOT NULL
  UNION
  SELECT
    category, competitor_id, product_id, channel_code, date_key,
    fiscal_year, fiscal_period, period_start_date, period_end_date
  FROM assortment_observations
  WHERE product_id IS NOT NULL
),
competitor_promotion_product_days AS (
  SELECT DISTINCT
    category, competitor_id, product_id, channel_code, date_key
  FROM promotion_observations
  WHERE product_id IS NOT NULL
),
promotion_presence_period_aggregates AS (
  SELECT
    coverage.category,
    coverage.competitor_id,
    coverage.channel_code,
    coverage.fiscal_year,
    coverage.fiscal_period,
    coverage.period_start_date,
    coverage.period_end_date,
    SUM(CASE WHEN own.product_id IS NOT NULL THEN 1 ELSE 0 END)
      AS own_promo_presence_count,
    SUM(CASE WHEN competitor.product_id IS NOT NULL THEN 1 ELSE 0 END)
      AS competitor_promo_presence_count,
    COUNT(*) AS comparable_promo_observation_count,
    COUNT(DISTINCT coverage.date_key) AS comparable_promo_day_count
  FROM promotion_coverage_product_days coverage
  LEFT JOIN own_promotion_product_days own
    ON coverage.product_id = own.product_id
   AND coverage.date_key = own.date_key
  LEFT JOIN competitor_promotion_product_days competitor
    ON coverage.category = competitor.category
   AND coverage.competitor_id = competitor.competitor_id
   AND coverage.product_id = competitor.product_id
   AND coverage.channel_code = competitor.channel_code
   AND coverage.date_key = competitor.date_key
  GROUP BY
    coverage.category, coverage.competitor_id, coverage.channel_code,
    coverage.fiscal_year, coverage.fiscal_period,
    coverage.period_start_date, coverage.period_end_date
),
promotion_detail_period_aggregates AS (
  SELECT
    category,
    competitor_id,
    channel_code,
    fiscal_year,
    fiscal_period,
    period_start_date,
    period_end_date,
    COUNT(*) AS competitor_promotion_observation_count,
    SUM(CASE WHEN discount_depth_pct IS NOT NULL THEN discount_depth_pct ELSE 0 END)
      AS discount_depth_pct_sum,
    SUM(CASE WHEN discount_depth_pct IS NOT NULL THEN 1 ELSE 0 END)
      AS valid_discount_depth_count,
    SUM(CASE WHEN promo_vehicle = 'circular_print' THEN 1 ELSE 0 END)
      AS circular_print_promo_count,
    SUM(CASE WHEN promo_vehicle = 'circular_digital' THEN 1 ELSE 0 END)
      AS circular_digital_promo_count,
    SUM(CASE WHEN promo_vehicle = 'onsite' THEN 1 ELSE 0 END)
      AS onsite_promo_count,
    SUM(CASE WHEN promo_vehicle = 'in_store' THEN 1 ELSE 0 END)
      AS in_store_promo_count,
    SUM(CASE WHEN promo_vehicle = 'email_app' THEN 1 ELSE 0 END)
      AS email_app_promo_count,
    SUM(CASE WHEN promo_vehicle = 'other' THEN 1 ELSE 0 END)
      AS other_promo_count,
    SUM(CASE WHEN promotion_detection_lag_days IS NOT NULL
             THEN promotion_detection_lag_days ELSE 0 END)
      AS promotion_detection_lag_days_sum,
    SUM(CASE WHEN promotion_detection_lag_days IS NOT NULL THEN 1 ELSE 0 END)
      AS promotion_detection_observation_count,
    CASE
      WHEN COUNT(DISTINCT currency_code) = 1 THEN MIN(currency_code)
      ELSE NULL
    END AS promotion_currency_code
  FROM promotion_observations
  GROUP BY
    category, competitor_id, channel_code, fiscal_year, fiscal_period,
    period_start_date, period_end_date
),
promotion_keys AS (
  SELECT category, competitor_id, channel_code, fiscal_year, fiscal_period,
         period_start_date, period_end_date
  FROM promotion_presence_period_aggregates
  UNION
  SELECT category, competitor_id, channel_code, fiscal_year, fiscal_period,
         period_start_date, period_end_date
  FROM promotion_detail_period_aggregates
),
promotion_period_aggregates AS (
  SELECT
    keys.*,
    COALESCE(presence.own_promo_presence_count, 0) AS own_promo_presence_count,
    COALESCE(presence.competitor_promo_presence_count, 0)
      AS competitor_promo_presence_count,
    COALESCE(presence.comparable_promo_observation_count, 0)
      AS comparable_promo_observation_count,
    COALESCE(presence.comparable_promo_day_count, 0) AS comparable_promo_day_count,
    COALESCE(detail.competitor_promotion_observation_count, 0)
      AS competitor_promotion_observation_count,
    COALESCE(detail.discount_depth_pct_sum, 0) AS discount_depth_pct_sum,
    COALESCE(detail.valid_discount_depth_count, 0) AS valid_discount_depth_count,
    COALESCE(detail.circular_print_promo_count, 0) AS circular_print_promo_count,
    COALESCE(detail.circular_digital_promo_count, 0) AS circular_digital_promo_count,
    COALESCE(detail.onsite_promo_count, 0) AS onsite_promo_count,
    COALESCE(detail.in_store_promo_count, 0) AS in_store_promo_count,
    COALESCE(detail.email_app_promo_count, 0) AS email_app_promo_count,
    COALESCE(detail.other_promo_count, 0) AS other_promo_count,
    COALESCE(detail.promotion_detection_lag_days_sum, 0)
      AS promotion_detection_lag_days_sum,
    COALESCE(detail.promotion_detection_observation_count, 0)
      AS promotion_detection_observation_count,
    detail.promotion_currency_code
  FROM promotion_keys keys
  LEFT JOIN promotion_presence_period_aggregates presence
    ON keys.category = presence.category
   AND keys.competitor_id = presence.competitor_id
   AND keys.channel_code = presence.channel_code
   AND keys.fiscal_year = presence.fiscal_year
   AND keys.fiscal_period = presence.fiscal_period
  LEFT JOIN promotion_detail_period_aggregates detail
    ON keys.category = detail.category
   AND keys.competitor_id = detail.competitor_id
   AND keys.channel_code = detail.channel_code
   AND keys.fiscal_year = detail.fiscal_year
   AND keys.fiscal_period = detail.fiscal_period
),
dimension_keys AS (
  SELECT category, competitor_id, channel_code, fiscal_year, fiscal_period,
         period_start_date, period_end_date
  FROM price_period_aggregates
  UNION
  SELECT category, competitor_id, channel_code, fiscal_year, fiscal_period,
         period_start_date, period_end_date
  FROM promotion_period_aggregates
  UNION
  SELECT category, competitor_id, channel_code, fiscal_year, fiscal_period,
         period_start_date, period_end_date
  FROM assortment_period_aggregates
),
combined_aggregates AS (
  SELECT
    k.category,
    k.competitor_id,
    k.channel_code,
    k.fiscal_year,
    k.fiscal_period,
    k.period_start_date,
    k.period_end_date,
    CASE
      WHEN price.price_currency_code IS NOT NULL
       AND promotion.promotion_currency_code IS NOT NULL
       AND price.price_currency_code <> promotion.promotion_currency_code
      THEN NULL
      ELSE COALESCE(price.price_currency_code, promotion.promotion_currency_code)
    END AS currency_code,
    CASE
      WHEN promotion.competitor_promotion_observation_count IS NOT NULL
       AND assortment.assortment_observation_count IS NOT NULL
      THEN 'promotion_assortment'
      WHEN price.competitor_observation_count IS NOT NULL THEN 'price'
      WHEN promotion.competitor_promotion_observation_count IS NOT NULL THEN 'promotion'
      ELSE 'assortment'
    END AS measure_scope,
    COALESCE(price.price_ratio_sum, 0) AS price_ratio_sum,
    COALESCE(price.valid_price_observation_count, 0) AS valid_price_observation_count,
    COALESCE(price.valid_price_product_count, 0) AS valid_price_product_count,
    COALESCE(price.observed_price_product_count, 0) AS observed_price_product_count,
    COALESCE(price.sales_weighted_price_ratio_sum, 0) AS sales_weighted_price_ratio_sum,
    COALESCE(price.matched_units, 0) AS matched_units,
    COALESCE(price.competitor_observation_count, 0) AS competitor_observation_count,
    COALESCE(promotion.own_promo_presence_count, 0) AS own_promo_presence_count,
    COALESCE(promotion.competitor_promo_presence_count, 0) AS competitor_promo_presence_count,
    COALESCE(promotion.comparable_promo_observation_count, 0) AS comparable_promo_observation_count,
    COALESCE(promotion.comparable_promo_day_count, 0) AS comparable_promo_day_count,
    COALESCE(promotion.competitor_promotion_observation_count, 0)
      AS competitor_promotion_observation_count,
    COALESCE(promotion.discount_depth_pct_sum, 0) AS discount_depth_pct_sum,
    COALESCE(promotion.valid_discount_depth_count, 0) AS valid_discount_depth_count,
    COALESCE(promotion.circular_print_promo_count, 0) AS circular_print_promo_count,
    COALESCE(promotion.circular_digital_promo_count, 0) AS circular_digital_promo_count,
    COALESCE(promotion.onsite_promo_count, 0) AS onsite_promo_count,
    COALESCE(promotion.in_store_promo_count, 0) AS in_store_promo_count,
    COALESCE(promotion.email_app_promo_count, 0) AS email_app_promo_count,
    COALESCE(promotion.other_promo_count, 0) AS other_promo_count,
    COALESCE(promotion.promotion_detection_lag_days_sum, 0)
      AS promotion_detection_lag_days_sum,
    COALESCE(promotion.promotion_detection_observation_count, 0)
      AS promotion_detection_observation_count,
    COALESCE(assortment.assortment_observation_count, 0) AS assortment_observation_count,
    COALESCE(assortment.listed_observation_count, 0) AS listed_observation_count,
    COALESCE(assortment.available_observation_count, 0) AS available_observation_count,
    COALESCE(assortment.out_of_stock_observation_count, 0) AS out_of_stock_observation_count,
    COALESCE(assortment.stock_flagged_observation_count, 0) AS stock_flagged_observation_count,
    COALESCE(assortment.points_of_availability_count, 0) AS points_of_availability_count,
    CASE
      WHEN assortment.assortment_observation_count IS NOT NULL
      THEN COALESCE(channel_counts.listed_channel_count, 0)
      ELSE 0
    END AS listed_channel_count,
    COALESCE(assortment.competitor_listed_item_count, 0) AS competitor_listed_item_count,
    COALESCE(assortment.matched_listed_product_count, 0) AS matched_listed_product_count,
    COALESCE(assortment.matched_listed_inactive_product_count, 0)
      AS matched_listed_inactive_product_count,
    COALESCE(assortment.observed_own_product_count, 0) AS observed_own_product_count,
    COALESCE(assortment.matched_listed_competitor_item_count, 0)
      AS matched_listed_competitor_item_count,
    COALESCE(assortment.unmatched_listed_item_count, 0) AS unmatched_listed_item_count,
    CASE
      WHEN assortment.assortment_observation_count IS NOT NULL
      THEN COALESCE(catalog.own_catalog_product_count, 0)
      ELSE 0
    END AS own_catalog_product_count,
    COALESCE(assortment.search_rank_sum, 0) AS search_rank_sum,
    COALESCE(assortment.search_rank_observation_count, 0) AS search_rank_observation_count,
    COALESCE(assortment.assortment_state_change_count, 0) AS assortment_state_change_count,
    COALESCE(assortment.assortment_detection_lag_days_sum, 0)
      AS assortment_detection_lag_days_sum,
    COALESCE(assortment.assortment_detection_observation_count, 0)
      AS assortment_detection_observation_count,
    COALESCE(assortment.observation_interval_days_sum, 0) AS observation_interval_days_sum,
    COALESCE(assortment.observation_interval_count, 0) AS observation_interval_count
  FROM dimension_keys k
  LEFT JOIN price_period_aggregates price
    ON k.category = price.category
   AND k.competitor_id = price.competitor_id
   AND k.channel_code = price.channel_code
   AND k.fiscal_year = price.fiscal_year
   AND k.fiscal_period = price.fiscal_period
  LEFT JOIN promotion_period_aggregates promotion
    ON k.category = promotion.category
   AND k.competitor_id = promotion.competitor_id
   AND k.channel_code = promotion.channel_code
   AND k.fiscal_year = promotion.fiscal_year
   AND k.fiscal_period = promotion.fiscal_period
  LEFT JOIN assortment_period_aggregates assortment
    ON k.category = assortment.category
   AND k.competitor_id = assortment.competitor_id
   AND k.channel_code = assortment.channel_code
   AND k.fiscal_year = assortment.fiscal_year
   AND k.fiscal_period = assortment.fiscal_period
  LEFT JOIN assortment_channel_counts channel_counts
    ON k.category = channel_counts.category
   AND k.competitor_id = channel_counts.competitor_id
   AND k.fiscal_year = channel_counts.fiscal_year
   AND k.fiscal_period = channel_counts.fiscal_period
  LEFT JOIN own_catalog_periods catalog
    ON k.category = catalog.category
   AND k.fiscal_year = catalog.fiscal_year
   AND k.fiscal_period = catalog.fiscal_period
),
period_named AS (
  SELECT
    a.*,
    c.competitor_name,
    ROW_NUMBER() OVER (
      PARTITION BY a.category, a.competitor_id, a.channel_code,
                   a.fiscal_year, a.fiscal_period
      ORDER BY c.effective_from_date DESC, c.competitor_sk DESC
    ) AS competitor_name_rank
  FROM combined_aggregates a
  LEFT JOIN ${catalog}.${bmv_schema}.competitor c
    ON a.competitor_id = c.competitor_id
   AND c.effective_from_date <= a.period_end_date
   AND (c.effective_to_date IS NULL OR c.effective_to_date > a.period_end_date)
)
SELECT
  category,
  competitor_id,
  competitor_name,
  channel_code,
  fiscal_year,
  fiscal_period,
  period_start_date,
  period_end_date,
  currency_code,
  measure_scope,
  CAST(price_ratio_sum AS DOUBLE) AS price_ratio_sum,
  CAST(valid_price_observation_count AS BIGINT) AS valid_price_observation_count,
  CAST(valid_price_product_count AS BIGINT) AS valid_price_product_count,
  CAST(observed_price_product_count AS BIGINT) AS observed_price_product_count,
  CAST(100.0 * price_ratio_sum / NULLIF(valid_price_observation_count, 0) AS DOUBLE)
    AS price_index_vs_competitor,
  CAST(sales_weighted_price_ratio_sum AS DOUBLE) AS sales_weighted_price_ratio_sum,
  CAST(matched_units AS DOUBLE) AS matched_units,
  CAST(100.0 * sales_weighted_price_ratio_sum / NULLIF(matched_units, 0) AS DOUBLE)
    AS sales_weighted_price_index_vs_competitor,
  CAST(100.0 * valid_price_product_count / NULLIF(observed_price_product_count, 0) AS DOUBLE)
    AS price_observation_coverage_pct,
  CAST(competitor_observation_count AS BIGINT) AS competitor_observation_count,
  CAST(own_promo_presence_count AS BIGINT) AS own_promo_presence_count,
  CAST(competitor_promo_presence_count AS BIGINT) AS competitor_promo_presence_count,
  CAST(comparable_promo_observation_count AS BIGINT) AS comparable_promo_observation_count,
  CAST(comparable_promo_day_count AS BIGINT) AS comparable_promo_day_count,
  CAST(competitor_promotion_observation_count AS BIGINT)
    AS competitor_promotion_observation_count,
  CAST(discount_depth_pct_sum AS DOUBLE) AS discount_depth_pct_sum,
  CAST(valid_discount_depth_count AS BIGINT) AS valid_discount_depth_count,
  CAST(100.0 * own_promo_presence_count
       / NULLIF(own_promo_presence_count + competitor_promo_presence_count, 0) AS DOUBLE)
    AS promo_sov_pct,
  CAST(discount_depth_pct_sum / NULLIF(valid_discount_depth_count, 0) AS DOUBLE)
    AS avg_discount_depth_pct,
  CAST(circular_print_promo_count AS BIGINT) AS circular_print_promo_count,
  CAST(circular_digital_promo_count AS BIGINT) AS circular_digital_promo_count,
  CAST(onsite_promo_count AS BIGINT) AS onsite_promo_count,
  CAST(in_store_promo_count AS BIGINT) AS in_store_promo_count,
  CAST(email_app_promo_count AS BIGINT) AS email_app_promo_count,
  CAST(other_promo_count AS BIGINT) AS other_promo_count,
  CAST(assortment_observation_count AS BIGINT) AS assortment_observation_count,
  CAST(listed_observation_count AS BIGINT) AS listed_observation_count,
  CAST(available_observation_count AS BIGINT) AS available_observation_count,
  CAST(out_of_stock_observation_count AS BIGINT) AS out_of_stock_observation_count,
  CAST(stock_flagged_observation_count AS BIGINT) AS stock_flagged_observation_count,
  CAST(points_of_availability_count AS BIGINT) AS points_of_availability_count,
  CAST(listed_channel_count AS BIGINT) AS listed_channel_count,
  CAST(100.0 * listed_observation_count / NULLIF(assortment_observation_count, 0) AS DOUBLE)
    AS listed_share_pct,
  CAST(100.0 * available_observation_count / NULLIF(stock_flagged_observation_count, 0) AS DOUBLE)
    AS availability_rate_pct,
  unmatched_listed_item_count > 0 AS unmatched_listed_item_present_flag,
  CAST(competitor_listed_item_count AS BIGINT) AS competitor_listed_item_count,
  CAST(matched_listed_product_count AS BIGINT) AS matched_listed_product_count,
  CAST(matched_listed_inactive_product_count AS BIGINT)
    AS matched_listed_inactive_product_count,
  CAST(observed_own_product_count AS BIGINT) AS observed_own_product_count,
  CAST(matched_listed_competitor_item_count AS BIGINT)
    AS matched_listed_competitor_item_count,
  CAST(unmatched_listed_item_count AS BIGINT) AS unmatched_listed_item_count,
  CAST(own_catalog_product_count AS BIGINT) AS own_catalog_product_count,
  CAST(100.0 * observed_own_product_count / NULLIF(own_catalog_product_count, 0) AS DOUBLE)
    AS own_catalog_observation_coverage_pct,
  CAST(100.0 * matched_listed_product_count / NULLIF(observed_own_product_count, 0) AS DOUBLE)
    AS assortment_overlap_pct,
  CAST(100.0 * (observed_own_product_count - matched_listed_product_count)
       / NULLIF(observed_own_product_count, 0) AS DOUBLE) AS assortment_uniqueness_pct,
  CAST(100.0 * matched_listed_product_count
       / NULLIF(observed_own_product_count + unmatched_listed_item_count, 0) AS DOUBLE)
    AS assortment_jaccard_index_pct,
  CAST(100.0 * matched_listed_competitor_item_count
       / NULLIF(competitor_listed_item_count, 0) AS DOUBLE) AS match_coverage_pct,
  CAST(search_rank_sum AS DOUBLE) AS search_rank_sum,
  CAST(search_rank_observation_count AS BIGINT) AS search_rank_observation_count,
  CAST(search_rank_sum / NULLIF(search_rank_observation_count, 0) AS DOUBLE)
    AS share_of_search_avg_rank,
  CAST(promotion_detection_lag_days_sum AS DOUBLE) AS promotion_detection_lag_days_sum,
  CAST(promotion_detection_observation_count AS BIGINT)
    AS promotion_detection_observation_count,
  CAST(promotion_detection_lag_days_sum
       / NULLIF(promotion_detection_observation_count, 0) AS DOUBLE)
    AS avg_promotion_detection_lag_days,
  CAST(assortment_detection_lag_days_sum AS DOUBLE) AS assortment_detection_lag_days_sum,
  CAST(assortment_detection_observation_count AS BIGINT)
    AS assortment_detection_observation_count,
  CAST(assortment_detection_lag_days_sum
       / NULLIF(assortment_detection_observation_count, 0) AS DOUBLE)
    AS avg_assortment_detection_lag_days,
  CAST(promotion_detection_lag_days_sum + assortment_detection_lag_days_sum AS DOUBLE)
    AS detection_lag_days_sum,
  CAST(promotion_detection_observation_count + assortment_detection_observation_count AS BIGINT)
    AS detection_lag_observation_count,
  CAST((promotion_detection_lag_days_sum + assortment_detection_lag_days_sum)
       / NULLIF(promotion_detection_observation_count
                + assortment_detection_observation_count, 0) AS DOUBLE)
    AS avg_detection_lag_upper_bound_days,
  CAST(assortment_state_change_count AS BIGINT) AS assortment_state_change_count,
  CAST(observation_interval_days_sum AS DOUBLE) AS observation_interval_days_sum,
  CAST(observation_interval_count AS BIGINT) AS observation_interval_count,
  CAST(observation_interval_days_sum / NULLIF(observation_interval_count, 0) AS DOUBLE)
    AS avg_observation_cadence_days,
  'own_list_price_vs_competitor_mrp' AS price_index_basis,
  'usable_price_products_over_observed_matched_products' AS price_coverage_basis,
  'promoted_product_days_over_any_competitor_observation_coverage'
    AS promo_sov_basis,
  'observed_listing_channels_locations_and_unmatched_match_quality'
    AS distribution_basis,
  'listed_assortment_observations_with_known_stock_state' AS availability_basis,
  'observed_active_own_products_vs_observed_competitor_items_match_floor_0_80'
    AS assortment_basis,
  'promo_start_or_prior_assortment_observation_upper_bound' AS detection_basis,
  CASE
    WHEN channel_code = 'all' THEN 'national_all_channel_price_observation'
    ELSE 'source_observed_channel_with_national_ALL_location_sentinel'
  END AS channel_basis
FROM period_named
WHERE competitor_name_rank = 1
CLUSTER BY (category, competitor_id, fiscal_year, fiscal_period);
