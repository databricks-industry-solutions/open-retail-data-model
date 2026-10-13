-- ============================================================
-- ORDM · Outcome Package · Actionable Customer Understanding
-- View: gold_customer_ltv   (MATERIALIZED VIEW)
-- Layer: outcome package (gold / consumable)
-- Materialization: Lakeflow Declarative Pipeline materialized view, refreshed on
--   the fiscal-period cadence. RFM scores and the value tier use STABLE fixed
--   thresholds (not population NTILE), so a customer's tier is reproducible across
--   refreshes; consumers (e.g. gold_category_growth, promo targeting,
--   gold_customer_behavioral_attributes) read the MATERIALIZED table.
-- Version: 0.5
-- Generated: 2026-06-09 (RFM/value-tier bucketing revised 2026-07-21: NTILE -> stable thresholds)
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- Per-customer lifetime value: historical realized value + a transparent
-- forward estimate, plus RFM segmentation and value tiers. Built on the BASE
-- dimensional model (customer_order_line + product for margin + the NRF 4-5-4
-- fiscal calendar) -- NOT on the in-progress C360/CDP semantic layer (none
-- exists yet). Keyed on the customer SURROGATE; no raw PII (loyalty/household
-- identifiers or names) is exposed -- those stay in the governed dimension.
--
-- Definitions (all explainable; predicted_clv is a heuristic, not an ML model):
--   recency_periods   = fiscal periods between the customer's last order and the
--                       latest period observed (NRF calendar).
--   frequency         = distinct purchase occasions (order_id) in the window.
--   total_spend       = SUM(net_amount); avg_order_value = total_spend / frequency.
--   historical_clv    = total realized gross margin = SUM(net_amount - units*unit_cost).
--   avg_order_margin  = historical_clv / frequency.
--   tenure_periods    = periods from first order to the latest observed period.
--   frequency_per_period = frequency / tenure_periods.
--   expected_active_periods = GREATEST(0, LEAST(tenure_periods, HORIZON_CAP)
--                       - recency_periods)  -- survival heuristic: loyalty (tenure,
--                       capped at HORIZON_CAP=12 periods ~ 1 year) extends the
--                       forward horizon; recency (time since last buy) shrinks it.
--   predicted_clv     = GREATEST(0, avg_order_margin * frequency_per_period
--                       * expected_active_periods).  Never negative.
--   r/f/m_score       = 1..5 scores from STABLE, FIXED THRESHOLDS (not population
--                       NTILE quintiles). 5 = best (most recent / most frequent /
--                       highest spend). Fixed cutoffs make a customer's tier
--                       REPRODUCIBLE across refreshes and unaffected by population
--                       shifts — a customer only changes tier when their OWN behavior
--                       crosses a cutoff, so a frozen campaign audience is stable.
--                       (An NTILE quintile drifts every refresh as the population
--                       moves, which made a pinned segment non-reproducible — the bug
--                       this fix removes.) Cutoffs (see the `scored` CTE):
--                         R: recency_periods 0 / <=1 / <=2 / <=4 / else  -> 5..1
--                         F: frequency >=12 / >=6 / >=3 / >=2 / else      -> 5..1
--                         M: total_spend >=5000 / >=2000 / >=750 / >=200 / else -> 5..1
--                       Cutoffs are documented deploy constants; adopters retune them
--                       per business at the two sites listed above (the R/F/M CASEs in
--                       the `scored` CTE and the value-tier CASE in the final SELECT).
--                       Raw recency/frequency/spend stay exposed as attributes so a
--                       consumer can rebucket if needed.
--                       CURRENCY/SCALE (M1): the monetary M and value_tier cutoffs are
--                       in the deploy's single base/reporting currency (the same
--                       `currency_code` all ORDM monetary columns use — a whole-currency-
--                       unit amount, e.g. 5000 = 5,000 of base currency, NOT cents and NOT
--                       thousands). They are illustrative mid-market retail defaults;
--                       adopters MUST retune them to their own currency and basket sizes.
--   rfm_score         = 100*R + 10*F + M  (classic 111..555 RFM cell).
--   value_tier        = STABLE historical_clv thresholds: PLATINUM >=2500 /
--                       GOLD >=1000 / SILVER >=250 / BRONZE else (fixed cutoffs, same
--                       reproducibility rationale as the R/F/M scores).
--   churn_risk_proxy  = heuristic flag: recency > CHURN_MULT(2.0) x the customer's
--                       own average cadence (tenure_periods / frequency).
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${acu_schema}.gold_customer_ltv AS
WITH params AS (
  SELECT 12 AS horizon_cap, 2.0 AS churn_mult
),
ord AS (
  SELECT
    col.profile_sk,
    col.profile_id,
    col.order_id,
    col.units,
    col.net_amount,
    (col.net_amount - col.units * pr.unit_cost) AS line_margin,
    (c.fiscal_year * 12 + c.fiscal_period) AS period_index
  FROM ${catalog}.${order_schema}.customer_order_line col
  JOIN ${catalog}.${product_schema}.product pr ON pr.product_sk = col.product_sk
  JOIN ${catalog}.${calendar_schema}.fiscal_calendar c ON col.order_date = c.date_key
),
obs AS (
  SELECT MAX(period_index) AS cur_period FROM ord
),
cust AS (
  SELECT
    o.profile_sk,
    o.profile_id,
    COUNT(DISTINCT o.order_id) AS frequency,
    SUM(o.net_amount)          AS total_spend,
    SUM(o.units)               AS total_units,
    SUM(o.line_margin)         AS historical_clv,
    MAX(o.period_index)        AS last_period,
    MIN(o.period_index)        AS first_period
  FROM ord o
  GROUP BY o.profile_sk, o.profile_id
),
metrics AS (
  SELECT
    c.profile_sk, c.profile_id, c.frequency, c.total_spend, c.total_units, c.historical_clv,
    (ob.cur_period - c.last_period)        AS recency_periods,
    (ob.cur_period - c.first_period + 1)   AS tenure_periods,
    c.total_spend  / NULLIF(c.frequency, 0) AS avg_order_value,
    c.historical_clv / NULLIF(c.frequency, 0) AS avg_order_margin,
    c.frequency / NULLIF(ob.cur_period - c.first_period + 1, 0) AS frequency_per_period
  FROM cust c
  CROSS JOIN obs ob
),
scored AS (
  SELECT
    m.*,
    p.horizon_cap, p.churn_mult,
    GREATEST(0, LEAST(m.tenure_periods, p.horizon_cap) - m.recency_periods) AS expected_active_periods,
    -- STABLE fixed-threshold R/F/M scores (not population NTILE) — reproducible across
    -- refreshes; a customer changes tier only when their own behavior crosses a cutoff.
    CASE WHEN m.recency_periods <= 0 THEN 5
         WHEN m.recency_periods <= 1 THEN 4
         WHEN m.recency_periods <= 2 THEN 3
         WHEN m.recency_periods <= 4 THEN 2
         ELSE 1 END AS r_score,
    CASE WHEN m.frequency >= 12 THEN 5
         WHEN m.frequency >= 6  THEN 4
         WHEN m.frequency >= 3  THEN 3
         WHEN m.frequency >= 2  THEN 2
         ELSE 1 END AS f_score,
    CASE WHEN m.total_spend >= 5000 THEN 5
         WHEN m.total_spend >= 2000 THEN 4
         WHEN m.total_spend >= 750  THEN 3
         WHEN m.total_spend >= 200  THEN 2
         ELSE 1 END AS m_score
  FROM metrics m
  CROSS JOIN params p
)
SELECT
  profile_sk,
  profile_id,
  recency_periods,
  frequency,
  total_units,
  total_spend,
  avg_order_value,
  historical_clv,
  expected_active_periods,
  GREATEST(0, avg_order_margin * frequency_per_period * expected_active_periods) AS predicted_clv,
  r_score,
  f_score,
  m_score,
  r_score * 100 + f_score * 10 + m_score AS rfm_score,
  -- STABLE value tier from fixed historical_clv thresholds (not an NTILE quartile) —
  -- reproducible across refreshes; see header.
  CASE WHEN historical_clv >= 2500 THEN 'PLATINUM'
       WHEN historical_clv >= 1000 THEN 'GOLD'
       WHEN historical_clv >= 250  THEN 'SILVER'
       ELSE 'BRONZE'
  END AS value_tier,
  (recency_periods > churn_mult * (tenure_periods / NULLIF(frequency, 0))) AS churn_risk_proxy
FROM scored;
