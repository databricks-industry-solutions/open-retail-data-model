-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Product Affinity Recommendations — reference template
-- MAGIC
-- MAGIC ORDM · Outcome Package · Actionable Customer Understanding · Product Affinity · Version 0.5
-- MAGIC
-- MAGIC Reference queries for the two recommendation modalities the Product Affinity capability
-- MAGIC ships, plus the honest hand-off to the ML modality an adopter adds:
-- MAGIC
-- MAGIC - **The DDL ships (derived, no ML):** `gold_product_affinity_pairwise` (rules-based
-- MAGIC   market-basket "frequently bought together": support/confidence/lift, per trailing
-- MAGIC   window) and `gold_customer_product_affinity` (recency-weighted purchase-history
-- MAGIC   affinity per customer × product), with the governed `mv_product_affinity` metric
-- MAGIC   surface. All computed from `customer_order_line` + `product` — no stored affinity
-- MAGIC   table, no synthetic producer.
-- MAGIC - **An adopter adds (model):** the last section is a **stub** showing where semantic /
-- MAGIC   latent recommendations (embeddings + Databricks Vector Search) slot in for the
-- MAGIC   cold-start and discovery cases the rules-based engine cannot serve. ORDM trains and
-- MAGIC   serves no models and stores no vectors — that stays the adopter's tooling, layered on
-- MAGIC   top of these conformed surfaces (mirrors how `agentic-commerce` builds a Vector Search
-- MAGIC   index over a curated gold surface; ADR 0016 adopter-managed lifecycle).
-- MAGIC
-- MAGIC Treat this as a starting point to adapt, not a managed pipeline. Every cell is read-only.
-- MAGIC Parameters use the same `${...}` tokens as the DDL (`catalog`, `acu_schema`); the seed
-- MAGIC product/customer ids below are illustrative — replace them (or wire them to widgets).

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 1. Frequently bought together (rules-based, long-run)
-- MAGIC For a seed product, the strongest `ALL_TIME` associations by lift — the classic
-- MAGIC checkout / product-detail "customers also bought" prompt. `confidence` is directional
-- MAGIC (P(buys B | bought A)); `lift > 1` means a real, above-chance association.

-- COMMAND ----------

SELECT
  product_id_b,
  product_name_b,
  category_b,
  cooccurrence_baskets,
  support,
  confidence,
  lift
FROM ${catalog}.${acu_schema}.gold_product_affinity_pairwise
WHERE product_id_a = 'P1'          -- seed product_id (replace with your own / a widget)
  AND time_window = 'ALL_TIME'
ORDER BY lift DESC, confidence DESC
LIMIT 20;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2. Trailing-window view — what is trending now vs. long-run
-- MAGIC The pairwise view recomputes the rules for `30D` / `90D` / `ALL_TIME` (anchored to the
-- MAGIC latest observed order date, not `current_date`). Comparing a short window to `ALL_TIME`
-- MAGIC surfaces **emerging** cross-sell — pairs rising recently before the all-time view
-- MAGIC catches them — which is the merchandising signal a single all-history rule misses.

-- COMMAND ----------

WITH w30 AS (
  SELECT product_id_a, product_id_b, lift AS lift_30d, cooccurrence_baskets
  FROM ${catalog}.${acu_schema}.gold_product_affinity_pairwise
  WHERE time_window = '30D' AND is_mirrored_pair = FALSE
),
w_all AS (
  SELECT product_id_a, product_id_b, lift AS lift_all_time
  FROM ${catalog}.${acu_schema}.gold_product_affinity_pairwise
  WHERE time_window = 'ALL_TIME' AND is_mirrored_pair = FALSE
)
SELECT
  w30.product_id_a,
  w30.product_id_b,
  w30.cooccurrence_baskets,
  w_all.lift_all_time,
  w30.lift_30d,
  w30.lift_30d - COALESCE(w_all.lift_all_time, 0) AS lift_uplift
FROM w30
LEFT JOIN w_all
  ON w_all.product_id_a = w30.product_id_a AND w_all.product_id_b = w30.product_id_b
WHERE w30.lift_30d > COALESCE(w_all.lift_all_time, 0)
ORDER BY lift_uplift DESC
LIMIT 50;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3. Cross-category cross-sell (undirected)
-- MAGIC Top pairs that span categories, for bundling / adjacency planning. `is_mirrored_pair =
-- MAGIC FALSE` returns each undirected pair once.

-- COMMAND ----------

SELECT
  category_a,
  product_name_a,
  category_b,
  product_name_b,
  cooccurrence_baskets,
  lift
FROM ${catalog}.${acu_schema}.gold_product_affinity_pairwise
WHERE time_window = 'ALL_TIME'
  AND is_mirrored_pair = FALSE
  AND category_a <> category_b
ORDER BY lift DESC
LIMIT 50;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 4. Recommended for you — per-customer purchase-history affinity
-- MAGIC `gold_customer_product_affinity` scores each product a customer has bought by
-- MAGIC repeat-depth × recency decay. Two uses: a personalized feed (top affinities), and a
-- MAGIC **re-purchase reminder** — high-affinity products a customer has not bought recently
-- MAGIC (their own decay has pulled the score down), i.e. a replenishment nudge.
-- MAGIC
-- MAGIC The affinity surface is all-history and carries no `product_status`, so a recommendation
-- MAGIC feed must gate on BUYABLE products itself — both queries join `product`
-- MAGIC (`is_current = TRUE AND product_status = 'active'`) so a discontinued SKU never surfaces.

-- COMMAND ----------

-- Top affinities for one customer (personalized feed) — buyable (active) products only.
SELECT
  a.product_id,
  a.product_name,
  a.category,
  a.purchase_count,
  a.last_purchase_date,
  a.recency_weight,
  a.affinity_score,
  a.affinity_band
FROM ${catalog}.${acu_schema}.gold_customer_product_affinity a
JOIN ${catalog}.${product_schema}.product p
  ON p.product_id = a.product_id AND p.is_current = TRUE AND p.product_status = 'active'
WHERE a.profile_id = 'C1'          -- seed profile_id (replace with your own / a widget)
ORDER BY a.affinity_score DESC
LIMIT 20;

-- COMMAND ----------

-- Re-purchase reminders: habitual products (>= 3 purchases) whose recency weight has decayed,
-- so they are due for a replenishment nudge — buyable (active) products only. Ranked by how
-- habitual, then how overdue.
SELECT
  a.profile_id,
  a.product_id,
  a.product_name,
  a.purchase_count,
  a.days_since_last_purchase,
  a.recency_weight,
  a.affinity_score
FROM ${catalog}.${acu_schema}.gold_customer_product_affinity a
JOIN ${catalog}.${product_schema}.product p
  ON p.product_id = a.product_id AND p.is_current = TRUE AND p.product_status = 'active'
WHERE a.purchase_count >= 3
  AND a.recency_weight < 0.5       -- past the 90-day half-life: overdue vs. the usual cadence
ORDER BY a.purchase_count DESC, a.days_since_last_purchase DESC
LIMIT 200;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 5. Category-level affinity (governed metric surface)
-- MAGIC `mv_product_affinity` is the Genie / AI-BI surface: affinity reach and average strength
-- MAGIC by category / brand / driver / band. Means are ratio-of-sums, so they re-aggregate at
-- MAGIC any grain.

-- COMMAND ----------

SELECT
  category,
  affinity_band,
  MEASURE(distinct_customers)   AS customers_with_affinity,
  MEASURE(distinct_products)    AS products_with_affinity,
  MEASURE(avg_affinity_score)   AS avg_affinity_score,
  MEASURE(total_affinity_spend) AS spend_behind_affinity
FROM ${catalog}.${acu_schema}.mv_product_affinity
GROUP BY category, affinity_band
ORDER BY category, affinity_band;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 6. (Adopter, optional) Semantic / latent recommendations — STUB
-- MAGIC The rules-based engine needs co-purchase history, so it cannot recommend a **brand-new
-- MAGIC product** (cold start) or find **latent similarity** across products never bought
-- MAGIC together. That is the source model's ML vector modality, deliberately **out of the ORDM
-- MAGIC DDL** (Unity Catalog has no `VECTOR` type; on Databricks this is Vector Search synced
-- MAGIC from Delta, not stored pgvector columns). The honesty contract: a model reads the SAME
-- MAGIC conformed surfaces this notebook queries — no schema change is needed.
-- MAGIC
-- MAGIC ```python
-- MAGIC # PYTHON (illustrative — not runnable as-is; requires an embedding model + a synced index)
-- MAGIC from databricks.vector_search.client import VectorSearchClient
-- MAGIC
-- MAGIC # 1. Curate the product surface to embed (name/brand/category/attributes) from the
-- MAGIC #    conformed product master — the same durable product_id these gold views key on.
-- MAGIC products = spark.table(f"{catalog}.product.product").where("is_current = true") \
-- MAGIC     .selectExpr("product_id", "concat_ws(' ', product_name, brand, category, subcategory) AS text")
-- MAGIC
-- MAGIC # 2. Embed (an adopter-chosen model) and sync to a Vector Search index — the ORDM pattern
-- MAGIC #    is to build the index OVER a curated Delta surface, as agentic-commerce does.
-- MAGIC vsc = VectorSearchClient()
-- MAGIC index = vsc.get_index(endpoint_name="ordm", index_name=f"{catalog}.{acu_schema}.product_affinity_vs")
-- MAGIC
-- MAGIC # 3. Similar-items / cold-start: nearest neighbours by cosine distance, then BLEND with the
-- MAGIC #    rules-based lift above (rules where co-purchase history exists, vectors where it does not).
-- MAGIC similar = index.similarity_search(query_text="<new product description>",
-- MAGIC                                   columns=["product_id"], num_results=10)
-- MAGIC ```
-- MAGIC
-- MAGIC Blending strategy is the adopter's: typically rules-based lift where a pair has enough
-- MAGIC co-occurrence history (high confidence), falling back to vector similarity for cold-start
-- MAGIC items and long-tail discovery. Both read the conformed core; neither changes it.
