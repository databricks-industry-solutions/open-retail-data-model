-- ============================================================
-- ORDM · Outcome Package · Actionable Customer Understanding
-- Metric View: product_affinity
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-08-30
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-30
-- ============================================================
-- Governed semantic surface over gold_customer_product_affinity: customer -> product
-- affinity reach and strength, sliced by product category / brand, the affinity driver,
-- and a coarse affinity band. For Genie / AI-BI ("how many customers have a HIGH affinity
-- to Coffee?", "average purchase-history affinity by brand"). No person-level PII — the
-- source keys on the pseudonymous profile_id, and this view exposes only durable product
-- attributes + counts.
--
-- SCOPE: this metric view governs the CUSTOMER×PRODUCT surface, where affinity_score /
-- recency_weight are per-row values a ratio-of-sums mean is well-defined over. The pairwise
-- market-basket surface (gold_product_affinity_pairwise) deliberately has NO metric view: its
-- support/confidence/lift are PAIR-LEVEL and NON-ADDITIVE (averaging lifts is not meaningful),
-- so it is consumed directly — ranked / looked up by key (sample-queries 10-11/14-15, the
-- notebook template) — not aggregated through a semantic layer.
--
-- SOURCED FROM THE GOLD AFFINITY SURFACE (one row per customer × product), so every
-- dimension is a DURABLE attribute (category / subcategory / brand / driver / band) and
-- never a version-specific SCD2 `_sk` (§A.16 — a metric view must not expose a bare SCD2
-- surrogate as a dimension). Rates/means are RATIO-OF-SUMS (SUM(x)/COUNT(*)) so they
-- re-aggregate correctly at any grain; a pre-computed per-row average could not.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${acu_schema}.mv_product_affinity
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Customer→product affinity reach and strength by category / brand / driver / band: how many customers and products carry an affinity, their average purchase-history affinity score and recency weight, and the units/spend behind them. Means are ratio-of-sums and re-aggregate at any grain."
source: |
  SELECT
    profile_id,
    product_id,
    category,
    subcategory,
    brand,
    primary_driver,
    affinity_band,
    affinity_score,
    recency_weight,
    total_units,
    total_net_amount
  FROM ${catalog}.${acu_schema}.gold_customer_product_affinity

fields:
  - name: category
    expr: category
    display_name: "Category"
    comment: "Product merchandising category (durable current label)."
    synonyms: ["product_category", "department"]
  - name: subcategory
    expr: subcategory
    display_name: "Subcategory"
    comment: "Product merchandising subcategory (durable current label)."
    synonyms: ["product_subcategory"]
  - name: brand
    expr: brand
    display_name: "Brand"
    comment: "Product brand (durable current label)."
    synonyms: ["product_brand", "label"]
  - name: primary_driver
    expr: primary_driver
    display_name: "Affinity Driver"
    comment: "What the affinity is derived from. v1 is always PURCHASE_HISTORY; browse-behavior and latent/embedding (ML) drivers are a documented follow-on."
    synonyms: ["driver", "affinity_source", "signal"]
  - name: affinity_band
    expr: affinity_band
    display_name: "Affinity Band"
    comment: "Coarse affinity strength bucket: high (>= 0.6) / medium (>= 0.2) / low."
    synonyms: ["affinity_tier", "strength_band"]

measures:
  - name: customer_product_pairs
    expr: COUNT(*)
    display_name: "Customer-Product Pairs"
    comment: "Count of (customer × product) affinity rows. Additive over the dimensions."
    synonyms: ["affinity_pairs", "pairs"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
  - name: distinct_customers
    expr: COUNT(DISTINCT profile_id)
    display_name: "Customers with Affinity"
    comment: "Distinct customers carrying an affinity on the selected slice (keyed on the durable pseudonymous profile_id)."
    synonyms: ["customers", "reach", "audience_size"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
  - name: distinct_products
    expr: COUNT(DISTINCT product_id)
    display_name: "Products with Affinity"
    comment: "Distinct products carrying an affinity on the selected slice."
    synonyms: ["products", "sku_reach"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
  - name: avg_affinity_score
    expr: SUM(affinity_score) / NULLIF(COUNT(*), 0)
    display_name: "Average Affinity Score"
    comment: "Mean purchase-history affinity score (0..1). Ratio-of-sums, so it re-aggregates at any grain."
    synonyms: ["mean_affinity", "affinity_strength"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 4
  - name: avg_recency_weight
    expr: SUM(recency_weight) / NULLIF(COUNT(*), 0)
    display_name: "Average Recency Weight"
    comment: "Mean recency-decay weight (0..1) across the affinity rows. Ratio-of-sums."
    synonyms: ["mean_recency", "recency"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 4
  - name: total_affinity_units
    expr: SUM(total_units)
    display_name: "Units Behind Affinity"
    comment: "Total units purchased across the affinity rows on the slice."
    synonyms: ["units", "quantity"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
  - name: total_affinity_spend
    expr: SUM(total_net_amount)
    display_name: "Spend Behind Affinity"
    comment: "Total net spend behind the affinity rows on the slice, in the reporting/base currency."
    synonyms: ["spend", "revenue", "net_amount"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 2
$$;
