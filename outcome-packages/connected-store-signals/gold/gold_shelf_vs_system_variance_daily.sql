-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_shelf_vs_system_variance_daily
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Ideal Lakebase serving projection.
-- Version: 0.5
-- Generated: 2026-08-20
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-20
-- ============================================================
-- GRAIN: one row per store × product × trading_date with both observed shelf evidence
-- and a same-date inventory snapshot.
--
-- EXPLICITLY DAILY (M2 — the _daily suffix names the comparison basis, mirroring RFID's
-- aligned_eod discipline): the day's LAST USABLE shelf reading per position, aggregated
-- to store × product, compared against inventory_position.units_on_hand_eod for the
-- SAME trading_date. Cross-date comparisons are not offered — an observed shelf from
-- Tuesday against Wednesday's book is not evidence of anything.
--
-- Observed units prefer the weight-derived estimate where the platform produces one,
-- else facings (a floor: facings count visible front units only — the comparison is
-- directional evidence for the phantom-stock conversation, not a stock count).
--
-- Phantom stock = positive EOD book units with zero observed units across the
-- product's observed positions (UC-RET-0204: 25-60% of OOS occur with the product
-- already in store). The inverse (observed > book) indicates record inaccuracy.
-- Unlike a current-state surface, this explicit EOD comparison intentionally ranks only
-- usable readings: the contract is the day's LAST USABLE reading. observed_positions vs
-- known_positions still publishes positions that had captures but no usable evidence.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_shelf_vs_system_variance_daily AS
WITH observed_position_day AS (
  SELECT DISTINCT
    o.store_id,
    o.trading_date,
    o.store_zone_id,
    o.product_id
  FROM ${catalog}.${css_schema}.shelf_state_observation o
), usable_ranked AS (
  -- This view's declared basis is LAST USABLE, so filter usability before ranking.
  SELECT
    o.store_id,
    o.trading_date,
    o.store_zone_id,
    o.product_id,
    o.shelf_state,
    o.observed_facing_count,
    o.estimated_unit_count,
    ROW_NUMBER() OVER (
      PARTITION BY o.store_zone_id, o.product_id, o.trading_date
      ORDER BY o.observation_ts DESC, o.ingest_timestamp DESC, o.shelf_state_observation_id DESC
    ) AS day_rank
  FROM ${catalog}.${css_schema}.shelf_state_observation o
  WHERE COALESCE(o.measurement_validity, 'valid') <> 'invalid'
    AND o.shelf_state <> 'unknown'
), usable_position_day AS (
  SELECT *
  FROM usable_ranked
  WHERE day_rank = 1
), observed_product_day AS (
  SELECT
    store_id,
    trading_date,
    product_id,
    COUNT(*) AS observed_positions
  FROM observed_position_day
  GROUP BY store_id, trading_date, product_id
), usable_product_day AS (
  SELECT
    store_id,
    trading_date,
    product_id,
    COUNT(*) AS known_positions,
    SUM(COALESCE(estimated_unit_count, observed_facing_count)) AS observed_units_on_shelf,
    SUM(CASE WHEN shelf_state = 'out_of_stock' THEN 1 ELSE 0 END) AS positions_oos
  FROM usable_position_day
  GROUP BY store_id, trading_date, product_id
)
SELECT
  opd.store_id,
  opd.trading_date,
  opd.product_id,
  opd.observed_positions,
  COALESCE(upd.known_positions, 0) AS known_positions,
  COALESCE(upd.positions_oos, 0) AS positions_oos,
  upd.observed_units_on_shelf,
  inv.units_on_hand_eod AS book_units_eod,
  inv.units_on_hand_eod - upd.observed_units_on_shelf AS unit_variance,
  abs(inv.units_on_hand_eod - upd.observed_units_on_shelf) AS absolute_unit_variance,
  -- Phantom stock: the book says units exist; the observed shelf says none do.
  (inv.units_on_hand_eod > 0
   AND COALESCE(upd.known_positions, 0) > 0
   AND COALESCE(upd.observed_units_on_shelf, 0) = 0) AS is_phantom_stock,
  -- Record inaccuracy in the other direction: shelf shows more than the book holds.
  (upd.observed_units_on_shelf IS NOT NULL
   AND upd.observed_units_on_shelf > COALESCE(inv.units_on_hand_eod, 0)) AS is_over_book,
  CAST(${shelf_as_of_ts} AS TIMESTAMP) AS fresh_as_of_ts
FROM observed_product_day opd
LEFT JOIN usable_product_day upd
  ON opd.store_id = upd.store_id
 AND opd.trading_date = upd.trading_date
 AND opd.product_id = upd.product_id
JOIN ${catalog}.${inventory_schema}.inventory_position inv
  ON opd.store_id = inv.store_id
 AND opd.product_id = inv.product_id
 AND opd.trading_date = inv.date_key;
