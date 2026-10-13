-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- Metric View: assortment_recommendations
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-06-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================
-- Assortment optimization recommendations.
--
-- Definitions (Assortment Optimization):
-- * category: Merchandising category
-- * recommendation: Rule-based assortment action (KEEP / DROP / EXPAND) — deterministic, not ML
-- * sku_count / drop_candidate_sku_count: SKUs total and rule-flagged for delist
-- * total_projected_volume_lift / total_projected_margin_lift_lc / total_cannibalization_drag_lc:
--   per-day scenario totals if every recommendation in the filtered set is applied (heuristic
--   projections; see gold_assortment_optimization)
--
-- RESTORED (after 0.2-beta): the projected-lift and cannibalization measures return, now over computed
-- columns. In 0.1-beta (§15 deprecation note) `avg_projected_volume_lift`, `avg_projected_margin_lift_lc`
-- and `total_cannibalization_drag_lc` were removed because their columns were 100% NULL. The two
-- projected-lift measures come back as SUMs named `total_projected_volume_lift` and
-- `total_projected_margin_lift_lc`: the lifts are additive per-day quantities, so a total is the
-- meaningful roll-up.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${bmv_schema}.mv_assortment_recommendations
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Assortment optimization recommendations."
source: >
  SELECT
    f.product_sk,
    f.store_sk,
    f.product_id,
    f.store_id,
    p.category,
    f.recommendation,
    f.projected_volume_lift,
    f.projected_margin_lift_lc,
    f.cannibalization_drag_lc
  FROM ${catalog}.${bmv_schema}.gold_assortment_optimization f
  LEFT JOIN ${catalog}.${product_schema}.product p ON f.product_sk = p.product_sk

fields:
  - name: product_sk
    expr: product_sk
    comment: "Surrogate key for the product."
  - name: store_sk
    expr: store_sk
    comment: "Surrogate key for the store."
  - name: product_id
    expr: product_id
    comment: "Universal article identifier"
    synonyms: ['sku', 'article_id', 'item_id']
  - name: store_id
    expr: store_id
    comment: "Universal store identifier"
    synonyms: ['location_id', 'branch_id']
  - name: category
    expr: category
    comment: "Product category"
    synonyms: ['department', 'merch_category']
  - name: recommendation
    expr: recommendation
    comment: "Rule-based assortment action (KEEP / DROP / EXPAND)"
    synonyms: ['assortment_action', 'action', 'decision']

measures:
  # ============================================================
  # Goal: Assortment Optimization
  # ============================================================
  - name: sku_count
    expr: count(distinct product_id)
    display_name: "SKU Count"
    comment: "Number of unique SKUs (counts distinct product_ids across the filtered set of stores, as the underlying table is at product x store grain)"
    synonyms: ['unique_items', 'item_count', 'assortment_size']
    format:
      type: number
      decimal_places:
        type: exact
        places: 0

  - name: total_projected_volume_lift
    expr: sum(projected_volume_lift)
    display_name: "Total Projected Volume Lift (units per selling day)"
    comment: "Change in units per selling day, at the baseline rate, if the recommendations are applied: EXPAND adds one facing (space-elasticity response), DROP removes the SKU's own baseline units, KEEP adds 0. Heuristic scenario, not a forecast."
    synonyms: ['projected_units_lift', 'volume_uplift']
    format:
      type: number
      decimal_places:
        type: exact
        places: 3

  - name: total_projected_margin_lift_lc
    expr: sum(projected_margin_lift_lc)
    display_name: "Total Projected Margin Lift (per selling day)"
    comment: "Net gross-margin change per selling day in local currency if the recommendations are applied: own margin change minus cannibalization drag on mapped substitutes. Heuristic scenario, not a forecast."
    synonyms: ['projected_margin_uplift', 'margin_delta']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: total_cannibalization_drag_lc
    expr: sum(cannibalization_drag_lc)
    display_name: "Total Cannibalization Drag (per selling day)"
    comment: "Gross margin per selling day the actions take from mapped substitutes: positive when EXPAND pulls demand from substitutes, negative when a DROP's demand is recaptured by them. Heuristic scenario."
    synonyms: ['cannibalization_impact', 'substitute_margin_drag']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: drop_candidate_sku_count
    expr: count(distinct case when recommendation = 'DROP' then product_id end)
    display_name: "DROP-candidate SKU Count"
    comment: "Unique SKUs the rule flags as DROP candidates (slow mover + weak margin)"
    synonyms: ['delist_candidates', 'drop_skus']
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
$$;
