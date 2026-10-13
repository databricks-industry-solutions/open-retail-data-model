-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Metric View: phantom_stock_candidates
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-10-05
-- LLM-generated: true (maintainer-reviewed before release)
-- ============================================================
-- RFID phantom stock investigation candidates: positive book stock with zero
-- observed serialized units. Rows are candidates for investigation only, not
-- proof that units exist elsewhere in the store.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.mv_phantom_stock_candidates
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "RFID phantom stock investigation candidates: positive EOD book stock with zero qualified physical evidence. These are investigation signals and must not be treated as autonomous inventory adjustments."
source: ${catalog}.${css_schema}.gold_rfid_oos_candidates

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

  - name: reconciliation_date
    expr: reconciliation_date
    display_name: "Reconciliation Date"
    comment: "EOD inventory snapshot date that revealed the phantom stock candidate."
    synonyms: ["date", "day", "snapshot_date"]

  - name: candidate_reason
    expr: candidate_reason
    display_name: "Candidate Reason"
    comment: "Always phantom_stock for RFID candidates: positive EOD book stock with zero qualified physical evidence."
    synonyms: ["reason", "trigger", "flag_reason"]

measures:
  - name: candidate_count
    expr: COUNT(*)
    display_name: "Candidate Count"
    comment: "Number of distinct phantom stock candidates in the grouping."
    synonyms: ["candidates", "investigations"]

  - name: eligible_units_total
    expr: SUM(eligible_tagged_units)
    display_name: "Eligible Serialized Units"
    comment: "Total distinct serialized items in scope for all candidates."
    synonyms: ["eligible_items", "tagged_units"]

  - name: observed_units_total
    expr: SUM(observed_units)
    display_name: "Observed Units"
    comment: "Total distinct serialized units observed across all candidates."
    synonyms: ["observed_items", "rfid_units"]

  - name: book_units_total
    expr: SUM(book_units_eod)
    display_name: "Book Units Total"
    comment: "Total end-of-day book inventory across all candidates."
    synonyms: ["ledger_units", "system_inventory"]

  - name: absolute_variance_total
    expr: SUM(absolute_unit_variance)
    display_name: "Total Absolute Variance"
    comment: "Sum of absolute observed-versus-book unit differences across all candidates."
    synonyms: ["total_variance", "variance"]

  - name: avg_absolute_variance
    expr: SUM(absolute_unit_variance) / NULLIF(COUNT(*), 0)
    display_name: "Average Absolute Variance"
    comment: "Mean absolute unit variance per candidate; indicates typical magnitude of discrepancies."
    synonyms: ["mean_variance", "avg_variance"]

  - name: high_severity_count
    expr: COUNT(*) FILTER (WHERE candidate_severity = 'high')
    display_name: "High Severity Candidates"
    comment: "Number of candidates at high severity (severity bands are high, medium, low)."
    synonyms: ["high_priority", "urgent_candidates"]

  - name: suspect_quality_count
    expr: COUNT(*) FILTER (WHERE data_quality_flag = TRUE)
    display_name: "Suspect Quality Candidates"
    comment: "Candidates flagged as a suspected data quality issue. Every RFID phantom-stock candidate is, by definition, a suspected book-record error."
    synonyms: ["low_quality", "needs_verification"]
$$;
