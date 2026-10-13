-- Databricks notebook source
-- MAGIC %md
-- MAGIC # RFID inventory accuracy walkthrough
-- MAGIC
-- MAGIC This notebook keeps `reconciliation_basis` visible. Only `aligned_eod` rows support
-- MAGIC the inventory-accuracy label; `misaligned` rows are observed-to-book evidence.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 1. Inspect session eligibility and basis

-- COMMAND ----------

SELECT
  store_id,
  trading_date,
  rfid_count_session_id,
  scope_type,
  reconciliation_basis,
  COUNT(*) AS eligible_products,
  SUM(eligible_tagged_units) AS eligible_tagged_units,
  SUM(observed_units) AS observed_units,
  SUM(book_units_eod) AS book_units_eod
FROM ${catalog}.${css_schema}.gold_inventory_accuracy_daily
WHERE trading_date >= current_date() - INTERVAL 7 DAYS
GROUP BY store_id, trading_date, rfid_count_session_id, scope_type, reconciliation_basis
ORDER BY trading_date DESC, store_id, rfid_count_session_id;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2. Publish the headline only from aligned EOD counts
-- MAGIC
-- MAGIC Use the latest daily projection here so repeated sessions do not repeat book stock.

-- COMMAND ----------

SELECT
  store_id,
  reconciliation_date,
  GREATEST(
    0.0,
    1.0 - SUM(absolute_unit_variance) /
      NULLIF(GREATEST(SUM(ABS(book_units_eod)), SUM(observed_units)), 0)
  ) AS inventory_accuracy_pct,
  SUM(CASE WHEN is_phantom_stock THEN 1 ELSE 0 END) AS phantom_stock_products,
  SUM(CASE WHEN is_record_inaccuracy THEN 1 ELSE 0 END) AS inaccurate_products
FROM ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest
WHERE reconciliation_basis = 'aligned_eod'
  AND reconciliation_date >= current_date() - INTERVAL 7 DAYS
GROUP BY store_id, reconciliation_date
ORDER BY reconciliation_date DESC, inventory_accuracy_pct;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3. Keep misaligned sessions as a separate diagnostic

-- COMMAND ----------

SELECT
  store_id,
  trading_date,
  rfid_count_session_id,
  SUM(observed_units) AS observed_units,
  SUM(book_units_eod) AS book_units_eod,
  GREATEST(
    0.0,
    1.0 - SUM(absolute_unit_variance) /
      NULLIF(GREATEST(SUM(ABS(book_units_eod)), SUM(observed_units)), 0)
  ) AS observed_to_book_agreement_pct
FROM ${catalog}.${css_schema}.gold_inventory_accuracy_daily
WHERE reconciliation_basis = 'misaligned'
  AND trading_date >= current_date() - INTERVAL 7 DAYS
GROUP BY store_id, trading_date, rfid_count_session_id
ORDER BY trading_date DESC, store_id;
