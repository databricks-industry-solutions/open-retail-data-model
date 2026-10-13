-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- Sample Queries
-- Version: 0.5
-- Generated: 2026-06-29
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-29 by @ojasvi-goyal-03
-- ============================================================

-- 1. Latest competitor prices
SELECT 
    cp.date_key,
    p.product_id,
    c.competitor_name,
    cp.competitor_price
FROM ${catalog}.${bmv_schema}.competitor_price cp
JOIN ${catalog}.${bmv_schema}.competitor c 
  ON cp.competitor_sk = c.competitor_sk
JOIN ${catalog}.${product_schema}.product p 
  ON cp.product_sk = p.product_sk
WHERE cp.date_key = (SELECT MAX(date_key) FROM ${catalog}.${bmv_schema}.competitor_price)
ORDER BY cp.competitor_price ASC
LIMIT 100;

-- 2. Top substitute relationships by affinity
SELECT 
    p1.product_id AS primary_product,
    p2.product_id AS substitute_product,
    pr.affinity_coefficient
FROM ${catalog}.${bmv_schema}.product_relationship pr
JOIN ${catalog}.${product_schema}.product p1 
  ON pr.product_sk = p1.product_sk
JOIN ${catalog}.${product_schema}.product p2 
  ON pr.related_product_sk = p2.product_sk
WHERE pr.relationship_type = 'substitute'
ORDER BY pr.affinity_coefficient DESC
LIMIT 50;

-- 3. Weekly stockouts vs price advantage
-- Identifies stockouts affecting pricing effectiveness by fiscal week.
SELECT
    fc.fiscal_week_id,
    p.product_id,
    c.competitor_name,
    COUNT(ip.inventory_position_sk) AS days_stocked_out,
    AVG(cp.competitor_price - pp.amount) AS avg_price_advantage
FROM ${catalog}.${bmv_schema}.competitor_price cp
JOIN ${catalog}.${bmv_schema}.competitor c 
  ON cp.competitor_sk = c.competitor_sk
JOIN ${catalog}.${product_schema}.product p 
  ON cp.product_sk = p.product_sk
JOIN ${catalog}.${product_schema}.product_price pp
  ON p.product_sk = pp.product_sk AND pp.price_type = 'list'
     AND cp.date_key BETWEEN pp.effective_from_date AND COALESCE(pp.effective_to_date, '9999-12-31')
JOIN ${catalog}.${inventory_schema}.inventory_position ip
  ON p.product_sk = ip.product_sk AND cp.date_key = ip.date_key
JOIN ${catalog}.${calendar_schema}.fiscal_calendar fc
  ON cp.date_key = fc.date_key
WHERE ip.is_stockout = true
  AND pp.amount < cp.competitor_price
GROUP BY fc.fiscal_week_id, p.product_id, c.competitor_name
ORDER BY days_stocked_out DESC, avg_price_advantage DESC
LIMIT 50;

-- 4. Space Productivity & Assortment Action
-- Shelf allocation vs computed velocity, margin contribution, and the rule-based recommendation.
-- (The model outputs for each action are in query 7.)
SELECT
    pl.store_id,
    p.product_id,
    p.product_name,
    pl.space_planning_category,
    pl.allocated_facings,
    pl.allocated_sqft,
    o.baseline_velocity,
    o.margin_contribution_pct,
    o.recommendation
FROM ${catalog}.${bmv_schema}.planogram pl
JOIN ${catalog}.${product_schema}.product p
  ON pl.product_sk = p.product_sk
JOIN ${catalog}.${bmv_schema}.gold_assortment_optimization o
  ON pl.product_sk = o.product_sk AND pl.store_sk = o.store_sk
WHERE pl.is_current = true
ORDER BY pl.allocated_facings DESC, o.margin_contribution_pct DESC
LIMIT 100;

-- 5. Space Productivity & Inventory Health
-- Compares product performance against physical shelf space and current stock levels.
SELECT
    p.product_id,
    p.product_name,
    o.rolling_revenue_14d,
    pl.allocated_sqft,
    o.rolling_revenue_14d / NULLIF(pl.allocated_sqft, 0) AS revenue_per_sqft,
    o.units_on_hand_eod,
    o.rolling_sales_velocity_14d,
    o.units_on_hand_eod / NULLIF(o.rolling_sales_velocity_14d, 0) AS days_on_hand
FROM ${catalog}.${bmv_schema}.gold_assortment_optimization o
JOIN ${catalog}.${product_schema}.product p
  ON o.product_sk = p.product_sk
JOIN ${catalog}.${bmv_schema}.planogram pl
  ON o.product_sk = pl.product_sk AND o.store_sk = pl.store_sk
WHERE pl.is_current = true
ORDER BY revenue_per_sqft ASC, days_on_hand DESC
LIMIT 100;

-- 6. Payment-side revenue leakage by store (realized-margin lens)
-- Ranks stores by leakage rate: contra-revenue (refunds + chargebacks + adjustments) as a share of
-- the settled-sale base, from gold_payment_actuals. Rate is a ratio-of-sums (never avg-of-per-row),
-- matching how the metric view will expose refund_rate / chargeback_rate.
SELECT
    s.store_id,
    s.store_name,
    SUM(pa.settled_sale_amount_lc)                          AS settled_sales_lc,
    SUM(pa.refund_amount_lc)                                AS refunds_lc,
    SUM(pa.chargeback_amount_lc)                            AS chargebacks_lc,
    SUM(pa.adjustment_amount_lc)                            AS adjustments_lc,
    (SUM(pa.refund_amount_lc) + SUM(pa.chargeback_amount_lc) + SUM(pa.adjustment_amount_lc))
      / NULLIF(SUM(pa.settled_sale_amount_lc), 0)           AS revenue_leakage_rate
FROM ${catalog}.${bmv_schema}.gold_payment_actuals pa
JOIN ${catalog}.${store_schema}.store s
  ON pa.store_sk = s.store_sk
GROUP BY s.store_id, s.store_name
HAVING SUM(pa.settled_sale_amount_lc) > 0
ORDER BY revenue_leakage_rate DESC
LIMIT 100;

-- 7. What each assortment action is worth (heuristic projections)
-- Per category and action: SKU x store count, the category's space elasticity (with its standard
-- error), and the per-selling-day scenario totals if the recommendations are applied. Margin lift is net of
-- cannibalization drag on mapped substitutes (drag > 0: EXPAND pulls from them; < 0: DROP is recaptured).
SELECT
    p.category,
    o.recommendation,
    COUNT(*)                                    AS sku_store_rows,
    ROUND(AVG(o.space_elasticity), 4)           AS avg_space_elasticity,
    ROUND(MAX(o.space_elasticity_se), 4)        AS max_space_elasticity_se,
    ROUND(SUM(o.projected_volume_lift), 2)      AS projected_units_per_selling_day,
    ROUND(SUM(o.projected_margin_lift_lc), 2)   AS projected_margin_per_selling_day_lc,
    ROUND(SUM(o.cannibalization_drag_lc), 2)    AS cannibalization_drag_per_selling_day_lc
FROM ${catalog}.${bmv_schema}.gold_assortment_optimization o
JOIN ${catalog}.${product_schema}.product p
  ON o.product_sk = p.product_sk
WHERE o.recommendation <> 'KEEP'
GROUP BY p.category, o.recommendation
ORDER BY projected_margin_per_selling_day_lc DESC;

-- 8. Realized vs booked margin by category and channel
-- Compares booked versus realized margin by product category, breaking down contributions from POS and order channels.
-- Shows margin erosion drivers by merchandise category (sale-cohort basis from gold_realized_margin).
SELECT
    p.category,
    SUM(grm.pos_units) AS pos_units,
    SUM(grm.pos_net_sales_lc) AS pos_revenue_lc,
    SUM(grm.order_units) AS order_units,
    SUM(grm.order_booked_sales_lc) AS order_booked_revenue_lc,
    SUM(grm.booked_revenue_lc) AS total_booked_revenue_lc,
    SUM(grm.realized_revenue_lc) AS total_realized_revenue_lc,
    SUM(grm.cogs_lc) AS total_cogs_lc,
    SUM(grm.booked_margin_lc) / NULLIF(SUM(grm.booked_revenue_lc), 0) AS booked_margin_pct,
    SUM(grm.realized_margin_lc) / NULLIF(SUM(grm.realized_revenue_lc), 0) AS realized_margin_pct,
    (SUM(grm.booked_margin_lc) - SUM(grm.realized_margin_lc)) / NULLIF(SUM(grm.booked_revenue_lc), 0) AS margin_erosion_pct
FROM ${catalog}.${bmv_schema}.gold_realized_margin grm
JOIN ${catalog}.${product_schema}.product p
  ON grm.product_sk = p.product_sk
GROUP BY p.category
ORDER BY margin_erosion_pct DESC
LIMIT 50;

-- 9. Leakage mix by store (sale-cohort basis)
-- Breaks revenue leakage (booked - realized) into its four drivers per store from gold_realized_margin:
-- order sales never captured or settled, refunds, chargebacks and adjustments. Grouped by the durable
-- store_id and labelled with the store's current name.
SELECT
    grm.store_id,
    cur.store_name,
    SUM(grm.order_booked_sales_lc) AS order_booked_sales_lc,
    SUM(grm.order_unsettled_sales_lc) AS unsettled_lc,
    SUM(grm.order_refund_lc) AS refunds_lc,
    SUM(grm.order_chargeback_lc) AS chargebacks_lc,
    SUM(grm.order_adjustment_lc) AS adjustments_lc,
    SUM(grm.leakage_lc) AS total_leakage_lc,
    SUM(grm.leakage_lc) / NULLIF(SUM(grm.order_booked_sales_lc), 0) AS order_channel_leakage_rate,
    SUM(grm.order_unsettled_sales_lc) / NULLIF(SUM(grm.leakage_lc), 0) AS unsettled_pct_of_leakage,
    SUM(grm.order_refund_lc) / NULLIF(SUM(grm.leakage_lc), 0) AS refund_pct_of_leakage,
    SUM(grm.order_chargeback_lc) / NULLIF(SUM(grm.leakage_lc), 0) AS chargeback_pct_of_leakage,
    SUM(grm.order_adjustment_lc) / NULLIF(SUM(grm.leakage_lc), 0) AS adjustment_pct_of_leakage
FROM ${catalog}.${bmv_schema}.gold_realized_margin grm
LEFT JOIN ${catalog}.${store_schema}.store cur
  ON grm.store_id = cur.store_id AND cur.is_current = true
GROUP BY grm.store_id, cur.store_name
HAVING SUM(grm.order_booked_sales_lc) > 0
ORDER BY total_leakage_lc DESC
LIMIT 100;

-- 10. Refund and chargeback rate trend by fiscal week (event-date basis)
-- Time-series of refund and chargeback rates by fiscal week from gold_payment_actuals (event-date cash basis).
-- Identifies seasonal patterns and deterioration trends in payment health.
SELECT
    fc.fiscal_week_id,
    MIN(fc.date_key) AS week_start_date,
    MAX(fc.date_key) AS week_end_date,
    SUM(pa.settled_sale_amount_lc) AS settled_sales_lc,
    SUM(pa.refund_amount_lc) AS refunds_lc,
    SUM(pa.refund_amount_lc) / NULLIF(SUM(pa.settled_sale_amount_lc), 0) AS refund_rate,
    SUM(pa.chargeback_amount_lc) AS chargebacks_lc,
    SUM(pa.chargeback_amount_lc) / NULLIF(SUM(pa.settled_sale_amount_lc), 0) AS chargeback_rate
FROM ${catalog}.${bmv_schema}.gold_payment_actuals pa
JOIN ${catalog}.${calendar_schema}.fiscal_calendar fc
  ON DATE(pa.date_key) = fc.date_key
GROUP BY fc.fiscal_week_id
ORDER BY fc.fiscal_week_id DESC
LIMIT 52;

-- 11. Products with highest margin erosion from booked to realized
-- Identifies products experiencing the largest margin compression from booking to realization (sale cohort).
-- Helps prioritize product quality, fulfillment, or return-prevention initiatives. Grouped by the durable
-- product_id and labelled with the current product name and category.
SELECT
    grm.product_id,
    cur.product_name,
    cur.category,
    SUM(grm.booked_revenue_lc) AS total_booked_revenue_lc,
    SUM(grm.realized_revenue_lc) AS total_realized_revenue_lc,
    SUM(grm.cogs_lc) AS total_cogs_lc,
    SUM(grm.booked_margin_lc) / NULLIF(SUM(grm.booked_revenue_lc), 0) AS booked_margin_pct,
    SUM(grm.realized_margin_lc) / NULLIF(SUM(grm.realized_revenue_lc), 0) AS realized_margin_pct,
    (SUM(grm.booked_margin_lc) - SUM(grm.realized_margin_lc)) / NULLIF(SUM(grm.booked_revenue_lc), 0) AS margin_erosion_pct
FROM ${catalog}.${bmv_schema}.gold_realized_margin grm
LEFT JOIN ${catalog}.${product_schema}.product cur
  ON grm.product_id = cur.product_id AND cur.is_current = true
GROUP BY grm.product_id, cur.product_name, cur.category
HAVING SUM(grm.booked_revenue_lc) > 5000
ORDER BY margin_erosion_pct DESC
LIMIT 100;
