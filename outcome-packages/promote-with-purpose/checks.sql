-- ============================================================
-- ORDM · Outcome Package · Promote with Purpose · data-quality checks
-- Version: 0.5 · Generated: 2026-06-09 · LLM-generated: true · Reviewed: 2026-06-09
-- Each assertion SELECTs violating rows; 0 rows = PASS. `metric` checks
-- report a value and never fail the run.
-- ============================================================

-- ---------- promotion_scope ----------

-- check: scope_keys_not_null | severity: error
SELECT * FROM ${catalog}.${promo_schema}.promotion_scope
WHERE scope_sk IS NULL OR scope_id IS NULL OR promo_id IS NULL
   OR product_id IS NULL OR store_id IS NULL;

-- check: scope_promotion_fk_orphan | severity: error
SELECT sc.* FROM ${catalog}.${promo_schema}.promotion_scope sc
LEFT JOIN ${catalog}.${marketing_schema}.promotion p ON sc.promo_sk = p.promo_sk
WHERE sc.promo_sk IS NOT NULL AND p.promo_sk IS NULL;

-- check: scope_product_fk_orphan | severity: error
SELECT sc.* FROM ${catalog}.${promo_schema}.promotion_scope sc
LEFT JOIN ${catalog}.${product_schema}.product p ON sc.product_sk = p.product_sk
WHERE sc.product_sk IS NOT NULL AND p.product_sk IS NULL;

-- check: scope_store_fk_orphan | severity: error
SELECT sc.* FROM ${catalog}.${promo_schema}.promotion_scope sc
LEFT JOIN ${catalog}.${store_schema}.store st ON sc.store_sk = st.store_sk
WHERE sc.store_sk IS NOT NULL AND st.store_sk IS NULL;

-- ---------- gold_trade_promotion ----------

-- check: gold_trade_promotion_grain_unique | severity: error
-- One row per promo x product x store x fiscal week, keyed on the DURABLE ids
-- (never the version-specific promo_sk); fiscal_week_id is part of the grain (the
-- view is weekly). A re-versioned promotion must not fragment into multiple rows —
-- the SCD2 fragmentation guard (standard §A.16). Dormant-green under single-version
-- synthetic data.
SELECT promo_id, product_id, store_id, fiscal_week_id
FROM ${catalog}.${promo_schema}.gold_trade_promotion
GROUP BY promo_id, product_id, store_id, fiscal_week_id
HAVING COUNT(*) > 1;

-- check: gold_promo_roi_grain_unique | severity: error
-- One row per promo x category, keyed on the durable promo_id. A re-versioned
-- promotion must not split its category ROI across surrogate keys (standard §A.16).
-- Dormant-green under single-version synthetic data.
SELECT promo_id, category
FROM ${catalog}.${promo_schema}.gold_promo_roi_by_category
GROUP BY promo_id, category
HAVING COUNT(*) > 1;

-- check: gold_weekly_baseline_grain_dupe_rows | severity: metric
-- Reported only (NOT an error): the view already GROUP BYs (product_sk, store_sk,
-- fiscal_week_index), so keyed on those this can never fire — it would be a no-op
-- error check. It is a metric placeholder until the fix-the-views PR re-grains the
-- window to durable product_id/store_id, at which point it becomes a real
-- error-severity grain guard keyed on the durable ids (like its five siblings).
SELECT COUNT(*) AS weekly_baseline_dupe_grain_rows FROM (
  SELECT product_sk, store_sk, fiscal_week_index
  FROM ${catalog}.${promo_schema}.gold_weekly_baseline
  GROUP BY product_sk, store_sk, fiscal_week_index
  HAVING COUNT(*) > 1
);

-- check: gold_trade_promotion_rowcount | severity: metric
-- Reported only: number of promo x product x store x week rows in the gold view.
SELECT COUNT(*) AS gold_rows FROM ${catalog}.${promo_schema}.gold_trade_promotion;

-- check: gold_baseline_units_null_rate | severity: metric
-- Reported only (never a failure): share of gold rows whose baseline_units is
-- NULL because fewer than 4 trailing non-promoted weeks were available.
SELECT ROUND(AVG(CASE WHEN baseline_units IS NULL THEN 1.0 ELSE 0.0 END), 4) AS baseline_null_rate
FROM ${catalog}.${promo_schema}.gold_trade_promotion;

-- ---------- gold_promo_roi (Post-Promotion ROI) ----------

-- check: roi_null_only_when_no_trade_spend | severity: error
-- ROI may be NULL only when trade_spend is 0/NULL (divide-by-zero guard) or
-- when incremental margin is itself undefined (no baseline). It must NOT be
-- NULL when both trade_spend and incremental_margin are present.
SELECT * FROM ${catalog}.${promo_schema}.gold_promo_roi
WHERE roi IS NULL
  AND trade_spend IS NOT NULL AND trade_spend <> 0
  AND incremental_margin IS NOT NULL;

-- check: gold_promo_roi_rowcount | severity: metric
SELECT COUNT(*) AS promo_rows FROM ${catalog}.${promo_schema}.gold_promo_roi;

-- check: gold_promo_roi_baseline_coverage | severity: metric
-- Reported only: share of promos with no usable baseline (NULL/zero), so
-- incremental/ROI are undefined for them. Surfaced, not a failure.
SELECT ROUND(AVG(CASE WHEN baseline_units IS NULL OR baseline_units = 0 THEN 1.0 ELSE 0.0 END), 4)
         AS baseline_missing_rate
FROM ${catalog}.${promo_schema}.gold_promo_roi;

-- check: gold_promo_roi_negative_net_count | severity: metric
-- Reported only: number of promos that lost money on a net-incremental basis
-- (cannibalization + forward-buy outweigh incremental margin). Not clamped.
SELECT COUNT(*) AS promos_with_negative_net
FROM ${catalog}.${promo_schema}.gold_promo_roi
WHERE net_incremental_margin < 0;

-- ============================================================
-- Location-Based Offers (offer_zone / location_offer / offer_event + gold)
-- ============================================================

-- ---------- PK not-null + uniqueness per silver table (1-3) ----------

-- check: offer_zone_keys_not_null | severity: error
SELECT * FROM ${catalog}.${promo_schema}.offer_zone
WHERE zone_sk IS NULL OR zone_id IS NULL;

-- check: offer_zone_pk_unique | severity: error
SELECT zone_sk, COUNT(*) AS rows
FROM ${catalog}.${promo_schema}.offer_zone
GROUP BY zone_sk
HAVING COUNT(*) > 1;

-- check: location_offer_keys_not_null | severity: error
SELECT * FROM ${catalog}.${promo_schema}.location_offer
WHERE location_offer_sk IS NULL OR location_offer_id IS NULL;

-- check: location_offer_pk_unique | severity: error
SELECT location_offer_sk, COUNT(*) AS rows
FROM ${catalog}.${promo_schema}.location_offer
GROUP BY location_offer_sk
HAVING COUNT(*) > 1;

-- check: offer_event_keys_not_null | severity: error
SELECT * FROM ${catalog}.${promo_schema}.offer_event
WHERE offer_event_sk IS NULL OR offer_event_id IS NULL
   OR location_offer_sk IS NULL
   OR customer_id IS NULL OR store_id IS NULL;

-- check: offer_event_pk_unique | severity: error
SELECT offer_event_sk, COUNT(*) AS rows
FROM ${catalog}.${promo_schema}.offer_event
GROUP BY offer_event_sk
HAVING COUNT(*) > 1;

-- ---------- semantic invariants (9-13, 16) ----------

-- check: location_offer_dwell_requires_min_dwell | severity: error
-- min_dwell_seconds is required exactly for trigger_type='dwell'.
SELECT * FROM ${catalog}.${promo_schema}.location_offer
WHERE trigger_type = 'dwell' AND min_dwell_seconds IS NULL;

-- check: offer_event_suppression_reason_iff_suppressed | severity: error
-- suppression_reason is set IFF event_type='suppressed' (both directions).
SELECT * FROM ${catalog}.${promo_schema}.offer_event
WHERE (event_type = 'suppressed' AND suppression_reason IS NULL)
   OR (event_type <> 'suppressed' AND suppression_reason IS NOT NULL);

-- check: offer_event_delivery_requires_consent | severity: error
-- The consent invariant: every delivered/opened/redeemed event is consent-verified.
SELECT * FROM ${catalog}.${promo_schema}.offer_event
WHERE event_type IN ('delivered', 'opened', 'redeemed')
  AND consent_verified IS NOT TRUE;

-- check: offer_event_redeemed_requires_transaction | severity: error
SELECT * FROM ${catalog}.${promo_schema}.offer_event
WHERE event_type = 'redeemed' AND transaction_id IS NULL;

-- check: offer_event_within_offer_window | severity: error
-- event_ts must fall inside the joined offer's [offer_start_ts, offer_end_ts].
SELECT e.offer_event_sk
FROM ${catalog}.${promo_schema}.offer_event e
JOIN ${catalog}.${promo_schema}.location_offer lo
  ON e.location_offer_sk = lo.location_offer_sk
WHERE e.event_ts < lo.offer_start_ts OR e.event_ts > lo.offer_end_ts;

-- check: offer_event_location_offer_fk_orphan | severity: error
-- Explicit referential-integrity check on the declared FK (offer_event -> location_offer).
SELECT e.offer_event_sk
FROM ${catalog}.${promo_schema}.offer_event e
LEFT JOIN ${catalog}.${promo_schema}.location_offer lo
  ON e.location_offer_sk = lo.location_offer_sk
WHERE lo.location_offer_sk IS NULL;

-- ---------- gold rate bounds 0..1 (14-15) ----------

-- check: gold_location_offer_performance_rate_bounds | severity: error
SELECT * FROM ${catalog}.${promo_schema}.gold_location_offer_performance
WHERE delivery_rate    < 0 OR delivery_rate    > 1
   OR open_rate        < 0 OR open_rate        > 1
   OR redemption_rate  < 0 OR redemption_rate  > 1
   OR suppression_rate < 0 OR suppression_rate > 1;

-- check: gold_zone_engagement_weekly_rate_bounds | severity: error
SELECT * FROM ${catalog}.${promo_schema}.gold_zone_engagement_weekly
WHERE conversion_rate < 0 OR conversion_rate > 1;
