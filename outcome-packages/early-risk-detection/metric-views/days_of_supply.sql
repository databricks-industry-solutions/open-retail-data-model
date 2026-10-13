-- ============================================================
-- ORDM · Outcome Package · Early Risk Detection
-- Metric View: days_of_supply
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-06-30
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-02 by @sreekanthmunigati
-- ============================================================
-- Days-of-supply and stockout risk metric. Per product x store,
-- shows how many days current inventory will last at the trailing
-- sales rate. Derived from gold_inventory_risk.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${risk_schema}.mv_days_of_supply
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Days-of-supply and stockout risk per product and store. Shows how many days current inventory will last at the trailing sales rate."
source: >
  SELECT
    ir.product_id,
    ir.product_sk,
    p.product_name,
    p.category,
    ir.store_id,
    ir.store_sk,
    ir.snapshot_date,
    ir.units_on_hand_eod,
    ir.units_in_transit,
    ir.avg_daily_sales,
    ir.days_of_supply,
    ir.days_of_supply_with_transit,
    ir.stockout_risk_score,
    ir.inventory_risk_tier,
    ir.is_stockout
  FROM ${catalog}.${risk_schema}.gold_inventory_risk ir
  JOIN ${catalog}.${product_schema}.product p
    ON p.product_id = ir.product_id AND p.is_current = TRUE

fields:
  - name: product_id
    expr: product_id
    display_name: "Product ID"
    comment: "Durable business key for the product."
    synonyms: ["SKU", "item_id", "product"]

  - name: product_name
    expr: product_name
    display_name: "Product Name"
    comment: "Display name of the product."
    synonyms: ["item_name", "product_description"]

  - name: category
    expr: category
    display_name: "Category"
    comment: "Product category."
    synonyms: ["product_category", "department"]

  - name: store_id
    expr: store_id
    display_name: "Store ID"
    comment: "Durable business key for the store."
    synonyms: ["location_id", "store", "site"]

  - name: snapshot_date
    expr: snapshot_date
    display_name: "Snapshot Date"
    comment: "Date of the inventory snapshot."
    synonyms: ["as_of_date", "inventory_date"]
    format:
      type: date
      date_format: year_month_day

  - name: inventory_risk_tier
    expr: inventory_risk_tier
    display_name: "Risk Tier"
    comment: "Inventory risk classification: stockout, critical, at_risk, healthy."
    synonyms: ["risk_level", "risk_category", "inventory_status"]

  - name: is_stockout
    expr: is_stockout
    display_name: "Is Stocked Out"
    comment: "Whether the product is currently stocked out at this store."
    synonyms: ["out_of_stock", "stockout_flag", "OOS"]

measures:
  - name: avg_days_of_supply
    expr: AVG(days_of_supply)
    display_name: "Avg Days of Supply"
    comment: "Average days of supply across products and stores. Lower = higher risk."
    synonyms: ["mean_DOS", "average_DOS", "avg_inventory_days"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: avg_days_of_supply_with_transit
    expr: AVG(days_of_supply_with_transit)
    display_name: "Avg Days of Supply (incl. Transit)"
    comment: "Average days of supply including units in transit."
    synonyms: ["DOS_with_transit", "total_DOS"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: avg_stockout_risk_score
    expr: AVG(stockout_risk_score)
    display_name: "Avg Stockout Risk Score"
    comment: "Average stockout risk score (0-100). Higher = riskier."
    synonyms: ["mean_risk_score", "risk_index"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 0

  - name: total_on_hand_units
    expr: SUM(units_on_hand_eod)
    display_name: "Total On-Hand Units"
    comment: "Sum of end-of-day on-hand units across products and stores."
    synonyms: ["inventory_units", "stock_on_hand", "SOH"]

  - name: total_in_transit_units
    expr: SUM(units_in_transit)
    display_name: "Total In-Transit Units"
    comment: "Sum of units currently in transit."
    synonyms: ["transit_units", "inbound_units"]

  - name: stockout_count
    expr: COUNT(*) FILTER (WHERE is_stockout = TRUE)
    display_name: "Stockout Count"
    comment: "Number of product-store combinations currently stocked out."
    synonyms: ["OOS_count", "out_of_stock_count"]

  - name: product_store_count
    expr: COUNT(*)
    display_name: "Product-Store Count"
    comment: "Number of product-store combinations in the snapshot."
    synonyms: ["position_count", "total_positions"]

  - name: avg_daily_sales_rate
    expr: AVG(avg_daily_sales)
    display_name: "Avg Daily Sales Rate"
    comment: "Average daily sales velocity (units per day)."
    synonyms: ["sales_velocity", "daily_demand"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1
$$;
