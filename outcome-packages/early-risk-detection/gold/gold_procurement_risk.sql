-- ============================================================
-- ORDM · Outcome Package · Early Risk Detection
-- View: gold_procurement_risk
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-06-09
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-09
-- ============================================================
-- A procurement risk register: one row per supplier (current fiscal period),
-- with the contributing factors as columns so the register explains itself.
-- Built on gold_supplier_scorecard (a MATERIALIZED VIEW) plus sourcing/spend
-- from the PO-line fact.
--
-- Factors (each 0-100, higher = riskier; missing inputs default to 0):
--   performance_risk    = 100 - current composite_score (inverse of the scorecard).
--   trend_risk          = decline in composite over the trailing K fiscal periods.
--                         trend_delta = composite_current - mean(composite over the
--                         K periods BEFORE current); only declines count:
--                         trend_risk = 100 * min(max(-trend_delta / TREND_CAP, 0), 1).
--                         A falling supplier surfaces even if its current score is OK.
--   concentration_risk  = 100 * concentration_hhi, where concentration_hhi is the
--                         supplier's spend-weighted average category HHI (Herfindahl
--                         index of supplier spend share within each category it serves).
--                         HHI convention: FRACTIONAL [0,1] (1 = single supplier).
--   single_source_flag  = TRUE if the supplier is the SOLE source for >= 1 SKU;
--                         single_sourced_sku_count exposes how many.
--   geo_risk            = 100 * the largest share that the supplier's OWN country holds
--                         of any category it serves; geo_concentration_flag if that
--                         share exceeds GEO_THRESHOLD.
--
-- risk_score = weighted blend of the five factors (weights in the `w` CTE, sum to 100).
-- risk_tier  = thresholds on risk_score, with two escalators: single_source_flag OR a
--              steep trend (trend_risk >= TREND_ESCALATE) force at least HIGH, so those
--              two exposures surface regardless of the blended score.
-- top_risk_factors = the up-to-3 factors with the largest weighted contribution.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${risk_schema}.gold_procurement_risk AS
WITH w AS (
  SELECT
    25 AS w_perf, 30 AS w_trend, 20 AS w_conc, 15 AS w_single, 10 AS w_geo,
    4 AS trend_periods, 30.0 AS trend_cap, 0.60 AS geo_threshold,
    70.0 AS trend_escalate, 25 AS t_med, 50 AS t_high, 75 AS t_crit
),
supplier_cur AS (
  SELECT supplier_sk, supplier_id, supplier_name, country_code
  FROM ${catalog}.${supplier_schema}.supplier
  WHERE is_current = true
),
sc AS (
  SELECT supplier_sk, supplier_id, composite_score,
         (fiscal_year * 12 + fiscal_period) AS period_index
  FROM ${catalog}.${risk_schema}.gold_supplier_scorecard
),
cur AS (
  SELECT supplier_sk, MAX(period_index) AS cur_idx FROM sc GROUP BY supplier_sk
),
current_score AS (
  SELECT s.supplier_sk, s.supplier_id, s.composite_score AS composite_current, s.period_index AS cur_idx
  FROM sc s
  JOIN cur c ON c.supplier_sk = s.supplier_sk AND s.period_index = c.cur_idx
),
trend AS (
  SELECT cs.supplier_sk, AVG(p.composite_score) AS trailing_mean
  FROM current_score cs
  CROSS JOIN w
  JOIN sc p ON p.supplier_sk = cs.supplier_sk
           AND p.period_index BETWEEN cs.cur_idx - w.trend_periods AND cs.cur_idx - 1
  GROUP BY cs.supplier_sk
),
po AS (
  SELECT pol.supplier_id, pol.product_id, pr.category,
         (pol.received_qty * pol.unit_price) AS line_spend
  FROM ${catalog}.${procurement_schema}.purchase_order_line pol
  JOIN ${catalog}.${product_schema}.product pr ON pr.product_sk = pol.product_sk
),
supplier_cat_spend AS (
  SELECT supplier_id, category, SUM(line_spend) AS sc_spend
  FROM po GROUP BY supplier_id, category
),
cat_spend AS (
  SELECT category, SUM(line_spend) AS cat_total FROM po GROUP BY category
),
cat_hhi AS (
  SELECT scs.category, SUM(POWER(scs.sc_spend / ct.cat_total, 2)) AS hhi
  FROM supplier_cat_spend scs
  JOIN cat_spend ct ON ct.category = scs.category
  GROUP BY scs.category
),
supplier_concentration AS (
  SELECT scs.supplier_id,
         SUM(scs.sc_spend * ch.hhi) / NULLIF(SUM(scs.sc_spend), 0) AS concentration_hhi
  FROM supplier_cat_spend scs
  JOIN cat_hhi ch ON ch.category = scs.category
  GROUP BY scs.supplier_id
),
sku_supplier AS (
  SELECT DISTINCT product_id, supplier_id
  FROM ${catalog}.${procurement_schema}.purchase_order_line
),
sku_counts AS (
  SELECT product_id, COUNT(*) AS n_suppliers FROM sku_supplier GROUP BY product_id
),
sole AS (
  SELECT ss.supplier_id, COUNT(*) AS single_sourced_sku_count
  FROM sku_supplier ss
  JOIN sku_counts sk ON sk.product_id = ss.product_id
  WHERE sk.n_suppliers = 1
  GROUP BY ss.supplier_id
),
cat_country_spend AS (
  SELECT po.category, su.country_code, SUM(po.line_spend) AS cc_spend
  FROM po
  JOIN supplier_cur su ON su.supplier_id = po.supplier_id
  GROUP BY po.category, su.country_code
),
cat_country_share AS (
  SELECT ccs.category, ccs.country_code, ccs.cc_spend / ct.cat_total AS country_share
  FROM cat_country_spend ccs
  JOIN cat_spend ct ON ct.category = ccs.category
),
supplier_geo AS (
  SELECT scs.supplier_id, MAX(ccsh.country_share) AS geo_country_share
  FROM supplier_cat_spend scs
  JOIN supplier_cur su ON su.supplier_id = scs.supplier_id
  JOIN cat_country_share ccsh ON ccsh.category = scs.category AND ccsh.country_code = su.country_code
  GROUP BY scs.supplier_id
),
assembled AS (
  SELECT
    cs.supplier_sk,
    cs.supplier_id,
    sup.supplier_name,
    sup.country_code,
    cs.composite_current,
    w.w_perf, w.w_trend, w.w_conc, w.w_single, w.w_geo,
    w.geo_threshold, w.trend_escalate, w.t_med, w.t_high, w.t_crit,
    GREATEST(0, LEAST(100, 100 - cs.composite_current)) AS performance_risk,
    100 * LEAST(GREATEST(
      -(cs.composite_current - COALESCE(t.trailing_mean, cs.composite_current)) / w.trend_cap, 0), 1) AS trend_risk,
    LEAST(COALESCE(sconc.concentration_hhi, 0) * 100, 100) AS concentration_risk,
    COALESCE(sconc.concentration_hhi, 0) AS concentration_hhi,
    COALESCE(so.single_sourced_sku_count, 0) AS single_sourced_sku_count,
    (COALESCE(so.single_sourced_sku_count, 0) >= 1) AS single_source_flag,
    LEAST(COALESCE(sg.geo_country_share, 0) * 100, 100) AS geo_risk,
    (COALESCE(sg.geo_country_share, 0) > w.geo_threshold) AS geo_concentration_flag
  FROM current_score cs
  CROSS JOIN w
  JOIN supplier_cur sup ON sup.supplier_sk = cs.supplier_sk
  LEFT JOIN trend t ON t.supplier_sk = cs.supplier_sk
  LEFT JOIN supplier_concentration sconc ON sconc.supplier_id = cs.supplier_id
  LEFT JOIN sole so ON so.supplier_id = cs.supplier_id
  LEFT JOIN supplier_geo sg ON sg.supplier_id = cs.supplier_id
),
scored AS (
  SELECT
    a.*,
    (CASE WHEN a.single_source_flag THEN 100 ELSE 0 END) AS single_source_risk,
    a.w_perf   * a.performance_risk                                       AS c_perf,
    a.w_trend  * a.trend_risk                                             AS c_trend,
    a.w_conc   * a.concentration_risk                                     AS c_conc,
    a.w_single * (CASE WHEN a.single_source_flag THEN 100 ELSE 0 END)     AS c_single,
    a.w_geo    * a.geo_risk                                               AS c_geo
  FROM assembled a
),
final AS (
  SELECT
    s.*,
    (s.c_perf + s.c_trend + s.c_conc + s.c_single + s.c_geo)
      / (s.w_perf + s.w_trend + s.w_conc + s.w_single + s.w_geo) AS risk_score
  FROM scored s
)
SELECT
  supplier_sk,
  supplier_id,
  supplier_name,
  country_code,
  composite_current,
  performance_risk,
  trend_risk,
  concentration_risk,
  concentration_hhi,
  single_source_flag,
  single_sourced_sku_count,
  geo_risk,
  geo_concentration_flag,
  risk_score,
  CASE
    WHEN risk_score >= t_crit THEN 'CRITICAL'
    WHEN risk_score >= t_high OR single_source_flag OR trend_risk >= trend_escalate THEN 'HIGH'
    WHEN risk_score >= t_med THEN 'MEDIUM'
    ELSE 'LOW'
  END AS risk_tier,
  concat_ws(', ',
    CASE WHEN (CAST(c_trend > c_perf AS INT) + CAST(c_conc > c_perf AS INT)
             + CAST(c_single > c_perf AS INT) + CAST(c_geo > c_perf AS INT)) < 3
          AND c_perf > 0 THEN 'performance' END,
    CASE WHEN (CAST(c_perf > c_trend AS INT) + CAST(c_conc > c_trend AS INT)
             + CAST(c_single > c_trend AS INT) + CAST(c_geo > c_trend AS INT)) < 3
          AND c_trend > 0 THEN 'trend' END,
    CASE WHEN (CAST(c_perf > c_conc AS INT) + CAST(c_trend > c_conc AS INT)
             + CAST(c_single > c_conc AS INT) + CAST(c_geo > c_conc AS INT)) < 3
          AND c_conc > 0 THEN 'concentration' END,
    CASE WHEN (CAST(c_perf > c_single AS INT) + CAST(c_trend > c_single AS INT)
             + CAST(c_conc > c_single AS INT) + CAST(c_geo > c_single AS INT)) < 3
          AND c_single > 0 THEN 'single_source' END,
    CASE WHEN (CAST(c_perf > c_geo AS INT) + CAST(c_trend > c_geo AS INT)
             + CAST(c_conc > c_geo AS INT) + CAST(c_single > c_geo AS INT)) < 3
          AND c_geo > 0 THEN 'geo' END
  ) AS top_risk_factors
FROM final;
