-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- View: gold_realized_margin
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-10-11
-- LLM-generated: true
-- Last reviewed: pending -- BMV owner ack required
-- ============================================================
-- Realized margin and revenue leakage at product x store x SALE day grain, across the two
-- separate channels ORDM models. Reads canonical core directly:
-- * transaction.sales (POS; no payment lifecycle), dated by the sale day
-- * orders.customer_order_line (orders), dated by order_date
-- * payment.payment (order payments only), re-allocated here to order lines with the SAME
--   weight, lifecycle dedup and status predicates as gold_payment_actuals, but attributed to the
--   original order's lines and order_date (sale cohort) instead of the payment event date.
--   gold_payment_actuals remains the event-date (cash) view; conservation checks tie the two.
--
-- Grain: product_sk x store_sk x date_key (+ currency_code in the channel join key).
-- Join strategy: FULL OUTER between the POS cohort and the order cohort, so a product x store x day
-- with sales on only one channel still appears. Missing side contributes 0 to all measures.
--
-- Realized margin = POS net sales + order settled sales - refunds - chargebacks - adjustments,
-- minus COGS (units x product.unit_cost on both channels; POS units are SUM(units), so any
-- negative return units an adopter loads reduce them). Booked margin uses POS net sales plus order
-- line net (booked) sales before settlement and reversals.
--
-- ALLOCATION PROXY (caveat, inherited from gold_payment_actuals): order-level refund/chargeback
-- amounts are allocated by each line's share of ORDER net revenue. This misattributes item-level
-- returns to sibling lines when only one item was actually returned; it is directionally correct
-- for store/category leakage. Do not read a single product x day cell as the exact item refunded.
--
-- SINGLE-SOURCE-OF-TRUTH RULE (avoid double-counting returns): merchandise-unit returns are the
-- `sales` domain (returns_units / net_units_sold); payment-side reversals (refund/chargeback)
-- are this view. COGS uses POS SUM(units) (net of any return units) and order line units. Payment
-- reversals reduce revenue. A composing view must not combine both (e.g., do not subtract refund dollars AND
-- reduce units for the same return).
--
-- Product is LEFT-joined so a sale whose product row is missing keeps its revenue; its COGS is
-- NULL-skipped, which bmv_realized_margin_unit_cost_coverage reports.
-- Amount basis: payment sale amounts are expected on the same tax- and shipping-exclusive basis as
-- customer_order_line.net_amount. An adopter whose tenders include tax or shipping must net them out
-- upstream; otherwise settled sales exceed booked sales and unsettled sales go negative
-- (bmv_realized_margin_unsettled_sanity). gold_payment_actuals shares this basis.
-- Stated assumptions: allocation proxy understood; refunded merchandise NOT assumed restocked
-- (COGS not recovered, conservative); COGS uses product.unit_cost at the version-specific product_sk;
-- adjustments are contra-revenue (as in gold_payment_actuals); adjustments/refunds with NULL
-- order_id cannot be allocated and are excluded; recent cohorts are immature (reversals land
-- weeks later, so a recent day's realized revenue still falls); operational estimates, not an
-- accounting close. GROUP BY includes both _sk and durable _id (SCD2 pattern).
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${bmv_schema}.gold_realized_margin AS

-- 1) POS sales cohort: sum units, net revenue, and COGS per product x store x sale_date
WITH pos AS (
  SELECT
    s.product_sk,
    s.product_id,
    s.store_sk,
    s.store_id,
    s.date_key,
    s.currency_code,
    SUM(s.units) AS pos_units,
    SUM(s.net_revenue) AS pos_net_sales_lc,
    SUM(s.units * p.unit_cost) AS pos_cogs_lc
  FROM ${catalog}.${transaction_schema}.sales s
  LEFT JOIN ${catalog}.${product_schema}.product p
    ON s.product_sk = p.product_sk
  GROUP BY s.product_sk, s.product_id, s.store_sk, s.store_id, s.date_key, s.currency_code
),

-- 2) line weight within its order = line net_amount / order net_amount total. Computed in
--    DECIMAL(18,6) precision; the allocated pieces are cast to DECIMAL(18,2) at the final SELECT.
line_weight AS (
  SELECT
    order_line_id,
    order_id,
    product_sk,
    store_sk,
    product_id,
    store_id,
    net_amount,
    units,
    GREATEST(CAST(net_amount AS DECIMAL(18,6)), 0)
      / NULLIF(SUM(GREATEST(net_amount, 0)) OVER (PARTITION BY order_id), 0) AS alloc_weight
  FROM ${catalog}.${order_schema}.customer_order_line
),

-- 3) collapse the append-only payment lifecycle to ONE row per payment_id -- the latest by
--    event_timestamp (payment_sk DESC as a deterministic tiebreaker on same-instant rows).
--    This ensures a sale that logged authorized -> captured -> settled contributes its magnitude
--    once, not three times. Seeded data emits one row per event, so today's output is identical;
--    the dedup binds the view to the CONTRACT (an append-only log), not to the generator's one-row-per-event convenience.
payment_current AS (
  SELECT * EXCEPT (rn) FROM (
    SELECT
      p.*,
      ROW_NUMBER() OVER (PARTITION BY p.payment_id
                         ORDER BY p.event_timestamp DESC, p.payment_sk DESC) AS rn
    FROM ${catalog}.${payment_schema}.payment p
  )
  WHERE rn = 1
),

-- 4) per-order aggregation of payment events (settled sales, refunds, chargebacks, adjustments).
--    Predicates MUST stay identical to gold_payment_actuals.
order_payment AS (
  SELECT
    p.order_id,
    SUM(CASE WHEN p.payment_type = 'sale'
             AND p.payment_status IN ('settled', 'captured')
           THEN p.amount ELSE 0 END) AS settled_sale_lc,
    SUM(CASE WHEN p.payment_type = 'refund'
             AND p.payment_status NOT IN ('authorized', 'declined', 'voided')
           THEN p.amount ELSE 0 END) AS refund_lc,
    SUM(CASE WHEN p.payment_type = 'chargeback'
             AND p.payment_status NOT IN ('authorized', 'declined', 'voided')
           THEN p.amount ELSE 0 END) AS chargeback_lc,
    SUM(CASE WHEN p.payment_type = 'adjustment'
             AND p.payment_status NOT IN ('authorized', 'declined', 'voided')
           THEN p.amount ELSE 0 END) AS adjustment_lc
  FROM payment_current p
  WHERE p.order_id IS NOT NULL
  GROUP BY p.order_id
),

-- 5) order lines enriched with line weights and order payment allocations.
order_lines AS (
  SELECT
    ol.product_sk,
    ol.product_id,
    ol.store_sk,
    ol.store_id,
    CAST(ol.order_date AS DATE) AS date_key,
    ol.currency_code,
    ol.units AS line_units,
    ol.net_amount AS line_booked_sales_lc,
    COALESCE(op.settled_sale_lc, 0) * COALESCE(lw.alloc_weight, 0) AS line_settled_sales_lc,
    COALESCE(op.refund_lc, 0) * COALESCE(lw.alloc_weight, 0) AS line_refund_lc,
    COALESCE(op.chargeback_lc, 0) * COALESCE(lw.alloc_weight, 0) AS line_chargeback_lc,
    COALESCE(op.adjustment_lc, 0) * COALESCE(lw.alloc_weight, 0) AS line_adjustment_lc,
    ol.units * p.unit_cost AS line_cogs_lc
  FROM ${catalog}.${order_schema}.customer_order_line ol
  LEFT JOIN line_weight lw
    ON lw.order_line_id = ol.order_line_id
  LEFT JOIN ${catalog}.${product_schema}.product p
    ON ol.product_sk = p.product_sk
  LEFT JOIN order_payment op
    ON op.order_id = ol.order_id
),

-- 6) order cohort: aggregate order lines to product x store x order_date grain.
orders_agg AS (
  SELECT
    product_sk,
    product_id,
    store_sk,
    store_id,
    date_key,
    currency_code,
    SUM(line_units) AS order_units,
    SUM(line_booked_sales_lc) AS order_booked_sales_lc,
    SUM(line_settled_sales_lc) AS order_settled_sales_lc,
    SUM(line_refund_lc) AS order_refund_lc,
    SUM(line_chargeback_lc) AS order_chargeback_lc,
    SUM(line_adjustment_lc) AS order_adjustment_lc,
    SUM(line_cogs_lc) AS order_cogs_lc
  FROM order_lines
  GROUP BY product_sk, product_id, store_sk, store_id, date_key, currency_code
),

-- 7) FULL OUTER JOIN: merge pos and order cohorts on product_sk, store_sk, date_key and
--    currency_code. Currency is part of the key so the two channels are never summed across
--    currencies: a mismatch yields two rows for one product x store x day, which the grain and
--    single-currency checks then surface. Missing side contributes 0 to all measures.
combined AS (
  SELECT
    COALESCE(p.product_sk, o.product_sk) AS product_sk,
    COALESCE(p.store_sk, o.store_sk) AS store_sk,
    COALESCE(p.product_id, o.product_id) AS product_id,
    COALESCE(p.store_id, o.store_id) AS store_id,
    COALESCE(p.date_key, o.date_key) AS date_key,
    COALESCE(p.currency_code, o.currency_code) AS currency_code,
    COALESCE(p.pos_units, 0) AS pos_units,
    COALESCE(p.pos_net_sales_lc, 0) AS pos_net_sales_lc,
    COALESCE(p.pos_cogs_lc, 0) AS pos_cogs_lc,
    COALESCE(o.order_units, 0) AS order_units,
    COALESCE(o.order_booked_sales_lc, 0) AS order_booked_sales_lc,
    COALESCE(o.order_settled_sales_lc, 0) AS order_settled_sales_lc,
    COALESCE(o.order_refund_lc, 0) AS order_refund_lc,
    COALESCE(o.order_chargeback_lc, 0) AS order_chargeback_lc,
    COALESCE(o.order_adjustment_lc, 0) AS order_adjustment_lc,
    COALESCE(o.order_cogs_lc, 0) AS order_cogs_lc
  FROM pos p
  FULL OUTER JOIN orders_agg o
    ON p.product_sk = o.product_sk
    AND p.store_sk = o.store_sk
    AND p.date_key = o.date_key
    AND p.currency_code = o.currency_code
),

-- 8) round each component ONCE; every total below is derived from these rounded components, so
--    the published identities (realized = pos net + settled - reversals, leakage = booked -
--    realized, margins = revenue - cogs) hold exactly on the output columns.
rounded AS (
  SELECT
    product_sk,
    store_sk,
    product_id,
    store_id,
    date_key,
    currency_code,
    CAST(pos_units AS DECIMAL(12,3))              AS pos_units,
    CAST(pos_net_sales_lc AS DECIMAL(18,2))       AS pos_net_sales_lc,
    CAST(pos_cogs_lc AS DECIMAL(18,2))            AS pos_cogs_lc,
    CAST(order_units AS DECIMAL(12,3))            AS order_units,
    CAST(order_booked_sales_lc AS DECIMAL(18,2))  AS order_booked_sales_lc,
    CAST(order_settled_sales_lc AS DECIMAL(18,2)) AS order_settled_sales_lc,
    CAST(order_refund_lc AS DECIMAL(18,2))        AS order_refund_lc,
    CAST(order_chargeback_lc AS DECIMAL(18,2))    AS order_chargeback_lc,
    CAST(order_adjustment_lc AS DECIMAL(18,2))    AS order_adjustment_lc,
    CAST(order_cogs_lc AS DECIMAL(18,2))          AS order_cogs_lc
  FROM combined
)

SELECT
  product_sk,
  store_sk,
  product_id,
  store_id,
  date_key,
  currency_code,
  pos_units,
  pos_net_sales_lc,
  pos_cogs_lc,
  order_units,
  order_booked_sales_lc,
  order_settled_sales_lc,
  CAST(order_booked_sales_lc - order_settled_sales_lc AS DECIMAL(18,2)) AS order_unsettled_sales_lc,
  order_refund_lc,
  order_chargeback_lc,
  order_adjustment_lc,
  order_cogs_lc,
  CAST(pos_net_sales_lc + order_booked_sales_lc AS DECIMAL(18,2)) AS booked_revenue_lc,
  CAST(pos_net_sales_lc + order_settled_sales_lc
       - order_refund_lc - order_chargeback_lc - order_adjustment_lc AS DECIMAL(18,2)) AS realized_revenue_lc,
  CAST((order_booked_sales_lc - order_settled_sales_lc)
       + order_refund_lc + order_chargeback_lc + order_adjustment_lc AS DECIMAL(18,2)) AS leakage_lc,
  CAST(pos_cogs_lc + order_cogs_lc AS DECIMAL(18,2)) AS cogs_lc,
  CAST(pos_net_sales_lc + order_booked_sales_lc
       - pos_cogs_lc - order_cogs_lc AS DECIMAL(18,2)) AS booked_margin_lc,
  CAST(pos_net_sales_lc + order_settled_sales_lc
       - order_refund_lc - order_chargeback_lc - order_adjustment_lc
       - pos_cogs_lc - order_cogs_lc AS DECIMAL(18,2)) AS realized_margin_lc
FROM rounded
CLUSTER BY (product_sk, store_sk, date_key);
