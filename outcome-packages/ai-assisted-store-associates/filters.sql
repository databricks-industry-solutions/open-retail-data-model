-- ============================================================
-- ORDM · Outcome Package · AI-Assisted Store Associates
-- Store-scope Unity Catalog row filters (deploy-time template)
-- Version: 0.5
-- Generated: 2026-08-11
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-11
-- ============================================================
-- Defence in depth for Genie / AI/BI / DBSQL readers who bypass the
-- Python lookup policy in tools/associate_realtime_access/.
--
-- NOT applied by tools/apply_model_ddl.py (same deploy-gated pattern as
-- canonical-core/*/masks.sql). Run AFTER gold objects exist. Adopters MUST
-- provision the account groups below (or rewrite the function body to their
-- IdP / HR entitlement source) before SET ROW FILTER.
--
-- Default group convention (replace with your naming):
--   aasa_cross_store          — supervisors / DMs / shared services
--   aasa_store_<store_id>     — associates entitled to that store_id
--
-- Alternate: map current_user() → labor.employee_store_eligibility via an
-- adopter identity bridge (not shipped — IdP linkage is environment-specific).
-- See notebook-templates/store_scope_row_filters.sql.
--
-- After --demote-materialized, inventory/order gold are plain VIEWs: use
-- ALTER VIEW instead of ALTER TABLE for those two objects.
-- ============================================================

CREATE OR REPLACE FUNCTION ${catalog}.${aasa_schema}.associate_store_scope(store_id STRING)
  RETURNS BOOLEAN
  RETURN (
    is_account_group_member('aasa_cross_store')
    OR is_account_group_member(concat('aasa_store_', store_id))
  );

-- Materialized serving surfaces (serving deploy). Demoted demo/CI: ALTER VIEW.
ALTER TABLE ${catalog}.${aasa_schema}.gold_associate_product_inventory_current
  SET ROW FILTER ${catalog}.${aasa_schema}.associate_store_scope ON (store_id);

ALTER TABLE ${catalog}.${aasa_schema}.gold_associate_order_status_current
  SET ROW FILTER ${catalog}.${aasa_schema}.associate_store_scope ON (store_id);

-- Remaining gold (plain views in this package)
ALTER VIEW ${catalog}.${aasa_schema}.gold_associate_price_promotion_current
  SET ROW FILTER ${catalog}.${aasa_schema}.associate_store_scope ON (store_id);

ALTER VIEW ${catalog}.${aasa_schema}.gold_associate_operational_context_current
  SET ROW FILTER ${catalog}.${aasa_schema}.associate_store_scope ON (store_id);

ALTER VIEW ${catalog}.${aasa_schema}.gold_associate_data_freshness
  SET ROW FILTER ${catalog}.${aasa_schema}.associate_store_scope ON (store_id);

-- Extension facts (optional; uncomment if associates query them directly)
-- ALTER TABLE ${catalog}.${aasa_schema}.associate_fulfillment_status
--   SET ROW FILTER ${catalog}.${aasa_schema}.associate_store_scope ON (store_id);
-- ALTER TABLE ${catalog}.${aasa_schema}.associate_context_event
--   SET ROW FILTER ${catalog}.${aasa_schema}.associate_store_scope ON (store_id);
