-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_inventory_accuracy_daily_latest
-- Layer: outcome package (gold / metric support)
-- Version: 0.5
-- Generated: 2026-08-18
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-19
-- ============================================================
-- GRAIN: store × product × reconciliation date × reconciliation basis.
-- Session-grain evidence remains in gold_inventory_accuracy_daily. This projection
-- selects the latest reconciliation within each daily basis so repeated counts do
-- not repeat the same EOD book quantity in additive metric-view measures.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest AS
WITH ranked AS (
  SELECT
    a.*,
    ROW_NUMBER() OVER (
      PARTITION BY store_id, product_id, reconciliation_date, reconciliation_basis
      ORDER BY reconciled_at_ts DESC, rfid_count_session_id DESC
    ) AS recency_rank
  FROM ${catalog}.${css_schema}.gold_inventory_accuracy_daily a
)
SELECT
  store_sk,
  store_id,
  product_sk,
  product_id,
  reconciliation_date,
  reconciliation_basis,
  department,
  category,
  subcategory,
  rfid_count_session_sk,
  rfid_count_session_id,
  trading_date AS session_trading_date,
  session_end_local_date,
  scope_type,
  eligible_tagged_units,
  observed_units,
  book_units_eod,
  unit_variance,
  absolute_unit_variance,
  inventory_accuracy_pct,
  observed_to_book_agreement_pct,
  is_phantom_stock,
  is_record_inaccuracy,
  reconciled_at_ts
FROM ranked
WHERE recency_rank = 1;
