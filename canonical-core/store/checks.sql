-- ============================================================
-- ORDM · Canonical Core · Store domain · data-quality checks
-- Version: 0.5 · Generated: 2026-06-09 · LLM-generated: true · Reviewed: 2026-06-09
-- Each assertion SELECTs violating rows; 0 rows = PASS.
-- ============================================================

-- check: store_keys_not_null | severity: error
SELECT * FROM ${catalog}.${store_schema}.store
WHERE store_sk IS NULL OR store_id IS NULL OR is_current IS NULL;

-- check: store_business_key_unique_current | severity: error
SELECT store_id, COUNT(*) AS current_versions
FROM ${catalog}.${store_schema}.store
WHERE is_current = true
GROUP BY store_id
HAVING COUNT(*) > 1;

-- check: store_format_domain | severity: error
SELECT * FROM ${catalog}.${store_schema}.store
WHERE store_format IS NOT NULL
  AND store_format NOT IN ('hypermarket', 'supermarket', 'convenience', 'drugstore', 'online');

-- check: store_status_domain | severity: error
SELECT * FROM ${catalog}.${store_schema}.store
WHERE store_status IS NOT NULL
  AND store_status NOT IN ('active', 'inactive', 'closed');

-- check: store_country_code_iso | severity: warn
SELECT * FROM ${catalog}.${store_schema}.store
WHERE country_code IS NOT NULL AND LENGTH(country_code) <> 2;
