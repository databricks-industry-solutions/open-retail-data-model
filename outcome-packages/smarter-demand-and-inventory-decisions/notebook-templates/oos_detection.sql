-- Databricks notebook source
-- MAGIC %md
-- MAGIC # OOS Detection & Lost-Sales Estimation — reference template
-- MAGIC
-- MAGIC ORDM · Outcome Package · Smarter Demand and Inventory Decisions · Version 0.5
-- MAGIC
-- MAGIC Reference implementation of the detection and lost-sales logic that the design
-- MAGIC (`docs/design/.../03-out-of-stocks-optimization.md`) specifies but the DDL alone cannot
-- MAGIC express. It **derives `oos_event` and `lost_sales_estimate` rows** from canonical
-- MAGIC core (`inventory_position`, `sales`) plus the sibling forecast views. Treat it as a
-- MAGIC starting point to adapt, not a managed pipeline — it is intentionally declarative and
-- MAGIC idempotent (`CREATE OR REPLACE TEMP VIEW`), and writes nothing unless you run the
-- MAGIC final MERGE cells.
-- MAGIC
-- MAGIC Parameters use the same `${...}` tokens as the DDL (`catalog`, `sdi_schema`,
-- MAGIC `inventory_schema`, `transaction_schema`). Set them via widgets or `spark.conf`.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 1. Signal: velocity collapse
-- MAGIC Latest-week units < 50% of the trailing 8-week weekly mean → an *inferred* OOS
-- MAGIC signal (design "velocity collapse"). This never treats stockout-constrained sales as
-- MAGIC true demand — it flags the collapse for promotion to an `oos_event`.

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _velocity_collapse AS
WITH weekly AS (
  SELECT
    s.product_id, s.store_id, fc.fiscal_week_id,
    SUM(s.units) AS units,
    MAX(s.date_key) AS week_end_date
  FROM ${catalog}.${transaction_schema}.sales s
  JOIN ${catalog}.${calendar_schema}.fiscal_calendar fc ON fc.date_key = s.date_key
  GROUP BY s.product_id, s.store_id, fc.fiscal_week_id
),
ranked AS (
  SELECT w.*,
         ROW_NUMBER() OVER (PARTITION BY product_id, store_id ORDER BY fiscal_week_id DESC) AS wk_desc,
         AVG(units) OVER (
           PARTITION BY product_id, store_id ORDER BY fiscal_week_id
           ROWS BETWEEN 8 PRECEDING AND 1 PRECEDING
         ) AS trailing_8wk_mean
  FROM weekly w
)
SELECT product_id, store_id, week_end_date, units, trailing_8wk_mean
FROM ranked
WHERE wk_desc = 1
  AND trailing_8wk_mean IS NOT NULL
  AND units < 0.5 * trailing_8wk_mean;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2. Signal: observed stockout (system on-hand = 0)
-- MAGIC The *observed*, high-confidence signal from core. Collapse consecutive stockout days
-- MAGIC per product×store into an episode with start/end dates and duration.

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _stockout_episodes AS
WITH flagged AS (
  SELECT
    product_sk, product_id, store_sk, store_id, date_key, stockout_pct_day,
    CASE WHEN is_stockout THEN 1 ELSE 0 END AS oos,
    -- island grouping: date minus a dense rank over stockout days is constant per run
    DATE_SUB(date_key,
      DENSE_RANK() OVER (PARTITION BY product_id, store_id ORDER BY date_key)) AS grp
  FROM ${catalog}.${inventory_schema}.inventory_position
  WHERE is_stockout = TRUE
)
SELECT
  product_sk, product_id, store_sk, store_id,
  MIN(date_key) AS oos_start_date_key,
  MAX(date_key) AS oos_end_date_key,
  DATEDIFF(MAX(date_key), MIN(date_key)) + 1 AS oos_duration_days,
  AVG(stockout_pct_day) AS stockout_pct_total
FROM flagged
GROUP BY product_sk, product_id, store_sk, store_id, grp;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3. Assemble `oos_event` candidates
-- MAGIC Combine observed episodes with a `detection_method`. Cause/severity are left to a
-- MAGIC scoring step (or planner review); defaults shown are conservative placeholders — do
-- MAGIC not ship them as truth. `oos_end_date_key` stays NULL while the latest snapshot is
-- MAGIC still stocked out (ongoing episode), matching `gold_oos_current` semantics.

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _oos_event_candidates AS
SELECT
  CONCAT('OOS-', e.product_id, '-', e.store_id, '-', DATE_FORMAT(e.oos_start_date_key, 'yyyyMMdd')) AS oos_event_id,
  e.product_sk, e.product_id, e.store_sk, e.store_id,
  e.oos_start_date_key,
  CASE WHEN latest.max_date = e.oos_end_date_key THEN CAST(NULL AS DATE) ELSE e.oos_end_date_key END AS oos_end_date_key,
  e.oos_duration_days,
  'inventory_snapshot' AS detection_method,
  'unknown'            AS oos_cause,      -- score in a downstream step; see gold_oos_preventability
  'medium'             AS oos_severity,   -- refine with ABC class + promo + duration matrix
  CAST(e.stockout_pct_total AS DECIMAL(5,4)) AS stockout_pct_total
FROM _stockout_episodes e
CROSS JOIN (SELECT MAX(date_key) AS max_date FROM ${catalog}.${inventory_schema}.inventory_position) latest;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 4. Lost-sales estimation (forecast-residual, censoring-aware)
-- MAGIC For each day within an episode, lost units = max(0, expected demand − actual sold),
-- MAGIC where expected demand is the effective forecast (never the stockout-censored actual).
-- MAGIC `lost_revenue` and `lost_margin` value the gap at list price and gross margin.

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _lost_sales_candidates AS
SELECT
  CONCAT('LSE-', c.oos_event_id, '-', DATE_FORMAT(d.date_key, 'yyyyMMdd')) AS lost_sales_estimate_id,
  c.oos_event_id,
  d.date_key AS estimate_date_key,
  COALESCE(sales.units, 0) AS actual_units_sold,
  CAST(COALESCE(ef.effective_forecast_quantity, 0) AS DECIMAL(12,3)) AS expected_units_demand,
  CAST(GREATEST(0, COALESCE(ef.effective_forecast_quantity, 0) - COALESCE(sales.units, 0)) AS DECIMAL(12,3)) AS lost_units,
  'forecast_residual' AS estimation_method,
  TRUE AS censoring_adjusted,
  CAST(GREATEST(0, COALESCE(ef.effective_forecast_quantity, 0) - COALESCE(sales.units, 0)) * p.list_price AS DECIMAL(18,2)) AS lost_revenue,
  CAST(GREATEST(0, COALESCE(ef.effective_forecast_quantity, 0) - COALESCE(sales.units, 0)) * GREATEST(p.list_price - p.unit_cost, 0) AS DECIMAL(18,2)) AS lost_margin
FROM _oos_event_candidates c
JOIN ${catalog}.${product_schema}.product p ON p.product_id = c.product_id AND p.is_current = TRUE
-- expand each episode to its days (bounded by the latest snapshot for ongoing episodes)
JOIN (SELECT MAX(date_key) AS max_date FROM ${catalog}.${inventory_schema}.inventory_position) latest
LATERAL VIEW EXPLODE(SEQUENCE(c.oos_start_date_key, COALESCE(c.oos_end_date_key, latest.max_date))) t AS date_key_seq
JOIN ${catalog}.${calendar_schema}.fiscal_calendar d ON d.date_key = t.date_key_seq
LEFT JOIN ${catalog}.${transaction_schema}.sales sales
  ON sales.product_id = c.product_id AND sales.store_id = c.store_id AND sales.date_key = d.date_key
LEFT JOIN ${catalog}.${sdi_schema}.planning_unit pu
  ON pu.product_id = c.product_id AND pu.store_id = c.store_id AND pu.grain_type = 'store_sku'
LEFT JOIN ${catalog}.${sdi_schema}.gold_effective_forecast ef
  ON ef.planning_unit_sk = pu.planning_unit_sk AND ef.forecast_date_key = d.date_key;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 5. Persist (optional)
-- MAGIC Uncomment to upsert into the extension tables. Business keys make this idempotent.
-- MAGIC Surrogate keys are IDENTITY-generated on insert, so we match on the durable id.

-- COMMAND ----------

-- MERGE INTO ${catalog}.${sdi_schema}.oos_event t
-- USING _oos_event_candidates s ON t.oos_event_id = s.oos_event_id
-- WHEN NOT MATCHED THEN INSERT (oos_event_id, product_sk, product_id, store_sk, store_id,
--   oos_start_date_key, oos_end_date_key, oos_duration_days, detection_method, oos_cause,
--   oos_severity, stockout_pct_total, record_source, load_timestamp)
-- VALUES (s.oos_event_id, s.product_sk, s.product_id, s.store_sk, s.store_id,
--   s.oos_start_date_key, s.oos_end_date_key, s.oos_duration_days, s.detection_method,
--   s.oos_cause, s.oos_severity, s.stockout_pct_total, 'oos_detection_notebook', current_timestamp());

-- COMMAND ----------

-- MAGIC %md
-- MAGIC The `demand_sensing_signal → oos_event` promotion loop (design data-flow edge) follows
-- MAGIC the same pattern: unresolved `_velocity_collapse` rows with no matching observed episode
-- MAGIC become `demand_sensing_signal` records, promoted to `oos_event` once corroborated.
