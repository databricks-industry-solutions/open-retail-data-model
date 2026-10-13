-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- View: gold_payment_actuals
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: pending — @ojasvi-goyal-03 (BMV owner) ack required
-- ============================================================
-- Payment-side revenue leakage at product x store x day, giving BMV a REALIZED-margin lens the
-- POS `sales` fact cannot: refunds, chargebacks, and adjustments (contra-revenue in money) plus a
-- settled-sale base. This is the first consumer of the canonical-core `payment` domain.
--
-- Grain bridge: `payment` is ORDER grain (order_id + profile, no product/store). It is allocated to
-- product x store x day through the `order.customer_order_line` bridge, weighting each order line by
-- its share of the order's net revenue (Kimball allocated-fact / relative-value allocation). The
-- token-qualified FROM payment JOIN customer_order_line is also what makes the explorer draw the
-- payment -> BMV (and order -> BMV) consumes edges.
--
-- ALLOCATION IS A PROXY (caveat): per-product refund/chargeback amounts are allocated by each line's
-- share of ORDER net revenue, because payment events are order-grain (no product/store). This is an
-- estimate: an order-level reversal is spread across all lines, so it can MISATTRIBUTE an item-level
-- return to sibling lines when only one item was actually returned. It is directionally correct for
-- store/category leakage; do not read a single product x day cell as the exact item that was refunded.
--
-- Attribution date = payment EVENT date (a refund/chargeback can land weeks after the sale; this view
-- reports when money actually leaves, matching how sales/inventory rows are dated). This is the
-- event-date (cash) lens read by mv_payment_actuals. gold_realized_margin provides the sale-cohort
-- variant, built on the same allocation and predicates.
--
-- APPEND-ONLY LIFECYCLE (H1 fix): `payment` is an append-only event log (see payment.sql header), so
-- one economic payment event can land as several rows sharing the same durable `payment_id` as it
-- moves authorized -> captured -> settled (or -> refunded). Summing all rows would double-count a
-- single sale/return. This view first collapses to the LATEST row per payment_id (by event_timestamp)
-- so each event contributes exactly once, then applies the status filters below. Seeded data emits one
-- row per event, so today's output is identical; the dedup binds the view to the CONTRACT (an
-- append-only log), not to the current generator's one-row-per-event convenience.
--
-- LIFECYCLE INVARIANT (stated assumption): a `sale`-typed payment_id terminates in `settled` or
-- `captured`, and a reversal is a DISTINCT payment_id (`refund`/`chargeback`/`adjustment` type),
-- which is how the generator emits it (a `sale` row never itself reaches `refunded`). The contract
-- (payment.sql) does not forbid a `sale`-typed id whose terminal row is `refunded`; such a row would
-- match neither the sale branch (status not settled/captured) nor the refund branch (type not
-- 'refund'), so it would contribute to no measure. That shape is not silently ignored: the
-- bmv_payment_sale_terminal_status check (checks.sql, WARN) surfaces any sale-typed payment_id whose
-- latest status is outside settled/captured, so the invariant is asserted rather than assumed. If an
-- adopter's data legitimately carries settled-then-refunded on one id, widen the sale branch then.
--
-- Definitions:
-- * settled_sale_amount_lc:  allocated sale-payment magnitude, status settled/captured (rate denominator/recon base)
-- * refund_amount_lc:        allocated refund magnitude (contra-revenue; excludes declined/voided — no money moved)
-- * chargeback_amount_lc:    allocated chargeback magnitude (involuntary reversal; excludes declined/voided; kept distinct from refunds)
-- * adjustment_amount_lc:    allocated adjustment magnitude (post-sale goodwill/correction; excludes declined/voided; sign ambiguous, treated as contra-revenue)
-- Rates (refund_rate, chargeback_rate) are computed in the metric view as ratio-of-sums over
-- settled_sale_amount_lc, never here and never as avg-of-per-row-ratios.
--
-- SINGLE-SOURCE-OF-TRUTH RULE (avoid double-counting returns): merchandise-unit returns are the
-- `sales`/`gold_sales_actuals` domain (its `returns_units` / `net_units_sold` columns); returns/
-- leakage in MONEY are this view's domain via `payment`. These are DIFFERENT measures (units vs
-- dollars) and both are valid. The rule: gold_realized_margin must subtract payment refunds OR
-- sales-side returns, never both, or it double-counts the same economic return. It uses the same
-- allocation and status/type predicates as this view (see order_payment CTE definition). (Note: on
-- today's seeded data `returns_units` is effectively 0 because `chk_sales_nonnegative` forbids
-- negative units, but do not rely on that staying true. Reconcile by measure type, not by assuming
-- one source is empty.)
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${bmv_schema}.gold_payment_actuals AS
-- 1) line weight within its order = line net_amount / order net_amount total. Computed in
--    DECIMAL(18,6) precision; the allocated pieces are cast to DECIMAL(18,2) once at the end.
WITH line_weight AS (
  SELECT
    order_line_id,
    order_id,
    product_sk,
    store_sk,
    product_id,
    store_id,
    -- GREATEST(...,0): `order.customer_order_line.net_amount` carries no non-negativity CHECK
    -- upstream (only units/gross_amount do), so a negative line net (deep discount, or a future
    -- return line) is clamped to 0 weight rather than flipping the allocation sign or tripping the
    -- error-severity bmv_payment_actuals_nonneg check on otherwise-valid core data. A near-zero
    -- (non-zero) order net escapes NULLIF; the clamp bounds the numerator's contribution.
    GREATEST(CAST(net_amount AS DECIMAL(18,6)), 0)
      / NULLIF(SUM(GREATEST(net_amount, 0)) OVER (PARTITION BY order_id), 0) AS alloc_weight
  FROM ${catalog}.${order_schema}.customer_order_line
),
-- 2) H1 fix: collapse the append-only lifecycle to ONE row per payment_id — the latest by
--    event_timestamp (payment_sk DESC as a deterministic tiebreaker on same-instant rows). This
--    ensures a sale that logged authorized -> captured -> settled contributes its magnitude once,
--    not three times, when the view is refreshed against real (multi-row) lifecycle data.
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
-- 3) each payment event, spread across its order's lines by weight. LEFT JOIN keeps payment events
--    whose order_id is null or has no matching order line (cash/adjustment/orphan) — they get a NULL
--    product/store and are routed to the unallocated bucket in the aggregation below.
allocated AS (
  SELECT
    lw.product_sk,
    lw.store_sk,
    lw.product_id,
    lw.store_id,
    CAST(p.event_timestamp AS DATE) AS date_key,
    p.currency_code,
    p.payment_type,
    p.payment_status,
    -- weight is NULL when the order has zero net (NULLIF) or no line match; fall back to no allocation
    CAST(p.amount * COALESCE(lw.alloc_weight, 0) AS DECIMAL(18,2)) AS allocated_amount_lc,
    p.amount AS payment_amount_lc,
    lw.alloc_weight
  FROM payment_current p
  LEFT JOIN line_weight lw
    ON lw.order_id = p.order_id
)
SELECT
  product_sk,
  store_sk,
  product_id,
  store_id,
  date_key,
  currency_code,
  -- M1 fix: every branch is now status-guarded to REALIZED money only. The sale branch keeps its
  -- positive allow-list (settled/captured); the contra-revenue branches exclude the non-realized
  -- states (authorized = not yet moved, declined/voided = never moved), so a voided/declined refund
  -- or chargeback no longer inflates leakage. The reconciliation denominator (checks.sql) uses the
  -- SAME predicate, so the metric still reflects allocation/bridge loss only.
  SUM(CASE WHEN payment_type = 'sale'
             AND payment_status IN ('settled', 'captured')
           THEN allocated_amount_lc ELSE 0 END)                      AS settled_sale_amount_lc,
  SUM(CASE WHEN payment_type = 'refund'
             AND payment_status NOT IN ('authorized', 'declined', 'voided')
           THEN allocated_amount_lc ELSE 0 END)                      AS refund_amount_lc,
  SUM(CASE WHEN payment_type = 'chargeback'
             AND payment_status NOT IN ('authorized', 'declined', 'voided')
           THEN allocated_amount_lc ELSE 0 END)                      AS chargeback_amount_lc,
  SUM(CASE WHEN payment_type = 'adjustment'
             AND payment_status NOT IN ('authorized', 'declined', 'voided')
           THEN allocated_amount_lc ELSE 0 END)                      AS adjustment_amount_lc
FROM allocated
-- Product-grain rows only: events that could not be allocated to a product line (null/orphan order,
-- or zero-net order) have product_sk IS NULL and are excluded here so the grain stays clean. The
-- bmv_payment_alloc_reconciliation check (checks.sql) surfaces the unallocated magnitude separately.
WHERE product_sk IS NOT NULL
GROUP BY product_sk, store_sk, product_id, store_id, date_key, currency_code
CLUSTER BY (product_sk, store_sk, date_key);
