-- ============================================================
-- ORDM · Canonical Core · Logistics domain · data-quality checks
-- Version: 0.5
-- Generated: 2026-06-30
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-30 by @sreekanthmunigati
-- ============================================================
-- Each assertion SELECTs violating rows; 0 rows = PASS. `metric` checks
-- report a value and never fail the run.
-- ============================================================

-- ========== lane ==========

-- check: lane_pk_unique | severity: error
SELECT lane_sk
FROM ${catalog}.${logistics_schema}.lane
GROUP BY lane_sk
HAVING COUNT(*) > 1;

-- check: lane_scd2_current_open | severity: error
SELECT * FROM ${catalog}.${logistics_schema}.lane
WHERE is_current = TRUE AND effective_to_date IS NOT NULL;

-- check: lane_scd2_noncurrent_closed | severity: error
SELECT * FROM ${catalog}.${logistics_schema}.lane
WHERE is_current = FALSE AND effective_to_date IS NULL;

-- check: lane_scd2_start_before_end | severity: error
SELECT * FROM ${catalog}.${logistics_schema}.lane
WHERE effective_to_date IS NOT NULL AND effective_from_date > effective_to_date;

-- check: lane_rowcount | severity: metric
SELECT COUNT(*) AS lane_rows FROM ${catalog}.${logistics_schema}.lane;

-- ========== shipment ==========

-- check: shipment_pk_unique | severity: error
SELECT shipment_sk
FROM ${catalog}.${logistics_schema}.shipment
GROUP BY shipment_sk
HAVING COUNT(*) > 1;

-- check: shipment_supplier_fk_orphan | severity: error
SELECT s.* FROM ${catalog}.${logistics_schema}.shipment s
LEFT JOIN ${catalog}.${supplier_schema}.supplier su ON s.supplier_sk = su.supplier_sk
WHERE su.supplier_sk IS NULL AND s.supplier_sk IS NOT NULL;

-- check: shipment_lane_fk_orphan | severity: error
SELECT s.* FROM ${catalog}.${logistics_schema}.shipment s
LEFT JOIN ${catalog}.${logistics_schema}.lane l ON s.lane_sk = l.lane_sk
WHERE l.lane_sk IS NULL AND s.lane_sk IS NOT NULL;

-- check: shipment_store_fk_orphan | severity: error
SELECT s.* FROM ${catalog}.${logistics_schema}.shipment s
LEFT JOIN ${catalog}.${store_schema}.store st ON s.destination_store_sk = st.store_sk
WHERE st.store_sk IS NULL AND s.destination_store_sk IS NOT NULL;

-- check: shipment_eta_after_ship | severity: error
SELECT * FROM ${catalog}.${logistics_schema}.shipment
WHERE estimated_arrival_date IS NOT NULL AND ship_date IS NOT NULL
  AND estimated_arrival_date < ship_date;

-- check: shipment_rowcount | severity: metric
SELECT COUNT(*) AS shipment_rows FROM ${catalog}.${logistics_schema}.shipment;

-- check: shipment_in_transit_count | severity: metric
SELECT COUNT(*) AS in_transit_shipments FROM ${catalog}.${logistics_schema}.shipment
WHERE shipment_status = 'in_transit';

-- ========== shipment_line ==========

-- check: shipment_line_pk_unique | severity: error
SELECT shipment_line_sk
FROM ${catalog}.${logistics_schema}.shipment_line
GROUP BY shipment_line_sk
HAVING COUNT(*) > 1;

-- check: shipment_line_shipment_fk_orphan | severity: error
SELECT sl.* FROM ${catalog}.${logistics_schema}.shipment_line sl
LEFT JOIN ${catalog}.${logistics_schema}.shipment s ON sl.shipment_sk = s.shipment_sk
WHERE s.shipment_sk IS NULL AND sl.shipment_sk IS NOT NULL;

-- check: shipment_line_product_fk_orphan | severity: error
SELECT sl.* FROM ${catalog}.${logistics_schema}.shipment_line sl
LEFT JOIN ${catalog}.${product_schema}.product p ON sl.product_sk = p.product_sk
WHERE p.product_sk IS NULL AND sl.product_sk IS NOT NULL;

-- check: shipment_line_po_line_fk_orphan | severity: error
-- Every non-null po_line_sk must reference an existing purchase_order_line (surrogate FK).
SELECT sl.* FROM ${catalog}.${logistics_schema}.shipment_line sl
LEFT JOIN ${catalog}.${procurement_schema}.purchase_order_line pol ON sl.po_line_sk = pol.po_line_sk
WHERE pol.po_line_sk IS NULL AND sl.po_line_sk IS NOT NULL;

-- check: shipment_line_rowcount | severity: metric
SELECT COUNT(*) AS shipment_line_rows FROM ${catalog}.${logistics_schema}.shipment_line;

-- ========== shipment_tracking ==========

-- check: shipment_tracking_pk_unique | severity: error
SELECT shipment_tracking_sk
FROM ${catalog}.${logistics_schema}.shipment_tracking
GROUP BY shipment_tracking_sk
HAVING COUNT(*) > 1;

-- check: shipment_tracking_shipment_fk_orphan | severity: error
SELECT st.* FROM ${catalog}.${logistics_schema}.shipment_tracking st
LEFT JOIN ${catalog}.${logistics_schema}.shipment s ON st.shipment_sk = s.shipment_sk
WHERE s.shipment_sk IS NULL AND st.shipment_sk IS NOT NULL;

-- check: shipment_tracking_event_ts_not_future | severity: error
SELECT * FROM ${catalog}.${logistics_schema}.shipment_tracking
WHERE event_timestamp > CURRENT_TIMESTAMP();

-- check: shipment_tracking_latency_nonnegative | severity: error
SELECT * FROM ${catalog}.${logistics_schema}.shipment_tracking
WHERE latency_seconds IS NOT NULL AND latency_seconds < 0;

-- check: shipment_tracking_lat_lon_range | severity: error
SELECT * FROM ${catalog}.${logistics_schema}.shipment_tracking
WHERE (latitude IS NOT NULL AND (latitude < -90 OR latitude > 90))
   OR (longitude IS NOT NULL AND (longitude < -180 OR longitude > 180));

-- check: shipment_tracking_rowcount | severity: metric
SELECT COUNT(*) AS shipment_tracking_rows FROM ${catalog}.${logistics_schema}.shipment_tracking;

-- check: shipment_tracking_avg_latency | severity: metric
SELECT ROUND(AVG(latency_seconds), 1) AS avg_latency_seconds
FROM ${catalog}.${logistics_schema}.shipment_tracking;

-- check: shipment_tracking_checkpoint_distribution | severity: metric
SELECT checkpoint_type, COUNT(*) AS event_count
FROM ${catalog}.${logistics_schema}.shipment_tracking
GROUP BY checkpoint_type;
