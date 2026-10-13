-- ============================================================
-- ORDM · Canonical Core · Order domain · data-quality checks
-- Version: 0.5 · Generated: 2026-06-09 · LLM-generated: true · Reviewed: 2026-06-09
-- Each assertion SELECTs violating rows; 0 rows = PASS.
-- ============================================================

-- check: col_keys_not_null | severity: error
SELECT * FROM ${catalog}.${order_schema}.customer_order_line
WHERE order_line_sk IS NULL OR order_line_id IS NULL OR order_id IS NULL
   OR profile_id IS NULL OR product_id IS NULL OR store_id IS NULL OR order_date IS NULL;

-- check: col_profile_fk_orphan | severity: error
SELECT col.* FROM ${catalog}.${order_schema}.customer_order_line col
LEFT JOIN ${catalog}.${customer_schema}.profile p ON col.profile_sk = p.profile_sk
WHERE col.profile_sk IS NOT NULL AND p.profile_sk IS NULL;

-- check: col_product_fk_orphan | severity: error
SELECT col.* FROM ${catalog}.${order_schema}.customer_order_line col
LEFT JOIN ${catalog}.${product_schema}.product pr ON col.product_sk = pr.product_sk
WHERE col.product_sk IS NOT NULL AND pr.product_sk IS NULL;

-- check: col_store_fk_orphan | severity: error
SELECT col.* FROM ${catalog}.${order_schema}.customer_order_line col
LEFT JOIN ${catalog}.${store_schema}.store st ON col.store_sk = st.store_sk
WHERE col.store_sk IS NOT NULL AND st.store_sk IS NULL;

-- check: col_quantities_nonnegative | severity: error
SELECT * FROM ${catalog}.${order_schema}.customer_order_line
WHERE units < 0 OR gross_amount < 0;

-- check: col_calendar_coverage | severity: error
SELECT col.order_date FROM ${catalog}.${order_schema}.customer_order_line col
LEFT JOIN ${catalog}.${calendar_schema}.fiscal_calendar c ON col.order_date = c.date_key
WHERE c.date_key IS NULL
GROUP BY col.order_date;

-- check: col_single_reporting_currency | severity: error
-- Amounts are normalized to the base currency; currency_code must be constant.
SELECT COUNT(DISTINCT currency_code) AS distinct_currencies
FROM ${catalog}.${order_schema}.customer_order_line
HAVING COUNT(DISTINCT currency_code) > 1;
