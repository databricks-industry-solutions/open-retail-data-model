-- ============================================================
-- ORDM · Deploy · 00_bootstrap_schemas
-- Version: 0.5
-- Generated: 2026-06-10
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-10
-- ============================================================
-- Run FIRST, before the table DDL. Creates one Unity Catalog schema per
-- canonical-core domain and outcome package, and enables PREDICTIVE
-- OPTIMIZATION on each so Databricks runs OPTIMIZE / VACUUM / statistics
-- automatically for the managed Delta tables (the recommended alternative to
-- hand-scheduled maintenance jobs). Catalog/schema names come from the deploy
-- config (databricks.yml variables); never hardcoded.
-- ============================================================

CREATE SCHEMA IF NOT EXISTS ${catalog}.${customer_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${product_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${store_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${calendar_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${transaction_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${marketing_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${order_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${payment_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${supplier_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${procurement_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${promo_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${risk_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${acu_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${dss_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${inventory_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${logistics_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${bmv_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${ac_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${ucv_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${cmn_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${sdi_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${equipment_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${labor_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${predops_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${interaction_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${css_schema};
CREATE SCHEMA IF NOT EXISTS ${catalog}.${aasa_schema};

ALTER SCHEMA ${catalog}.${customer_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${product_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${store_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${calendar_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${transaction_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${marketing_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${order_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${payment_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${supplier_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${procurement_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${promo_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${risk_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${acu_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${dss_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${inventory_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${logistics_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${bmv_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${ac_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${ucv_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${cmn_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${sdi_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${equipment_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${labor_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${predops_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${interaction_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${css_schema} ENABLE PREDICTIVE OPTIMIZATION;
ALTER SCHEMA ${catalog}.${aasa_schema} ENABLE PREDICTIVE OPTIMIZATION;
