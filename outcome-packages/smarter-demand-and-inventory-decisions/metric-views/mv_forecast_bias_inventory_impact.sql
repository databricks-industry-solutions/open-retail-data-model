-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- Metric View: mv_forecast_bias_inventory_impact
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-07-21
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${sdi_schema}.mv_forecast_bias_inventory_impact
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Implied inventory and lost-sales impact from forecast bias."
source: >
  SELECT ih.abc_class, ih.xyz_class, ih.product_id, ih.store_id,
         ih.inventory_value, ih.forecast_bias_pct,
         ih.inventory_value * COALESCE(ih.forecast_bias_pct, 0) / 100 AS bias_inventory_impact
  FROM ${catalog}.${sdi_schema}.gold_inventory_health ih
fields:
  - name: abc_class
    expr: abc_class
    display_name: "ABC Class"
    comment: "Volume tier A/B/C."
    synonyms: ['volume_tier', 'abc']
  - name: xyz_class
    expr: xyz_class
    display_name: "XYZ Class"
    comment: "Variability tier X/Y/Z."
    synonyms: ['variability_tier', 'xyz']
  - name: product_id
    expr: product_id
    display_name: "Product ID"
    comment: "Product business key."
    synonyms: ['sku', 'item_id', 'product']
  - name: store_id
    expr: store_id
    display_name: "Store ID"
    comment: "Store business key."
    synonyms: ['location_id', 'site', 'store']

measures:
  - name: total_bias_impact
    expr: SUM(bias_inventory_impact)
    display_name: "Total Bias Impact"
    comment: "Sum of bias-driven inventory value impact, reporting currency."
    synonyms: ['bias_dollar_impact', 'bias_exposure']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2
  - name: total_inventory_value
    expr: SUM(inventory_value)
    display_name: "Total Inventory Value"
    comment: "Total on-hand inventory value, reporting currency."
    synonyms: ['inventory_value', 'stock_value']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2
  - name: weighted_bias_pct
    expr: SUM(forecast_bias_pct * inventory_value) / NULLIF(SUM(inventory_value), 0)
    display_name: "Weighted Bias %"
    comment: "Inventory-value-weighted forecast bias: SUM(bias x inventory_value) / SUM(inventory_value). A ratio of sums, not a mean of per-row percentages — consistent with the A6 ratio-of-sums convention in the other governed metric views. Weighting by inventory value ties bias to the exposure it drives in this impact view."
    synonyms: ['weighted_bias', 'forecast_bias', 'mean_bias']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2
$$;
