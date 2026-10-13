-- ============================================================
-- ORDM · Canonical Core · Product domain · data-quality checks
-- Version: 0.5 · Generated: 2026-06-09 · LLM-generated: true · Reviewed: 2026-06-09
-- Each assertion SELECTs violating rows; 0 rows = PASS.
-- ============================================================

-- check: product_keys_not_null | severity: error
SELECT * FROM ${catalog}.${product_schema}.product
WHERE product_sk IS NULL OR product_id IS NULL OR is_current IS NULL;

-- check: product_business_key_unique_current | severity: error
SELECT product_id, COUNT(*) AS current_versions
FROM ${catalog}.${product_schema}.product
WHERE is_current = true
GROUP BY product_id
HAVING COUNT(*) > 1;

-- check: product_status_domain | severity: error
SELECT * FROM ${catalog}.${product_schema}.product
WHERE product_status IS NOT NULL
  AND product_status NOT IN ('active', 'inactive', 'discontinued');

-- check: product_uom_domain | severity: error
SELECT * FROM ${catalog}.${product_schema}.product
WHERE unit_of_measure IS NOT NULL
  AND unit_of_measure NOT IN ('each', 'kg', 'g', 'l', 'ml', 'pack');

-- check: product_unit_cost_nonnegative | severity: error
SELECT * FROM ${catalog}.${product_schema}.product
WHERE unit_cost IS NOT NULL AND unit_cost < 0;

-- check: product_unit_cost_below_list_price | severity: warn
-- Cost above list price means a structural loss-leader; surface it for review.
SELECT * FROM ${catalog}.${product_schema}.product
WHERE unit_cost IS NOT NULL AND list_price IS NOT NULL AND unit_cost > list_price;

-- check: product_single_reporting_currency | severity: error
-- The canonical core is single-currency: every monetary column is stored in
-- the base currency, so currency_code must be constant. (transaction_currency_code
-- carries the original sourcing currency and is intentionally NOT constrained.)
SELECT COUNT(DISTINCT currency_code) AS distinct_currencies
FROM ${catalog}.${product_schema}.product
HAVING COUNT(DISTINCT currency_code) > 1;

-- ------------------------------------------------------------
-- product_price (temporal price history)
-- ------------------------------------------------------------

-- check: product_price_keys_not_null | severity: error
SELECT * FROM ${catalog}.${product_schema}.product_price
WHERE product_price_sk IS NULL OR product_price_id IS NULL OR product_id IS NULL
   OR price_type IS NULL OR effective_from_date IS NULL OR is_current IS NULL;

-- check: product_price_type_domain | severity: error
SELECT * FROM ${catalog}.${product_schema}.product_price
WHERE price_type NOT IN ('list', 'cost', 'promotional', 'contract');

-- check: product_price_amount_nonnegative | severity: error
SELECT * FROM ${catalog}.${product_schema}.product_price
WHERE amount IS NOT NULL AND amount < 0;

-- check: product_price_single_current_per_type | severity: error
-- At most one current price per (product, price_type).
SELECT product_id, price_type, COUNT(*) AS current_rows
FROM ${catalog}.${product_schema}.product_price
WHERE is_current = true
GROUP BY product_id, price_type
HAVING COUNT(*) > 1;

-- check: product_price_product_orphan | severity: error
-- Every priced product_id must exist in the product master.
SELECT pp.product_id FROM ${catalog}.${product_schema}.product_price pp
LEFT JOIN (SELECT DISTINCT product_id FROM ${catalog}.${product_schema}.product) p
  ON pp.product_id = p.product_id
WHERE p.product_id IS NULL
GROUP BY pp.product_id;

-- check: product_price_product_sk_orphan | severity: error
-- The declared FK is on the surrogate: every non-null product_sk must exist in the product master.
SELECT pp.* FROM ${catalog}.${product_schema}.product_price pp
LEFT JOIN ${catalog}.${product_schema}.product p ON pp.product_sk = p.product_sk
WHERE pp.product_sk IS NOT NULL AND p.product_sk IS NULL;

-- check: product_price_single_reporting_currency | severity: error
SELECT COUNT(DISTINCT currency_code) AS distinct_currencies
FROM ${catalog}.${product_schema}.product_price
HAVING COUNT(DISTINCT currency_code) > 1;
