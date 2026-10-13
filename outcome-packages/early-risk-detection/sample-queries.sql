-- ============================================================
-- ORDM · Outcome Package · Early Risk Detection
-- Sample Queries
-- Version: 0.5
-- Generated: 2026-07-01
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-01 by @sreekanthmunigati
-- ============================================================

-- 1. Top 20 products at highest stockout risk
-- Shows products with the highest stockout risk score across all stores,
-- including in-transit replenishment status.
SELECT
    ir.product_id,
    p.product_name,
    p.category,
    ir.store_id,
    st.store_name,
    ir.units_on_hand_eod,
    ir.units_in_transit,
    ir.days_of_supply,
    ir.stockout_risk_score,
    ir.inventory_risk_tier
FROM ${catalog}.${risk_schema}.gold_inventory_risk ir
JOIN ${catalog}.${product_schema}.product p
  ON p.product_sk = ir.product_sk AND p.is_current = TRUE
JOIN ${catalog}.${store_schema}.store st
  ON st.store_sk = ir.store_sk AND st.is_current = TRUE
WHERE ir.inventory_risk_tier IN ('stockout', 'critical')
ORDER BY ir.stockout_risk_score DESC
LIMIT 20;

-- 2. Supplier risk overview with open alert counts
-- Ranks suppliers by procurement risk score alongside their active
-- disruption alert volume.
SELECT
    pr.supplier_id,
    sup.supplier_name,
    pr.risk_tier,
    pr.risk_score,
    pr.single_source_flag,
    pr.concentration_hhi,
    COALESCE(alerts.open_alerts, 0) AS open_alerts,
    COALESCE(alerts.critical_alerts, 0) AS critical_alerts
FROM ${catalog}.${risk_schema}.gold_procurement_risk pr
JOIN ${catalog}.${supplier_schema}.supplier sup
  ON sup.supplier_sk = pr.supplier_sk AND sup.is_current = TRUE
LEFT JOIN (
    SELECT
        supplier_id,
        COUNT(*) AS open_alerts,
        SUM(CASE WHEN severity = 'critical' THEN 1 ELSE 0 END) AS critical_alerts
    FROM ${catalog}.${risk_schema}.disruption_alert
    WHERE alert_status IN ('open', 'acknowledged')
    GROUP BY supplier_id
) alerts ON alerts.supplier_id = pr.supplier_id
ORDER BY pr.risk_score DESC
LIMIT 30;

-- 3. Shipments with significant ETA slip by carrier and lane
-- Identifies late shipments grouped by carrier and lane for pattern
-- detection and carrier performance analysis.
SELECT
    cs.carrier_name,
    cs.transport_mode,
    la.origin_location_name,
    la.destination_location_name,
    COUNT(*) AS shipment_count,
    ROUND(AVG(cs.eta_slip_days), 1) AS avg_eta_slip_days,
    MAX(cs.eta_slip_days) AS max_eta_slip_days,
    SUM(CASE WHEN cs.current_status = 'delivered' THEN 1 ELSE 0 END) AS delivered,
    SUM(CASE WHEN cs.current_status = 'in_transit' THEN 1 ELSE 0 END) AS in_transit
FROM ${catalog}.${risk_schema}.gold_shipment_current_state cs
JOIN ${catalog}.${logistics_schema}.lane la
  ON la.lane_sk = cs.lane_sk AND la.is_current = TRUE
WHERE cs.eta_slip_days > 0
GROUP BY cs.carrier_name, cs.transport_mode, la.origin_location_name, la.destination_location_name
ORDER BY avg_eta_slip_days DESC
LIMIT 20;

-- 4. Control tower triage: open critical alerts with inventory context
-- The primary operational query for the control tower — critical alerts
-- enriched with shipment state and inventory risk.
SELECT
    ct.alert_title,
    ct.severity,
    ct.alert_status,
    ct.alert_type,
    ct.shipment_id,
    ct.shipment_current_status,
    ct.shipment_current_eta,
    ct.shipment_eta_slip_days,
    ct.supplier_name,
    ct.supplier_risk_tier,
    ct.inventory_on_hand,
    ct.inventory_in_transit,
    ct.inventory_is_stockout,
    ct.assigned_to,
    ct.created_timestamp
FROM ${catalog}.${risk_schema}.gold_control_tower ct
WHERE ct.alert_status IN ('open', 'acknowledged')
  AND ct.severity = 'critical'
ORDER BY ct.created_timestamp DESC;

-- 5. Feed freshness dashboard
-- Monitors data pipeline health by checking how current each feed is.
-- Queries underlying tables directly; mv_feed_freshness is a UC Metric View
-- whose measures require MEASURE() syntax and cannot be SELECTed as bare columns.
SELECT
    feed_name,
    last_event_timestamp,
    last_ingest_timestamp,
    avg_latency_seconds,
    feed_age_minutes,
    CASE
      WHEN feed_age_minutes > 1440 THEN 'stale'
      WHEN feed_age_minutes > 60 THEN 'delayed'
      ELSE 'fresh'
    END AS freshness_status
FROM (
    SELECT
      'shipment_tracking' AS feed_name,
      MAX(event_timestamp) AS last_event_timestamp,
      MAX(ingest_timestamp) AS last_ingest_timestamp,
      ROUND(AVG(latency_seconds), 1) AS avg_latency_seconds,
      ROUND((UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(MAX(ingest_timestamp))) / 60.0, 1) AS feed_age_minutes
    FROM ${catalog}.${logistics_schema}.shipment_tracking
    UNION ALL
    SELECT
      'disruption_event',
      MAX(event_timestamp),
      MAX(ingest_timestamp),
      ROUND(AVG(latency_seconds), 1),
      ROUND((UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(MAX(ingest_timestamp))) / 60.0, 1)
    FROM ${catalog}.${risk_schema}.disruption_event
    UNION ALL
    SELECT
      'inventory_position',
      CAST(MAX(date_key) AS TIMESTAMP),
      MAX(load_timestamp),
      NULL,
      ROUND((UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(MAX(load_timestamp))) / 60.0, 1)
    FROM ${catalog}.${inventory_schema}.inventory_position
)
ORDER BY feed_age_minutes DESC;
