-- ============================================================
-- ORDM · Outcome Package · AI-Assisted Store Associates
-- View: gold_associate_product_inventory_current   (MATERIALIZED VIEW)
-- Layer: outcome package (gold / consumable)
-- Materialization: Lakeflow Declarative Pipeline materialized view for
--   associate point-lookup latency. Clustered on (store_id, product_id).
--   Demo/CI may --demote-materialized to a plain view (tools/ddl_exec.py).
-- Version: 0.5
-- Generated: 2026-08-11
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-11
-- ============================================================
-- Product × store current inventory context for associates.
-- Base state comes from the latest canonical-core inventory_position
-- day snapshot; optional associate_context_event inventory overlays
-- supply fresher intra-day quantities when present.
--
-- Honesty fields (must be surfaced to associates):
--   inventory_basis = daily_snapshot | event_overlay
--   location_basis  = event_location_code | not_modeled  (no shelf/bay geo)
--   nearby_store_match_basis = same_region_on_hand when set (not distance)
-- Freshness target: day-grain snapshot by end of business day; event
-- overlay SLA objective ≤ 5 minutes from ingest when streaming is wired
-- by the adopter. Stale/delayed flags are explicit — never silent.
-- No unit_cost / margin / loss-prevention fields.
--
-- Store-scope: apply the deploy-time row filter in filters.sql so Genie /
-- DBSQL consumers cannot bypass the Python policy layer.
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${aasa_schema}.gold_associate_product_inventory_current AS
WITH latest_position AS (
  SELECT
    ip.*,
    ROW_NUMBER() OVER (
      PARTITION BY ip.product_id, ip.store_id
      ORDER BY ip.date_key DESC, ip.load_timestamp DESC, ip.inventory_position_sk DESC
    ) AS rn
  FROM ${catalog}.${inventory_schema}.inventory_position ip
),
latest_inv_event AS (
  SELECT
    e.*,
    ROW_NUMBER() OVER (
      PARTITION BY e.product_id, e.store_id
      ORDER BY e.event_timestamp DESC, e.ingest_timestamp DESC, e.associate_context_event_sk DESC
    ) AS rn
  FROM ${catalog}.${aasa_schema}.associate_context_event e
  WHERE e.event_domain = 'inventory'
    AND e.product_id IS NOT NULL
    AND e.store_id IS NOT NULL
),
nearby AS (
  SELECT
    lp.product_id,
    lp.store_id AS home_store_id,
    other.store_id AS nearby_store_id,
    other.units_on_hand_eod AS nearby_on_hand,
    ROW_NUMBER() OVER (
      PARTITION BY lp.product_id, lp.store_id
      ORDER BY other.units_on_hand_eod DESC, other.store_id
    ) AS nearby_rn
  FROM latest_position lp
  JOIN ${catalog}.${store_schema}.store hs
    ON hs.store_id = lp.store_id AND hs.is_current = TRUE
  JOIN ${catalog}.${store_schema}.store ns
    ON ns.is_current = TRUE
   AND ns.store_id <> hs.store_id
   AND ns.region = hs.region
   AND ns.store_status = 'active'
  JOIN latest_position other
    ON other.rn = 1
   AND other.product_id = lp.product_id
   AND other.store_id = ns.store_id
   AND COALESCE(other.units_on_hand_eod, 0) > 0
  WHERE lp.rn = 1
)
SELECT
  p.product_sk,
  p.product_id,
  p.sku,
  p.gtin,
  p.product_name,
  p.brand,
  p.category,
  p.department,
  s.store_sk,
  s.store_id,
  s.store_name,
  s.region,
  s.district,
  COALESCE(ev.quantity_on_hand, lp.units_on_hand_eod) AS quantity_on_hand,
  COALESCE(ev.quantity_available,
           CASE
             WHEN lp.units_on_hand_eod IS NULL THEN NULL
             ELSE GREATEST(lp.units_on_hand_eod - COALESCE(ev.quantity_reserved, 0), CAST(0 AS DECIMAL(12,3)))
           END) AS quantity_available_to_sell,
  COALESCE(ev.quantity_reserved, CAST(0 AS DECIMAL(12,3))) AS quantity_reserved,
  COALESCE(ev.quantity_in_transit, lp.units_in_transit) AS quantity_in_transit,
  CASE
    WHEN COALESCE(ev.status_code, CAST(NULL AS STRING)) IN ('IN_STOCK', 'LOW_STOCK', 'OUT_OF_STOCK', 'UNKNOWN')
      THEN ev.status_code
    WHEN COALESCE(lp.is_stockout, FALSE) = TRUE
      OR COALESCE(ev.quantity_on_hand, lp.units_on_hand_eod) IS NULL
      OR COALESCE(ev.quantity_on_hand, lp.units_on_hand_eod) <= 0
      THEN 'OUT_OF_STOCK'
    WHEN COALESCE(lp.replenishment_flag, FALSE) = TRUE
      OR COALESCE(ev.quantity_on_hand, lp.units_on_hand_eod) < 5
      THEN 'LOW_STOCK'
    WHEN COALESCE(ev.quantity_on_hand, lp.units_on_hand_eod) IS NOT NULL
      THEN 'IN_STOCK'
    ELSE 'UNKNOWN'
  END AS stock_status,
  COALESCE(lp.replenishment_flag, FALSE) AS replenishment_indicator,
  -- Optional free-text location from an inventory event only. ORDM has no
  -- shelf/bay/planogram geo model; NULL means location is NOT_AVAILABLE.
  ev.location_code AS sales_floor_or_backroom_location,
  CASE
    WHEN ev.location_code IS NOT NULL THEN 'event_location_code'
    ELSE 'not_modeled'
  END AS location_basis,
  -- Same-region active store with on-hand > 0 (highest qty, then store_id).
  -- Not distance-ranked; not a geo nearest-neighbor.
  nb.nearby_store_id AS nearby_store_with_stock_id,
  nb.nearby_on_hand AS nearby_store_on_hand,
  CASE
    WHEN nb.nearby_store_id IS NOT NULL THEN 'same_region_on_hand'
    ELSE CAST(NULL AS STRING)
  END AS nearby_store_match_basis,
  lp.date_key AS snapshot_date_key,
  -- event_overlay = intra-day signal present; daily_snapshot = EOD fact only.
  CASE
    WHEN ev.associate_context_event_id IS NOT NULL THEN 'event_overlay'
    ELSE 'daily_snapshot'
  END AS inventory_basis,
  COALESCE(ev.event_timestamp, CAST(lp.date_key AS TIMESTAMP)) AS source_event_timestamp,
  COALESCE(ev.ingest_timestamp, lp.load_timestamp) AS source_ingest_timestamp,
  COALESCE(ev.processed_timestamp, lp.load_timestamp) AS current_state_updated_at,
  COALESCE(ev.source_system, lp.record_source) AS source_system,
  CASE
    -- Day-grain snapshot without overlay: freshness is calendar age of date_key,
    -- not "live shelf" freshness. Same-day EOD snapshot => fresh for EOD semantics;
    -- prior-day snapshot => delayed; >1 day behind => stale.
    WHEN ev.associate_context_event_id IS NULL AND lp.date_key IS NULL THEN 'UNKNOWN'
    WHEN ev.associate_context_event_id IS NULL AND lp.date_key = CURRENT_DATE() THEN 'fresh'
    WHEN ev.associate_context_event_id IS NULL AND DATEDIFF(CURRENT_DATE(), lp.date_key) = 1 THEN 'delayed'
    WHEN ev.associate_context_event_id IS NULL AND DATEDIFF(CURRENT_DATE(), lp.date_key) > 1 THEN 'stale'
    WHEN COALESCE(ev.ingest_timestamp, lp.load_timestamp) IS NULL THEN 'UNKNOWN'
    WHEN (UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(COALESCE(ev.ingest_timestamp, lp.load_timestamp))) > 86400
      THEN 'stale'
    WHEN (UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(COALESCE(ev.ingest_timestamp, lp.load_timestamp))) > 3600
      THEN 'delayed'
    ELSE 'fresh'
  END AS freshness_status,
  CASE
    WHEN ev.associate_context_event_id IS NULL AND lp.date_key IS NOT NULL
      THEN ROUND(DATEDIFF(CURRENT_DATE(), lp.date_key) * 1440.0, 1)
    ELSE ROUND(
      (UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(COALESCE(ev.ingest_timestamp, lp.load_timestamp))) / 60.0,
      1
    )
  END AS freshness_lag_minutes,
  CASE
    WHEN lp.inventory_position_sk IS NULL THEN 'No inventory position for this product and store.'
    WHEN ev.associate_context_event_id IS NOT NULL
      THEN CONCAT(
        'Intra-day inventory from event overlay ', ev.associate_context_event_id,
        '. Location is optional free-text location_code only (no shelf/bay geo model).',
        CASE
          WHEN nb.nearby_store_id IS NOT NULL
            THEN CONCAT(' Nearby alternative ', nb.nearby_store_id,
                        ' is same-region with on-hand > 0 (not distance-ranked).')
          ELSE ''
        END
      )
    ELSE CONCAT(
      'End-of-day inventory_position snapshot for date_key=', CAST(lp.date_key AS STRING),
      ' — not live shelf counts. Wire associate_context_event inventory overlays for intra-day freshness.',
      CASE
        WHEN nb.nearby_store_id IS NOT NULL
          THEN CONCAT(' Nearby alternative ', nb.nearby_store_id,
                      ' is same-region with on-hand > 0 (not distance-ranked).')
        ELSE ''
      END
    )
  END AS explanation,
  CASE
    WHEN ev.associate_context_event_id IS NULL AND lp.date_key IS NOT NULL AND lp.date_key < CURRENT_DATE()
      THEN CONCAT(
        'Quantities are from an end-of-day snapshot (date_key=', CAST(lp.date_key AS STRING),
        '), not live shelf counts; verify on floor before acting.'
      )
    WHEN ev.associate_context_event_id IS NULL
      THEN 'Quantities are end-of-day snapshot grain — not intra-day real-time unless an inventory event overlay is present.'
    WHEN (UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(COALESCE(ev.ingest_timestamp, lp.load_timestamp))) > 3600
      THEN 'Inventory event overlay exceeds freshness SLA; verify on floor before acting.'
    ELSE CAST(NULL AS STRING)
  END AS warning
FROM latest_position lp
JOIN ${catalog}.${product_schema}.product p
  ON p.product_id = lp.product_id AND p.is_current = TRUE
JOIN ${catalog}.${store_schema}.store s
  ON s.store_id = lp.store_id AND s.is_current = TRUE
LEFT JOIN latest_inv_event ev
  ON ev.rn = 1
 AND ev.product_id = lp.product_id
 AND ev.store_id = lp.store_id
LEFT JOIN nearby nb
  ON nb.nearby_rn = 1
 AND nb.product_id = lp.product_id
 AND nb.home_store_id = lp.store_id
WHERE lp.rn = 1
CLUSTER BY (store_id, product_id);
