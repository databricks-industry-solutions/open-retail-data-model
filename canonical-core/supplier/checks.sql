-- ============================================================
-- ORDM · Canonical Core · Supplier domain · data-quality checks
-- Version: 0.5 · Generated: 2026-06-09 · LLM-generated: true · Reviewed: 2026-06-09
-- Each assertion SELECTs violating rows; 0 rows = PASS.
-- ============================================================

-- check: supplier_keys_not_null | severity: error
SELECT * FROM ${catalog}.${supplier_schema}.supplier
WHERE supplier_sk IS NULL OR supplier_id IS NULL OR is_current IS NULL;

-- check: supplier_business_key_unique_current | severity: error
SELECT supplier_id, COUNT(*) AS current_versions
FROM ${catalog}.${supplier_schema}.supplier
WHERE is_current = true
GROUP BY supplier_id
HAVING COUNT(*) > 1;

-- check: supplier_type_domain | severity: error
SELECT * FROM ${catalog}.${supplier_schema}.supplier
WHERE supplier_type IS NOT NULL
  AND supplier_type NOT IN ('manufacturer', 'distributor', 'wholesaler', 'importer', 'broker');

-- check: supplier_status_domain | severity: error
SELECT * FROM ${catalog}.${supplier_schema}.supplier
WHERE supplier_status IS NOT NULL
  AND supplier_status NOT IN ('active', 'inactive', 'suspended');

-- check: supplier_country_code_iso | severity: warn
SELECT * FROM ${catalog}.${supplier_schema}.supplier
WHERE country_code IS NOT NULL AND LENGTH(country_code) <> 2;
