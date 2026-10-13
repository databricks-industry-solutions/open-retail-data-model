-- ============================================================
-- ORDM · Outcome Package · Promote with Purpose
-- View: gold_promo_roi_by_category   (MATERIALIZED VIEW; drill grain of gold_promo_roi)
-- Layer: outcome package (gold / consumable)
-- Materialization: Lakeflow Declarative Pipeline materialized view (reads the
--   materialized gold_weekly_baseline). gold_promo_roi and gold_category_growth
--   read this MATERIALIZED table, so the decomposition runs once per refresh.
-- Version: 0.5
-- Generated: 2026-06-09
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-09
-- ============================================================
-- Post-Promotion ROI at promo x category grain. gold_promo_roi rolls this
-- up to one row per promo. Definitions:
--   baseline_*        : from the trailing-8 non-promoted-week mean
--                       (gold_weekly_baseline), summed over the promo window
--                       (i.e. scaled to the promo's duration).
--   incremental_units = promoted_units - baseline_units (NOT clamped; a
--                       negative value is a real "promo lost volume" signal).
--   incremental_margin= promoted_margin - baseline_margin, where
--                       margin = revenue - units * product.unit_cost.
--   trade_spend       : planned_trade_spend allocated to the category by its
--                       share of the promo's scope rows (realized actuals are
--                       not modelled — see summary).
--   roi               = incremental_margin / NULLIF(trade_spend, 0).
--   cannibalization   : shortfall below baseline on SUBSTITUTE SKUs (same
--                       category, NOT on this promo) in the promo's stores
--                       during the window.
--   forward_buy       : shortfall below baseline on the PROMOTED SKUs in the
--                       N fiscal weeks after the promo (pantry loading);
--                       N = forward_buy_weeks (default 2, see params CTE; keep
--                       in sync with seeds.yaml post_promo.forward_buy_weeks).
--   net_incremental_margin = incremental_margin - cannibalization_margin
--                            - forward_buy_margin.
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${promo_schema}.gold_promo_roi_by_category AS
WITH params AS (
  SELECT 2 AS forward_buy_weeks
),
fiscal_weeks AS (
  SELECT DISTINCT fiscal_week_id, fiscal_week_index
  FROM ${catalog}.${calendar_schema}.fiscal_calendar
),
prod AS (
  SELECT product_sk, category, list_price, unit_cost
  FROM ${catalog}.${product_schema}.product
  WHERE is_current = true
),
promo AS (
  SELECT
    p.promo_sk, p.promo_id, p.promo_name, p.promo_type, p.funding_type,
    p.funded_by, p.start_date, p.end_date, p.planned_trade_spend, p.planned_lift_pct,
    sw.fiscal_week_index AS start_idx,
    ew.fiscal_week_index AS end_idx
  FROM ${catalog}.${marketing_schema}.promotion p
  JOIN fiscal_weeks sw ON sw.fiscal_week_id = p.fiscal_week_start
  JOIN fiscal_weeks ew ON ew.fiscal_week_id = p.fiscal_week_end
  WHERE p.is_current = true
    AND p.promo_id <> 'NO_PROMO'
),
scope_prod AS (
  SELECT
    sc.promo_sk, sc.product_sk, sc.store_sk,
    pr.category, pr.list_price, pr.unit_cost
  FROM ${catalog}.${promo_schema}.promotion_scope sc
  JOIN prod pr ON pr.product_sk = sc.product_sk
),
wb AS (
  SELECT product_sk, store_sk, fiscal_week_index, actual_units, actual_revenue, baseline_units
  FROM ${catalog}.${promo_schema}.gold_weekly_baseline
),
promo_cats AS (
  SELECT DISTINCT promo_sk, category FROM scope_prod
),
promo_store AS (
  SELECT DISTINCT promo_sk, store_sk FROM scope_prod
),
scope_size AS (
  SELECT promo_sk, COUNT(*) AS n_total FROM scope_prod GROUP BY promo_sk
),
scope_size_cat AS (
  SELECT promo_sk, category, COUNT(*) AS n_cat FROM scope_prod GROUP BY promo_sk, category
),
-- substitute SKUs: same category, NOT in this promo's scope, in its stores
substitutes AS (
  SELECT
    pc.promo_sk, pc.category, pr.product_sk AS sub_product_sk,
    ps.store_sk, pr.list_price, pr.unit_cost
  FROM promo_cats pc
  JOIN prod pr ON pr.category = pc.category
  JOIN promo_store ps ON ps.promo_sk = pc.promo_sk
  WHERE NOT EXISTS (
    SELECT 1 FROM scope_prod sp
    WHERE sp.promo_sk = pc.promo_sk AND sp.product_sk = pr.product_sk
  )
),
promoted_cat AS (
  SELECT
    sp.promo_sk,
    sp.category,
    SUM(wb.actual_units)                                    AS promoted_units,
    SUM(wb.actual_revenue)                                  AS promoted_revenue,
    SUM(wb.actual_units * sp.unit_cost)                     AS promoted_cogs,
    SUM(wb.baseline_units)                                  AS baseline_units,
    SUM(wb.baseline_units * sp.list_price)                  AS baseline_revenue,
    SUM(wb.baseline_units * (sp.list_price - sp.unit_cost)) AS baseline_margin
  FROM promo p
  JOIN scope_prod sp ON sp.promo_sk = p.promo_sk
  JOIN wb ON wb.product_sk = sp.product_sk AND wb.store_sk = sp.store_sk
         AND wb.fiscal_week_index BETWEEN p.start_idx AND p.end_idx
  GROUP BY sp.promo_sk, sp.category
),
cannib_cat AS (
  SELECT
    sub.promo_sk,
    sub.category,
    SUM(GREATEST(wb.baseline_units - wb.actual_units, 0)) AS cannibalized_units,
    SUM(GREATEST(wb.baseline_units - wb.actual_units, 0) * (sub.list_price - sub.unit_cost)) AS cannibalization_margin
  FROM promo p
  JOIN substitutes sub ON sub.promo_sk = p.promo_sk
  JOIN wb ON wb.product_sk = sub.sub_product_sk AND wb.store_sk = sub.store_sk
         AND wb.fiscal_week_index BETWEEN p.start_idx AND p.end_idx
  WHERE wb.baseline_units IS NOT NULL
  GROUP BY sub.promo_sk, sub.category
),
fb_cat AS (
  SELECT
    sp.promo_sk,
    sp.category,
    SUM(GREATEST(wb.baseline_units - wb.actual_units, 0)) AS forward_buy_units,
    SUM(GREATEST(wb.baseline_units - wb.actual_units, 0) * (sp.list_price - sp.unit_cost)) AS forward_buy_margin
  FROM promo p
  CROSS JOIN params
  JOIN scope_prod sp ON sp.promo_sk = p.promo_sk
  JOIN wb ON wb.product_sk = sp.product_sk AND wb.store_sk = sp.store_sk
         AND wb.fiscal_week_index BETWEEN p.end_idx + 1 AND p.end_idx + params.forward_buy_weeks
  WHERE wb.baseline_units IS NOT NULL
  GROUP BY sp.promo_sk, sp.category
)
SELECT
  p.promo_id,
  p.promo_name,
  p.promo_type,
  p.funding_type,
  p.funded_by,
  p.start_date,
  p.end_date,
  pm.category,
  pm.promoted_units,
  pm.promoted_revenue,
  (pm.promoted_revenue - pm.promoted_cogs)                       AS promoted_margin,
  pm.baseline_units,
  pm.baseline_revenue,
  pm.baseline_margin,
  (pm.promoted_units - pm.baseline_units)                        AS incremental_units,
  (pm.promoted_revenue - pm.baseline_revenue)                    AS incremental_revenue,
  ((pm.promoted_revenue - pm.promoted_cogs) - pm.baseline_margin) AS incremental_margin,
  (p.planned_trade_spend * ssc.n_cat / NULLIF(ss.n_total, 0))    AS trade_spend,
  ((pm.promoted_revenue - pm.promoted_cogs) - pm.baseline_margin)
    / NULLIF(p.planned_trade_spend * ssc.n_cat / NULLIF(ss.n_total, 0), 0) AS roi,
  p.planned_lift_pct,
  (100.0 * (pm.promoted_units - pm.baseline_units) / NULLIF(pm.baseline_units, 0)) AS realized_lift_pct,
  COALESCE(cn.cannibalized_units, 0)     AS cannibalization_units,
  COALESCE(cn.cannibalization_margin, 0) AS cannibalization_margin,
  COALESCE(fb.forward_buy_units, 0)      AS forward_buy_units,
  COALESCE(fb.forward_buy_margin, 0)     AS forward_buy_margin,
  (((pm.promoted_revenue - pm.promoted_cogs) - pm.baseline_margin)
    - COALESCE(cn.cannibalization_margin, 0)
    - COALESCE(fb.forward_buy_margin, 0)) AS net_incremental_margin
FROM promoted_cat pm
JOIN promo p ON p.promo_sk = pm.promo_sk
JOIN scope_size ss ON ss.promo_sk = pm.promo_sk
JOIN scope_size_cat ssc ON ssc.promo_sk = pm.promo_sk AND ssc.category = pm.category
LEFT JOIN cannib_cat cn ON cn.promo_sk = pm.promo_sk AND cn.category = pm.category
LEFT JOIN fb_cat fb ON fb.promo_sk = pm.promo_sk AND fb.category = pm.category;
