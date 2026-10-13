-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- Metric View: mv_oos_rate
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-07-21
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${sdi_schema}.mv_oos_rate
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Reactive OOS rate and stockout SKU-day counts by store and category."
source: >
  SELECT store_id, category, fiscal_week_id, stockout_sku_days, total_sku_days
  FROM ${catalog}.${sdi_schema}.gold_oos_rate
fields:
  - name: store_id
    expr: store_id
    display_name: "Store ID"
    comment: "Store business key."
    synonyms: ['location_id', 'site', 'store']
  - name: category
    expr: category
    display_name: "Category"
    comment: "Product category."
    synonyms: ['product_category', 'merch_category']
  - name: fiscal_week_id
    expr: fiscal_week_id
    display_name: "Fiscal Week"
    comment: "Fiscal week identifier (YYYYWW)."
    synonyms: ['week', 'fiscal_period', 'period']

measures:
  - name: oos_rate_pct
    expr: SUM(stockout_sku_days) / NULLIF(SUM(total_sku_days), 0)
    display_name: "OOS Rate %"
    comment: "Out-of-stock rate as a ratio of sums: total stockout SKU-days / total SKU-days (0-1). Volume-weighted, not a mean of per-group rates."
    synonyms: ['stockout_rate', 'oos_rate', 'availability_gap']
    format:
      type: number
      decimal_places:
        type: exact
        places: 4
  - name: total_stockout_sku_days
    expr: SUM(stockout_sku_days)
    display_name: "Stockout SKU-Days"
    comment: "Total stockout SKU-days."
    synonyms: ['oos_sku_days', 'stockout_days']
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
  - name: total_sku_days
    expr: SUM(total_sku_days)
    display_name: "Total SKU-Days"
    comment: "Total product-store-day observations."
    synonyms: ['sku_days', 'observation_days']
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
$$;
