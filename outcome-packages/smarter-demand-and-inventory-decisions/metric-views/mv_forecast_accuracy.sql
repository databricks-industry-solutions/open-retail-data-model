-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- Metric View: mv_forecast_accuracy
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-07-21
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${sdi_schema}.mv_forecast_accuracy
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Forecast accuracy by planning unit and ABC/XYZ segment. Error KPIs (WMAPE, bias) are volume-weighted ratios of sums, the retail-standard convention — not a mean of per-row percentages. IMPORTANT: filter to a single grain_type when a deployment populates more than one planning grain (e.g. store_sku AND dc_product), otherwise measures sum across overlapping grains and double-count."
source: >
  SELECT planning_unit_id, forecast_date_key, grain_type, abc_class, xyz_class,
         actual_quantity, forecast_quantity, is_stockout_censored
  FROM ${catalog}.${sdi_schema}.gold_forecast_accuracy
fields:
  - name: planning_unit_id
    expr: planning_unit_id
    display_name: "Planning Unit"
    comment: "Planning unit business key."
    synonyms: ['dfu_id', 'planning_unit', 'forecast_unit']
  - name: forecast_date_key
    expr: forecast_date_key
    display_name: "Forecast Date"
    comment: "Forecast period."
    synonyms: ['period', 'forecast_period', 'week']
  - name: grain_type
    expr: grain_type
    display_name: "Planning Grain"
    comment: "Planning grain of the unit (store_sku, dc_product, account_product_region). Filter to ONE grain before aggregating measures to avoid cross-grain double-counting."
    synonyms: ['planning_grain', 'grain', 'hierarchy_level']
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

measures:
  - name: wmape
    expr: SUM(ABS(actual_quantity - forecast_quantity)) / NULLIF(SUM(ABS(actual_quantity)), 0)
    display_name: "WMAPE"
    comment: "Weighted mean absolute percentage error: SUM(|actual - forecast|) / SUM(|actual|). The retail-standard volume-weighted error; well-defined when individual actuals are zero, unlike per-row MAPE."
    synonyms: ['weighted_mape', 'error_rate', 'wape']
    format:
      type: number
      decimal_places:
        type: exact
        places: 4
  - name: accuracy_pct
    expr: 1 - (SUM(ABS(actual_quantity - forecast_quantity)) / NULLIF(SUM(ABS(actual_quantity)), 0))
    display_name: "Accuracy %"
    comment: "Volume-weighted forecast accuracy (1 - WMAPE), 0-1."
    synonyms: ['forecast_accuracy', 'fit']
    format:
      type: number
      decimal_places:
        type: exact
        places: 4
  - name: weighted_bias_pct
    expr: SUM(forecast_quantity - actual_quantity) / NULLIF(SUM(actual_quantity), 0)
    display_name: "Weighted Bias %"
    comment: "Volume-weighted forecast bias: SUM(forecast - actual) / SUM(actual), a 0-1 fraction. Positive = over-forecast (excess inventory), negative = under-forecast (stockout risk). Named weighted_bias_pct (not bias_pct) to avoid the same-name/different-scale collision with forecast_accuracy.bias_pct, which is whole percentage points."
    synonyms: ['forecast_bias', 'weighted_bias', 'bias_pct']
    format:
      type: number
      decimal_places:
        type: exact
        places: 4
  - name: planning_unit_count
    expr: COUNT(DISTINCT planning_unit_id)
    display_name: "Planning Unit Count"
    comment: "Number of distinct planning units evaluated."
    synonyms: ['dfu_count', 'unit_count']
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
$$;
