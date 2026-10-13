-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Realized Margin & Revenue Leakage: Analysis Notebook
-- MAGIC
-- MAGIC ORDM · Outcome Package · Balancing Margin and Volume · Version 0.5
-- MAGIC
-- MAGIC Analyzes booked vs. realized margin, revenue leakage patterns, and payment
-- MAGIC health across product categories and store locations. Compares sale-cohort
-- MAGIC vs. event-date perspectives to isolate timing effects.
-- MAGIC
-- MAGIC **Prerequisites**
-- MAGIC 1. Gold tables deployed: `gold_realized_margin`, `gold_payment_actuals`.
-- MAGIC 2. Metric views deployed: `mv_realized_margin`, `mv_payment_actuals`.
-- MAGIC 3. Widgets / spark.conf for `${catalog}`, `${bmv_schema}`, `${product_schema}`,
-- MAGIC    `${store_schema}`, and `${calendar_schema}` tokens (same as other ORDM notebooks).
-- MAGIC
-- MAGIC **Structure**
-- MAGIC 1. Booked vs. realized margin by product category (sale-cohort).
-- MAGIC 2. Leakage mix composition (refunds, chargebacks, adjustments).
-- MAGIC 3. Sale-cohort vs. event-date reconciliation (timing comparison).
-- MAGIC 4. Chargeback hotspots by store (fraud/dispute risk ranking).

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 1. Booked vs. Realized Margin by Product Category
-- MAGIC Shows margin compression by category, driven by booked-to-realized revenue
-- MAGIC leakage on the order channel. Highlights categories needing review.

-- COMMAND ----------

SELECT
    p.category,
    SUM(grm.booked_revenue_lc) AS booked_revenue_lc,
    SUM(grm.cogs_lc) AS cogs_lc,
    SUM(grm.booked_margin_lc) AS booked_margin_lc,
    ROUND(SUM(grm.booked_margin_lc) / NULLIF(SUM(grm.booked_revenue_lc), 0), 4)
                                                        AS booked_margin_pct,
    SUM(grm.realized_revenue_lc) AS realized_revenue_lc,
    SUM(grm.realized_margin_lc) AS realized_margin_lc,
    ROUND(SUM(grm.realized_margin_lc) / NULLIF(SUM(grm.realized_revenue_lc), 0), 4)
                                                        AS realized_margin_pct,
    SUM(grm.leakage_lc) AS leakage_lc,
    SUM(grm.booked_margin_lc) - SUM(grm.realized_margin_lc) AS margin_compression_lc,
    ROUND((SUM(grm.booked_margin_lc) - SUM(grm.realized_margin_lc))
        / NULLIF(SUM(grm.booked_margin_lc), 0), 4) AS margin_compression_pct
FROM ${catalog}.${bmv_schema}.gold_realized_margin grm
JOIN ${catalog}.${product_schema}.product p
  ON grm.product_sk = p.product_sk
GROUP BY p.category
ORDER BY margin_compression_lc DESC NULLS LAST;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2. Leakage Mix Composition
-- MAGIC Breaks down payment reversals by type: refunds (voluntary), chargebacks
-- MAGIC (involuntary disputes), and adjustments (goodwill / corrections), as a share of
-- MAGIC settled order sales. Basis: event date (cash perspective). This excludes unsettled
-- MAGIC order sales; for full leakage (booked - realized, including unsettled) use
-- MAGIC gold_realized_margin.leakage_lc.

-- COMMAND ----------

SELECT
    'All Operations' AS dimension,
    SUM(pa.settled_sale_amount_lc) AS settled_sales_lc,
    SUM(pa.refund_amount_lc) AS refunds_lc,
    ROUND(SUM(pa.refund_amount_lc) / NULLIF(SUM(pa.settled_sale_amount_lc), 0), 4)
                                                        AS refund_rate,
    SUM(pa.chargeback_amount_lc) AS chargebacks_lc,
    ROUND(SUM(pa.chargeback_amount_lc) / NULLIF(SUM(pa.settled_sale_amount_lc), 0), 4)
                                                        AS chargeback_rate,
    SUM(pa.adjustment_amount_lc) AS adjustments_lc,
    ROUND(SUM(pa.adjustment_amount_lc) / NULLIF(SUM(pa.settled_sale_amount_lc), 0), 4)
                                                        AS adjustment_rate,
    SUM(pa.refund_amount_lc) + SUM(pa.chargeback_amount_lc) + SUM(pa.adjustment_amount_lc)
                                                        AS payment_reversals_lc,
    ROUND((SUM(pa.refund_amount_lc) + SUM(pa.chargeback_amount_lc) + SUM(pa.adjustment_amount_lc))
        / NULLIF(SUM(pa.settled_sale_amount_lc), 0), 4) AS payment_reversal_rate,
    ROUND(SUM(pa.refund_amount_lc) / NULLIF(
        SUM(pa.refund_amount_lc) + SUM(pa.chargeback_amount_lc) + SUM(pa.adjustment_amount_lc), 0), 4)
                                                        AS refund_pct_of_reversals,
    ROUND(SUM(pa.chargeback_amount_lc) / NULLIF(
        SUM(pa.refund_amount_lc) + SUM(pa.chargeback_amount_lc) + SUM(pa.adjustment_amount_lc), 0), 4)
                                                        AS chargeback_pct_of_reversals,
    ROUND(SUM(pa.adjustment_amount_lc) / NULLIF(
        SUM(pa.refund_amount_lc) + SUM(pa.chargeback_amount_lc) + SUM(pa.adjustment_amount_lc), 0), 4)
                                                        AS adjustment_pct_of_reversals
FROM ${catalog}.${bmv_schema}.gold_payment_actuals pa;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3. Sale-Cohort vs. Event-Date Reconciliation
-- MAGIC Same quantity on both sides: order-channel payment reversals (refunds +
-- MAGIC chargebacks + adjustments) as a share of order-channel settled sales, by month.
-- MAGIC The cohort row dates each reversal by the original order date; the event row by
-- MAGIC the payment event date. Over the full history the reversal totals agree (the
-- MAGIC conservation checks enforce that), so the month-by-month gap is mostly reversal
-- MAGIC timing: event-dated reversals trail their sales. The settled-sales denominator is
-- MAGIC also dated differently (order date vs capture date), so where capture lags the order
-- MAGIC part of the gap comes from the denominator. Recent sale cohorts look better than
-- MAGIC they will end up.

-- COMMAND ----------

WITH cohort_summary AS (
    SELECT
        'Sale cohort (order date)' AS perspective,
        DATE_TRUNC('month', grm.date_key) AS period,
        SUM(grm.order_settled_sales_lc) AS settled_sales_lc,
        SUM(grm.order_refund_lc) + SUM(grm.order_chargeback_lc) + SUM(grm.order_adjustment_lc)
                                                            AS payment_reversals_lc
    FROM ${catalog}.${bmv_schema}.gold_realized_margin grm
    GROUP BY period
),
event_summary AS (
    SELECT
        'Event date (payment date)' AS perspective,
        DATE_TRUNC('month', pa.date_key) AS period,
        SUM(pa.settled_sale_amount_lc) AS settled_sales_lc,
        SUM(pa.refund_amount_lc) + SUM(pa.chargeback_amount_lc) + SUM(pa.adjustment_amount_lc)
                                                            AS payment_reversals_lc
    FROM ${catalog}.${bmv_schema}.gold_payment_actuals pa
    GROUP BY period
)
SELECT
    perspective,
    period,
    settled_sales_lc,
    payment_reversals_lc,
    ROUND(payment_reversals_lc / NULLIF(settled_sales_lc, 0), 4) AS payment_reversal_rate
FROM (
    SELECT * FROM cohort_summary
    UNION ALL
    SELECT * FROM event_summary
)
ORDER BY period DESC, perspective;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 4. Chargeback Hotspots by Store
-- MAGIC Ranks stores by chargeback rate (event-date basis). High chargeback stores
-- MAGIC may signal fraud patterns, payment processor issues, or regional disputes.
-- MAGIC Supports loss-prevention and compliance investigations.

-- COMMAND ----------

SELECT
    s.store_id,
    s.store_name,
    COALESCE(s.region, 'Unknown') AS region,
    SUM(pa.settled_sale_amount_lc) AS settled_sales_lc,
    SUM(pa.chargeback_amount_lc) AS chargebacks_lc,
    ROUND(SUM(pa.chargeback_amount_lc) / NULLIF(SUM(pa.settled_sale_amount_lc), 0), 4)
                                                        AS chargeback_rate,
    COUNT(DISTINCT DATE(pa.date_key)) AS days_with_activity,
    COUNT(DISTINCT pa.product_sk) AS unique_products,
    ROUND(SUM(pa.chargeback_amount_lc) / NULLIF(COUNT(DISTINCT DATE(pa.date_key)), 0), 2)
                                                        AS avg_chargeback_per_day_lc
FROM ${catalog}.${bmv_schema}.gold_payment_actuals pa
JOIN ${catalog}.${store_schema}.store s
  ON pa.store_sk = s.store_sk
GROUP BY s.store_id, s.store_name, s.region
HAVING SUM(pa.settled_sale_amount_lc) > 0
ORDER BY chargeback_rate DESC NULLS LAST
LIMIT 100;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 5. Optional: Recent Cohort Maturity Check
-- MAGIC Recent sale days may not yet have received all reversals. This query shows
-- MAGIC booked revenue vs. settled revenue by recency to flag immature periods in
-- MAGIC downstream analysis.

-- COMMAND ----------

-- Recency is measured back from the latest sale day in the data (not CURRENT_DATE), so the query
-- also works on a historical or synthetic dataset.
WITH latest AS (
    SELECT MAX(date_key) AS max_date_key
    FROM ${catalog}.${bmv_schema}.gold_realized_margin
),
cohort_maturity AS (
    SELECT
        grm.date_key,
        DATEDIFF(l.max_date_key, grm.date_key) AS days_before_latest_sale,
        SUM(grm.booked_revenue_lc) AS booked_revenue_lc,
        SUM(grm.order_settled_sales_lc) AS settled_sales_lc,
        SUM(grm.order_unsettled_sales_lc) AS unsettled_sales_lc,
        SUM(grm.leakage_lc) AS leakage_lc,
        ROUND(SUM(grm.leakage_lc) / NULLIF(SUM(grm.booked_revenue_lc), 0), 4)
                                                            AS leakage_rate,
        COUNT(DISTINCT grm.product_id) AS products_sold
    FROM ${catalog}.${bmv_schema}.gold_realized_margin grm
    CROSS JOIN latest l
    GROUP BY grm.date_key, l.max_date_key
)
SELECT *
FROM cohort_maturity
WHERE days_before_latest_sale <= 60
ORDER BY days_before_latest_sale ASC;
