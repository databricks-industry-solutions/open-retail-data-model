-- ============================================================
-- ORDM · Outcome Package · Early Risk Detection
-- Metric View: stockout_risk
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-06-30
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-02 by @sreekanthmunigati
-- ============================================================
-- Stockout risk summary aggregated by product and store. Highlights
-- items currently stocked out or at critical days-of-supply, with
-- in-transit visibility to assess whether replenishment is en route.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${risk_schema}.mv_stockout_risk
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Stockout risk summary highlighting products at critical or stocked-out inventory levels, with in-transit replenishment visibility."
source: >
  SELECT
    ir.product_id,
    ir.product_sk,
    p.product_name,
    p.category,
    ir.store_id,
    ir.store_sk,
    st.store_name,
    ir.snapshot_date,
    ir.units_on_hand_eod,
    ir.units_in_transit,
    ir.avg_daily_sales,
    ir.days_of_supply,
    ir.days_of_supply_with_transit,
    ir.stockout_risk_score,
    ir.inventory_risk_tier,
    ir.is_stockout,
    (ir.units_in_transit > 0 AND ir.inventory_risk_tier IN ('critical', 'stockout')) AS is_replenishment_pending,
    CASE
      WHEN ir.avg_daily_sales > 0 AND ir.is_stockout = FALSE
        THEN ROUND(ir.units_on_hand_eod / ir.avg_daily_sales, 1)
      ELSE 0
    END AS est_days_to_stockout
  FROM ${catalog}.${risk_schema}.gold_inventory_risk ir
  JOIN ${catalog}.${product_schema}.product p
    ON p.product_id = ir.product_id AND p.is_current = TRUE
  JOIN ${catalog}.${store_schema}.store st
    ON st.store_id = ir.store_id AND st.is_current = TRUE
  WHERE ir.inventory_risk_tier IN ('stockout', 'critical', 'at_risk')

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
    synonyms: ["location_id", "site"]

  - name: store_name
    expr: store_name
    display_name: "Store Name"
    comment: "Display name of the store."
    synonyms: ["location_name", "site_name"]

  - name: inventory_risk_tier
    expr: inventory_risk_tier
    display_name: "Risk Tier"
    comment: "Inventory risk classification: stockout, critical, at_risk."
    synonyms: ["risk_level", "risk_category", "inventory_status"]

  - name: is_replenishment_pending
    expr: is_replenishment_pending
    display_name: "Replenishment Pending"
    comment: "Whether in-transit stock exists that could resolve a critical or stockout situation."
    synonyms: ["has_inbound", "replenishment_flag"]

measures:
  - name: at_risk_count
    expr: COUNT(*)
    display_name: "At-Risk Positions"
    comment: "Number of product-store positions at stockout, critical, or at_risk tier."
    synonyms: ["risk_count", "flagged_positions"]

  - name: stockout_count
    expr: COUNT(*) FILTER (WHERE is_stockout = TRUE)
    display_name: "Stockout Count"
    comment: "Number of product-store positions currently stocked out."
    synonyms: ["OOS_count", "out_of_stock_count"]

  - name: critical_count
    expr: COUNT(*) FILTER (WHERE inventory_risk_tier = 'critical')
    display_name: "Critical Count"
    comment: "Number of product-store positions at critical days-of-supply."
    synonyms: ["critical_positions"]

  - name: avg_stockout_risk_score
    expr: AVG(stockout_risk_score)
    display_name: "Avg Risk Score"
    comment: "Average stockout risk score (0-100) across at-risk positions."
    synonyms: ["mean_risk_score", "risk_index"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 0

  - name: avg_days_of_supply
    expr: AVG(days_of_supply)
    display_name: "Avg Days of Supply"
    comment: "Average days of supply across at-risk positions."
    synonyms: ["mean_DOS", "avg_DOS"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: avg_est_days_to_stockout
    expr: AVG(est_days_to_stockout)
    display_name: "Avg Days to Stockout"
    comment: "Average estimated days until stockout without replenishment."
    synonyms: ["time_to_stockout", "days_remaining"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: replenishment_pending_count
    expr: COUNT(*) FILTER (WHERE is_replenishment_pending = TRUE)
    display_name: "Replenishment Pending"
    comment: "Number of critical/stockout positions with in-transit replenishment."
    synonyms: ["pending_restock", "inbound_count"]

  - name: total_on_hand_units
    expr: SUM(units_on_hand_eod)
    display_name: "Total On-Hand Units"
    comment: "Sum of on-hand units across at-risk positions."
    synonyms: ["stock_on_hand", "SOH"]

  - name: total_in_transit_units
    expr: SUM(units_in_transit)
    display_name: "Total In-Transit Units"
    comment: "Sum of in-transit units for at-risk positions."
    synonyms: ["inbound_units", "transit_stock"]
$$;
