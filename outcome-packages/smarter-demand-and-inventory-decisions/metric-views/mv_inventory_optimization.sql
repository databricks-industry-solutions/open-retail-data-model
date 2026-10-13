-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- Metric View: mv_inventory_optimization
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-07-21
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${sdi_schema}.mv_inventory_optimization
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Inventory optimization KPIs with policy targets. Days-of-supply is a portfolio ratio of sums (on-hand / daily sell rate), not a mean of per-SKU ratios."
source: >
  SELECT product_id, store_id, abc_class, inventory_position_status,
         units_on_hand_eod, units_in_transit, avg_daily_sales,
         inventory_value, overstock_quantity
  FROM ${catalog}.${sdi_schema}.gold_inventory_health
fields:
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
  - name: abc_class
    expr: abc_class
    display_name: "ABC Class"
    comment: "Volume tier A/B/C."
    synonyms: ['volume_tier', 'abc']
  - name: inventory_position_status
    expr: inventory_position_status
    display_name: "Status"
    comment: "Inventory health status."
    synonyms: ['health_status', 'stock_status']

measures:
  - name: days_of_supply
    expr: SUM(units_on_hand_eod) / NULLIF(SUM(avg_daily_sales), 0)
    display_name: "Days of Supply"
    comment: "Portfolio days of supply: total on-hand units / total daily sell rate. A ratio of sums (volume-weighted), not a mean of per-SKU ratios."
    synonyms: ['dos', 'days_cover', 'days_of_cover']
    format:
      type: number
      decimal_places:
        type: exact
        places: 1
  - name: days_of_supply_with_transit
    expr: (SUM(units_on_hand_eod) + SUM(COALESCE(units_in_transit, 0))) / NULLIF(SUM(avg_daily_sales), 0)
    display_name: "Days of Supply (incl. Transit)"
    comment: "Portfolio days of supply including in-transit units: (on-hand + in-transit) / total daily sell rate."
    synonyms: ['dos_with_transit', 'total_dos']
    format:
      type: number
      decimal_places:
        type: exact
        places: 1
  - name: total_overstock_units
    expr: SUM(overstock_quantity)
    display_name: "Overstock Units"
    comment: "Total units on hand above policy max across the group (a quantity, not a currency value)."
    synonyms: ['excess_units', 'overstock_quantity']
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
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
$$;
