-- ============================================================
-- ORDM · Canonical Core · Procurement domain · data-quality checks
-- Version: 0.5 · Generated: 2026-06-09 · LLM-generated: true · Reviewed: 2026-06-09
-- Each assertion SELECTs violating rows; 0 rows = PASS.
-- ============================================================

-- check: pol_keys_not_null | severity: error
SELECT * FROM ${catalog}.${procurement_schema}.purchase_order_line
WHERE po_line_sk IS NULL OR po_line_id IS NULL OR supplier_id IS NULL
   OR product_id IS NULL OR store_id IS NULL OR order_date IS NULL;

-- check: pol_supplier_fk_orphan | severity: error
SELECT pol.* FROM ${catalog}.${procurement_schema}.purchase_order_line pol
LEFT JOIN ${catalog}.${supplier_schema}.supplier s ON pol.supplier_sk = s.supplier_sk
WHERE pol.supplier_sk IS NOT NULL AND s.supplier_sk IS NULL;

-- check: pol_product_fk_orphan | severity: error
SELECT pol.* FROM ${catalog}.${procurement_schema}.purchase_order_line pol
LEFT JOIN ${catalog}.${product_schema}.product p ON pol.product_sk = p.product_sk
WHERE pol.product_sk IS NOT NULL AND p.product_sk IS NULL;

-- check: pol_store_fk_orphan | severity: error
SELECT pol.* FROM ${catalog}.${procurement_schema}.purchase_order_line pol
LEFT JOIN ${catalog}.${store_schema}.store st ON pol.store_sk = st.store_sk
WHERE pol.store_sk IS NOT NULL AND st.store_sk IS NULL;

-- check: pol_quantities_nonnegative | severity: error
SELECT * FROM ${catalog}.${procurement_schema}.purchase_order_line
WHERE ordered_qty < 0 OR received_qty < 0 OR defective_qty < 0 OR returned_qty < 0;

-- check: pol_received_not_over_ordered | severity: error
-- No over-delivery, so fill_rate stays within [0, 1].
SELECT * FROM ${catalog}.${procurement_schema}.purchase_order_line
WHERE received_qty > ordered_qty;

-- check: pol_status_domain | severity: error
SELECT * FROM ${catalog}.${procurement_schema}.purchase_order_line
WHERE order_status IS NOT NULL
  AND order_status NOT IN ('open', 'received', 'closed', 'cancelled');

-- check: pol_calendar_coverage | severity: error
-- Every order_date must exist in the fiscal calendar (needed for the period grain).
SELECT pol.order_date FROM ${catalog}.${procurement_schema}.purchase_order_line pol
LEFT JOIN ${catalog}.${calendar_schema}.fiscal_calendar c ON pol.order_date = c.date_key
WHERE c.date_key IS NULL
GROUP BY pol.order_date;

-- check: pol_single_reporting_currency | severity: error
-- Prices are normalized to the base currency; currency_code must be constant.
SELECT COUNT(DISTINCT currency_code) AS distinct_currencies
FROM ${catalog}.${procurement_schema}.purchase_order_line
HAVING COUNT(DISTINCT currency_code) > 1;
