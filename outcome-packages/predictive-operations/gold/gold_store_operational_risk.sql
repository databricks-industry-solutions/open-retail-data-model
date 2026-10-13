-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · Store Performance use case
-- View: gold_store_operational_risk
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-09-01
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-27 by @sreekanthmunigati
-- ============================================================
-- The Store Operational Risk Score: one row per store (current as_of_date),
-- estimating near-term operational/financial deterioration risk. Composes
-- FIVE sub-scores -- four from other packages (inventory, supply_chain,
-- sales_margin, equipment) plus labor from this package's gold_labor_risk
-- (ADR 0043) -- into a single store-grain triage surface plus a per-domain
-- diagnostic breakdown.
--
-- HONESTY (ADR 0028): operational_risk_score is a transparent, expert-weighted
-- HEURISTIC INDEX (0-100, higher = riskier), NOT a calibrated probability.
-- ORDM trains/serves no models; a probability needs labeled outcome history.
--
-- DEPLOY ORDER: this view READS other packages' gold views, so deploy
-- early-risk-detection and balancing-margin-and-volume BEFORE this package
-- (bounded gold->gold read, legal under LAYER-INTEGRITY; precedent ADR 0024).
--
-- Sub-scores (each 0-100, higher = riskier; missing = NULL, EXCLUDED from the
-- composite denominator — missing means unknown, not safe):
--   inventory_risk     = velocity-weighted mean of gold_inventory_risk
--                        .stockout_risk_score over the store's SKUs (high-velocity
--                        SKUs at risk dominate; MEAN would dilute a localized crisis).
--   supply_chain_risk  = spend-weighted mean of gold_procurement_risk.risk_score
--                        over suppliers that ship to the store (via
--                        purchase_order_line.store_sk, the ship-to location).
--   sales_margin_risk  = 60% sales-trend decline (recent vs prior window net sales)
--                        + 40% discount depth (margin-compression proxy), each
--                        normalized 0-100. baseline_units_sold is a NULL placeholder
--                        in BMV today, so trend is used instead of vs-baseline.
--   equipment_risk     = criticality-weighted mean of (100 - health_score) over the
--                        store's equipment from gold_equipment_health.
--   labor_risk         = from gold_labor_risk (ADR 0043); NULL only if unscored.
--   cx_risk            = DEFERRED, always NULL until a CX source lands.
--
-- HORIZON: horizon_days (7) is the DECLARED forward assessment horizon the whole
-- composite is interpreted against — uniform across every row so scores are
-- comparable. It is a label, NOT a claim that every input is windowed to 7 days:
-- each sub-score reads the window diagnostic for its domain (inventory/supply-
-- chain/equipment are current-state; sales_margin uses a trailing 14-day-vs-prior-
-- 14-day trend, since a 7-day sales trend is too noisy). See the design spec §4.7
-- for the per-domain window table. Strictly horizon-matched or multi-horizon
-- variants would be separate columns (risk_7d, risk_30d), never mixed in one.
--
-- Composite = SUM(weight_i * score_i) / SUM(weight_i over PRESENT domains).
-- Escalators (non-compensatory, copied from gold_procurement_risk's pattern):
--   - worst-domain floor: any present sub-score >= DOMAIN_CRITICAL forces >= HIGH.
--   - steep-trend force:  a steep sales decline (sales_trend_risk >= TREND_ESCALATE)
--                         forces >= HIGH, so the "102%-of-target but sliding" store
--                         surfaces even when the blend looks calm.
-- top_risk_domains = the up-to-3 domains with the largest weighted contribution.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${predops_schema}.gold_store_operational_risk AS
WITH w AS (
  SELECT
    35.0 AS w_inv, 25.0 AS w_sup, 25.0 AS w_sales, 15.0 AS w_equip, 15.0 AS w_labor,
    7    AS horizon_days,
    14   AS sales_window,        -- trailing days for the recent/prior sales windows
    90   AS spend_window,        -- trailing days of PO history for supplier-mix weights
                                 -- (wider than sales_window: procurement cadence is slower,
                                 --  but bounded so stale/one-off buys don't dominate the mix)
    0.30 AS trend_cap,           -- a 30% net-sales decline maps trend risk to 100
    70.0 AS trend_escalate,      -- steep-trend force threshold on sales_trend_risk
    75.0 AS domain_critical,     -- any present sub-score >= this forces >= HIGH
    25.0 AS t_med, 50.0 AS t_high, 75.0 AS t_crit
),
stores AS (
  SELECT store_sk, store_id, store_name, region, district
  FROM ${catalog}.${store_schema}.store
  WHERE is_current = TRUE
),
-- as_of_date is the SCORED-AS-OF date (the declared grain), anchored to the
-- calendar, not to any one input domain — so the snapshot means "as of when we
-- scored," and it never goes NULL if an input package is absent.
as_of AS (
  SELECT CURRENT_DATE() AS as_of_date
),
-- The sales TREND is computed over the sales data's own reach (a trend needs real
-- consecutive periods), so its windows anchor to the latest sales date, COALESCEd
-- to today so the windows never collapse when balancing-margin-and-volume is absent.
sales_anchor AS (
  SELECT COALESCE(MAX(date_key), CURRENT_DATE()) AS anchor_date
  FROM ${catalog}.${bmv_schema}.gold_sales_actuals
),
-- The supply-chain spend window is anchored to the PROCUREMENT clock (latest
-- order_date), NOT the sales clock: procurement recency is independent of sales
-- freshness, and borrowing the sales anchor would silently empty the spend window
-- (and NULL out the 25-weight supply-chain domain for every store) whenever sales
-- data lags PO data by more than spend_window. COALESCEd to today so the window
-- never collapses when procurement data is absent.
spend_anchor AS (
  SELECT COALESCE(MAX(order_date), CURRENT_DATE()) AS anchor_date
  FROM ${catalog}.${procurement_schema}.purchase_order_line
),

-- 1. Inventory: velocity-weighted mean of stockout_risk_score per store.
inv AS (
  SELECT
    store_id,
    CASE
      WHEN SUM(trailing_units_sold) > 0
        THEN SUM(stockout_risk_score * trailing_units_sold) / SUM(trailing_units_sold)
      ELSE AVG(CAST(stockout_risk_score AS DOUBLE))
    END AS inventory_risk
  FROM ${catalog}.${risk_schema}.gold_inventory_risk
  GROUP BY store_id
),

-- 2. Supply-chain: spend-weighted supplier risk over suppliers shipping to the store.
-- Spend is bounded to a trailing spend_window (by order_date) off the PROCUREMENT
-- anchor so the supplier-mix weights reflect the CURRENT sourcing pattern, not stale
-- lifetime purchases — and independent of how fresh the sales feed is.
store_supplier_spend AS (
  SELECT pol.store_id, pol.supplier_id,
         SUM(pol.received_qty * pol.unit_price) AS spend
  FROM ${catalog}.${procurement_schema}.purchase_order_line pol
  CROSS JOIN spend_anchor pa
  CROSS JOIN w
  WHERE pol.order_date BETWEEN DATE_SUB(pa.anchor_date, w.spend_window - 1) AND pa.anchor_date
  GROUP BY pol.store_id, pol.supplier_id
),
sup AS (
  SELECT
    sss.store_id,
    CASE
      WHEN SUM(sss.spend) > 0
        THEN SUM(pr.risk_score * sss.spend) / SUM(sss.spend)
      ELSE AVG(pr.risk_score)
    END AS supply_chain_risk
  FROM store_supplier_spend sss
  JOIN ${catalog}.${risk_schema}.gold_procurement_risk pr
    ON pr.supplier_id = sss.supplier_id
  GROUP BY sss.store_id
),

-- 3. Sales/margin: recent-vs-prior net-sales trend + discount depth, per store.
sales_daily AS (
  SELECT store_id, date_key,
         SUM(net_sales_lc)      AS net_sales_lc,
         SUM(discount_value_lc) AS discount_value_lc
  FROM ${catalog}.${bmv_schema}.gold_sales_actuals
  GROUP BY store_id, date_key
),
sales_windows AS (
  SELECT
    sd.store_id,
    SUM(CASE WHEN sd.date_key BETWEEN DATE_SUB(sa.anchor_date, w.sales_window - 1) AND sa.anchor_date
             THEN sd.net_sales_lc ELSE 0 END) AS recent_net_sales,
    SUM(CASE WHEN sd.date_key BETWEEN DATE_SUB(sa.anchor_date, 2 * w.sales_window - 1)
                                 AND DATE_SUB(sa.anchor_date, w.sales_window)
             THEN sd.net_sales_lc ELSE 0 END) AS prior_net_sales,
    SUM(CASE WHEN sd.date_key BETWEEN DATE_SUB(sa.anchor_date, w.sales_window - 1) AND sa.anchor_date
             THEN sd.net_sales_lc ELSE 0 END)     AS recent_sales_for_disc,
    SUM(CASE WHEN sd.date_key BETWEEN DATE_SUB(sa.anchor_date, w.sales_window - 1) AND sa.anchor_date
             THEN sd.discount_value_lc ELSE 0 END) AS recent_discount
  FROM sales_daily sd
  CROSS JOIN sales_anchor sa
  CROSS JOIN w
  GROUP BY sd.store_id
),
sales_raw AS (
  SELECT
    sw.store_id,
    -- Only DECLINES count: (prior - recent)/prior, capped at trend_cap, scaled to 100.
    CASE
      WHEN sw.prior_net_sales > 0
        THEN 100.0 * LEAST(GREATEST(
               CAST(sw.prior_net_sales - sw.recent_net_sales AS DOUBLE)
                 / sw.prior_net_sales / w.trend_cap, 0), 1)
      ELSE NULL
    END AS sales_trend_risk,
    -- Discount depth: discount / (net sales + discount), as a margin-compression proxy.
    CASE
      WHEN (sw.recent_sales_for_disc + sw.recent_discount) > 0
        THEN CAST(sw.recent_discount AS DOUBLE)
               / (sw.recent_sales_for_disc + sw.recent_discount)
      ELSE NULL
    END AS discount_rate
  FROM sales_windows sw
  CROSS JOIN w
),
-- Normalize discount depth against its realized cross-store p95 (not a nominal clamp).
disc_p95 AS (
  SELECT PERCENTILE(discount_rate, 0.95) AS p95_discount
  FROM sales_raw WHERE discount_rate IS NOT NULL
),
sales AS (
  SELECT
    sr.store_id,
    sr.sales_trend_risk,
    CASE
      WHEN sr.sales_trend_risk IS NULL AND sr.discount_rate IS NULL THEN NULL
      ELSE 0.60 * COALESCE(sr.sales_trend_risk, 0)
         + 0.40 * COALESCE(
             CASE WHEN dp.p95_discount > 0
                  THEN 100.0 * LEAST(sr.discount_rate / dp.p95_discount, 1)
                  ELSE 0 END, 0)
    END AS sales_margin_risk
  FROM sales_raw sr
  CROSS JOIN disc_p95 dp
),

-- 4. Equipment: criticality-weighted mean of (100 - health_score) per store.
equip AS (
  SELECT
    store_id,
    SUM((100 - health_score) * CASE criticality
          WHEN 'critical' THEN 4.0 WHEN 'high' THEN 3.0
          WHEN 'medium' THEN 2.0 ELSE 1.0 END)
      / NULLIF(SUM(CASE criticality
          WHEN 'critical' THEN 4.0 WHEN 'high' THEN 3.0
          WHEN 'medium' THEN 2.0 ELSE 1.0 END), 0) AS equipment_risk
  FROM ${catalog}.${predops_schema}.gold_equipment_health
  GROUP BY store_id
),

-- 5. Labor: store-grain coverage shortfall risk (ADR 0043).
labor AS (
  SELECT store_id, labor_risk
  FROM ${catalog}.${predops_schema}.gold_labor_risk
),

assembled AS (
  SELECT
    s.store_sk, s.store_id, s.store_name, s.region, s.district,
    a.as_of_date, w.horizon_days,
    w.w_inv, w.w_sup, w.w_sales, w.w_equip, w.w_labor,
    w.trend_escalate, w.domain_critical, w.t_med, w.t_high, w.t_crit,
    inv.inventory_risk,
    sup.supply_chain_risk,
    sales.sales_margin_risk,
    sales.sales_trend_risk,
    equip.equipment_risk,
    labor.labor_risk,                     -- from gold_labor_risk (ADR 0043)
    CAST(NULL AS DOUBLE) AS cx_risk       -- DEFERRED (still no CX source)
  FROM stores s
  CROSS JOIN as_of a
  CROSS JOIN w
  LEFT JOIN inv   ON inv.store_id   = s.store_id
  LEFT JOIN sup   ON sup.store_id   = s.store_id
  LEFT JOIN sales ON sales.store_id = s.store_id
  LEFT JOIN equip ON equip.store_id = s.store_id
  LEFT JOIN labor ON labor.store_id = s.store_id
),
scored AS (
  SELECT
    a.*,
    -- Weighted contributions (0 when the domain is absent, so excluded from both
    -- numerator and denominator below).
    CASE WHEN a.inventory_risk    IS NOT NULL THEN a.w_inv   * a.inventory_risk    ELSE 0 END AS c_inv,
    CASE WHEN a.supply_chain_risk IS NOT NULL THEN a.w_sup   * a.supply_chain_risk ELSE 0 END AS c_sup,
    CASE WHEN a.sales_margin_risk IS NOT NULL THEN a.w_sales * a.sales_margin_risk ELSE 0 END AS c_sales,
    CASE WHEN a.equipment_risk    IS NOT NULL THEN a.w_equip * a.equipment_risk    ELSE 0 END AS c_equip,
    CASE WHEN a.labor_risk        IS NOT NULL THEN a.w_labor * a.labor_risk        ELSE 0 END AS c_labor,
    CASE WHEN a.inventory_risk    IS NOT NULL THEN a.w_inv   ELSE 0 END
      + CASE WHEN a.supply_chain_risk IS NOT NULL THEN a.w_sup   ELSE 0 END
      + CASE WHEN a.sales_margin_risk IS NOT NULL THEN a.w_sales ELSE 0 END
      + CASE WHEN a.equipment_risk    IS NOT NULL THEN a.w_equip ELSE 0 END
      + CASE WHEN a.labor_risk        IS NOT NULL THEN a.w_labor ELSE 0 END AS weight_present,
    (CASE WHEN a.inventory_risk    IS NOT NULL THEN 1 ELSE 0 END
      + CASE WHEN a.supply_chain_risk IS NOT NULL THEN 1 ELSE 0 END
      + CASE WHEN a.sales_margin_risk IS NOT NULL THEN 1 ELSE 0 END
      + CASE WHEN a.equipment_risk    IS NOT NULL THEN 1 ELSE 0 END
      + CASE WHEN a.labor_risk        IS NOT NULL THEN 1 ELSE 0 END) AS domains_scored,
    -- worst-domain floor: does any PRESENT domain go critical?
    (COALESCE(a.inventory_risk, 0)    >= a.domain_critical
      OR COALESCE(a.supply_chain_risk, 0) >= a.domain_critical
      OR COALESCE(a.sales_margin_risk, 0) >= a.domain_critical
      OR COALESCE(a.equipment_risk, 0)    >= a.domain_critical
      OR COALESCE(a.labor_risk, 0)        >= a.domain_critical) AS any_domain_critical
  FROM assembled a
),
final AS (
  SELECT
    s.*,
    CASE WHEN s.weight_present > 0
         THEN (s.c_inv + s.c_sup + s.c_sales + s.c_equip + s.c_labor) / s.weight_present
         ELSE NULL END AS operational_risk_score
  FROM scored s
)
SELECT
  store_sk,
  store_id,
  store_name,
  region,
  district,
  as_of_date,
  horizon_days,
  ROUND(operational_risk_score, 1) AS operational_risk_score,
  inventory_risk,
  supply_chain_risk,
  sales_margin_risk,
  equipment_risk,
  labor_risk,
  cx_risk,
  domains_scored,
  CASE
    -- No present domain (domains_scored = 0 -> score is NULL): the store is
    -- UNSCORED, not low-risk. Surfacing it as UNKNOWN keeps the composite honest
    -- to the "missing = unknown, not safe" contract (a LOW here would hide a
    -- store we have no signal for).
    WHEN operational_risk_score IS NULL THEN 'UNKNOWN'
    WHEN operational_risk_score >= t_crit THEN 'CRITICAL'
    WHEN operational_risk_score >= t_high
      OR any_domain_critical
      OR COALESCE(sales_trend_risk, 0) >= trend_escalate THEN 'HIGH'
    WHEN operational_risk_score >= t_med THEN 'MEDIUM'
    ELSE 'LOW'
  END AS operational_risk_tier,
  -- Up-to-3 domains with the largest weighted contribution (the Diagnose step).
  -- Sort the (contribution, domain) pairs descending, keep the positive ones, take
  -- the top 3 by SLICE — a hard cap of 3 even under a tie (the earlier rank-count
  -- form could emit 4 on a bottom tie). Only present domains contribute (c_* is 0
  -- when the sub-score is NULL), so they are filtered out by the c > 0 test.
  concat_ws(', ', slice(transform(
    filter(
      sort_array(array(
        named_struct('c', c_inv,   'd', 'inventory'),
        named_struct('c', c_sup,   'd', 'supply_chain'),
        named_struct('c', c_sales, 'd', 'sales_margin'),
        named_struct('c', c_equip, 'd', 'equipment'),
        named_struct('c', c_labor, 'd', 'labor')
      ), false),
      x -> x.c > 0
    ), x -> x.d), 1, 3)) AS top_risk_domains
FROM final;
