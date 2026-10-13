-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- View: gold_assortment_optimization
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-06-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================
-- Assortment optimization: features, a rule-based recommendation, and heuristic model outputs.
--
-- Definitions (Assortment Optimization):
-- * allocated_facings: Number of facings on the planogram
-- * allocated_sqft: Square footage on the planogram
-- * substitute_demand_transfer_pct: Share of the SKU's demand assumed to move to its mapped substitutes
--     if it is removed (from gold_affinity_features; heuristic over product_relationship affinities).
--     Feature input, not a governed measure.
-- * rolling_sales_velocity_14d: 14-day rolling average of daily units sold
-- * rolling_revenue_14d: 14-day rolling sum of daily net revenue
-- * rolling_margin_14d: 14-day rolling sum of daily gross-margin dollars (numerator)
-- * units_on_hand_eod: Units on hand at end of day
-- * baseline_units_28d / baseline_nonpromo_days_28d: 28-day non-promo unit sum and day count (numerator/denominator)
-- * baseline_velocity: COMPUTED — 28-day non-promo observed mean units/day (heuristic proxy, not a
--     de-seasonalized model baseline)
-- * margin_contribution_pct: COMPUTED — 14-day realized gross-margin rate (margin$ / rate-bearing
--     revenue; m2: denominator excludes days lacking a gross-margin rate so it isn't biased downward)
-- * recommendation: COMPUTED — rule-based assortment action (KEEP / DROP / EXPAND) over velocity +
--     margin buckets and days-on-hand (deterministic, not ML)
-- * space_elasticity: COMPUTED (heuristic) — % change in units per 1% change in facings, per
--     space-planning category: within-product, cross-store log-log slope of non-promo velocity on
--     facings, shrunk toward a 0.17 prior (Eisend 2014 meta-analytic average) by its standard error,
--     clamped to [0, 1]. Observational, not causal: stores that give fast sellers more facings bias it up.
-- * space_elasticity_se / space_elasticity_n_obs: standard error of the shrunk estimate and the number
--     of product x store x allocation observations behind it (0 = prior only)
-- * projected_volume_lift: COMPUTED (scenario) — change in this SKU's own units per selling day at the baseline
--     rate if the recommendation is applied: EXPAND adds one facing (baseline x ((f+1)/f)^elasticity - 1),
--     DROP removes the SKU (-baseline), KEEP is 0
-- * projected_margin_lift_lc: COMPUTED (scenario) — net gross-margin change per selling day =
--     projected_volume_lift x own unit margin - cannibalization_drag_lc
-- * cannibalization_drag_lc: COMPUTED (scenario) — margin per selling day the action takes from mapped
--     substitutes = projected_volume_lift x store-conditional transfer (over substitutes sold in the
--     store) x substitute unit margin.
--     Positive on EXPAND (substitutes lose), negative on DROP (substitutes recapture), 0 on KEEP.
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${bmv_schema}.gold_assortment_optimization AS
-- daily spine: sales joined to margin-rate and promo-flag at the same product x store x day
-- grain, so every rolling window below is computed BEFORE the latest-snapshot (rn=1) filter.
WITH daily AS (
  SELECT
    s.product_sk,
    s.store_sk,
    s.product_id,
    s.store_id,
    s.date_key,
    s.units_sold,
    s.net_sales_lc,
    -- daily gross-margin dollars = net sales * that day's gross-margin rate. COALESCE(0) on
    -- days with no positive-units price row (gold_price_actuals filters units > 0).
    s.net_sales_lc * COALESCE(pa.gross_margin_pct, 0) AS daily_margin_lc,
    -- m2 fix: revenue base for the MARGIN RATE only — net sales on days that actually have a
    -- gross-margin rate. Revenue on a rate-less day would otherwise sit in the rate denominator with
    -- 0 in the numerator, biasing margin_contribution_pct downward. Kept separate from
    -- rolling_revenue_14d (total revenue), which space/velocity measures still need in full.
    CASE WHEN pa.gross_margin_pct IS NOT NULL THEN s.net_sales_lc END AS margin_base_rev_lc,
    -- units on the same rate-bearing days, so unit margin = margin$ / units shares one day-set
    CASE WHEN pa.gross_margin_pct IS NOT NULL THEN s.units_sold END   AS margin_base_units,
    COALESCE(pf.is_on_promo, FALSE)                    AS is_on_promo
  FROM ${catalog}.${bmv_schema}.gold_sales_actuals s
  LEFT JOIN ${catalog}.${bmv_schema}.gold_price_actuals pa
    ON s.product_sk = pa.product_sk AND s.store_sk = pa.store_sk AND s.date_key = pa.date_key
  LEFT JOIN ${catalog}.${bmv_schema}.gold_promotional_features pf
    ON s.product_sk = pf.product_sk AND s.store_sk = pf.store_sk AND s.date_key = pf.date_key
),
rolling_calc AS (
  SELECT
    product_sk,
    store_sk,
    product_id,
    store_id,
    date_key,
    AVG(units_sold)      OVER w14 AS rolling_sales_velocity_14d,
    SUM(net_sales_lc)    OVER w14 AS rolling_revenue_14d,
    SUM(daily_margin_lc) OVER w14 AS rolling_margin_14d,                                 -- additive numerator
    SUM(margin_base_rev_lc) OVER w14 AS rolling_margin_base_rev_14d,                     -- rate denominator (m2): revenue on rate-bearing days only
    SUM(margin_base_units) OVER w14 AS rolling_margin_base_units_14d,                    -- unit-margin denominator (rate-bearing days)
    SUM(CASE WHEN NOT is_on_promo THEN units_sold ELSE 0 END) OVER w28 AS baseline_units_28d,        -- non-promo units
    SUM(CASE WHEN NOT is_on_promo THEN 1          ELSE 0 END) OVER w28 AS baseline_nonpromo_days_28d, -- non-promo day count
    ROW_NUMBER() OVER (PARTITION BY product_sk, store_sk ORDER BY date_key DESC) AS rn
  FROM daily
  WINDOW
    w14 AS (PARTITION BY product_sk, store_sk ORDER BY date_key ROWS BETWEEN 13 PRECEDING AND CURRENT ROW),
    w28 AS (PARTITION BY product_sk, store_sk ORDER BY date_key ROWS BETWEEN 27 PRECEDING AND CURRENT ROW)
),
-- ------------------------------------------------------------
-- Space elasticity (heuristic, per space-planning category).
-- One observation per product x store x planogram allocation: mean units on NON-promo selling
-- days (promo lift would swamp the space signal) against the facings in force on those days.
-- Keyed on the durable product_id / store_id so a product's SCD2 versions pool together.
-- ------------------------------------------------------------
space_obs AS (
  SELECT
    pl.space_planning_category AS category,
    d.product_id,
    d.store_id,
    LN(pl.allocated_facings) AS ln_facings,
    LN(AVG(d.units_sold))    AS ln_velocity
  FROM daily d
  JOIN ${catalog}.${bmv_schema}.planogram pl
    ON d.product_sk = pl.product_sk AND d.store_sk = pl.store_sk AND d.date_key >= pl.effective_from_date AND (pl.effective_to_date IS NULL OR d.date_key < pl.effective_to_date)
  WHERE NOT d.is_on_promo AND d.units_sold > 0 AND pl.allocated_facings > 0
  GROUP BY pl.space_planning_category, d.product_id, d.store_id, pl.effective_from_date, pl.allocated_facings
  -- at least 5 selling days per observation, and a mean of at least 3 units/day: at 1-3 units a
  -- day integer rounding swamps a proportional space response, so very slow SKUs only add noise.
  HAVING COUNT(*) >= 5 AND AVG(d.units_sold) >= 3
),
-- within-product centering: compares the SAME product across stores / allocations, so a product
-- that simply sells more everywhere does not read as a space effect.
space_obs_centered AS (
  SELECT
    category,
    product_id,
    ln_facings  - AVG(ln_facings)  OVER (PARTITION BY category, product_id) AS x,
    ln_velocity - AVG(ln_velocity) OVER (PARTITION BY category, product_id) AS y,
    COUNT(*) OVER (PARTITION BY category, product_id)                     AS obs_in_product
  FROM space_obs
),
space_fit AS (
  SELECT
    category,
    REGR_SLOPE(y, x)           AS slope,
    REGR_SXX(y, x)             AS sxx,
    REGR_SYY(y, x)             AS syy,
    REGR_COUNT(y, x)           AS n_obs,
    COUNT(DISTINCT product_id) AS n_products
  FROM space_obs_centered
  WHERE obs_in_product >= 2                              -- a lone observation carries no within-product variation
  GROUP BY category
),
space_fit_se AS (
  SELECT
    category,
    slope,
    n_obs,
    -- OLS slope standard error; residual dof = n - (one mean per product) - 1 slope
    CASE WHEN sxx > 0 AND n_obs - n_products - 1 > 0
         THEN SQRT(GREATEST(syy - slope * slope * sxx, 0) / ((n_obs - n_products - 1) * sxx)) END AS slope_se
  FROM space_fit
),
-- precision-weighted shrinkage toward the prior (normal prior: mean 0.17, sd 0.10). A tight fit keeps
-- its own slope; a noisy or missing fit falls back toward 0.17. Driven from every planogram category,
-- so a category with no usable fit (all slow movers, or each product allocated in one store only)
-- gets the prior with n_obs = 0 rather than NULL.
space_elasticity_by_category AS (
  SELECT
    c.category,
    CASE WHEN f.slope_se IS NULL THEN 0.17
         ELSE (0.01 * f.slope + f.slope_se * f.slope_se * 0.17) / (0.01 + f.slope_se * f.slope_se) END AS elasticity_raw,
    CASE WHEN f.slope_se IS NULL THEN 0.10
         ELSE SQRT((0.01 * f.slope_se * f.slope_se) / (0.01 + f.slope_se * f.slope_se)) END        AS elasticity_se,
    CASE WHEN f.slope_se IS NULL THEN 0 ELSE f.n_obs END                                           AS n_obs
  FROM (SELECT DISTINCT space_planning_category AS category
        FROM ${catalog}.${bmv_schema}.planogram
        WHERE space_planning_category IS NOT NULL) c
  LEFT JOIN space_fit_se f ON f.category = c.category
),
-- latest snapshot per product x store, with the unit margin both the SKU and its substitutes use
latest AS (
  SELECT
    r.*,
    r.rolling_margin_14d / NULLIF(r.rolling_margin_base_units_14d, 0) AS unit_margin_lc
  FROM rolling_calc r
  WHERE r.rn = 1
),
-- affinity-weighted unit margin of the SKU's mapped substitutes in the same store
substitute_margin AS (
  SELECT
    pr.product_id,
    l.store_id,
    SUM(l.unit_margin_lc * pr.affinity_coefficient)
      / NULLIF(SUM(CASE WHEN l.unit_margin_lc IS NOT NULL THEN pr.affinity_coefficient END), 0) AS substitute_unit_margin_lc
  FROM ${catalog}.${bmv_schema}.product_relationship pr
  JOIN latest l ON l.product_id = pr.related_product_id
  WHERE pr.relationship_type = 'substitute'
  GROUP BY pr.product_id, l.store_id                     -- durable keys (SCD2-safe)
),
-- store-conditional demand transfer: 1 - product of (1 - affinity) over the mapped substitutes that
-- sell in this store, so a store carrying only some substitutes recaptures only their share. One row
-- per substitute (deduplicated across SCD2 versions) before combining.
store_transfer AS (
  SELECT
    product_id,
    store_id,
    1 - EXP(SUM(LN(1 - LEAST(affinity, 0.9999)))) AS transfer_pct
  FROM (
    SELECT pr.product_id, pr.related_product_id, l.store_id,
           MAX(CAST(pr.affinity_coefficient AS DOUBLE)) AS affinity
    FROM ${catalog}.${bmv_schema}.product_relationship pr
    JOIN latest l ON l.product_id = pr.related_product_id
    WHERE pr.relationship_type = 'substitute' AND pr.affinity_coefficient > 0
    GROUP BY pr.product_id, pr.related_product_id, l.store_id
  )
  GROUP BY product_id, store_id
),
base AS (
  SELECT
    r.product_sk,
    r.store_sk,
    r.product_id,
    r.store_id,
    r.date_key,
    pl.allocated_facings,
    pl.allocated_sqft,
    af.substitute_demand_transfer_pct,
    COALESCE(stt.transfer_pct, 0) AS store_transfer_pct,
    r.rolling_sales_velocity_14d,
    r.rolling_revenue_14d,
    ip.units_on_hand_eod,
    r.rolling_margin_14d,
    r.rolling_margin_base_rev_14d,
    r.baseline_units_28d,
    r.baseline_nonpromo_days_28d,
    r.baseline_units_28d / NULLIF(r.baseline_nonpromo_days_28d, 0) AS baseline_velocity_raw,
    r.unit_margin_lc,
    -- no mapped substitute sells in this store -> nothing to transfer to (0); substitutes sell here but
    -- their margin is unknown -> fall back to the SKU's own unit margin
    CASE WHEN sm.product_id IS NULL THEN 0
         ELSE COALESCE(sm.substitute_unit_margin_lc, r.unit_margin_lc) END AS substitute_unit_margin_lc,
    -- clamp to [0, 1] with CASE, not LEAST/GREATEST: those skip NULLs, which would turn a SKU with no
    -- planogram row (no category, so no estimate) into 0 instead of NULL.
    CASE WHEN se.elasticity_raw < 0 THEN 0 WHEN se.elasticity_raw > 1 THEN 1 ELSE se.elasticity_raw END AS space_elasticity,
    se.elasticity_se AS space_elasticity_se,
    se.n_obs AS space_elasticity_n_obs,
    -- recommendation: deterministic rule over the already-reviewed velocity + margin buckets and
    -- days-on-hand. Never NULL (unmatched bucket rows fall through to KEEP).
    CASE
      WHEN bf.demand_velocity_bucket = 'Slow Mover'
           AND bf.margin_health_bucket IN ('Bleeding', 'Low')
        THEN 'DROP'
      WHEN bf.demand_velocity_bucket = 'Fast Mover'
           AND bf.margin_health_bucket IN ('High', 'Healthy')
           AND ip.units_on_hand_eod / NULLIF(r.rolling_sales_velocity_14d, 0) < 14   -- days-on-hand < 14 -> tight stock
        THEN 'EXPAND'
      ELSE 'KEEP'
    END AS recommendation
  FROM latest r
  LEFT JOIN ${catalog}.${bmv_schema}.planogram pl
    ON r.product_sk = pl.product_sk AND r.store_sk = pl.store_sk AND r.date_key >= pl.effective_from_date AND (pl.effective_to_date IS NULL OR r.date_key < pl.effective_to_date)
  LEFT JOIN ${catalog}.${bmv_schema}.gold_affinity_features af
    ON r.product_sk = af.product_sk AND r.store_sk = af.store_sk AND r.date_key = af.date_key
  LEFT JOIN ${catalog}.${inventory_schema}.inventory_position ip
    ON r.product_sk = ip.product_sk AND r.store_sk = ip.store_sk AND r.date_key = ip.date_key
  LEFT JOIN ${catalog}.${bmv_schema}.gold_bucket_features bf
    ON r.product_sk = bf.product_sk AND r.store_sk = bf.store_sk AND r.date_key = bf.date_key
  LEFT JOIN space_elasticity_by_category se
    ON pl.space_planning_category = se.category
  LEFT JOIN substitute_margin sm
    ON r.product_id = sm.product_id AND r.store_id = sm.store_id
  LEFT JOIN store_transfer stt
    ON r.product_id = stt.product_id AND r.store_id = stt.store_id
),
projected AS (
  SELECT
    b.*,
    -- this SKU's own units/day change at the baseline rate if the recommendation is applied
    CASE b.recommendation
      WHEN 'EXPAND' THEN b.baseline_velocity_raw * (POW((b.allocated_facings + 1.0) / NULLIF(b.allocated_facings, 0), b.space_elasticity) - 1)
      WHEN 'DROP'   THEN -b.baseline_velocity_raw
      ELSE 0
    END AS volume_lift_raw
  FROM base b
)
SELECT
  p.product_sk,
  p.store_sk,
  p.product_id,
  p.store_id,
  p.date_key AS snapshot_date,
  
  -- ============================================================
  -- Model Inputs
  -- ============================================================
  p.allocated_facings,
  p.allocated_sqft,
  p.substitute_demand_transfer_pct,
  p.rolling_sales_velocity_14d,
  
  -- ============================================================
  -- Model Outputs — COMPUTED (heuristic / rule-based, from ORDM data)
  -- ============================================================
  p.rolling_revenue_14d,
  p.units_on_hand_eod,
  -- additive numerators/denominators, exposed so metric views do ratio-of-sums (not avg-of-ratios)
  CAST(p.rolling_margin_14d         AS DECIMAL(18,2)) AS rolling_margin_14d,
  -- m2: revenue base for the margin RATE (rate-bearing days only). Distinct from rolling_revenue_14d.
  CAST(p.rolling_margin_base_rev_14d AS DECIMAL(18,2)) AS rolling_margin_base_rev_14d,
  CAST(p.baseline_units_28d         AS DECIMAL(18,3)) AS baseline_units_28d,
  CAST(p.baseline_nonpromo_days_28d AS INT)           AS baseline_nonpromo_days_28d,
  -- baseline_velocity: non-promo observed mean units/day over 28d (a heuristic proxy, NOT a
  -- de-seasonalized model baseline).
  CAST(p.baseline_velocity_raw AS DECIMAL(12,3)) AS baseline_velocity,
  -- margin_contribution_pct: 14d realized gross-margin rate = margin$ / RATE-BEARING revenue over the
  -- SAME window (m2: denominator is rolling_margin_base_rev_14d, not total revenue, so days with no
  -- gross-margin rate don't drag the rate down — numerator and denominator share the same day-set).
  CAST(p.rolling_margin_14d / NULLIF(p.rolling_margin_base_rev_14d, 0) AS DECIMAL(8,4)) AS margin_contribution_pct,
  CAST(p.recommendation AS STRING) AS recommendation,

  -- ============================================================
  -- Model Outputs — HEURISTIC estimators and scenario projections (deterministic SQL over ORDM
  -- data, not a fitted causal model; adopters can replace any of them with their own model output).
  -- NULL where an input is missing: no planogram row (elasticity, EXPAND lift) or no margin rate.
  -- ============================================================
  CAST(p.space_elasticity       AS DECIMAL(8,4)) AS space_elasticity,
  CAST(p.space_elasticity_se    AS DECIMAL(8,4)) AS space_elasticity_se,
  CAST(p.space_elasticity_n_obs AS INT)          AS space_elasticity_n_obs,
  CAST(p.volume_lift_raw AS DECIMAL(12,3)) AS projected_volume_lift,
  CAST(p.volume_lift_raw * p.unit_margin_lc
       - p.volume_lift_raw * p.store_transfer_pct * p.substitute_unit_margin_lc
       AS DECIMAL(18,2)) AS projected_margin_lift_lc,
  -- drag uses the store-conditional transfer (substitutes ranged in this store), not the product-level
  -- substitute_demand_transfer_pct input
  CAST(p.volume_lift_raw * p.store_transfer_pct * p.substitute_unit_margin_lc
       AS DECIMAL(18,2)) AS cannibalization_drag_lc

FROM projected p
CLUSTER BY (product_sk, store_sk, snapshot_date);
