-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- Metric View: mv_lost_sales
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-07-21
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${sdi_schema}.mv_lost_sales
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Lost sales units and revenue from out-of-stock episodes."
source: >
  SELECT category, oos_cause, fiscal_week_id, total_lost_units, total_lost_revenue, oos_event_count
  FROM ${catalog}.${sdi_schema}.gold_lost_sales_summary
fields:
  - name: category
    expr: category
    display_name: "Category"
    comment: "Product category."
    synonyms: ['product_category', 'merch_category']
  - name: oos_cause
    expr: oos_cause
    display_name: "OOS Cause"
    comment: "Root cause of the stockout."
    synonyms: ['stockout_cause', 'root_cause']
  - name: fiscal_week_id
    expr: fiscal_week_id
    display_name: "Fiscal Week"
    comment: "Fiscal week identifier (YYYYWW)."
    synonyms: ['week', 'fiscal_period', 'period']

measures:
  - name: total_lost_units
    expr: SUM(total_lost_units)
    display_name: "Lost Units"
    comment: "Total estimated lost units."
    synonyms: ['lost_volume', 'missed_units']
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
  - name: total_lost_revenue
    expr: SUM(total_lost_revenue)
    display_name: "Lost Revenue"
    comment: "Total estimated lost revenue, reporting currency."
    synonyms: ['lost_sales_dollars', 'revenue_at_risk']
    format:
      type: number
      decimal_places:
        type: exact
        places: 2
  - name: total_oos_events
    expr: SUM(oos_event_count)
    display_name: "OOS Events"
    comment: "Number of out-of-stock episodes."
    synonyms: ['stockout_events', 'oos_count']
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
$$;
