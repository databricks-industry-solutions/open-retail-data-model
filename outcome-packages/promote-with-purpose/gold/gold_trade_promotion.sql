-- ============================================================
-- ORDM · Outcome Package · Promote with Purpose
-- View: gold_trade_promotion
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-06-09
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-09
-- ============================================================
-- One row per promotion x product x store x fiscal week. Joins the
-- trade-promotion dimension to its product/store scope and to weekly POS
-- sales, with planned trade spend allocated evenly across the promo's
-- scope and weeks, and a baseline of trailing non-promoted demand.
--
-- Baseline: mean weekly non-promoted units over the trailing 8 fiscal weeks
-- (current week excluded) for the same product x store; NULL when fewer than
-- 4 non-promoted weeks are available (DQ reports the NULL rate as a metric).
-- All retail-week logic flows through the NRF 4-5-4 fiscal calendar.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${promo_schema}.gold_trade_promotion AS
WITH weekly_sales AS (
  -- Weekly POS sales per product x store x fiscal week, attributed to a promo.
  SELECT
    s.product_sk,
    s.store_sk,
    s.promo_sk,
    s.promo_id,
    c.fiscal_week_id,
    c.fiscal_week_index,
    SUM(s.units)       AS units,
    SUM(s.net_revenue) AS net_revenue
  FROM ${catalog}.${transaction_schema}.sales s
  JOIN ${catalog}.${calendar_schema}.fiscal_calendar c
    ON s.date_key = c.date_key
  GROUP BY s.product_sk, s.store_sk, s.promo_sk, s.promo_id,
           c.fiscal_week_id, c.fiscal_week_index
),
weekly_baseline_input AS (
  -- One row per product x store x week: non-promoted units that week.
  SELECT
    product_sk,
    store_sk,
    fiscal_week_index,
    SUM(CASE WHEN promo_id = 'NO_PROMO' THEN units END) AS nonpromo_units
  FROM weekly_sales
  GROUP BY product_sk, store_sk, fiscal_week_index
),
baseline AS (
  -- Trailing 8 non-promoted weeks (current week excluded); NULL if < 4 available.
  SELECT
    product_sk,
    store_sk,
    fiscal_week_index,
    CASE
      WHEN COUNT(nonpromo_units) OVER baseline_window >= 4
      THEN AVG(nonpromo_units) OVER baseline_window
    END AS baseline_units
  FROM weekly_baseline_input
  WINDOW baseline_window AS (
    PARTITION BY product_sk, store_sk
    ORDER BY fiscal_week_index
    RANGE BETWEEN 8 PRECEDING AND 1 PRECEDING
  )
),
fiscal_weeks AS (
  -- Week-level slice of the calendar.
  SELECT DISTINCT fiscal_week_id, fiscal_week_index
  FROM ${catalog}.${calendar_schema}.fiscal_calendar
),
promo_scope_size AS (
  SELECT promo_sk, COUNT(*) AS n_scope
  FROM ${catalog}.${promo_schema}.promotion_scope
  GROUP BY promo_sk
),
promo_week_count AS (
  SELECT p.promo_sk, COUNT(*) AS n_weeks
  FROM ${catalog}.${marketing_schema}.promotion p
  JOIN fiscal_weeks fw
    ON fw.fiscal_week_id BETWEEN p.fiscal_week_start AND p.fiscal_week_end
  WHERE p.is_current = true
  GROUP BY p.promo_sk
)
SELECT
  p.promo_id,
  p.promo_name,
  p.promo_type,
  p.funding_type,
  p.funded_by,
  pr.product_id,
  pr.product_name,
  pr.category,
  pr.subcategory,
  pr.brand,
  st.store_id,
  st.store_name,
  st.store_format,
  st.region,
  fw.fiscal_week_id,
  COALESCE(ws.units, 0)       AS promoted_units,
  COALESCE(ws.net_revenue, 0) AS promoted_revenue,
  p.planned_trade_spend / NULLIF(pss.n_scope * pwc.n_weeks, 0) AS planned_trade_spend,
  p.planned_lift_pct,
  b.baseline_units
FROM ${catalog}.${marketing_schema}.promotion p
JOIN ${catalog}.${promo_schema}.promotion_scope sc
  ON sc.promo_sk = p.promo_sk
JOIN ${catalog}.${product_schema}.product pr
  ON pr.product_sk = sc.product_sk
JOIN ${catalog}.${store_schema}.store st
  ON st.store_sk = sc.store_sk
JOIN fiscal_weeks fw
  ON fw.fiscal_week_id BETWEEN p.fiscal_week_start AND p.fiscal_week_end
JOIN promo_scope_size pss
  ON pss.promo_sk = p.promo_sk
JOIN promo_week_count pwc
  ON pwc.promo_sk = p.promo_sk
LEFT JOIN weekly_sales ws
  ON ws.promo_sk = p.promo_sk
 AND ws.product_sk = sc.product_sk
 AND ws.store_sk = sc.store_sk
 AND ws.fiscal_week_index = fw.fiscal_week_index
LEFT JOIN baseline b
  ON b.product_sk = sc.product_sk
 AND b.store_sk = sc.store_sk
 AND b.fiscal_week_index = fw.fiscal_week_index
WHERE p.is_current = true
  AND p.promo_id <> 'NO_PROMO';
