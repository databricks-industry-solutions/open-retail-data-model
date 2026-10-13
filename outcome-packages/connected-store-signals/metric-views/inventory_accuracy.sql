-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Metric View: inventory_accuracy
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-08-18
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-19
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.mv_inventory_accuracy
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "RFID observed-versus-book reconciliation. Inventory accuracy is restricted to aligned full-store EOD counts; other sessions remain explicitly labeled agreement evidence."
source: ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest

fields:
  - name: store_id
    expr: store_id
    display_name: "Store"
    comment: "Durable store business key."
    synonyms: ["store", "site", "location"]

  - name: product_id
    expr: product_id
    display_name: "Product"
    comment: "Durable product business key."
    synonyms: ["product", "sku", "item"]

  - name: department
    expr: department
    display_name: "Department"
    comment: "Product department resolved from the inventory snapshot's product version."
    synonyms: ["dept", "merchandising_department"]

  - name: category
    expr: category
    display_name: "Category"
    comment: "Product merchandising category."
    synonyms: ["product_category", "merchandising_category"]

  - name: reconciliation_date
    expr: reconciliation_date
    display_name: "Reconciliation Date"
    comment: "EOD inventory snapshot date used by the reconciliation; post-midnight closing counts map to the preceding local date."
    synonyms: ["date", "day", "snapshot_date", "inventory_date"]

  - name: reconciliation_basis
    expr: reconciliation_basis
    display_name: "Reconciliation Basis"
    comment: "aligned_eod supports the inventory-accuracy label; misaligned supports observed-to-book agreement only."
    synonyms: ["basis", "alignment", "count_basis"]

measures:
  - name: reconciled_product_count
    expr: COUNT(*)
    display_name: "Reconciled Product Count"
    comment: "Latest daily product reconciliations in the grouping, one per reconciliation basis."
    synonyms: ["products_counted", "reconciliations"]

  - name: observed_units
    expr: SUM(observed_units) FILTER (WHERE reconciliation_basis = 'aligned_eod')
    display_name: "Observed Units"
    comment: "Distinct serialized units observed in the latest aligned full-store EOD counts."
    synonyms: ["rfid_units", "physical_count", "observed_inventory"]

  - name: book_units
    expr: SUM(book_units_eod) FILTER (WHERE reconciliation_basis = 'aligned_eod')
    display_name: "Book Units EOD"
    comment: "End-of-day book quantity for the latest aligned full-store EOD counts; filtering prevents the same snapshot from being repeated by misaligned evidence."
    synonyms: ["system_units", "ledger_units", "book_inventory"]

  - name: absolute_unit_variance
    expr: SUM(absolute_unit_variance) FILTER (WHERE reconciliation_basis = 'aligned_eod')
    display_name: "Absolute Unit Variance"
    comment: "Sum of absolute observed-versus-book unit differences for aligned full-store EOD counts."
    synonyms: ["count_variance", "inventory_variance", "unit_difference"]

  - name: inventory_accuracy_pct
    expr: GREATEST(0.0, 1.0 - (SUM(absolute_unit_variance) FILTER (WHERE reconciliation_basis = 'aligned_eod') / NULLIF(GREATEST(SUM(ABS(book_units_eod)) FILTER (WHERE reconciliation_basis = 'aligned_eod'), SUM(observed_units) FILTER (WHERE reconciliation_basis = 'aligned_eod')), 0)))
    display_name: "Inventory Accuracy"
    comment: "Weighted count agreement for aligned full-store EOD sessions only."
    synonyms: ["inventory_accuracy_pct", "stock_accuracy", "ledger_accuracy"]
    format:
      type: percentage
      decimal_places: {type: exact, places: 1}

  - name: observed_to_book_agreement_pct
    expr: GREATEST(0.0, 1.0 - (SUM(absolute_unit_variance) FILTER (WHERE reconciliation_basis = 'misaligned') / NULLIF(GREATEST(SUM(ABS(book_units_eod)) FILTER (WHERE reconciliation_basis = 'misaligned'), SUM(observed_units) FILTER (WHERE reconciliation_basis = 'misaligned')), 0)))
    display_name: "Observed-to-Book Agreement"
    comment: "Agreement proxy for sessions that are not aligned to the EOD book snapshot; not labeled inventory accuracy."
    synonyms: ["agreement_rate", "count_agreement", "observed_book_match"]
    format:
      type: percentage
      decimal_places: {type: exact, places: 1}

  - name: phantom_stock_rate
    expr: CAST(COUNT(*) FILTER (WHERE is_phantom_stock) AS DOUBLE) / NULLIF(COUNT(*) FILTER (WHERE reconciliation_basis = 'aligned_eod'), 0)
    display_name: "Phantom Stock Rate"
    comment: "Share of aligned eligible product reconciliations with positive book stock and zero observed units."
    synonyms: ["phantom_rate", "ghost_inventory_rate"]
    format:
      type: percentage
      decimal_places: {type: exact, places: 1}
$$;
