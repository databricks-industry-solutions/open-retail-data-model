-- ============================================================
-- ORDM · Outcome Package · Actionable Customer Understanding
-- View: gold_customer_product_affinity   (MATERIALIZED VIEW)
-- Layer: outcome package (gold / consumable)
-- Materialization: Lakeflow Declarative Pipeline materialized view, refreshed on the
--   same batch cadence as the other affinity/CLV surfaces.
-- Version: 0.5
-- Generated: 2026-08-30
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-30
-- ============================================================
-- Individualized customer -> product affinity: one row per (customer × product) the
-- customer has purchased, with a transparent, recency-weighted PURCHASE-HISTORY affinity
-- score. Feeds "recommended for you" / personalized re-purchase prompts. Built on the BASE
-- order fact; keyed on the DURABLE, pseudonymous profile_id (no raw PII). This is the
-- explicit, explainable modality (NOT an ML model) — the analogue of predicted_clv's
-- heuristic-not-model stance.
--
-- Definitions (all explainable; TUNABLE constants in the `params` CTE):
--   as_of_date         = MAX(order_date) in the data — the evaluation clock is anchored to
--                        the latest observed order (NOT CURRENT_DATE), so the surface is
--                        reproducible on historical demo data (mirrors gold_customer_ltv).
--   purchase_count     = distinct orders (occasions) the customer bought this product on.
--   recency_weight     = pow(0.5, days_since_last_purchase / HALF_LIFE_DAYS): an
--                        exponential time-decay in (0, 1]. HALF_LIFE_DAYS = 90 → a product
--                        last bought 90 days ago carries half the weight of one bought today.
--   purchase_intensity = LEAST(1.0, purchase_count / TARGET_REPEAT): repeat-purchase depth
--                        normalized to [0, 1]. TARGET_REPEAT = 5 → 5+ purchases = full intensity.
--   affinity_score     = LEAST(1.0, purchase_intensity * recency_weight), in [0, 1]. Combines
--                        "how habitually" (intensity) with "how recently" (decay).
--   affinity_band      = high (>= 0.6) / medium (>= 0.2) / low, for coarse targeting + as a
--                        governed metric-view dimension.
--   primary_driver     = 'PURCHASE_HISTORY' (constant in v1). The source model's BROWSE_BEHAVIOR
--                        and latent/embedding (ML vector) drivers are a documented follow-on
--                        (see README design notes / glossary); when added they populate other
--                        primary_driver values without changing this view's grain.
--
-- CURRENCY: total_net_amount is a monetary fact in the deploy's SINGLE base/reporting
-- currency. The canonical core is single-currency by construction (customer_order_line.
-- currency_code equals the deploy base_currency), so currency_code is invariant across rows;
-- it is carried as an output column for lineage, and the invariant is enforced by
-- customer_product_affinity_single_currency (checks.sql) — same posture as gold_customer_ltv.
--
-- SCD2 (§A.16): aggregated purely on the DURABLE profile_id + product_id carried by
-- customer_order_line — no version-specific `_sk` in any GROUP BY / DISTINCT. `product` is
-- read (current version) for display labels only, joined on the durable product_id (never an
-- `_sk = _sk` equi-join), so there is no fragmentation, fan-out, or reverse-drop.
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${acu_schema}.gold_customer_product_affinity AS
WITH params AS (
  SELECT 5 AS target_repeat, 90 AS half_life_days
),
lines AS (
  SELECT profile_id, product_id, order_id, order_date, event_timestamp, units, net_amount, currency_code
  FROM ${catalog}.${order_schema}.customer_order_line
  WHERE profile_id IS NOT NULL AND product_id IS NOT NULL
),
obs AS (
  SELECT MAX(order_date) AS as_of_date FROM lines
),
agg AS (
  SELECT
    l.profile_id,
    l.product_id,
    COUNT(DISTINCT l.order_id) AS purchase_count,
    SUM(l.units)               AS total_units,
    SUM(l.net_amount)          AS total_net_amount,
    MAX(l.currency_code)       AS currency_code,
    MIN(l.order_date)          AS first_purchase_date,
    MAX(l.order_date)          AS last_purchase_date,
    -- true event instant of the most recent purchase (carries time-of-day, not midnight).
    MAX(l.event_timestamp)     AS last_event_ts
  FROM lines l
  GROUP BY l.profile_id, l.product_id
),
prod AS (
  -- current product labels only; joined on the durable product_id below.
  SELECT product_id, product_name, category, subcategory, brand
  FROM ${catalog}.${product_schema}.product
  WHERE is_current = TRUE
),
scored AS (
  SELECT
    a.*,
    datediff(o.as_of_date, a.last_purchase_date)                    AS days_since_last_purchase,
    LEAST(1.0, a.purchase_count / p.target_repeat)                  AS purchase_intensity,
    pow(0.5, datediff(o.as_of_date, a.last_purchase_date) / p.half_life_days) AS recency_weight
  FROM agg a
  CROSS JOIN obs o
  CROSS JOIN params p
),
banded AS (
  -- Round the affinity score ONCE here, then bucket affinity_band on that same rounded value,
  -- so the displayed score and band never disagree at a bucket boundary (e.g. a raw 0.59996
  -- rounds to 0.6000 and must read 'high', not 'medium').
  SELECT
    s.*,
    CAST(LEAST(1.0, s.purchase_intensity * s.recency_weight) AS DECIMAL(5,4)) AS affinity_score
  FROM scored s
)
SELECT
  concat_ws('|', s.profile_id, s.product_id) AS customer_product_affinity_id,  -- convenience label; enforced grain is (profile_id, product_id). Assumes durable ids are pipe-free.
  s.profile_id,
  s.product_id,
  pr.product_name,
  pr.category,
  pr.subcategory,
  pr.brand,
  CAST(s.purchase_count   AS BIGINT)        AS purchase_count,
  CAST(s.total_units      AS BIGINT)        AS total_units,
  CAST(s.total_net_amount AS DECIMAL(18,2)) AS total_net_amount,
  s.currency_code,
  s.first_purchase_date,
  s.last_purchase_date,
  s.last_event_ts                           AS last_purchased_at,
  s.days_since_last_purchase,
  CAST(s.recency_weight AS DECIMAL(5,4))    AS recency_weight,
  s.affinity_score,
  CASE WHEN s.affinity_score >= 0.6 THEN 'high'
       WHEN s.affinity_score >= 0.2 THEN 'medium'
       ELSE 'low' END                       AS affinity_band,
  'PURCHASE_HISTORY'                        AS primary_driver
FROM banded s
LEFT JOIN prod pr ON pr.product_id = s.product_id;
