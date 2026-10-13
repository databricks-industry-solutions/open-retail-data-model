-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Store-scope row filters — deploy template
-- MAGIC
-- MAGIC ORDM · Outcome Package · AI-Assisted Store Associates · Version 0.5
-- MAGIC
-- MAGIC Applies Unity Catalog row filters so Genie / DBSQL / AI/BI cannot read
-- MAGIC another store's associate gold rows. Complements (does not replace) the
-- MAGIC Python policy in `tools/associate_realtime_access/`.
-- MAGIC
-- MAGIC **Prerequisites**
-- MAGIC 1. Gold DDL applied (`gold_associate_*_current` exist).
-- MAGIC 2. Account groups provisioned for the convention in `filters.sql`
-- MAGIC    (`aasa_cross_store`, `aasa_store_<store_id>`), **or** rewrite the
-- MAGIC    function to your entitlement source.
-- MAGIC 3. Widgets / spark.conf for `${catalog}` and `${aasa_schema}` tokens
-- MAGIC    (same as other ORDM notebooks).
-- MAGIC
-- MAGIC Treat this as adopter-run SQL, not a managed ORDM pipeline.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 1. Create / replace the filter function
-- MAGIC Edit group names to match your IdP before running in production.

-- COMMAND ----------

CREATE OR REPLACE FUNCTION ${catalog}.${aasa_schema}.associate_store_scope(store_id STRING)
  RETURNS BOOLEAN
  RETURN (
    is_account_group_member('aasa_cross_store')
    OR is_account_group_member(concat('aasa_store_', store_id))
  );

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2. Attach filters to gold surfaces
-- MAGIC Serving deploy (real MVs): `ALTER TABLE` on inventory + order.
-- MAGIC Demo / `--demote-materialized`: switch those two to `ALTER VIEW`.

-- COMMAND ----------

ALTER TABLE ${catalog}.${aasa_schema}.gold_associate_product_inventory_current
  SET ROW FILTER ${catalog}.${aasa_schema}.associate_store_scope ON (store_id);

ALTER TABLE ${catalog}.${aasa_schema}.gold_associate_order_status_current
  SET ROW FILTER ${catalog}.${aasa_schema}.associate_store_scope ON (store_id);

ALTER VIEW ${catalog}.${aasa_schema}.gold_associate_price_promotion_current
  SET ROW FILTER ${catalog}.${aasa_schema}.associate_store_scope ON (store_id);

ALTER VIEW ${catalog}.${aasa_schema}.gold_associate_operational_context_current
  SET ROW FILTER ${catalog}.${aasa_schema}.associate_store_scope ON (store_id);

ALTER VIEW ${catalog}.${aasa_schema}.gold_associate_data_freshness
  SET ROW FILTER ${catalog}.${aasa_schema}.associate_store_scope ON (store_id);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3. Optional — labor eligibility bridge (adopter pattern)
-- MAGIC If associates are not in `aasa_store_*` groups, replace the function body
-- MAGIC with a `current_user()` → employee_id → `employee_store_eligibility` join
-- MAGIC after you map UC principals to `labor.employee`. ORDM does not ship that
-- MAGIC identity bridge (IdP-specific). Sketch:
-- MAGIC
-- MAGIC ```sql
-- MAGIC -- CREATE OR REPLACE FUNCTION ...associate_store_scope(store_id STRING)
-- MAGIC -- RETURNS BOOLEAN
-- MAGIC -- RETURN EXISTS (
-- MAGIC --   SELECT 1
-- MAGIC --   FROM ${catalog}.${labor_schema}.employee e
-- MAGIC --   JOIN ${catalog}.${labor_schema}.employee_store_eligibility ese
-- MAGIC --     ON ese.employee_id = e.employee_id AND ese.is_current = TRUE
-- MAGIC --   WHERE e.is_current = TRUE
-- MAGIC --     AND e.employee_id = <your_principal_to_employee_map>(current_user())
-- MAGIC --     AND ese.store_id = store_id
-- MAGIC -- ) OR is_account_group_member('aasa_cross_store');
-- MAGIC ```

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 4. Smoke check
-- MAGIC As a store-scoped principal, `SELECT DISTINCT store_id FROM ...inventory_current`
-- MAGIC should return only entitled stores. As `aasa_cross_store`, all stores.

-- COMMAND ----------

SELECT 'attach complete — verify with a store-scoped principal' AS status;
