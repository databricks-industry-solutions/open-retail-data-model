-- ============================================================
-- ORDM · Canonical Core · Payment domain · data-quality checks
-- Version: 0.5 · Generated: 2026-06-10 · LLM-generated: true · Reviewed: 2026-06-10
-- Each assertion SELECTs violating rows; 0 rows = PASS.
-- ============================================================

-- check: payment_keys_not_null | severity: error
SELECT * FROM ${catalog}.${payment_schema}.payment
WHERE payment_sk IS NULL OR payment_id IS NULL OR profile_id IS NULL
   OR payment_type IS NULL OR amount IS NULL;

-- check: payment_id_unique | severity: error
SELECT payment_id, COUNT(*) AS rows
FROM ${catalog}.${payment_schema}.payment
GROUP BY payment_id
HAVING COUNT(*) > 1;

-- check: payment_type_domain | severity: error
SELECT * FROM ${catalog}.${payment_schema}.payment
WHERE payment_type NOT IN ('sale', 'refund', 'adjustment', 'chargeback');

-- check: payment_method_domain | severity: error
SELECT * FROM ${catalog}.${payment_schema}.payment
WHERE payment_method IS NOT NULL
  AND payment_method NOT IN ('card', 'cash', 'wallet', 'bank_transfer', 'gift_card', 'voucher');

-- check: payment_status_domain | severity: error
SELECT * FROM ${catalog}.${payment_schema}.payment
WHERE payment_status IS NOT NULL
  AND payment_status NOT IN ('authorized', 'captured', 'settled', 'declined', 'refunded', 'voided');

-- check: payment_amount_nonnegative | severity: error
-- amount is a magnitude; direction is carried by payment_type.
SELECT * FROM ${catalog}.${payment_schema}.payment
WHERE amount < 0;

-- check: payment_profile_businesskey_orphan | severity: error
SELECT p.payment_id FROM ${catalog}.${payment_schema}.payment p
LEFT JOIN (SELECT DISTINCT profile_id FROM ${catalog}.${customer_schema}.profile) c
  ON p.profile_id = c.profile_id
WHERE c.profile_id IS NULL
GROUP BY p.payment_id;

-- check: payment_order_orphan | severity: warn
-- Most payments settle a known order; adjustments may not, so this is a warning.
SELECT p.order_id FROM ${catalog}.${payment_schema}.payment p
LEFT JOIN (SELECT DISTINCT order_id FROM ${catalog}.${order_schema}.customer_order_line) o
  ON p.order_id = o.order_id
WHERE p.order_id IS NOT NULL AND o.order_id IS NULL
GROUP BY p.order_id;

-- check: payment_single_reporting_currency | severity: error
SELECT COUNT(DISTINCT currency_code) AS distinct_currencies
FROM ${catalog}.${payment_schema}.payment
HAVING COUNT(DISTINCT currency_code) > 1;
