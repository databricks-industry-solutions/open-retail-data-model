-- ============================================================
-- ORDM · Outcome Package · Actionable Customer Understanding
-- View: gold_product_affinity_pairwise   (MATERIALIZED VIEW)
-- Layer: outcome package (gold / consumable)
-- Materialization: Lakeflow Declarative Pipeline materialized view. Market-basket
--   association rules are a self-join over the order history, so this is refreshed on a
--   batch cadence (the ORDM-idiomatic form of the source model's "run as an INSERT INTO
--   the affinity table" batch engine), not recomputed per query.
-- Version: 0.5
-- Generated: 2026-08-30
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-31
-- ============================================================
-- Rules-based product affinity: "frequently bought together" association rules
-- (support / confidence / lift) computed by MARKET BASKET ANALYSIS over the
-- customer-attributed order fact (customer_order_line), for MULTIPLE TRAILING WINDOWS.
-- One row per DIRECTED product pair × time_window (A -> B): support and lift are symmetric,
-- confidence is directional, so both A->B and B->A are emitted. Built entirely on the BASE
-- dimensional model — no ML, no stored affinity table, no synthetic producer: the durable
-- product_id lives on customer_order_line, and `product` is read (current version) only for
-- display labels (name / category / brand).
--
-- CONSUMPTION: this rules table is consumed DIRECTLY — its metrics are PAIR-LEVEL and
-- NON-ADDITIVE (lift/confidence/support do not re-aggregate; you rank/look them up by key),
-- so there is deliberately no metric view over it (see sample-queries 10-11/14-15 and the
-- notebook template). The governed metric surface `mv_product_affinity` covers the
-- customer×product affinity surface instead, where ratio-of-sums measures are well-defined.
--
-- TIME WINDOWS (the source model's grain axis): rules are computed independently for each
-- window in the `windows` CTE — `30D`, `90D`, and `ALL_TIME`. The trailing cutoffs are
-- anchored to `as_of_date = MAX(order_date)` in the data (NOT current_date, which would empty
-- the surface on historical demo data — mirrors how gold_customer_ltv anchors "now"). A basket
-- (order) enters a window if its order_date is on/after the cutoff (ALL_TIME has no cutoff).
-- Add/adjust windows in one place: the `windows` VALUES list. support/confidence/lift are
-- recomputed per window, so a pair can rank differently (or drop out) in a shorter window as
-- recent behavior shifts.
--
-- Metric definitions (classic association-rule algebra; see glossary.md), PER WINDOW:
--   basket                = one order_id (a purchase occasion). A product is counted ONCE per
--                           basket (DISTINCT), so re-buying the same SKU on two lines of one
--                           order is a single co-occurrence unit.
--   total_baskets         = COUNT(DISTINCT order_id) within the window.
--   antecedent_baskets    = baskets containing A;  consequent_baskets = baskets containing B.
--   cooccurrence_baskets  = baskets containing BOTH A and B.
--   support(A,B)          = cooccurrence_baskets / total_baskets      (how common the pair is).
--   confidence(A->B)      = cooccurrence_baskets / antecedent_baskets (P(B in basket | A in basket)).
--   lift(A,B)             = support(A,B) / (support(A) * support(B))  (association vs. chance;
--                           > 1 = positive/meaningful, = 1 = independent, < 1 = substitutes).
--
-- TUNABLE PRUNING CONSTANTS (illustrative retail defaults; adopters retune to their own
-- catalogue size and basket depth). They keep statistically insignificant noise out of the
-- serving surface, and all five live in ONE place — the `params` CTE below (mirroring
-- gold_customer_product_affinity's params CTE), referenced by the item/pair filters and the
-- final WHERE so there is a single edit site:
--   min_item_baskets = 5   -- drop low-volume products BEFORE pairing (the popular_basket
--                             semi-join), so the O(basket_size^2) self-join never processes
--                             long-tail SKUs (basket stuffers / long tail inflate lift).
--   min_pair_baskets = 3   -- a pair must co-occur at least this many times in the window.
--   min_support      = 0.0002, min_confidence = 0.02, min_lift = 1.05.
-- NOTE ON SYNTHETIC DATA: ORDM's synthetic baskets draw products uniformly at random, so real
-- correlation is faint and this surface is intentionally SPARSE on shipped data (lift ~ 1.0,
-- few pairs clear min_lift). On real, correlated purchase data it populates densely. The Spark
-- logic test proves the algebra — and the windowing — on a deliberately correlated fixture.
--
-- SCD2 (§A.16): co-occurrence is computed purely on the DURABLE product_id carried by
-- customer_order_line, so no version-specific `_sk` enters a GROUP BY or a COUNT(DISTINCT)
-- (no fragmentation / double-count). `product` is read for labels via its CURRENT version
-- and joined on the durable product_id — never an `_sk = _sk` equi-join, so no reverse-drop.
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${acu_schema}.gold_product_affinity_pairwise AS
WITH params AS (
  -- TUNABLE PRUNING CONSTANTS — the SINGLE place adopters retune (see header).
  SELECT
    5      AS min_item_baskets,   -- min baskets a SKU must appear in (per window) to be paired
    3      AS min_pair_baskets,   -- min baskets a pair must co-occur in (per window)
    0.0002 AS min_support,        -- min support to serve
    0.02   AS min_confidence,     -- min directional confidence to serve
    1.05   AS min_lift            -- min lift (positive association over chance)
),
obs AS (
  -- The evaluation clock: latest observed order date, so trailing windows are reproducible.
  SELECT MAX(order_date) AS as_of_date
  FROM ${catalog}.${order_schema}.customer_order_line
  WHERE order_id IS NOT NULL AND product_id IS NOT NULL
),
windows AS (
  -- The trailing windows the rules are computed over. window_days NULL = ALL_TIME (no cutoff).
  SELECT * FROM VALUES
    ('30D', 30),
    ('90D', 90),
    ('ALL_TIME', CAST(NULL AS INT))
  AS w(time_window, window_days)
),
basket_line AS (
  -- one (basket, product) per row + the basket date; DISTINCT collapses repeat lines of a SKU.
  SELECT DISTINCT order_id, product_id, order_date
  FROM ${catalog}.${order_schema}.customer_order_line
  WHERE order_id IS NOT NULL AND product_id IS NOT NULL
),
basket AS (
  -- assign each basket to every window whose trailing cutoff it falls within.
  SELECT w.time_window, b.order_id, b.product_id
  FROM basket_line b
  CROSS JOIN windows w
  CROSS JOIN obs o
  WHERE w.window_days IS NULL
     OR b.order_date >= date_sub(o.as_of_date, w.window_days)
),
total AS (
  SELECT time_window, CAST(COUNT(DISTINCT order_id) AS DOUBLE) AS total_baskets
  FROM basket
  GROUP BY time_window
),
item_freq AS (
  -- product volume per window, pruned to min_item_baskets. Count then filter (rather than a
  -- HAVING literal) so the threshold reads from the params CTE, keeping the single edit site.
  SELECT ic.time_window, ic.product_id, ic.basket_count
  FROM (
    SELECT time_window, product_id, CAST(COUNT(DISTINCT order_id) AS DOUBLE) AS basket_count
    FROM basket
    GROUP BY time_window, product_id
  ) ic
  CROSS JOIN params p
  WHERE ic.basket_count >= p.min_item_baskets
),
popular_basket AS (
  -- Prune BEFORE pairing (a semi-join, not a post-filter): keep only (basket, product) rows
  -- whose product cleared min_item_baskets in that window, so the O(basket_size^2) self-join
  -- below never processes long-tail SKUs. This is a deliberate volume floor and is LOSSY by
  -- design: with min_item_baskets (5) > min_pair_baskets (3), a product appearing in only 4
  -- baskets is dropped even though it could co-occur with a partner in 3-4 of them and clear
  -- min_pair_baskets. Rare-product pairs are traded away for noise reduction; set
  -- min_item_baskets <= min_pair_baskets if a lossless prune is wanted instead.
  SELECT b.time_window, b.order_id, b.product_id
  FROM basket b
  JOIN item_freq f ON f.time_window = b.time_window AND f.product_id = b.product_id
),
pair_freq AS (
  -- directed co-occurrence within a basket, over popular products only, pruned to min_pair_baskets.
  SELECT pc.time_window, pc.product_id_a, pc.product_id_b, pc.pair_basket_count
  FROM (
    SELECT
      a.time_window,
      a.product_id AS product_id_a,
      b.product_id AS product_id_b,
      CAST(COUNT(DISTINCT a.order_id) AS DOUBLE) AS pair_basket_count
    FROM popular_basket a
    JOIN popular_basket b
      ON a.time_window = b.time_window AND a.order_id = b.order_id AND a.product_id <> b.product_id
    GROUP BY a.time_window, a.product_id, b.product_id
  ) pc
  CROSS JOIN params p
  WHERE pc.pair_basket_count >= p.min_pair_baskets
),
prod AS (
  -- Current product labels only. Joined on the durable product_id below (no `_sk` equi-join),
  -- so `is_current` here is a plain current-snapshot pick and carries no SCD2-join-contract risk.
  SELECT product_id, product_name, category, subcategory, brand
  FROM ${catalog}.${product_schema}.product
  WHERE is_current = TRUE
),
metrics AS (
  SELECT
    p.time_window,
    p.product_id_a,
    p.product_id_b,
    p.pair_basket_count,
    fa.basket_count AS antecedent_baskets,
    fb.basket_count AS consequent_baskets,
    t.total_baskets,
    p.pair_basket_count / t.total_baskets                                   AS support,
    p.pair_basket_count / fa.basket_count                                   AS confidence,
    (p.pair_basket_count / t.total_baskets)
      / ((fa.basket_count / t.total_baskets) * (fb.basket_count / t.total_baskets)) AS lift
  FROM pair_freq p
  JOIN item_freq fa ON fa.time_window = p.time_window AND fa.product_id = p.product_id_a
  JOIN item_freq fb ON fb.time_window = p.time_window AND fb.product_id = p.product_id_b
  JOIN total t ON t.time_window = p.time_window
)
SELECT
  concat_ws('|', m.product_id_a, m.product_id_b, m.time_window) AS product_affinity_id,  -- convenience label; enforced grain is (product_id_a, product_id_b, time_window). Assumes durable ids are pipe-free.
  m.product_id_a,
  pa.product_name AS product_name_a,
  pa.category     AS category_a,
  pa.brand        AS brand_a,
  m.product_id_b,
  pb.product_name AS product_name_b,
  pb.category     AS category_b,
  pb.brand        AS brand_b,
  m.time_window,
  -- the anchor the trailing windows trail from (MAX(order_date) in the data), so a consumer
  -- comparing a 30D row to ALL_TIME can see the window's end date. Same value on every row.
  o.as_of_date    AS computed_through_date,
  CAST(m.pair_basket_count   AS BIGINT) AS cooccurrence_baskets,
  CAST(m.antecedent_baskets  AS BIGINT) AS antecedent_baskets,
  CAST(m.consequent_baskets  AS BIGINT) AS consequent_baskets,
  CAST(m.total_baskets       AS BIGINT) AS total_baskets,
  CAST(m.support    AS DECIMAL(12,8)) AS support,
  CAST(m.confidence AS DECIMAL(12,8)) AS confidence,
  CAST(m.lift       AS DECIMAL(18,8)) AS lift,
  -- TRUE on the mirror copy (A > B) so a consumer wanting the undirected pair once can
  -- filter is_mirrored_pair = FALSE; directional consumers keep both.
  (m.product_id_a > m.product_id_b)   AS is_mirrored_pair
FROM metrics m
LEFT JOIN prod pa ON pa.product_id = m.product_id_a
LEFT JOIN prod pb ON pb.product_id = m.product_id_b
CROSS JOIN params p
CROSS JOIN obs o
WHERE m.support    >= p.min_support
  AND m.confidence >= p.min_confidence
  AND m.lift       >= p.min_lift;
