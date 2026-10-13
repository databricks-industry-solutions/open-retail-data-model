-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_rfid_oos_candidates
-- Layer: outcome package (gold / dormant SDI seam)
-- Version: 0.5
-- Generated: 2026-08-18
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-19
-- ============================================================
-- GRAIN: one store × product × reconciliation date with latest aligned
-- phantom-stock evidence. These are investigation candidates, not stockout
-- episodes: no end date, duration, misplaced cause, or shrinkage cause is inferred.
-- The SDI detection-method enum does not yet admit `rfid`, so this view remains
-- read-only until that separately owned change is approved.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_rfid_oos_candidates AS
SELECT
  concat(
    'rfid-candidate|', store_id, '|', product_id, '|',
    CAST(reconciliation_date AS STRING)
  ) AS rfid_oos_candidate_id,
  product_sk,
  product_id,
  store_sk,
  store_id,
  reconciliation_date,
  rfid_count_session_sk,
  rfid_count_session_id,
  eligible_tagged_units,
  observed_units,
  book_units_eod,
  absolute_unit_variance,
  'rfid' AS detection_method,
  'phantom_stock' AS candidate_reason,
  -- Triage order for the investigation queue, banded on the BOOK quantity because that
  -- is the exposure at risk: the units the system still believes are sellable but RFID
  -- did not observe. >=10 book units = a full facing's worth of phantom stock (high);
  -- >=3 = more than a single-unit miscount, so worth a walk (medium); 1-2 units are
  -- within routine count noise (low). Illustrative demo bands, NOT an ORDM standard --
  -- retailers should retune per category velocity and tag read reliability.
  CASE
    WHEN book_units_eod >= 10 THEN 'high'
    WHEN book_units_eod >= 3 THEN 'medium'
    ELSE 'low'
  END AS candidate_severity,
  TRUE AS data_quality_flag,
  reconciled_at_ts AS evidence_at_ts,
  'connected_store_signals_rfid' AS record_source,
  current_timestamp() AS load_timestamp
FROM ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest
WHERE reconciliation_basis = 'aligned_eod'
  AND is_phantom_stock = TRUE;
