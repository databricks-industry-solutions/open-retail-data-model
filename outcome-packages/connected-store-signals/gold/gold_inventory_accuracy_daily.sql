-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_inventory_accuracy_daily
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-08-18
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-19
-- ============================================================
-- GRAIN: count session × store × product × session trading date.
-- Only full-store sessions closing in the reference EOD alignment window
-- (20:00-02:59 local) receive the `aligned_eod` basis and inventory-accuracy
-- label. Other sessions expose observed-to-book agreement only.
-- `reconciliation_date` is the EOD inventory snapshot date. For sessions ending
-- between 00:00 and 02:59 local it is the preceding local calendar date; it is
-- deliberately distinct from the session's declared `trading_date`.
-- RFID eligibility is a documented heuristic: an active commissioned item for the
-- product was observed at the store during the preceding 90 days.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_inventory_accuracy_daily AS
WITH eligible AS (
  SELECT
    s.rfid_count_session_sk,
    s.rfid_count_session_id,
    s.store_sk,
    s.store_id,
    s.trading_date,
    s.scope_type,
    s.ended_at_ts,
    CAST(date_from_unix_date(
      CAST(FLOOR(
        (unix_timestamp(s.ended_at_ts) + s.utc_offset_minutes * 60) / 86400
      ) AS INT)
    ) AS DATE) AS session_end_local_date,
    CAST(pmod(
      FLOOR((unix_timestamp(s.ended_at_ts) + s.utc_offset_minutes * 60) / 3600),
      24
    ) AS INT) AS ended_hour_of_day,
    e.product_id,
    COUNT(DISTINCT e.tagged_item_id) AS eligible_tagged_units
  FROM ${catalog}.${css_schema}.rfid_count_session s
  JOIN ${catalog}.${css_schema}.rfid_read_event e
    ON e.store_id = s.store_id
   AND e.product_id IS NOT NULL
   AND e.event_ts BETWEEN s.ended_at_ts - INTERVAL 90 DAYS AND s.ended_at_ts
  JOIN ${catalog}.${css_schema}.tagged_item i
    ON e.tagged_item_sk = i.tagged_item_sk
   AND i.commissioned_at_ts <= s.ended_at_ts
   AND (i.decommissioned_at_ts IS NULL OR i.decommissioned_at_ts >= s.ended_at_ts)
  GROUP BY s.rfid_count_session_sk, s.rfid_count_session_id,
           s.store_sk, s.store_id, s.trading_date, s.scope_type,
           s.ended_at_ts, s.utc_offset_minutes, e.product_id
), observed AS (
  SELECT
    rfid_count_session_sk,
    product_id,
    COUNT(DISTINCT tagged_item_id) AS observed_units
  FROM ${catalog}.${css_schema}.rfid_read_event
  WHERE rfid_count_session_sk IS NOT NULL
    AND product_id IS NOT NULL
    AND COALESCE(is_stray_suspect, FALSE) = FALSE
  GROUP BY rfid_count_session_sk, product_id
), reconciled AS (
  SELECT
    el.*,
    COALESCE(o.observed_units, 0) AS observed_units,
    ip.units_on_hand_eod AS book_units_eod,
    COALESCE(o.observed_units, 0) - ip.units_on_hand_eod AS unit_variance,
    ABS(COALESCE(o.observed_units, 0) - ip.units_on_hand_eod) AS absolute_unit_variance,
    CAST(CASE
      WHEN el.ended_hour_of_day BETWEEN 0 AND 2
      THEN date_sub(el.session_end_local_date, 1)
      ELSE el.session_end_local_date
    END AS DATE) AS reconciliation_date,
    CASE
      WHEN el.scope_type = 'full_store'
       AND (el.ended_hour_of_day >= 20 OR el.ended_hour_of_day <= 2)
      THEN 'aligned_eod'
      ELSE 'misaligned'
    END AS reconciliation_basis,
    ip.product_sk,
    p.department,
    p.category,
    p.subcategory
  FROM eligible el
  LEFT JOIN observed o
    ON el.rfid_count_session_sk = o.rfid_count_session_sk
   AND el.product_id = o.product_id
  JOIN ${catalog}.${inventory_schema}.inventory_position ip
    ON ip.store_id = el.store_id
   AND ip.product_id = el.product_id
   AND ip.date_key = CASE
     WHEN el.ended_hour_of_day BETWEEN 0 AND 2
     THEN date_sub(el.session_end_local_date, 1)
     ELSE el.session_end_local_date
   END
  LEFT JOIN ${catalog}.${product_schema}.product p
    ON ip.product_sk = p.product_sk
)
SELECT
  rfid_count_session_sk,
  rfid_count_session_id,
  store_sk,
  store_id,
  product_sk,
  product_id,
  trading_date,
  session_end_local_date,
  reconciliation_date,
  department,
  category,
  subcategory,
  scope_type,
  reconciliation_basis,
  eligible_tagged_units,
  observed_units,
  book_units_eod,
  unit_variance,
  absolute_unit_variance,
  CASE WHEN reconciliation_basis = 'aligned_eod' THEN
    CASE
      WHEN GREATEST(ABS(book_units_eod), observed_units) = 0 THEN 1.0
      ELSE GREATEST(
        0.0,
        1.0 - (absolute_unit_variance /
               NULLIF(GREATEST(ABS(book_units_eod), observed_units), 0))
      )
    END
  END AS inventory_accuracy_pct,
  CASE WHEN reconciliation_basis = 'misaligned' THEN
    CASE
      WHEN GREATEST(ABS(book_units_eod), observed_units) = 0 THEN 1.0
      ELSE GREATEST(
        0.0,
        1.0 - (absolute_unit_variance /
               NULLIF(GREATEST(ABS(book_units_eod), observed_units), 0))
      )
    END
  END AS observed_to_book_agreement_pct,
  reconciliation_basis = 'aligned_eod'
    AND book_units_eod > 0
    AND observed_units = 0
    AND eligible_tagged_units > 0 AS is_phantom_stock,
  reconciliation_basis = 'aligned_eod'
    AND unit_variance <> 0 AS is_record_inaccuracy,
  ended_at_ts AS reconciled_at_ts
FROM reconciled;
