-- ============================================================
-- ORDM · Outcome Package · Actionable Customer Understanding · data-quality checks
-- Version: 0.5 · Generated: 2026-06-09 (behavioral/membership checks added 2026-07-21) · LLM-generated: true · Reviewed: 2026-07-21
-- Each assertion SELECTs violating rows; 0 rows = PASS. `metric` checks report
-- a value and never fail the run.
-- ============================================================

-- check: ltv_no_raw_pii | severity: error
-- The gold view must NOT expose raw PII columns (loyalty/household ids, names,
-- dob). PII stays in the governed dimension; the view keys on the surrogate.
SELECT column_name
FROM ${catalog}.information_schema.columns
WHERE table_schema = '${acu_schema}'
  AND table_name = 'gold_customer_ltv'
  AND column_name IN ('loyalty_id', 'household_id', 'first_name', 'middle_name',
                      'last_name', 'date_of_birth', 'name_prefix', 'name_suffix', 'contact_value');

-- check: ltv_grain_unique | severity: error
-- One row per customer, keyed on the DURABLE profile_id (never the version-specific
-- profile_sk). A re-versioned customer must not fragment into multiple rows — the
-- SCD2 fragmentation guard (standard §A.16). Dormant-green under single-version synthetic
-- data; fires once profile carries history.
SELECT profile_id
FROM ${catalog}.${acu_schema}.gold_customer_ltv
GROUP BY profile_id
HAVING COUNT(*) > 1;

-- check: ltv_rfm_components_range | severity: error
SELECT * FROM ${catalog}.${acu_schema}.gold_customer_ltv
WHERE r_score NOT BETWEEN 1 AND 5 OR f_score NOT BETWEEN 1 AND 5 OR m_score NOT BETWEEN 1 AND 5;

-- check: ltv_value_tier_domain | severity: error
SELECT * FROM ${catalog}.${acu_schema}.gold_customer_ltv
WHERE value_tier NOT IN ('PLATINUM', 'GOLD', 'SILVER', 'BRONZE');

-- check: ltv_predicted_clv_nonnegative | severity: error
SELECT * FROM ${catalog}.${acu_schema}.gold_customer_ltv
WHERE predicted_clv < 0;

-- check: ltv_customer_fk_orphan | severity: error
SELECT g.* FROM ${catalog}.${acu_schema}.gold_customer_ltv g
LEFT JOIN ${catalog}.${customer_schema}.profile p ON g.profile_sk = p.profile_sk
WHERE p.profile_sk IS NULL;

-- check: ltv_rowcount | severity: metric
SELECT COUNT(*) AS ltv_rows FROM ${catalog}.${acu_schema}.gold_customer_ltv;

-- check: ltv_value_tier_spread | severity: metric
-- Reported only: distinct value tiers present (4 = full spread).
SELECT COUNT(DISTINCT value_tier) AS distinct_tiers FROM ${catalog}.${acu_schema}.gold_customer_ltv;

-- check: ltv_predicted_clv_null_rate | severity: metric
SELECT ROUND(AVG(CASE WHEN predicted_clv IS NULL THEN 1.0 ELSE 0.0 END), 4) AS predicted_null_rate
FROM ${catalog}.${acu_schema}.gold_customer_ltv;

-- ---------- behavioral segmentation (gold_customer_behavioral_attributes) ----------

-- check: behavioral_attributes_grain_unique | severity: error
-- One current row per customer (the wide trait surface / parent model).
SELECT profile_id
FROM ${catalog}.${acu_schema}.gold_customer_behavioral_attributes
GROUP BY profile_id
HAVING COUNT(*) > 1;

-- check: behavioral_attributes_no_raw_pii | severity: error
-- The trait surface must NOT expose raw PII; it keys on the pseudonymous profile_id.
SELECT column_name
FROM ${catalog}.information_schema.columns
WHERE table_schema = '${acu_schema}'
  AND table_name = 'gold_customer_behavioral_attributes'
  AND column_name IN ('loyalty_id', 'household_id', 'first_name', 'middle_name',
                      'last_name', 'date_of_birth', 'name_prefix', 'name_suffix', 'contact_value');

-- check: behavioral_attributes_lifecycle_domain | severity: error
SELECT * FROM ${catalog}.${acu_schema}.gold_customer_behavioral_attributes
WHERE lifecycle_stage NOT IN ('new', 'active', 'lapsing', 'churned');

-- check: behavioral_attributes_opt_in_domain | severity: error
SELECT * FROM ${catalog}.${acu_schema}.gold_customer_behavioral_attributes
WHERE opt_in_status NOT IN ('opted_in', 'opted_out', 'unknown');

-- ---------- behavioral segmentation (segment_membership) ----------

-- check: segment_membership_grain_unique | severity: error
-- One row per (profile_id x audience_id x as_of_date) — no fan-out/double-count.
SELECT profile_id, audience_id, as_of_date
FROM ${catalog}.${acu_schema}.segment_membership
GROUP BY profile_id, audience_id, as_of_date
HAVING COUNT(*) > 1;

-- check: segment_membership_keys_not_null | severity: error
SELECT * FROM ${catalog}.${acu_schema}.segment_membership
WHERE segment_membership_id IS NULL OR profile_id IS NULL OR audience_id IS NULL OR as_of_date IS NULL;

-- check: segment_membership_status_domain | severity: error
SELECT * FROM ${catalog}.${acu_schema}.segment_membership
WHERE membership_status IS NOT NULL
  AND membership_status NOT IN ('realized', 'existing', 'exited');

-- check: segment_membership_score_range | severity: error
SELECT * FROM ${catalog}.${acu_schema}.segment_membership
WHERE membership_score IS NOT NULL AND (membership_score < 0 OR membership_score > 1);

-- check: segment_membership_profile_fk_orphan | severity: error
-- Membership profile_id must resolve to a current customer profile (durable-key FK).
SELECT m.segment_membership_id, m.profile_id
FROM ${catalog}.${acu_schema}.segment_membership m
LEFT JOIN ${catalog}.${customer_schema}.profile p
  ON m.profile_id = p.profile_id AND p.is_current = TRUE
WHERE p.profile_id IS NULL;

-- check: segment_membership_audience_fk_orphan | severity: error
-- Membership audience_id must resolve to a current segment definition (durable-key FK
-- into the shared silver marketing.audience dim, ADR 0022).
SELECT m.segment_membership_id, m.audience_id
FROM ${catalog}.${acu_schema}.segment_membership m
LEFT JOIN ${catalog}.${marketing_schema}.audience a
  ON m.audience_id = a.audience_id AND a.is_current = TRUE
WHERE a.audience_id IS NULL;

-- check: segment_membership_rowcount | severity: metric
SELECT COUNT(*) AS membership_rows FROM ${catalog}.${acu_schema}.segment_membership;

-- ---------- Market Analysis competitive position ----------

-- check: market_analysis_grain_unique | severity: error
-- One row per category × durable competitor × observed channel × fiscal period.
SELECT category, competitor_id, channel_code, fiscal_year, fiscal_period
FROM ${catalog}.${acu_schema}.gold_competitive_position
GROUP BY category, competitor_id, channel_code, fiscal_year, fiscal_period
HAVING COUNT(*) > 1;

-- check: market_analysis_count_consistency | severity: error
-- Raw numerators cannot exceed their same-grain observation populations.
-- listed_channel_count is period-grain and intentionally repeats on channel rows,
-- so it cannot be compared with per-channel listed_observation_count here.
SELECT *
FROM ${catalog}.${acu_schema}.gold_competitive_position
WHERE valid_price_product_count > observed_price_product_count
   OR valid_price_observation_count > competitor_observation_count
   OR own_promo_presence_count > comparable_promo_observation_count
   OR competitor_promo_presence_count > comparable_promo_observation_count
   OR comparable_promo_day_count > comparable_promo_observation_count
   OR valid_discount_depth_count > competitor_promotion_observation_count
   OR circular_print_promo_count + circular_digital_promo_count
      + onsite_promo_count + in_store_promo_count
      + email_app_promo_count + other_promo_count
      <> competitor_promotion_observation_count
   OR listed_observation_count > assortment_observation_count
   OR stock_flagged_observation_count > listed_observation_count
   OR available_observation_count + out_of_stock_observation_count
      <> stock_flagged_observation_count
   OR points_of_availability_count > listed_observation_count
   OR matched_listed_competitor_item_count > competitor_listed_item_count
   OR unmatched_listed_item_count > competitor_listed_item_count
   OR observed_own_product_count > own_catalog_product_count
   OR matched_listed_product_count > observed_own_product_count
   OR matched_listed_inactive_product_count > competitor_listed_item_count
   OR search_rank_observation_count > assortment_observation_count
   OR detection_lag_observation_count
      <> promotion_detection_observation_count
       + assortment_detection_observation_count
   OR assortment_detection_observation_count > assortment_state_change_count
   OR observation_interval_count > assortment_observation_count;

-- check: market_analysis_percentage_bounds | severity: error
SELECT *
FROM ${catalog}.${acu_schema}.gold_competitive_position
WHERE (price_observation_coverage_pct IS NOT NULL
       AND price_observation_coverage_pct NOT BETWEEN 0 AND 100)
   OR (promo_sov_pct IS NOT NULL AND promo_sov_pct NOT BETWEEN 0 AND 100)
   OR (avg_discount_depth_pct IS NOT NULL AND avg_discount_depth_pct NOT BETWEEN 0 AND 100)
   OR (listed_share_pct IS NOT NULL AND listed_share_pct NOT BETWEEN 0 AND 100)
   OR (availability_rate_pct IS NOT NULL AND availability_rate_pct NOT BETWEEN 0 AND 100)
   OR (assortment_overlap_pct IS NOT NULL AND assortment_overlap_pct NOT BETWEEN 0 AND 100)
   OR (assortment_uniqueness_pct IS NOT NULL
       AND assortment_uniqueness_pct NOT BETWEEN 0 AND 100)
   OR (assortment_jaccard_index_pct IS NOT NULL
       AND assortment_jaccard_index_pct NOT BETWEEN 0 AND 100)
   OR (match_coverage_pct IS NOT NULL AND match_coverage_pct NOT BETWEEN 0 AND 100)
   OR (own_catalog_observation_coverage_pct IS NOT NULL
       AND own_catalog_observation_coverage_pct NOT BETWEEN 0 AND 100)
   OR (share_of_search_avg_rank IS NOT NULL AND share_of_search_avg_rank <= 0)
   OR (avg_detection_lag_upper_bound_days IS NOT NULL
       AND avg_detection_lag_upper_bound_days < 0)
   OR (avg_promotion_detection_lag_days IS NOT NULL
       AND avg_promotion_detection_lag_days < 0)
   OR (avg_assortment_detection_lag_days IS NOT NULL
       AND avg_assortment_detection_lag_days < 0)
   OR (avg_observation_cadence_days IS NOT NULL AND avg_observation_cadence_days < 0)
   OR (price_index_vs_competitor IS NOT NULL AND price_index_vs_competitor <= 0)
   OR (sales_weighted_price_index_vs_competitor IS NOT NULL
       AND sales_weighted_price_index_vs_competitor <= 0);

-- check: market_analysis_currency_known | severity: error
-- A NULL with monetary observations means currencies disagreed inside one grain.
-- Assortment-only rows carry no currency and remain NULL-honest.
SELECT *
FROM ${catalog}.${acu_schema}.gold_competitive_position
WHERE (valid_price_observation_count > 0 OR competitor_promotion_observation_count > 0)
  AND currency_code IS NULL;

-- Structural output guard scoped to the registered Market Analysis objects. ACU legitimately
-- contains person-level customer use cases, so a schema-wide guard would be incorrect.
-- check: market_analysis_no_person_level_columns | severity: error
SELECT column_name, table_name
FROM ${catalog}.information_schema.columns
WHERE table_schema = '${acu_schema}'
  AND table_name IN (
    'competitor_promotion', 'competitor_assortment', 'competitor_product_match',
    'market_benchmark', 'gold_competitive_position', 'mv_competitive_position',
    'gold_market_share', 'mv_market_share'
  )
  AND (
    lower(column_name) LIKE '%profile%'
    OR lower(column_name) LIKE '%customer%'
    OR lower(column_name) LIKE '%household%'
    OR lower(column_name) LIKE '%loyalty%'
    OR (
      lower(column_name) LIKE '%email%'
      -- Aggregate promotion-vehicle count for promo_vehicle='email_app'; not an address.
      AND lower(column_name) <> 'email_app_promo_count'
    )
    OR lower(column_name) LIKE '%phone%'
    OR lower(column_name) LIKE '%address%'
    OR lower(column_name) LIKE '%device_id%'
    OR lower(column_name) LIKE '%session_id%'
    OR lower(column_name) LIKE '%person%'
    OR lower(column_name) LIKE '%demographic%'
    OR lower(column_name) LIKE '%gender%'
    OR lower(column_name) LIKE '%ethnicity%'
    OR lower(column_name) LIKE '%age_bracket%'
    OR lower(column_name) LIKE '%reidentification_key%'
  );

-- Antitrust wall: Market Analysis may read competitor pricing, but no price-producing
-- surface may read Market Analysis. The deployed schema list is rendered from the
-- market_analysis_no_pricing_lineage registry in standards/rules.yaml through the
-- databricks.yml schema-token resolver, including deployment overrides. The static test
-- globs every committed gold/metric/core SQL file as the auto-extending backstop.
-- That static scan is the materialized-view coverage when a runtime omits MV bodies from
-- information_schema.views.
-- check: market_analysis_no_pricing_lineage | severity: error
WITH market_analysis_objects(object_name) AS (
  VALUES ${market_analysis_protected_object_values}
)
SELECT DISTINCT v.table_schema, v.table_name
FROM ${catalog}.information_schema.views v
JOIN market_analysis_objects source_object
  ON regexp_like(
    replace(lower(v.view_definition), '`', ''),
    concat('[.]', source_object.object_name, '([^a-z0-9_]|$)')
  )
WHERE lower(v.table_schema) IN (${market_analysis_price_producing_schema_literals})
  AND regexp_like(lower(v.table_name), '${market_analysis_price_producing_name_pattern}')
  AND NOT EXISTS (
    SELECT 1
    FROM market_analysis_objects own_object
    WHERE own_object.object_name = lower(v.table_name)
  );

-- Licensed-benchmark wall: market_benchmark and its serving derivatives are
-- internal-use-only by default. DSWS owns every repository sharing, clean-room
-- and Delta-Sharing publication surface, and its deployed schema is rendered
-- from the standards registry. The static test scans the registered source path.
-- check: market_benchmark_no_redistribution_lineage | severity: error
WITH licensed_market_objects(object_name) AS (
  VALUES ${market_benchmark_licensed_object_values}
)
SELECT DISTINCT v.table_schema, v.table_name
FROM ${catalog}.information_schema.views v
JOIN licensed_market_objects source_object
  ON regexp_like(
    replace(lower(v.view_definition), '`', ''),
    concat('[.]', source_object.object_name, '([^a-z0-9_]|$)')
  )
WHERE lower(v.table_schema) IN (${market_benchmark_sharing_schema_literals})
  AND NOT EXISTS (
    SELECT 1
    FROM licensed_market_objects own_object
    WHERE own_object.object_name = lower(v.table_name)
  );

-- check: market_analysis_rowcount | severity: metric
SELECT COUNT(*) AS competitive_position_rows
FROM ${catalog}.${acu_schema}.gold_competitive_position;

-- ========== Market Analysis PR 2 source interfaces ==========

-- check: competitor_promotion_grain_unique | severity: error
SELECT competitor_promotion_id
FROM ${catalog}.${acu_schema}.competitor_promotion
GROUP BY competitor_promotion_id
HAVING COUNT(*) > 1;

-- check: competitor_promotion_source_identity | severity: error
SELECT *
FROM ${catalog}.${acu_schema}.competitor_promotion
WHERE competitor_promotion_id <> concat_ws('|', record_source, source_observation_id);

-- check: competitor_promotion_competitor_logical_fk_orphan | severity: error
SELECT p.*
FROM ${catalog}.${acu_schema}.competitor_promotion p
WHERE NOT EXISTS (
  SELECT 1
  FROM ${catalog}.${bmv_schema}.competitor c
  WHERE c.competitor_id = p.competitor_id
);

-- check: competitor_promotion_product_fk_orphan | severity: error
SELECT p.*
FROM ${catalog}.${acu_schema}.competitor_promotion p
LEFT JOIN ${catalog}.${product_schema}.product d ON p.product_sk = d.product_sk
WHERE p.product_sk IS NOT NULL AND d.product_sk IS NULL;

-- check: competitor_promotion_calendar_fk_orphan | severity: error
SELECT p.*
FROM ${catalog}.${acu_schema}.competitor_promotion p
LEFT JOIN ${catalog}.${calendar_schema}.fiscal_calendar c ON p.date_key = c.date_key
WHERE c.date_key IS NULL;

-- check: competitor_promotion_single_currency | severity: error
SELECT 1
FROM ${catalog}.${acu_schema}.competitor_promotion
HAVING COUNT(DISTINCT currency_code) > 1
    OR COUNT(CASE WHEN currency_code IS NULL THEN 1 END) > 0;

-- check: competitor_promotion_discount_consistency | severity: error
SELECT *
FROM ${catalog}.${acu_schema}.competitor_promotion
WHERE promo_price IS NOT NULL
  AND regular_price IS NOT NULL
  AND discount_depth_pct IS NOT NULL
  AND regular_price > 0
  AND ABS(discount_depth_pct - 100.0 * (regular_price - promo_price) / regular_price) > 0.02;

-- check: competitor_assortment_grain_unique | severity: error
SELECT competitor_assortment_id
FROM ${catalog}.${acu_schema}.competitor_assortment
GROUP BY competitor_assortment_id
HAVING COUNT(*) > 1;

-- check: competitor_assortment_source_identity | severity: error
SELECT *
FROM ${catalog}.${acu_schema}.competitor_assortment
WHERE competitor_assortment_id <> concat_ws('|', record_source, source_observation_id);

-- check: competitor_assortment_competitor_logical_fk_orphan | severity: error
SELECT a.*
FROM ${catalog}.${acu_schema}.competitor_assortment a
WHERE NOT EXISTS (
  SELECT 1
  FROM ${catalog}.${bmv_schema}.competitor c
  WHERE c.competitor_id = a.competitor_id
);

-- check: competitor_assortment_product_fk_orphan | severity: error
SELECT a.*
FROM ${catalog}.${acu_schema}.competitor_assortment a
LEFT JOIN ${catalog}.${product_schema}.product p ON a.product_sk = p.product_sk
WHERE a.product_sk IS NOT NULL AND p.product_sk IS NULL;

-- check: competitor_assortment_calendar_fk_orphan | severity: error
SELECT a.*
FROM ${catalog}.${acu_schema}.competitor_assortment a
LEFT JOIN ${catalog}.${calendar_schema}.fiscal_calendar c ON a.date_key = c.date_key
WHERE c.date_key IS NULL;

-- check: competitor_assortment_observation_state | severity: error
SELECT *
FROM ${catalog}.${acu_schema}.competitor_assortment
WHERE is_listed = FALSE AND is_available = TRUE;

-- check: competitor_product_match_grain_unique | severity: error
SELECT competitor_id, competitor_item_ref
FROM ${catalog}.${acu_schema}.competitor_product_match
GROUP BY competitor_id, competitor_item_ref
HAVING COUNT(*) > 1;

-- check: competitor_product_match_identity | severity: error
SELECT *
FROM ${catalog}.${acu_schema}.competitor_product_match
WHERE competitor_product_match_id <> concat_ws('|', competitor_id, competitor_item_ref);

-- check: competitor_product_match_competitor_logical_fk_orphan | severity: error
SELECT m.*
FROM ${catalog}.${acu_schema}.competitor_product_match m
WHERE NOT EXISTS (
  SELECT 1
  FROM ${catalog}.${bmv_schema}.competitor c
  WHERE c.competitor_id = m.competitor_id
);

-- check: competitor_product_match_product_fk_orphan | severity: error
SELECT m.*
FROM ${catalog}.${acu_schema}.competitor_product_match m
LEFT JOIN ${catalog}.${product_schema}.product p ON m.product_sk = p.product_sk
WHERE p.product_sk IS NULL;

-- check: competitor_product_match_snapshot_drift | severity: warn
-- Serving KPIs intentionally use point-in-time observation snapshots. This check
-- makes drift against the active Type-1 provenance registry visible without
-- rewriting history or making append-only observations depend on mutable state.
WITH latest_assortment_match AS (
  SELECT *
  FROM (
    SELECT
      competitor_id,
      competitor_item_ref,
      product_id,
      match_type,
      match_confidence,
      ROW_NUMBER() OVER (
        PARTITION BY competitor_id, competitor_item_ref
        ORDER BY observed_at_ts DESC, load_timestamp DESC, competitor_assortment_id DESC
      ) AS observation_rank
    FROM ${catalog}.${acu_schema}.competitor_assortment
  ) ranked
  WHERE observation_rank = 1
),
active_registry_match AS (
  SELECT competitor_id, competitor_item_ref, product_id, match_type, match_confidence
  FROM ${catalog}.${acu_schema}.competitor_product_match
  WHERE is_active = TRUE
)
SELECT
  COALESCE(snapshot.competitor_id, registry.competitor_id) AS competitor_id,
  COALESCE(snapshot.competitor_item_ref, registry.competitor_item_ref)
    AS competitor_item_ref
FROM latest_assortment_match snapshot
FULL OUTER JOIN active_registry_match registry
  ON snapshot.competitor_id = registry.competitor_id
 AND snapshot.competitor_item_ref = registry.competitor_item_ref
WHERE snapshot.competitor_id IS NULL
   OR registry.competitor_id IS NULL
   OR NOT (snapshot.product_id <=> registry.product_id)
   OR NOT (snapshot.match_type <=> registry.match_type)
   OR NOT (snapshot.match_confidence <=> registry.match_confidence);

-- check: market_benchmark_grain_unique | severity: error
SELECT market_benchmark_id
FROM ${catalog}.${acu_schema}.market_benchmark
GROUP BY market_benchmark_id
HAVING COUNT(*) > 1;

-- check: market_benchmark_source_identity | severity: error
SELECT *
FROM ${catalog}.${acu_schema}.market_benchmark
WHERE market_benchmark_id <> concat_ws('|', record_source, source_observation_id);

-- check: market_benchmark_competitor_logical_fk_orphan | severity: error
SELECT b.*
FROM ${catalog}.${acu_schema}.market_benchmark b
WHERE b.competitor_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM ${catalog}.${bmv_schema}.competitor c
    WHERE c.competitor_id = b.competitor_id
  );

-- check: market_benchmark_calendar_fk_orphan | severity: error
-- Provider periods retain their own vocabulary; only the literal end date maps to
-- the daily fiscal calendar, with no claim that provider weeks equal fiscal weeks.
SELECT b.*
FROM ${catalog}.${acu_schema}.market_benchmark b
LEFT JOIN ${catalog}.${calendar_schema}.fiscal_calendar c ON b.period_end_date = c.date_key
WHERE c.date_key IS NULL;

-- check: market_benchmark_single_currency | severity: error
SELECT 1
FROM ${catalog}.${acu_schema}.market_benchmark
HAVING COUNT(DISTINCT currency_code) > 1
    OR COUNT(CASE WHEN currency_code IS NULL THEN 1 END) > 0;

-- check: market_benchmark_latest_unique | severity: error
SELECT benchmark_cell_id
FROM ${catalog}.${acu_schema}.gold_market_share
GROUP BY benchmark_cell_id
HAVING COUNT(*) <> 1;

-- check: market_benchmark_share_sum | severity: warn
-- Gold excludes total-category denominator cells. A sum below 100 is an honest
-- unmeasured remainder; only over-allocation beyond rounding tolerance is flagged.
-- Subject types are non-mutually-exclusive measurement lenses: banners, brands and
-- private label may overlap, so the per-subject_type partition is deliberate.
SELECT
  record_source, market_definition, geography_level, geography_code,
  category_ref, subject_type, period_type, period_end_date,
  SUM(provider_reported_market_share_pct) AS measured_subject_share_pct
FROM ${catalog}.${acu_schema}.gold_market_share
WHERE provider_reported_market_share_pct IS NOT NULL
GROUP BY
  record_source, market_definition, geography_level, geography_code,
  category_ref, subject_type, period_type, period_end_date
HAVING SUM(provider_reported_market_share_pct) > 100.01;

-- check: market_share_banner_set_share_sum | severity: warn
-- Own and competitor banners form one mutually-exclusive lens, so validate their
-- combined reported share without mixing in overlapping brand/private-label lenses.
SELECT
  record_source, market_definition, geography_level, geography_code,
  category_ref, period_type, period_end_date,
  SUM(provider_reported_market_share_pct) AS measured_banner_share_pct
FROM ${catalog}.${acu_schema}.gold_market_share
WHERE subject_type IN ('own_banner', 'competitor_banner')
  AND provider_reported_market_share_pct IS NOT NULL
GROUP BY
  record_source, market_definition, geography_level, geography_code,
  category_ref, period_type, period_end_date
HAVING SUM(provider_reported_market_share_pct) > 100.01;

-- check: market_share_percentage_bounds | severity: error
SELECT *
FROM ${catalog}.${acu_schema}.gold_market_share
WHERE (market_share_pct IS NOT NULL AND market_share_pct NOT BETWEEN 0 AND 100)
   OR (provider_reported_market_share_pct IS NOT NULL
       AND provider_reported_market_share_pct NOT BETWEEN 0 AND 100)
   OR (acv_weighted_distribution_pct IS NOT NULL
       AND acv_weighted_distribution_pct NOT BETWEEN 0 AND 100)
   OR (numeric_distribution_pct IS NOT NULL
       AND numeric_distribution_pct NOT BETWEEN 0 AND 100);

-- check: market_share_component_consistency | severity: error
SELECT *
FROM ${catalog}.${acu_schema}.gold_market_share
WHERE market_share_sales_amount IS NOT NULL
  AND market_size_sales_amount IS NOT NULL
  AND market_share_sales_amount > market_size_sales_amount;

-- check: market_share_rowcount | severity: metric
-- Counts served non-total subject cells; denominator-only total-category cells stay internal.
SELECT COUNT(*) AS market_share_subject_rows
FROM ${catalog}.${acu_schema}.gold_market_share;

-- ========== Product Affinity ==========
-- These serving surfaces are DERIVED gold materialized views (no source table, no
-- synthetic producer), so every assertion passes vacuously on an empty result — the
-- affinity surface is intentionally sparse on ORDM's uniform-random synthetic baskets.

-- check: product_affinity_pairwise_grain_unique | severity: error
-- One row per directed pair × window (product_id_a × product_id_b × time_window).
SELECT product_id_a, product_id_b, time_window
FROM ${catalog}.${acu_schema}.gold_product_affinity_pairwise
GROUP BY product_id_a, product_id_b, time_window
HAVING COUNT(*) > 1;

-- check: product_affinity_pairwise_keys_not_null | severity: error
-- The grain key and both pair legs must be non-null (symmetric with
-- customer_product_affinity_keys_not_null). The view can't emit nulls today (its source
-- filters product_id/order_id IS NOT NULL), so this guards the invariant against future
-- source changes rather than a current defect.
SELECT *
FROM ${catalog}.${acu_schema}.gold_product_affinity_pairwise
WHERE product_affinity_id IS NULL OR product_id_a IS NULL OR product_id_b IS NULL OR time_window IS NULL;

-- check: product_affinity_pairwise_metric_bounds | severity: error
-- Support/confidence are probabilities (0..1); lift is a non-negative ratio; a pair
-- never pairs a product with itself.
SELECT *
FROM ${catalog}.${acu_schema}.gold_product_affinity_pairwise
WHERE support NOT BETWEEN 0 AND 1
   OR confidence NOT BETWEEN 0 AND 1
   OR lift < 0
   OR product_id_a = product_id_b;

-- check: product_affinity_pairwise_count_consistency | severity: error
-- Co-occurrence cannot exceed either single-item basket count or the basket total.
SELECT *
FROM ${catalog}.${acu_schema}.gold_product_affinity_pairwise
WHERE cooccurrence_baskets > antecedent_baskets
   OR cooccurrence_baskets > consequent_baskets
   OR antecedent_baskets > total_baskets
   OR consequent_baskets > total_baskets;

-- check: product_affinity_pairwise_product_fk_orphan | severity: error
-- Both pair legs must resolve to a current product (durable-key FK into product).
SELECT g.product_affinity_id
FROM ${catalog}.${acu_schema}.gold_product_affinity_pairwise g
WHERE NOT EXISTS (
        SELECT 1 FROM ${catalog}.${product_schema}.product p
        WHERE p.product_id = g.product_id_a AND p.is_current = TRUE)
   OR NOT EXISTS (
        SELECT 1 FROM ${catalog}.${product_schema}.product p
        WHERE p.product_id = g.product_id_b AND p.is_current = TRUE);

-- check: product_affinity_pairwise_rowcount | severity: metric
SELECT COUNT(*) AS pairwise_affinity_rows
FROM ${catalog}.${acu_schema}.gold_product_affinity_pairwise;

-- check: customer_product_affinity_grain_unique | severity: error
-- One row per (customer × product), keyed on the durable profile_id + product_id.
SELECT profile_id, product_id
FROM ${catalog}.${acu_schema}.gold_customer_product_affinity
GROUP BY profile_id, product_id
HAVING COUNT(*) > 1;

-- check: customer_product_affinity_keys_not_null | severity: error
SELECT *
FROM ${catalog}.${acu_schema}.gold_customer_product_affinity
WHERE customer_product_affinity_id IS NULL OR profile_id IS NULL OR product_id IS NULL;

-- check: customer_product_affinity_score_range | severity: error
-- affinity_score and recency_weight are bounded [0,1]; days_since_last_purchase >= 0.
SELECT *
FROM ${catalog}.${acu_schema}.gold_customer_product_affinity
WHERE affinity_score NOT BETWEEN 0 AND 1
   OR recency_weight NOT BETWEEN 0 AND 1
   OR days_since_last_purchase < 0;

-- check: customer_product_affinity_band_domain | severity: error
SELECT *
FROM ${catalog}.${acu_schema}.gold_customer_product_affinity
WHERE affinity_band NOT IN ('high', 'medium', 'low');

-- check: customer_product_affinity_single_currency | severity: error
-- total_net_amount is a monetary fact, so it must never silently mix currencies: the
-- canonical core is single-reporting-currency by construction, so the view carries exactly
-- one currency_code and never a NULL. Mirrors competitor_promotion_single_currency /
-- market_benchmark_single_currency (DQ-FACT-COVERAGE, standard §A.12). Vacuously green when empty.
SELECT 1
FROM ${catalog}.${acu_schema}.gold_customer_product_affinity
HAVING COUNT(DISTINCT currency_code) > 1
    OR COUNT(CASE WHEN currency_code IS NULL THEN 1 END) > 0;

-- check: customer_product_affinity_no_raw_pii | severity: error
-- Keyed on the pseudonymous profile_id; no raw PII columns may appear.
SELECT column_name
FROM ${catalog}.information_schema.columns
WHERE table_schema = '${acu_schema}'
  AND table_name = 'gold_customer_product_affinity'
  AND column_name IN ('loyalty_id', 'household_id', 'first_name', 'middle_name',
                      'last_name', 'date_of_birth', 'name_prefix', 'name_suffix', 'contact_value');

-- check: customer_product_affinity_profile_fk_orphan | severity: error
SELECT g.customer_product_affinity_id, g.profile_id
FROM ${catalog}.${acu_schema}.gold_customer_product_affinity g
LEFT JOIN ${catalog}.${customer_schema}.profile p
  ON g.profile_id = p.profile_id AND p.is_current = TRUE
WHERE p.profile_id IS NULL;

-- check: customer_product_affinity_product_fk_orphan | severity: error
SELECT g.customer_product_affinity_id, g.product_id
FROM ${catalog}.${acu_schema}.gold_customer_product_affinity g
LEFT JOIN ${catalog}.${product_schema}.product p
  ON g.product_id = p.product_id AND p.is_current = TRUE
WHERE p.product_id IS NULL;

-- check: customer_product_affinity_rowcount | severity: metric
SELECT COUNT(*) AS customer_product_affinity_rows
FROM ${catalog}.${acu_schema}.gold_customer_product_affinity;
