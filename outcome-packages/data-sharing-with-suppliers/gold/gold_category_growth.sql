-- ============================================================
-- ORDM · Outcome Package · Data Sharing with Suppliers
-- View: gold_category_growth
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-06-09
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-09
-- ============================================================
-- Category growth, one row per category x fiscal period (NRF 4-5-4). Phase-0
-- decision: INTERPRETATION A (collaborative) -- growth analysed WITH and
-- attributed TO suppliers, integrating the promo-ROI, customer-LTV and
-- supplier scorecards (each a MATERIALIZED VIEW, so this view reads precomputed
-- tables, not the recomputed DAG). Upstream signals are LEFT JOINed, so the view
-- returns rows (and NULLs those columns) if an upstream view yields nothing.
--
-- Revenue base = POS `sales` x product x fiscal calendar (scanned once, reused).
--
-- Period comparison uses the fiscal period_index = fiscal_year*12 + fiscal_period,
-- so PoP = index-1 and YoY = index-12 always compare LIKE fiscal periods (never
-- raw calendar offsets):
--   pop_growth_pct = 100 * (revenue - prior_period_revenue) / prior_period_revenue
--   yoy_growth_pct = 100 * (revenue - prior_year_revenue)  / prior_year_revenue
-- (NULL when the prior period/year is absent; so are delta_revenue and all four
-- effects when there is no prior period.)
--
-- Growth decomposition of delta_revenue = revenue - prior_period_revenue, with
-- D = distribution points (distinct product x store), q = units/point (U/D),
-- P = avg price (R/U); subscripts 0=prior, 1=current. The four effects RECONCILE
-- EXACTLY to delta_revenue:
--   distribution_effect = (D1 - D0) * q0 * P0
--   volume_effect       = D1 * (q1 - q0) * P0
--   price_effect        = U1 * price_component
--   mix_effect          = U1 * mix_component
-- where, over the category's sub-categories sc (weights w = unit share, p = sub-
-- category avg price; new/dropped sub-cats contribute 0 on the missing side):
--   mix_component   = SUM( (w1_sc - w0_sc) * p0_sc )
--   price_component = SUM( w1_sc * (p1_sc - p0_sc) )
-- so (mix_component + price_component) = (P1 - P0) and the four effects sum to
-- U1*P1 - U0*P0 = delta_revenue.
--
-- category_share        = category_revenue / total revenue that period.
-- promo_contribution    = incremental margin (gold_promo_roi_by_category) for the
--                         category in the period (promo mapped to its end period).
-- value_share_*         = revenue split across CLV value tiers (gold_customer_ltv,
--                         customer-attributed orders) -- high- vs low-value growth.
-- supplier_contribution = top supplier's share of category procurement spend, with
--                         its scorecard composite (gold_supplier_scorecard).
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${dss_schema}.gold_category_growth AS
WITH base AS (
  -- single scan of the POS sales fact, joined to product and the calendar
  SELECT
    pr.category,
    pr.subcategory,
    s.product_sk,
    s.store_sk,
    s.units,
    s.net_revenue,
    (s.net_revenue - s.units * pr.unit_cost) AS line_margin,
    (c.fiscal_year * 12 + c.fiscal_period)   AS period_index,
    c.fiscal_year,
    c.fiscal_period
  FROM ${catalog}.${transaction_schema}.sales s
  JOIN ${catalog}.${product_schema}.product pr ON pr.product_sk = s.product_sk
  JOIN ${catalog}.${calendar_schema}.fiscal_calendar c ON s.date_key = c.date_key
),
cat AS (
  SELECT
    category, fiscal_year, fiscal_period, period_index,
    SUM(net_revenue) AS revenue,
    SUM(units)       AS units,
    SUM(line_margin) AS margin,
    -- distribution = number of active product x store selling points. approx_count_distinct
    -- (HyperLogLog) avoids an exact-distinct shuffle on the sales fact at scale.
    approx_count_distinct(CONCAT(CAST(product_sk AS STRING), '-', CAST(store_sk AS STRING))) AS dist_points
  FROM base
  GROUP BY category, fiscal_year, fiscal_period, period_index
),
subcat AS (
  SELECT category, subcategory, period_index,
         SUM(units) AS units, SUM(net_revenue) AS revenue
  FROM base
  GROUP BY category, subcategory, period_index
),
subcat_pop AS (
  -- current vs prior-period sub-category, full-outer so new/dropped sub-cats appear
  SELECT
    COALESCE(s1.category, s0.category)             AS category,
    COALESCE(s1.period_index, s0.period_index + 1) AS period_index,
    COALESCE(s1.units, 0)   AS u1_sc,
    COALESCE(s1.revenue, 0) AS r1_sc,
    COALESCE(s0.units, 0)   AS u0_sc,
    COALESCE(s0.revenue, 0) AS r0_sc
  FROM subcat s1
  FULL OUTER JOIN subcat s0
    ON s0.category = s1.category AND s0.subcategory = s1.subcategory
   AND s0.period_index = s1.period_index - 1
),
mixprice AS (
  SELECT
    sp.category, sp.period_index,
    SUM((sp.u1_sc / NULLIF(cu1.units, 0) - sp.u0_sc / NULLIF(cu0.units, 0))
        * COALESCE(sp.r0_sc / NULLIF(sp.u0_sc, 0), 0)) AS mix_component,
    SUM((sp.u1_sc / NULLIF(cu1.units, 0))
        * (COALESCE(sp.r1_sc / NULLIF(sp.u1_sc, 0), 0) - COALESCE(sp.r0_sc / NULLIF(sp.u0_sc, 0), 0))) AS price_component
  FROM subcat_pop sp
  JOIN cat cu1 ON cu1.category = sp.category AND cu1.period_index = sp.period_index
  LEFT JOIN cat cu0 ON cu0.category = sp.category AND cu0.period_index = sp.period_index - 1
  GROUP BY sp.category, sp.period_index
),
promo_cat AS (
  SELECT g.category, (c.fiscal_year * 12 + c.fiscal_period) AS period_index,
         SUM(g.incremental_margin) AS promo_incremental_margin
  FROM ${catalog}.${promo_schema}.gold_promo_roi_by_category g
  JOIN ${catalog}.${calendar_schema}.fiscal_calendar c ON g.end_date = c.date_key
  GROUP BY g.category, (c.fiscal_year * 12 + c.fiscal_period)
),
value_mix AS (
  SELECT cr.category, cr.period_index,
    SUM(CASE WHEN cr.value_tier = 'PLATINUM' THEN cr.rev ELSE 0 END) / NULLIF(SUM(cr.rev), 0) AS value_share_platinum,
    SUM(CASE WHEN cr.value_tier = 'GOLD'     THEN cr.rev ELSE 0 END) / NULLIF(SUM(cr.rev), 0) AS value_share_gold,
    SUM(CASE WHEN cr.value_tier = 'SILVER'   THEN cr.rev ELSE 0 END) / NULLIF(SUM(cr.rev), 0) AS value_share_silver,
    SUM(CASE WHEN cr.value_tier = 'BRONZE'   THEN cr.rev ELSE 0 END) / NULLIF(SUM(cr.rev), 0) AS value_share_bronze
  FROM (
    SELECT pr.category, (c.fiscal_year * 12 + c.fiscal_period) AS period_index,
           ltv.value_tier, SUM(col.net_amount) AS rev
    FROM ${catalog}.${order_schema}.customer_order_line col
    JOIN ${catalog}.${product_schema}.product pr ON pr.product_sk = col.product_sk
    JOIN ${catalog}.${calendar_schema}.fiscal_calendar c ON col.order_date = c.date_key
    JOIN ${catalog}.${acu_schema}.gold_customer_ltv ltv ON ltv.profile_sk = col.profile_sk
    GROUP BY pr.category, (c.fiscal_year * 12 + c.fiscal_period), ltv.value_tier
  ) cr
  GROUP BY cr.category, cr.period_index
),
supplier_cat_spend AS (
  SELECT pr.category, pol.supplier_id, SUM(pol.received_qty * pol.unit_price) AS spend
  FROM ${catalog}.${procurement_schema}.purchase_order_line pol
  JOIN ${catalog}.${product_schema}.product pr ON pr.product_sk = pol.product_sk
  GROUP BY pr.category, pol.supplier_id
),
top_supplier AS (
  SELECT category, supplier_id,
         spend / NULLIF(SUM(spend) OVER (PARTITION BY category), 0) AS supplier_top_share,
         ROW_NUMBER() OVER (PARTITION BY category ORDER BY spend DESC) AS rn
  FROM supplier_cat_spend
),
supplier_score AS (
  SELECT supplier_id, AVG(composite_score) AS supplier_top_score
  FROM ${catalog}.${risk_schema}.gold_supplier_scorecard
  GROUP BY supplier_id
)
SELECT
  c1.category,
  c1.fiscal_year,
  c1.fiscal_period,
  c1.revenue AS category_revenue,
  c1.units   AS category_units,
  c1.margin  AS category_margin,
  c0.revenue AS prior_period_revenue,
  (c1.revenue - c0.revenue) AS delta_revenue,
  100.0 * (c1.revenue - c0.revenue) / NULLIF(c0.revenue, 0) AS pop_growth_pct,
  y0.revenue AS prior_year_revenue,
  100.0 * (c1.revenue - y0.revenue) / NULLIF(y0.revenue, 0) AS yoy_growth_pct,
  ((c1.dist_points - c0.dist_points) * (c0.units / NULLIF(c0.dist_points, 0)) * (c0.revenue / NULLIF(c0.units, 0))) AS distribution_effect,
  (c1.dist_points * (c1.units / NULLIF(c1.dist_points, 0) - c0.units / NULLIF(c0.dist_points, 0)) * (c0.revenue / NULLIF(c0.units, 0))) AS volume_effect,
  -- No prior period -> no decomposition: without the CASE, price_component falls back
  -- to the full average price (p0 = 0), so price_effect would equal the period's whole
  -- revenue and inflate any roll-up of the effects.
  CASE WHEN c0.category IS NOT NULL THEN c1.units * mp.price_component END AS price_effect,
  CASE WHEN c0.category IS NOT NULL THEN c1.units * mp.mix_component END   AS mix_effect,
  c1.revenue / NULLIF(SUM(c1.revenue) OVER (PARTITION BY c1.period_index), 0) AS category_share,
  pc.promo_incremental_margin AS promo_contribution,
  vm.value_share_platinum,
  vm.value_share_gold,
  vm.value_share_silver,
  vm.value_share_bronze,
  ts.supplier_id        AS top_supplier_id,
  ts.supplier_top_share,
  ss.supplier_top_score
FROM cat c1
LEFT JOIN cat c0 ON c0.category = c1.category AND c0.period_index = c1.period_index - 1
LEFT JOIN cat y0 ON y0.category = c1.category AND y0.period_index = c1.period_index - 12
LEFT JOIN mixprice mp ON mp.category = c1.category AND mp.period_index = c1.period_index
LEFT JOIN promo_cat pc ON pc.category = c1.category AND pc.period_index = c1.period_index
LEFT JOIN value_mix vm ON vm.category = c1.category AND vm.period_index = c1.period_index
LEFT JOIN top_supplier ts ON ts.category = c1.category AND ts.rn = 1
LEFT JOIN supplier_score ss ON ss.supplier_id = ts.supplier_id;
