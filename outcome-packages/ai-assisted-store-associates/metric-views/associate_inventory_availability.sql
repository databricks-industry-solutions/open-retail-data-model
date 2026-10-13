-- ============================================================
-- ORDM · Outcome Package · AI-Assisted Store Associates
-- Metric View: associate_inventory_availability
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-08-11
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-11
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${aasa_schema}.mv_associate_inventory_availability
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Associate-facing product availability KPIs by store and stock status."
source: >
  SELECT
    store_id,
    store_name,
    product_id,
    product_name,
    stock_status,
    freshness_status,
    quantity_on_hand,
    quantity_available_to_sell,
    quantity_reserved,
    quantity_in_transit
  FROM ${catalog}.${aasa_schema}.gold_associate_product_inventory_current

fields:
  - name: store_id
    expr: store_id
    display_name: "Store ID"
    comment: "Durable store business key for the associate store scope."
    synonyms: ["location_id", "store"]

  - name: store_name
    expr: store_name
    display_name: "Store Name"
    comment: "Current store name from the conformed store master."
    synonyms: ["location_name"]

  - name: product_id
    expr: product_id
    display_name: "Product ID"
    comment: "Durable product business key (SKU/item)."
    synonyms: ["SKU", "item_id"]

  - name: product_name
    expr: product_name
    display_name: "Product Name"
    comment: "Current product name from the conformed product master."
    synonyms: ["item_name", "sku_name"]

  - name: stock_status
    expr: stock_status
    display_name: "Stock Status"
    comment: "IN_STOCK, LOW_STOCK, OUT_OF_STOCK, or UNKNOWN."
    synonyms: ["availability_status", "inventory_status"]

  - name: freshness_status
    expr: freshness_status
    display_name: "Freshness Status"
    comment: "Lag band for event overlays; calendar age of date_key for daily snapshots."
    synonyms: ["data_freshness"]

measures:
  - name: quantity_on_hand
    expr: SUM(quantity_on_hand)
    display_name: "On Hand"
    comment: "On-hand units before reservations."
    synonyms: ["on_hand_units"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 0

  - name: quantity_available_to_sell
    expr: SUM(quantity_available_to_sell)
    display_name: "Available to Sell"
    comment: "Available-to-sell units after reservations."
    synonyms: ["ATS", "available_units"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 0

  - name: out_of_stock_skus
    expr: COUNT(*) FILTER (WHERE stock_status = 'OUT_OF_STOCK')
    display_name: "Out of Stock SKUs"
    comment: "Product-store rows currently at OUT_OF_STOCK."
    synonyms: ["oos_count"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 0

  - name: low_stock_skus
    expr: COUNT(*) FILTER (WHERE stock_status = 'LOW_STOCK')
    display_name: "Low Stock SKUs"
    comment: "Product-store rows currently at LOW_STOCK."
    synonyms: ["low_stock_count"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
$$;
