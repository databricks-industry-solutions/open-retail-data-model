-- ============================================================
-- ORDM · Canonical Core · Marketing domain · data-quality checks
-- Version: 0.5 · Generated: 2026-06-09 · LLM-generated: true · Reviewed: 2026-06-19
-- Each assertion SELECTs violating rows; 0 rows = PASS.
-- ============================================================

-- ---------- promotion ----------

-- check: promotion_keys_not_null | severity: error
SELECT * FROM ${catalog}.${marketing_schema}.promotion
WHERE promo_sk IS NULL OR promo_id IS NULL OR is_current IS NULL;

-- check: promotion_business_key_unique_current | severity: error
SELECT promo_id, COUNT(*) AS current_versions
FROM ${catalog}.${marketing_schema}.promotion
WHERE is_current = true
GROUP BY promo_id
HAVING COUNT(*) > 1;

-- check: promotion_type_domain | severity: error
SELECT * FROM ${catalog}.${marketing_schema}.promotion
WHERE promo_type IS NOT NULL
  AND promo_type NOT IN ('TPR', 'FEATURE', 'DISPLAY', 'FEATURE_AND_DISPLAY', 'BOGO', 'COUPON', 'BUNDLE');

-- check: promotion_funding_type_domain | severity: error
SELECT * FROM ${catalog}.${marketing_schema}.promotion
WHERE funding_type IS NOT NULL
  AND funding_type NOT IN ('OFF_INVOICE', 'BILL_BACK', 'SCAN_DOWN', 'LUMP_SUM');

-- check: promotion_funded_by_domain | severity: error
SELECT * FROM ${catalog}.${marketing_schema}.promotion
WHERE funded_by IS NOT NULL
  AND funded_by NOT IN ('SUPPLIER', 'RETAILER', 'SHARED');

-- check: promotion_date_order | severity: error
-- End date must not precede start date.
SELECT * FROM ${catalog}.${marketing_schema}.promotion
WHERE start_date IS NOT NULL AND end_date IS NOT NULL AND end_date < start_date;

-- check: promotion_supplier_share_range | severity: error
-- supplier_share_pct must be within [0, 100] when present.
SELECT * FROM ${catalog}.${marketing_schema}.promotion
WHERE supplier_share_pct IS NOT NULL AND (supplier_share_pct < 0 OR supplier_share_pct > 100);

-- check: promotion_supplier_share_required | severity: error
-- supplier_share_pct is mandatory unless the retailer funds the whole promotion.
SELECT * FROM ${catalog}.${marketing_schema}.promotion
WHERE funded_by IS NOT NULL AND funded_by <> 'RETAILER' AND supplier_share_pct IS NULL;

-- ---------- audience (segment-definition dimension; promoted from CMN, ADR 0022) ----------

-- check: audience_keys_not_null | severity: error
SELECT * FROM ${catalog}.${marketing_schema}.audience
WHERE audience_sk IS NULL OR audience_id IS NULL OR is_current IS NULL;

-- check: audience_business_key_unique_current | severity: error
-- Exactly one current version per durable audience_id.
SELECT audience_id, COUNT(*) AS current_versions
FROM ${catalog}.${marketing_schema}.audience
WHERE is_current = true
GROUP BY audience_id
HAVING COUNT(*) > 1;

-- check: audience_type_domain | severity: error
SELECT * FROM ${catalog}.${marketing_schema}.audience
WHERE audience_type IS NOT NULL
  AND audience_type NOT IN ('first_party', 'modeled', 'lookalike', 'demographic', 'behavioral', 'contextual', 'retargeting', 'custom');

-- check: audience_origin_domain | severity: error
SELECT * FROM ${catalog}.${marketing_schema}.audience
WHERE audience_origin IS NOT NULL
  AND audience_origin NOT IN ('crm', 'loyalty', 'modeled', 'third_party', 'platform', 'survey');

-- check: audience_segmentation_basis_domain | severity: error
SELECT * FROM ${catalog}.${marketing_schema}.audience
WHERE segmentation_basis IS NOT NULL
  AND segmentation_basis NOT IN ('behavioral', 'value_rfm', 'lifecycle', 'demographic', 'geographic', 'predictive', 'lookalike', 'contextual');

-- check: audience_definition_origin_domain | severity: error
SELECT * FROM ${catalog}.${marketing_schema}.audience
WHERE definition_origin IS NOT NULL
  AND definition_origin NOT IN ('canned', 'custom', 'agent_generated');

-- check: audience_definition_method_domain | severity: error
SELECT * FROM ${catalog}.${marketing_schema}.audience
WHERE definition_method IS NOT NULL
  AND definition_method NOT IN ('rule', 'ml_score', 'imported');

-- check: audience_evaluation_mode_domain | severity: error
SELECT * FROM ${catalog}.${marketing_schema}.audience
WHERE evaluation_mode IS NOT NULL
  AND evaluation_mode NOT IN ('batch', 'streaming', 'edge');

-- check: audience_size_nonnegative | severity: error
SELECT * FROM ${catalog}.${marketing_schema}.audience
WHERE size_estimate IS NOT NULL AND size_estimate < 0;

-- check: audience_scd2_current_open | severity: error
SELECT * FROM ${catalog}.${marketing_schema}.audience
WHERE (is_current = true AND effective_to_date IS NOT NULL) OR (is_current = false AND effective_to_date IS NULL);

-- check: audience_scd2_date_order | severity: error
SELECT * FROM ${catalog}.${marketing_schema}.audience
WHERE effective_to_date IS NOT NULL AND effective_to_date <= effective_from_date;
