-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Store Operational Risk Scoring — reference template
-- MAGIC
-- MAGIC ORDM · Outcome Package · Predictive Operations · Store Performance · Version 0.5
-- MAGIC
-- MAGIC Reference implementation of the **Observe → Detect → Predict → Diagnose → Act → Measure**
-- MAGIC loop for the Store Operational Risk Score. It shows the honest hand-off between what the
-- MAGIC *data model* ships and what an *adopter's model* adds:
-- MAGIC
-- MAGIC - **The DDL ships (heuristic):** `gold_store_operational_risk` computes a transparent,
-- MAGIC   expert-weighted index (0-100) from four data-backed domain sub-scores. This notebook's
-- MAGIC   first path simply snapshots that view into the append-only `store_risk_score` fact with
-- MAGIC   `score_method = 'heuristic'`.
-- MAGIC - **An adopter adds (model):** the second path is a **stub** showing where a fitted model
-- MAGIC   would read the same conformed feature columns, produce a *calibrated probability* and a
-- MAGIC   *dollar impact*, and write rows with `score_method = 'model'`, `model_version`, and
-- MAGIC   `predicted_impact_amount`. ORDM trains and serves no models — that stays the adopter's
-- MAGIC   tooling (ADR 0028, ADR 0016 adopter-managed lifecycle).
-- MAGIC
-- MAGIC Treat this as a starting point to adapt, not a managed pipeline. It is declarative and
-- MAGIC idempotent; it writes nothing unless you run the final MERGE/INSERT cells. Parameters use
-- MAGIC the same `${...}` tokens as the DDL (`catalog`, `predops_schema`). Set them via widgets or
-- MAGIC `spark.conf`.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 1. Observe / Detect / Predict — snapshot the heuristic score
-- MAGIC The shipped `gold_store_operational_risk` view already Observes the leading indicators,
-- MAGIC Detects abnormal domains (per-domain sub-scores), and produces the heuristic composite +
-- MAGIC tier. This view stages one snapshot row per store for a given `as_of_date`.

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _heuristic_snapshot AS
SELECT
  -- Business key is unique at the table grain (store x as_of_date x score_method),
  -- so a later score_method='model' row does not collide with this heuristic row.
  concat_ws('|', store_id, CAST(as_of_date AS STRING), 'heuristic') AS store_risk_score_id,
  store_sk,
  store_id,
  as_of_date,
  horizon_days,
  operational_risk_score,
  operational_risk_tier,
  domains_scored,
  top_risk_domains,
  inventory_risk,
  supply_chain_risk,
  sales_margin_risk,
  equipment_risk,
  labor_risk,              -- from gold_labor_risk when labor domain is present (ADR 0043)
  cx_risk,                 -- NULL until CX source lands (deferred)
  'heuristic'                       AS score_method,
  CAST(NULL AS STRING)              AS model_version,
  CAST(NULL AS DECIMAL(18,2))       AS predicted_impact_amount,
  CAST(NULL AS STRING)              AS currency_code,
  'notebook:store_risk_scoring'     AS record_source,
  CURRENT_TIMESTAMP()               AS load_timestamp
FROM ${catalog}.${predops_schema}.gold_store_operational_risk;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2. Persist the heuristic snapshot (append-only)
-- MAGIC The fact is append-only, keyed at store × as_of_date × score_method. MERGE keeps a
-- MAGIC re-run for the same day idempotent instead of appending duplicates. Uncomment to write.

-- COMMAND ----------

-- MERGE INTO ${catalog}.${predops_schema}.store_risk_score AS t
-- USING _heuristic_snapshot AS s
--   ON  t.store_id = s.store_id
--   AND t.as_of_date = s.as_of_date
--   AND t.score_method = s.score_method
-- WHEN NOT MATCHED THEN INSERT (
--   store_risk_score_id, store_sk, store_id, as_of_date, horizon_days,
--   operational_risk_score, operational_risk_tier, domains_scored, top_risk_domains,
--   inventory_risk, supply_chain_risk, sales_margin_risk, equipment_risk, labor_risk, cx_risk,
--   score_method, model_version, predicted_impact_amount, currency_code,
--   record_source, load_timestamp
-- ) VALUES (
--   s.store_risk_score_id, s.store_sk, s.store_id, s.as_of_date, s.horizon_days,
--   s.operational_risk_score, s.operational_risk_tier, s.domains_scored, s.top_risk_domains,
--   s.inventory_risk, s.supply_chain_risk, s.sales_margin_risk, s.equipment_risk, s.labor_risk, s.cx_risk,
--   s.score_method, s.model_version, s.predicted_impact_amount, s.currency_code,
--   s.record_source, s.load_timestamp
-- );

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3. (Adopter, optional) Predict with a model — STUB
-- MAGIC This is where a *fitted* model replaces the heuristic. The point of ORDM's honesty
-- MAGIC contract: the conformed feature columns are the same ones the heuristic reads, so a model
-- MAGIC is a drop-in that populates the reserved columns without any schema change.
-- MAGIC
-- MAGIC ```python
-- MAGIC # PYTHON (illustrative — not runnable as-is; requires labeled outcome history + a trained model)
-- MAGIC features = spark.table(f"{catalog}.{predops_schema}.gold_store_operational_risk") \
-- MAGIC     .select("store_id", "as_of_date",
-- MAGIC             "inventory_risk", "supply_chain_risk", "sales_margin_risk", "equipment_risk")
-- MAGIC
-- MAGIC import mlflow
-- MAGIC model = mlflow.pyfunc.load_model("models:/store_operational_risk/Production")
-- MAGIC scored = model.predict(features)   # -> calibrated_probability (0-1), predicted_impact_amount
-- MAGIC
-- MAGIC # Convert the calibrated probability to the shared 0-100 index scale, set the honesty
-- MAGIC # columns, and write rows with score_method = 'model' + a real model_version. Only NOW is
-- MAGIC # a probability defensible — it is backed by a validated model, not threshold math.
-- MAGIC (scored
-- MAGIC   .withColumn("operational_risk_score", col("calibrated_probability") * 100)
-- MAGIC   .withColumn("score_method", lit("model"))
-- MAGIC   .withColumn("model_version", lit(model.metadata.workforce_optimization_run_id))
-- MAGIC   .write.mode("append")
-- MAGIC   .saveAsTable(f"{catalog}.{predops_schema}.store_risk_score"))
-- MAGIC ```

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 4. Act / Measure
-- MAGIC Act (the recommended action + expected impact) is **adopter-owned tooling** (ADR 0016
-- MAGIC adopter-managed lifecycle) — ORDM defines the score and the reserved impact column but
-- MAGIC does not execute interventions. Measure closes the loop: after an intervention, compare
-- MAGIC the store's later `store_risk_score` snapshots to confirm the risk fell.

-- COMMAND ----------

SELECT
  store_id,
  as_of_date,
  operational_risk_score,
  operational_risk_tier,
  top_risk_domains
FROM ${catalog}.${predops_schema}.store_risk_score
WHERE score_method = 'heuristic'
ORDER BY store_id, as_of_date;
