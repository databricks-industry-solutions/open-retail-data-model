-- ============================================================
-- ORDM · Outcome Package · Actionable Customer Understanding
-- File: relationships.sql
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Enum CHECK constraints for the behavioral-segmentation extension table
-- (segment_membership), plus the documented logical relationships. Run AFTER the
-- canonical-core customer/marketing tables exist.
--
-- segment_membership is keyed for activation on the DURABLE business keys
-- (profile_id, audience_id) — the stable keys a reverse-ETL platform diffs on — not
-- on SCD2 surrogates, so its cross-table relationships are LOGICAL (durable-key,
-- enforced by DQ orphan checks), not declared UC surrogate FKs:
--   segment_membership.profile_id  -> customer.profile.profile_id (is_current = TRUE)
--   segment_membership.audience_id -> marketing.audience.audience_id (is_current = TRUE)
-- (See checks.sql: segment_membership_*_fk_orphan.)
-- ============================================================

-- Enum / state-domain CHECK constraints (always-on enforcement).
ALTER TABLE ${catalog}.${acu_schema}.segment_membership
  ADD CONSTRAINT chk_segment_membership_status
  CHECK (membership_status IS NULL OR membership_status IN ('realized', 'existing', 'exited'));

ALTER TABLE ${catalog}.${acu_schema}.segment_membership
  ADD CONSTRAINT chk_segment_membership_assignment_method
  CHECK (assignment_method IS NULL OR assignment_method IN ('rule', 'ml_score', 'imported'));

ALTER TABLE ${catalog}.${acu_schema}.segment_membership
  ADD CONSTRAINT chk_segment_membership_score_range
  CHECK (membership_score IS NULL OR (membership_score >= 0 AND membership_score <= 1));

-- ========== Market Analysis PR 2 observation and benchmark interfaces ==========
-- BMV remains the sole owner of competitor identity (ADR 0042). These four ACU
-- interfaces retain competitor_sk as point-in-time lineage, but their cross-package
-- relationship is LOGICAL on durable competitor_id and enforced by DQ orphan checks:
--   *.competitor_id -> balancing_margin_and_volume.competitor.competitor_id
-- Product references remain declared UC FKs into canonical core.

-- ---------------- competitor_promotion ----------------
ALTER TABLE ${catalog}.${acu_schema}.competitor_promotion
  ADD CONSTRAINT fk_competitor_promotion_product
  FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);

ALTER TABLE ${catalog}.${acu_schema}.competitor_promotion
  ADD CONSTRAINT chk_competitor_promotion_channel
  CHECK (channel_code IN ('online', 'in_store', 'marketplace', 'other'));

ALTER TABLE ${catalog}.${acu_schema}.competitor_promotion
  ADD CONSTRAINT chk_competitor_promotion_vehicle
  CHECK (promo_vehicle IN ('circular_print', 'circular_digital', 'onsite', 'in_store', 'email_app', 'other'));

ALTER TABLE ${catalog}.${acu_schema}.competitor_promotion
  ADD CONSTRAINT chk_competitor_promotion_type
  CHECK (promo_type IN ('TPR', 'FEATURE', 'DISPLAY', 'FEATURE_AND_DISPLAY', 'BOGO', 'COUPON', 'BUNDLE'));

ALTER TABLE ${catalog}.${acu_schema}.competitor_promotion
  ADD CONSTRAINT chk_competitor_promotion_match_type
  CHECK (match_type IS NULL OR match_type IN ('exact', 'equivalent', 'similar'));

ALTER TABLE ${catalog}.${acu_schema}.competitor_promotion
  ADD CONSTRAINT chk_competitor_promotion_match_method
  CHECK (match_method IS NULL OR match_method IN ('gtin', 'mpn_brand', 'ai_text', 'ai_image', 'manual'));

ALTER TABLE ${catalog}.${acu_schema}.competitor_promotion
  ADD CONSTRAINT chk_competitor_promotion_ranges
  CHECK (
    (promo_price IS NULL OR promo_price >= 0)
    AND (regular_price IS NULL OR regular_price >= 0)
    AND (discount_depth_pct IS NULL OR discount_depth_pct BETWEEN 0 AND 100)
    AND (match_confidence IS NULL OR match_confidence BETWEEN 0 AND 1)
    AND (placement_rank IS NULL OR placement_rank > 0)
  );

ALTER TABLE ${catalog}.${acu_schema}.competitor_promotion
  ADD CONSTRAINT chk_competitor_promotion_window
  CHECK (promo_start_date IS NULL OR promo_end_date IS NULL OR promo_end_date >= promo_start_date);

ALTER TABLE ${catalog}.${acu_schema}.competitor_promotion
  ADD CONSTRAINT chk_competitor_promotion_match_snapshot
  CHECK (
    (product_sk IS NULL AND product_id IS NULL AND match_type IS NULL AND match_method IS NULL AND match_confidence IS NULL)
    OR (product_sk IS NOT NULL AND product_id IS NOT NULL AND match_type IS NOT NULL AND match_method IS NOT NULL AND match_confidence IS NOT NULL)
  );

-- ---------------- competitor_assortment ----------------
ALTER TABLE ${catalog}.${acu_schema}.competitor_assortment
  ADD CONSTRAINT fk_competitor_assortment_product
  FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);

ALTER TABLE ${catalog}.${acu_schema}.competitor_assortment
  ADD CONSTRAINT chk_competitor_assortment_channel
  CHECK (channel_code IN ('online', 'in_store', 'marketplace', 'other'));

ALTER TABLE ${catalog}.${acu_schema}.competitor_assortment
  ADD CONSTRAINT chk_competitor_assortment_match_type
  CHECK (match_type IS NULL OR match_type IN ('exact', 'equivalent', 'similar'));

ALTER TABLE ${catalog}.${acu_schema}.competitor_assortment
  ADD CONSTRAINT chk_competitor_assortment_match_method
  CHECK (match_method IS NULL OR match_method IN ('gtin', 'mpn_brand', 'ai_text', 'ai_image', 'manual'));

ALTER TABLE ${catalog}.${acu_schema}.competitor_assortment
  ADD CONSTRAINT chk_competitor_assortment_ranges
  CHECK (
    (match_confidence IS NULL OR match_confidence BETWEEN 0 AND 1)
    AND (search_rank IS NULL OR search_rank > 0)
  );

ALTER TABLE ${catalog}.${acu_schema}.competitor_assortment
  ADD CONSTRAINT chk_competitor_assortment_match_snapshot
  CHECK (
    (product_sk IS NULL AND product_id IS NULL AND match_type IS NULL AND match_method IS NULL AND match_confidence IS NULL)
    OR (product_sk IS NOT NULL AND product_id IS NOT NULL AND match_type IS NOT NULL AND match_method IS NOT NULL AND match_confidence IS NOT NULL)
  );

-- ---------------- competitor_product_match ----------------
-- Observation competitor_item_ref values also have a logical provenance link to
-- this mutable Type-1 registry, never a hard FK: observations retain point-in-time
-- match snapshots. A warn DQ check compares latest assortment snapshots with active
-- registry rows so drift stays visible without rewriting history.

ALTER TABLE ${catalog}.${acu_schema}.competitor_product_match
  ADD CONSTRAINT fk_competitor_product_match_product
  FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);

ALTER TABLE ${catalog}.${acu_schema}.competitor_product_match
  ADD CONSTRAINT chk_competitor_product_match_type
  CHECK (match_type IN ('exact', 'equivalent', 'similar'));

ALTER TABLE ${catalog}.${acu_schema}.competitor_product_match
  ADD CONSTRAINT chk_competitor_product_match_method
  CHECK (match_method IN ('gtin', 'mpn_brand', 'ai_text', 'ai_image', 'manual'));

ALTER TABLE ${catalog}.${acu_schema}.competitor_product_match
  ADD CONSTRAINT chk_competitor_product_match_confidence
  CHECK (match_confidence BETWEEN 0 AND 1);

ALTER TABLE ${catalog}.${acu_schema}.competitor_product_match
  ADD CONSTRAINT chk_competitor_product_match_dates
  CHECK (last_verified_date >= first_matched_date);

-- ---------------- market_benchmark ----------------
ALTER TABLE ${catalog}.${acu_schema}.market_benchmark
  ADD CONSTRAINT chk_market_benchmark_geography_level
  CHECK (geography_level IN ('total', 'region', 'market', 'key_account', 'account_market'));

ALTER TABLE ${catalog}.${acu_schema}.market_benchmark
  ADD CONSTRAINT chk_market_benchmark_subject
  CHECK (
    subject_type IN ('own_banner', 'competitor_banner', 'brand', 'private_label', 'total_category')
    AND (
      (subject_type = 'total_category' AND subject_id IS NULL AND competitor_sk IS NULL AND competitor_id IS NULL)
      OR (subject_type = 'competitor_banner' AND subject_id IS NOT NULL AND competitor_sk IS NOT NULL AND competitor_id IS NOT NULL)
      OR (subject_type IN ('own_banner', 'brand', 'private_label') AND subject_id IS NOT NULL AND competitor_sk IS NULL AND competitor_id IS NULL)
    )
  );

ALTER TABLE ${catalog}.${acu_schema}.market_benchmark
  ADD CONSTRAINT chk_market_benchmark_period_type
  CHECK (period_type IN ('week', 'quad_week', '13_week', '52_week'));

ALTER TABLE ${catalog}.${acu_schema}.market_benchmark
  ADD CONSTRAINT chk_market_benchmark_percentages
  CHECK (
    (market_share_pct IS NULL OR market_share_pct BETWEEN 0 AND 100)
    AND (acv_weighted_distribution_pct IS NULL OR acv_weighted_distribution_pct BETWEEN 0 AND 100)
    AND (numeric_distribution_pct IS NULL OR numeric_distribution_pct BETWEEN 0 AND 100)
  );

ALTER TABLE ${catalog}.${acu_schema}.market_benchmark
  ADD CONSTRAINT chk_market_benchmark_nonnegative_measures
  CHECK (
    (sales_amount IS NULL OR sales_amount >= 0)
    AND (unit_volume IS NULL OR unit_volume >= 0)
    AND (eq_volume IS NULL OR eq_volume >= 0)
    AND (tdp IS NULL OR tdp >= 0)
    AND (promo_sales_amount IS NULL OR promo_sales_amount >= 0)
    AND (base_sales_amount IS NULL OR base_sales_amount >= 0)
  );

ALTER TABLE ${catalog}.${acu_schema}.market_benchmark
  ADD CONSTRAINT chk_market_benchmark_restatement_lineage
  CHECK (
    (is_restatement = TRUE AND restates_market_benchmark_id IS NOT NULL)
    OR (is_restatement = FALSE AND restates_market_benchmark_id IS NULL)
  );
